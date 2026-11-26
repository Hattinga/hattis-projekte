//! WASAPI capture → render loop for the audio thread (see the parent module).

use std::time::{Duration, Instant};

use windows::Win32::Devices::FunctionDiscovery::PKEY_Device_FriendlyName;
use windows::Win32::Foundation::{CloseHandle, HANDLE, WAIT_FAILED, WAIT_TIMEOUT};
use windows::Win32::Media::Audio::{
    AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY, AUDCLNT_BUFFERFLAGS_SILENT, AUDCLNT_SHAREMODE_SHARED,
    AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM, AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
    AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY, DEVICE_STATE_ACTIVE, EDataFlow, IAudioCaptureClient,
    IAudioClient, IAudioRenderClient, IMMDevice, IMMDeviceEnumerator, MMDeviceEnumerator,
    WAVEFORMATEX, WAVEFORMATEXTENSIBLE, WAVEFORMATEXTENSIBLE_0, eCapture, eConsole, eRender,
};
use windows::Win32::Media::KernelStreaming::{
    SPEAKER_FRONT_LEFT, SPEAKER_FRONT_RIGHT, WAVE_FORMAT_EXTENSIBLE,
};
use windows::Win32::Media::Multimedia::KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
use windows::Win32::System::Com::StructuredStorage::{PropVariantClear, PropVariantToStringAlloc};
use windows::Win32::System::Com::{
    CLSCTX_ALL, COINIT_MULTITHREADED, CoCreateInstance, CoInitializeEx, CoTaskMemFree,
    CoUninitialize, STGM_READ,
};
use windows::Win32::System::Threading::{CreateEventW, WaitForMultipleObjects};
use windows::core::PCWSTR;

use super::{AudioOptions, AudioState, PlayoutBuffer, Shared};

const CHANNELS: u16 = 2;
/// Queued audio the playout buffer aims at (on top of the WASAPI buffers).
const TARGET_MS: u32 = 30;
/// Requested WASAPI buffer for each stream (100 ns units): 20 ms.
const STREAM_BUFFER_HNS: i64 = 200_000;
/// Wait for the stream events at most this long, so a stop request is seen.
const WAIT_MS: u32 = 200;
/// Consecutive event timeouts after which the devices count as stuck.
const MAX_TIMEOUTS: u32 = 10;
const STATUS_INTERVAL: Duration = Duration::from_millis(500);
/// A session that ran this long resets the retry backoff.
const STABLE_AFTER: Duration = Duration::from_secs(30);
/// How often to look again for a missing input endpoint.
const NO_INPUT_RETRY: Duration = Duration::from_secs(3);

enum SessionError {
    /// No recording endpoint matches the video device.
    NoInput(String),
    Failed(String),
}

impl From<windows::core::Error> for SessionError {
    fn from(err: windows::core::Error) -> Self {
        Self::Failed(err.to_string())
    }
}

pub(super) fn run(shared: &Shared, options: &AudioOptions) {
    // SAFETY: COM for this thread only; balanced by CoUninitialize below.
    if let Err(err) = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) }.ok() {
        shared.set_status(|s| s.state = AudioState::Retrying(format!("COM: {err}")));
        return;
    }
    let mut attempt = 0u32;
    while !stopping(shared) {
        let started = Instant::now();
        let delay = match session(shared, options) {
            Ok(()) => break,
            Err(SessionError::NoInput(wanted)) => {
                tracing::debug!(%wanted, "no audio input endpoint for the video device");
                shared.set_status(|s| s.state = AudioState::NoInput { wanted });
                NO_INPUT_RETRY
            }
            Err(SessionError::Failed(err)) => {
                attempt = if started.elapsed() >= STABLE_AFTER {
                    1
                } else {
                    attempt + 1
                };
                let delay = Duration::from_secs((2u64 << attempt.min(3).saturating_sub(1)).min(10));
                tracing::warn!(%err, retry_in_s = delay.as_secs(), "audio failed");
                shared.set_status(|s| s.state = AudioState::Retrying(err));
                delay
            }
        };
        sleep_unless_stopped(shared, delay);
    }
    // SAFETY: balances the successful CoInitializeEx; every COM object of
    // this thread was released inside `session`.
    unsafe { CoUninitialize() };
}

fn stopping(shared: &Shared) -> bool {
    shared.stop.load(std::sync::atomic::Ordering::Relaxed)
}

fn sleep_unless_stopped(shared: &Shared, total: Duration) {
    let end = Instant::now() + total;
    while !stopping(shared) && Instant::now() < end {
        std::thread::sleep(Duration::from_millis(100));
    }
}

/// One capture → render session; returns `Ok` only when asked to stop.
fn session(shared: &Shared, options: &AudioOptions) -> Result<(), SessionError> {
    // Declared first so they are closed last, after the streams are gone.
    let render_event = Event::new()?;
    let capture_event = Event::new()?;
    // SAFETY: plain COM object creation on an MTA thread.
    let enumerator: IMMDeviceEnumerator =
        unsafe { CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL) }?;
    let (input, input_name) = find_input(&enumerator, &options.video_device)?
        .ok_or_else(|| SessionError::NoInput(options.video_device.clone()))?;
    let (output, output_name) = find_output(&enumerator, options.output.as_deref())?;

    // SAFETY: activating an endpoint of this enumerator.
    let render: IAudioClient = unsafe { output.Activate(CLSCTX_ALL, None) }?;
    let sample_rate = mix_rate(&render)?;
    let format = float_stereo(sample_rate);

    initialize(&render, &format, &render_event)?;
    // SAFETY: plain queries on an initialized client.
    let render_frames = unsafe { render.GetBufferSize() }?;
    let render_client: IAudioRenderClient = unsafe { render.GetService() }?;

    // SAFETY: activating an endpoint of this enumerator.
    let capture: IAudioClient = unsafe { input.Activate(CLSCTX_ALL, None) }?;
    initialize(&capture, &format, &capture_event)?;
    // SAFETY: plain query on an initialized client.
    let capture_client: IAudioCaptureClient = unsafe { capture.GetService() }?;

    let mut buffer = PlayoutBuffer::new(usize::from(CHANNELS), sample_rate, TARGET_MS);
    let _render_running = Running::start(&render)?;
    let _capture_running = Running::start(&capture)?;
    tracing::info!(input = %input_name, output = %output_name, sample_rate, render_frames, "audio started");
    shared.set_status(|s| {
        s.state = AudioState::Playing {
            input: input_name.clone(),
            output: output_name.clone(),
            sample_rate,
        };
    });

    let mut scratch = Vec::new();
    let mut timeouts = 0u32;
    let mut next_status = Instant::now();
    let handles = [capture_event.0, render_event.0];
    while !stopping(shared) {
        // SAFETY: both handles are valid events owned by this function.
        let wait = unsafe { WaitForMultipleObjects(&handles, false, WAIT_MS) };
        if wait == WAIT_FAILED {
            return Err(SessionError::Failed(format!(
                "waiting for audio events failed: {}",
                windows::core::Error::from_thread()
            )));
        }
        if wait == WAIT_TIMEOUT {
            timeouts += 1;
            if timeouts >= MAX_TIMEOUTS {
                return Err(SessionError::Failed(
                    "audio devices stopped responding".into(),
                ));
            }
        } else {
            timeouts = 0;
        }
        drain_capture(&capture_client, &mut buffer)?;
        fill_render(
            &render,
            &render_client,
            render_frames,
            &mut buffer,
            shared.gain(),
            &mut scratch,
        )?;

        if Instant::now() >= next_status {
            next_status = Instant::now() + STATUS_INTERVAL;
            let level_ms = buffer.level() as f32 * 1000.0 / sample_rate as f32;
            let stats = buffer.stats();
            shared.set_status(|s| {
                s.buffer_ms = level_ms;
                s.stats = stats;
            });
        }
    }
    let stats = buffer.stats();
    tracing::info!(
        underruns = stats.underruns,
        dropped = stats.dropped,
        inserted = stats.inserted,
        trimmed = stats.trimmed,
        "audio stopped"
    );
    Ok(())
}

fn initialize(
    client: &IAudioClient,
    format: &WAVEFORMATEXTENSIBLE,
    event: &Event,
) -> windows::core::Result<()> {
    // SAFETY: `format` is a complete WAVEFORMATEXTENSIBLE (cbSize covers the
    // extension), valid for the call; shared mode requires periodicity 0.
    unsafe {
        client.Initialize(
            AUDCLNT_SHAREMODE_SHARED,
            AUDCLNT_STREAMFLAGS_EVENTCALLBACK
                | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM
                | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
            STREAM_BUFFER_HNS,
            0,
            (format as *const WAVEFORMATEXTENSIBLE).cast::<WAVEFORMATEX>(),
            None,
        )?;
        client.SetEventHandle(event.0)
    }
}

/// Moves every available capture packet into the playout buffer.
fn drain_capture(
    capture: &IAudioCaptureClient,
    buffer: &mut PlayoutBuffer,
) -> windows::core::Result<()> {
    loop {
        // SAFETY: plain query on a started client.
        if unsafe { capture.GetNextPacketSize() }? == 0 {
            return Ok(());
        }
        let mut data = std::ptr::null_mut();
        let mut frames = 0u32;
        let mut flags = 0u32;
        // SAFETY: valid out-pointers; on success `data` holds `frames`
        // frames in our format until ReleaseBuffer.
        unsafe { capture.GetBuffer(&mut data, &mut frames, &mut flags, None, None) }?;
        let samples = frames as usize * usize::from(CHANNELS);
        if flags & AUDCLNT_BUFFERFLAGS_SILENT.0 as u32 != 0 || data.is_null() {
            buffer.push_silence(frames as usize);
        } else {
            // SAFETY: the buffer holds `samples` f32 values (4 bytes each)
            // until ReleaseBuffer; read as bytes, so alignment is irrelevant.
            let bytes = unsafe { std::slice::from_raw_parts(data, samples * 4) };
            let values: Vec<f32> = bytes
                .as_chunks::<4>()
                .0
                .iter()
                .map(|b| f32::from_le_bytes(*b))
                .collect();
            buffer.push(&values);
        }
        if flags & AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY.0 as u32 != 0 {
            tracing::debug!("audio capture discontinuity");
        }
        // SAFETY: releases exactly the frames obtained above.
        unsafe { capture.ReleaseBuffer(frames) }?;
    }
}

/// Fills the free part of the render buffer from the playout buffer.
fn fill_render(
    render: &IAudioClient,
    render_client: &IAudioRenderClient,
    render_frames: u32,
    buffer: &mut PlayoutBuffer,
    gain: f32,
    scratch: &mut Vec<f32>,
) -> windows::core::Result<()> {
    // SAFETY: plain query on a started client.
    let padding = unsafe { render.GetCurrentPadding() }?;
    let free = render_frames.saturating_sub(padding);
    if free == 0 {
        return Ok(());
    }
    let samples = free as usize * usize::from(CHANNELS);
    scratch.clear();
    scratch.resize(samples, 0.0);
    buffer.pull(scratch, gain);
    // SAFETY: requests `free` frames, which fit (buffer size − padding); the
    // pointer is valid for `samples` f32 values until ReleaseBuffer.
    unsafe {
        let data = render_client.GetBuffer(free)?;
        let bytes = std::slice::from_raw_parts_mut(data, samples * 4);
        for (dst, value) in bytes.as_chunks_mut::<4>().0.iter_mut().zip(scratch.iter()) {
            *dst = value.to_le_bytes();
        }
        render_client.ReleaseBuffer(free, 0)
    }
}

/// The recording endpoint whose name contains the video device's name.
/// Never falls back to another (e.g. the default) recording device.
fn find_input(
    enumerator: &IMMDeviceEnumerator,
    video_device: &str,
) -> windows::core::Result<Option<(IMMDevice, String)>> {
    let wanted = video_device.trim().to_lowercase();
    if wanted.len() < 3 {
        return Ok(None);
    }
    Ok(endpoints(enumerator, eCapture)?
        .into_iter()
        .find(|(_, name)| name.to_lowercase().contains(&wanted)))
}

/// The output named in the settings (part of the name is enough), else the
/// Windows default output.
fn find_output(
    enumerator: &IMMDeviceEnumerator,
    wanted: Option<&str>,
) -> windows::core::Result<(IMMDevice, String)> {
    if let Some(wanted) = wanted
        .map(|w| w.trim().to_lowercase())
        .filter(|w| !w.is_empty())
    {
        if let Some(found) = endpoints(enumerator, eRender)?
            .into_iter()
            .find(|(_, name)| name.to_lowercase().contains(&wanted))
        {
            return Ok(found);
        }
        tracing::warn!(%wanted, "audio output not found, using the Windows default");
    }
    // SAFETY: plain query on the enumerator.
    let device = unsafe { enumerator.GetDefaultAudioEndpoint(eRender, eConsole) }?;
    let name = friendly_name(&device).unwrap_or_else(|_| "default output".into());
    Ok((device, name))
}

/// Names of the active recording and playback endpoints (for
/// `--list-devices`). Runs on its own MTA thread.
pub(super) fn endpoint_names() -> Result<(Vec<String>, Vec<String>), String> {
    std::thread::Builder::new()
        .name("audio-list".into())
        .spawn(|| {
            // SAFETY: COM for this thread only; balanced below.
            unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) }
                .ok()
                .map_err(|e| e.to_string())?;
            let result = (|| {
                // SAFETY: plain COM object creation on an MTA thread.
                let enumerator: IMMDeviceEnumerator =
                    unsafe { CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL) }?;
                let names = |flow| -> windows::core::Result<Vec<String>> {
                    Ok(endpoints(&enumerator, flow)?
                        .into_iter()
                        .map(|(_, n)| n)
                        .collect())
                };
                Ok::<_, windows::core::Error>((names(eCapture)?, names(eRender)?))
            })()
            .map_err(|e| e.to_string());
            // SAFETY: balances CoInitializeEx; the enumerator is released.
            unsafe { CoUninitialize() };
            result
        })
        .map_err(|e| e.to_string())?
        .join()
        .map_err(|_| "audio enumeration thread panicked".to_string())?
}

/// Active endpoints of one direction with their friendly names.
fn endpoints(
    enumerator: &IMMDeviceEnumerator,
    flow: EDataFlow,
) -> windows::core::Result<Vec<(IMMDevice, String)>> {
    // SAFETY: plain queries on the enumerator and its collection.
    unsafe {
        let collection = enumerator.EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE)?;
        let mut list = Vec::new();
        for i in 0..collection.GetCount()? {
            let device = collection.Item(i)?;
            let name = friendly_name(&device).unwrap_or_else(|_| "<unnamed endpoint>".into());
            list.push((device, name));
        }
        Ok(list)
    }
}

fn friendly_name(device: &IMMDevice) -> windows::core::Result<String> {
    // SAFETY: the property store is read-only and released at the end; the
    // PROPVARIANT is cleared and the allocated string freed exactly once.
    unsafe {
        let store = device.OpenPropertyStore(STGM_READ)?;
        let mut value = store.GetValue(&PKEY_Device_FriendlyName)?;
        let text = PropVariantToStringAlloc(&value);
        let _ = PropVariantClear(&mut value);
        let text = text?;
        let name = text.to_string().unwrap_or_default();
        CoTaskMemFree(Some(text.0.cast_const().cast()));
        Ok(name)
    }
}

/// Sample rate of the output's shared-mode mix format.
fn mix_rate(client: &IAudioClient) -> windows::core::Result<u32> {
    // SAFETY: GetMixFormat returns a CoTaskMemAlloc'ed format we must free;
    // it is read unaligned (the struct is packed) before being freed.
    unsafe {
        let format = client.GetMixFormat()?;
        let rate = std::ptr::read_unaligned(format).nSamplesPerSec;
        CoTaskMemFree(Some(format.cast_const().cast()));
        Ok(rate)
    }
}

/// 32-bit float stereo at `sample_rate`, the format of both streams.
fn float_stereo(sample_rate: u32) -> WAVEFORMATEXTENSIBLE {
    let block_align = CHANNELS * 4;
    WAVEFORMATEXTENSIBLE {
        Format: WAVEFORMATEX {
            wFormatTag: WAVE_FORMAT_EXTENSIBLE as u16,
            nChannels: CHANNELS,
            nSamplesPerSec: sample_rate,
            nAvgBytesPerSec: sample_rate * u32::from(block_align),
            nBlockAlign: block_align,
            wBitsPerSample: 32,
            cbSize: (std::mem::size_of::<WAVEFORMATEXTENSIBLE>()
                - std::mem::size_of::<WAVEFORMATEX>()) as u16,
        },
        Samples: WAVEFORMATEXTENSIBLE_0 {
            wValidBitsPerSample: 32,
        },
        dwChannelMask: SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT,
        SubFormat: KSDATAFORMAT_SUBTYPE_IEEE_FLOAT,
    }
}

/// An auto-reset event, closed on drop.
struct Event(HANDLE);

impl Event {
    fn new() -> windows::core::Result<Self> {
        // SAFETY: unnamed auto-reset event, initially not signalled.
        unsafe { CreateEventW(None, false, false, PCWSTR::null()) }.map(Self)
    }
}

impl Drop for Event {
    fn drop(&mut self) {
        // SAFETY: the handle came from CreateEventW and is closed once.
        let _ = unsafe { CloseHandle(self.0) };
    }
}

/// A started stream, stopped on drop (also on error paths).
struct Running<'a>(&'a IAudioClient);

impl<'a> Running<'a> {
    fn start(client: &'a IAudioClient) -> windows::core::Result<Self> {
        // SAFETY: the client is initialized.
        unsafe { client.Start() }?;
        Ok(Self(client))
    }
}

impl Drop for Running<'_> {
    fn drop(&mut self) {
        // SAFETY: stops a stream this guard started.
        if let Err(err) = unsafe { self.0.Stop() } {
            tracing::debug!(%err, "IAudioClient::Stop");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn float_stereo_format_is_consistent() {
        let f = float_stereo(48_000);
        let base = f.Format;
        assert_eq!({ base.nBlockAlign }, 8);
        assert_eq!({ base.nAvgBytesPerSec }, 384_000);
        assert_eq!({ base.cbSize }, 22);
        assert_eq!({ f.dwChannelMask }, 3);
    }
}
