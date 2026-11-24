//! Media Foundation capture source: `IMFSourceReader` in asynchronous mode.
//!
//! ```text
//! capture thread                           MF work-queue thread
//! ──────────────                           ────────────────────
//! ReadSample() ─────── one request ──────► OnReadSample(sample)
//!                                            └─ try_send(message)
//! next_frame(): recv_timeout(200 ms) ◄───────────┘
//!   ├─ ReadSample()   next request goes out before the copy
//!   └─ copy NV12 planes without pitch/padding → Frame
//! ```
//!
//! Why asynchronous: a synchronous `ReadSample` blocks with no timeout. A
//! device without an HDMI signal may deliver nothing at all, and the capture
//! thread would then never see the stop request (the window would hang on
//! close). Here `next_frame` returns `Ok(None)` after [`FRAME_WAIT`].
//!
//! Exactly one read is in flight at any time, so at most one sample message
//! (plus one flush confirmation) can be queued: the channel is bounded by
//! that protocol, not by trust.
//!
//! Only native media types are used (`MF_READWRITE_DISABLE_CONVERTERS`): the
//! selected mode is exactly one the driver reported, without hidden format
//! conversion by the source reader. Only NV12 is implemented, the format the
//! renderer consumes directly. On the UGREEN 25854 the NV12 types are most
//! likely produced by Windows decoding the card's MJPEG stream (see
//! docs/hardware-probe-2026-11-24.md); that decode is part of the path.

use std::sync::mpsc::{Receiver, RecvTimeoutError, SyncSender, TrySendError, sync_channel};
use std::time::{Duration, Instant};

use windows::Win32::Foundation::{E_ACCESSDENIED, E_POINTER};
use windows::Win32::Media::MediaFoundation::{
    IMF2DBuffer2, IMFActivate, IMFAttributes, IMFMediaBuffer, IMFMediaEvent, IMFMediaSource,
    IMFMediaType, IMFSample, IMFSourceReader, IMFSourceReaderCallback,
    IMFSourceReaderCallback_Impl, MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME,
    MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, MF_E_HW_MFT_FAILED_START_STREAMING,
    MF_E_NO_MORE_TYPES, MF_E_VIDEO_RECORDING_DEVICE_INVALIDATED,
    MF_E_VIDEO_RECORDING_DEVICE_PREEMPTED, MF_LOW_LATENCY, MF_MT_DEFAULT_STRIDE, MF_MT_FRAME_RATE,
    MF_MT_FRAME_SIZE, MF_MT_SUBTYPE, MF_MT_VIDEO_NOMINAL_RANGE, MF_MT_YUV_MATRIX,
    MF_READWRITE_DISABLE_CONVERTERS, MF_SOURCE_READER_ALL_STREAMS, MF_SOURCE_READER_ASYNC_CALLBACK,
    MF_SOURCE_READER_FIRST_VIDEO_STREAM, MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED,
    MF_SOURCE_READERF_ENDOFSTREAM, MF_SOURCE_READERF_ERROR,
    MF_SOURCE_READERF_NATIVEMEDIATYPECHANGED, MF_SOURCE_READERF_STREAMTICK,
    MF2DBuffer_LockFlags_Read, MFCreateAttributes, MFCreateSourceReaderFromMediaSource,
    MFGetSystemTime, MFNominalRange_0_255, MFNominalRange_16_235,
    MFSampleExtension_DeviceReferenceSystemTime, MFVideoFormat_NV12, MFVideoTransferMatrix_BT601,
    MFVideoTransferMatrix_BT709,
};
use windows::core::{GUID, HRESULT, Interface, Ref, implement};

use super::{
    MediaTypeInfo, MfSession, allocated_string, describe, dump_attributes, enumerate_video_sources,
    subtype_name,
};
use crate::capture::{
    ColorSpace, DeviceSelector, Frame, FrameRate, ModeSelector, PixelFormat, SourceError,
    SourceInfo, VideoMode, VideoSource, YuvMatrix, YuvRange,
};
use crate::metrics::DurationStats;

const FIRST_VIDEO: u32 = MF_SOURCE_READER_FIRST_VIDEO_STREAM.0 as u32;
const ALL_STREAMS: u32 = MF_SOURCE_READER_ALL_STREAMS.0 as u32;
/// Longest wait in `next_frame` before it returns `Ok(None)`.
const FRAME_WAIT: Duration = Duration::from_millis(200);
/// How long dropping the source waits for the reader to confirm a flush.
const FLUSH_WAIT: Duration = Duration::from_secs(1);
/// One sample message plus one flush confirmation (see module docs).
const MESSAGE_CAPACITY: usize = 2;
/// Most padding rows accepted below the visible image (1080 → 1088 is 8).
const MAX_ROW_PADDING: usize = 64;
/// A timestamp jump longer than this is a stream discontinuity (e.g. signal
/// lost and back), not a run of dropped frames.
const MAX_GAP_100NS: i64 = 10_000_000;

/// Counters kept by the source for diagnostics (`--probe`, shutdown log).
#[derive(Debug, Clone, Default)]
pub struct CaptureStats {
    /// Reads that returned a sample with data, in any format.
    pub samples: u64,
    /// Arrival of the first sample with data.
    pub first_sample_at: Option<Instant>,
    /// Samples converted into frames (NV12 only).
    pub frames: u64,
    /// Reads that completed without a sample (gap in the stream).
    pub stream_ticks: u64,
    /// Samples that could not be converted (logged, skipped).
    pub bad_samples: u64,
    /// Time to copy one sample into the dense frame layout.
    pub copy_time: DurationStats,
    /// Interval between consecutive device timestamps (`llTimestamp`).
    pub sample_interval: DurationStats,
    /// `MFGetSystemTime()` in the callback minus the sample's
    /// `MFSampleExtension_DeviceReferenceSystemTime`, when the driver sets
    /// it. What the driver's reference time marks is driver-specific; this
    /// is not HDMI input time.
    pub device_to_callback: DurationStats,
    /// Samples whose device reference time lay in the future (clocks not
    /// comparable).
    pub device_time_after_callback: u64,
    /// Buffer layout of the most recent sample, as text.
    pub layout: Option<String>,
}

/// Source reader settings.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ReaderOptions {
    /// Set `MF_LOW_LATENCY` on the source reader (environment:
    /// `FRAMERUSH_MF_LOW_LATENCY=1`). Off by default until its effect on
    /// latency is measured (M3).
    pub low_latency: bool,
    /// Accept any native format and only count its samples (`--probe`).
    /// Without it, only NV12 can be opened.
    pub allow_any_format: bool,
}

impl ReaderOptions {
    pub fn from_env() -> Self {
        Self {
            low_latency: std::env::var("FRAMERUSH_MF_LOW_LATENCY").is_ok_and(|v| v.trim() == "1"),
            allow_any_format: false,
        }
    }
}

/// An opened Media Foundation capture device.
pub struct MediaFoundationSource {
    info: SourceInfo,
    device_index: usize,
    symbolic_link: String,
    native_index: u32,
    options: ReaderOptions,
    stream: StreamFormat,
    reader: IMFSourceReader,
    messages: Receiver<ReaderMessage>,
    read_pending: bool,
    clock: SequenceClock,
    last_timestamp: Option<i64>,
    stats: CaptureStats,
    layout_logged: bool,
    /// Held for its Drop: shuts the media source down after the reader is gone.
    _device: ActiveDevice,
    /// Declared last so it is dropped last: MFShutdown and CoUninitialize
    /// must run after every COM object above has been released.
    _session: MfSession,
}

impl MediaFoundationSource {
    /// Opens `device` in the selected native mode and starts reading.
    ///
    /// Must be called on the thread that will use the source (the capture
    /// thread); it initializes COM (MTA) and Media Foundation there.
    pub fn open(
        device: &DeviceSelector,
        mode: &ModeSelector,
        options: ReaderOptions,
    ) -> Result<Self, SourceError> {
        let session =
            MfSession::start().map_err(|e| device_error("cannot start Media Foundation", &e))?;
        let activates = enumerate_video_sources()
            .map_err(|e| device_error("cannot enumerate capture devices", &e))?;
        let (device_index, activate) = select_device(activates, device)?;
        let name = allocated_string(&activate, &MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME)
            .unwrap_or_else(|_| "<unnamed device>".into());
        let symbolic_link = allocated_string(
            &activate,
            &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK,
        )
        .unwrap_or_default();

        // SAFETY: activating a device source enumerated in this MF session.
        let media_source: IMFMediaSource = unsafe { activate.ActivateObject() }
            .map_err(|e| device_error(&format!("cannot open {name:?}"), &e))?;
        // From here on, `device` shuts the source down on every exit path.
        let device = ActiveDevice {
            activate,
            source: media_source,
        };

        let (tx, messages) = sync_channel(MESSAGE_CAPACITY);
        let callback: IMFSourceReaderCallback = ReaderCallback { tx }.into();
        let reader =
            create_reader(&device.source, &callback, options.low_latency).map_err(|e| {
                device_error(&format!("cannot create a source reader for {name:?}"), &e)
            })?;
        // SAFETY: stream selection on a live reader; constant stream id.
        unsafe { reader.SetStreamSelection(FIRST_VIDEO, true) }?;

        let (native_index, native_type) =
            select_native_type(&reader, mode, options.allow_any_format)?;
        // SAFETY: `native_type` is one of this reader's native types, so the
        // reader selects it on the device without inserting converters.
        unsafe { reader.SetCurrentMediaType(FIRST_VIDEO, None, &native_type) }.map_err(|e| {
            device_error(
                &format!("the device rejected native mode #{native_index}"),
                &e,
            )
        })?;
        // SAFETY: plain query on a live reader.
        let current = unsafe { reader.GetCurrentMediaType(FIRST_VIDEO) }
            .map_err(|e| device_error("cannot read back the selected mode", &e))?;
        let stream = StreamFormat::from_media_type(&current, options.allow_any_format)?;
        // For count-only formats (probe) `format` is not meaningful; the
        // probe prints `format_name()` instead. The viewer only opens NV12.
        let mode = VideoMode {
            width: stream.width,
            height: stream.height,
            format: PixelFormat::Nv12,
            frame_rate: stream.frame_rate,
        };
        tracing::info!(
            device = %name,
            index = device_index,
            link = %symbolic_link,
            native_index,
            format = %subtype_name(stream.subtype),
            %mode,
            color = %stream.color,
            color_reported = stream.color_reported,
            default_stride = ?stream.default_stride,
            low_latency = options.low_latency,
            "capture device opened"
        );
        for (key, value) in dump_attributes(&current) {
            tracing::debug!("current media type: {key} = {value}");
        }

        let mut source = Self {
            info: SourceInfo { name, mode },
            device_index,
            symbolic_link,
            native_index,
            options,
            clock: SequenceClock::new(stream.frame_rate),
            stream,
            reader,
            messages,
            read_pending: false,
            last_timestamp: None,
            stats: CaptureStats::default(),
            layout_logged: false,
            _device: device,
            _session: session,
        };
        source.request_sample()?;
        Ok(source)
    }

    pub fn device_index(&self) -> usize {
        self.device_index
    }

    pub fn symbolic_link(&self) -> &str {
        &self.symbolic_link
    }

    /// Index of the selected type in the device's native type list.
    pub fn native_index(&self) -> u32 {
        self.native_index
    }

    pub fn color(&self) -> (ColorSpace, bool) {
        (self.stream.color, self.stream.color_reported)
    }

    /// The negotiated format, e.g. "YUY2 1920x1080 @ 10 fps".
    pub fn format_description(&self) -> String {
        format!(
            "{} {}x{} @ {} fps",
            subtype_name(self.stream.subtype),
            self.stream.width,
            self.stream.height,
            self.stream.frame_rate
        )
    }

    pub fn stats(&self) -> &CaptureStats {
        &self.stats
    }

    /// Every attribute of the media type currently negotiated with the device.
    pub fn current_type_attributes(&self) -> Vec<(String, String)> {
        // SAFETY: plain query on a live reader.
        match unsafe { self.reader.GetCurrentMediaType(FIRST_VIDEO) } {
            Ok(current) => dump_attributes(&current),
            Err(e) => vec![("error".into(), e.to_string())],
        }
    }

    fn request_sample(&mut self) -> Result<(), SourceError> {
        // SAFETY: asynchronous mode: every out-parameter must be null; the
        // result arrives in ReaderCallback::OnReadSample.
        unsafe {
            self.reader
                .ReadSample(FIRST_VIDEO, 0, None, None, None, None)
        }
        .map_err(|e| device_error("ReadSample failed", &e))?;
        self.read_pending = true;
        Ok(())
    }

    fn reload_format(&mut self) -> Result<(), SourceError> {
        // SAFETY: plain query on a live reader.
        let current = unsafe { self.reader.GetCurrentMediaType(FIRST_VIDEO) }
            .map_err(|e| device_error("cannot read the changed media type", &e))?;
        self.stream = StreamFormat::from_media_type(&current, self.options.allow_any_format)?;
        self.clock = SequenceClock::new(self.stream.frame_rate);
        self.last_timestamp = None;
        self.layout_logged = false;
        tracing::warn!(
            width = self.stream.width,
            height = self.stream.height,
            fps = %self.stream.frame_rate,
            color = %self.stream.color,
            "capture media type changed"
        );
        Ok(())
    }

    fn handle_sample(&mut self, read: ReadResult) -> Result<Option<Frame>, SourceError> {
        self.read_pending = false;
        tracing::trace!(
            status = %read.status,
            flags = read.flags,
            timestamp = read.timestamp,
            has_sample = read.sample.is_some(),
            "OnReadSample"
        );
        read.status
            .ok()
            .map_err(|e| device_error("reading from the device failed", &e))?;
        let flags = read.flags;
        if flags & MF_SOURCE_READERF_ERROR.0 as u32 != 0 {
            return Err(SourceError::Device(
                "the source reader reported a stream error".into(),
            ));
        }
        if flags & MF_SOURCE_READERF_ENDOFSTREAM.0 as u32 != 0 {
            return Err(SourceError::Device("the device ended the stream".into()));
        }
        if flags & MF_SOURCE_READERF_NATIVEMEDIATYPECHANGED.0 as u32 != 0 {
            tracing::warn!("the device changed its native media type");
        }
        if flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED.0 as u32 != 0 {
            self.reload_format()?;
        }
        // Keep the device busy: the next request goes out before the copy.
        self.request_sample()?;

        let Some(sample) = read.sample else {
            if flags & MF_SOURCE_READERF_STREAMTICK.0 as u32 != 0 {
                self.stats.stream_ticks += 1;
                tracing::debug!(timestamp = read.timestamp, "stream tick (gap, no sample)");
            }
            return Ok(None);
        };
        let sample = sample.0;
        self.stats.samples += 1;
        self.stats.first_sample_at.get_or_insert(read.received_at);

        if let Some(last) = self.last_timestamp
            && read.timestamp > last
        {
            self.stats
                .sample_interval
                .record(hns_to_duration(read.timestamp - last));
        }
        self.last_timestamp = Some(read.timestamp);
        // SAFETY: attribute read on a live sample.
        if let Ok(device_time) =
            unsafe { sample.GetUINT64(&MFSampleExtension_DeviceReferenceSystemTime) }
        {
            match read.received_mf_time.checked_sub(device_time as i64) {
                Some(delta) if delta >= 0 => {
                    self.stats.device_to_callback.record(hns_to_duration(delta));
                }
                _ => self.stats.device_time_after_callback += 1,
            }
        }

        if self.stream.subtype != MFVideoFormat_NV12 {
            // Count-only format (probe): note the size, convert nothing.
            // SAFETY: plain query on a live sample.
            let len = unsafe { sample.GetTotalLength() }.unwrap_or(0);
            self.stats.layout = Some(format!(
                "{} sample, {len} bytes (counted, not converted)",
                subtype_name(self.stream.subtype)
            ));
            return Ok(None);
        }

        let copy_start = Instant::now();
        let (data, layout) = match copy_nv12_sample(&sample, &self.stream) {
            Ok(result) => result,
            Err(err) => {
                self.stats.bad_samples += 1;
                if self.stats.bad_samples <= 5 {
                    tracing::warn!(%err, "sample skipped");
                }
                return Ok(None);
            }
        };
        self.stats.copy_time.record(copy_start.elapsed());
        self.stats.frames += 1;
        if !self.layout_logged {
            self.layout_logged = true;
            tracing::info!(layout = %layout, "first sample");
        }
        self.stats.layout = Some(layout);

        Ok(Some(Frame {
            sequence: self.clock.next(read.timestamp),
            width: self.stream.width,
            height: self.stream.height,
            format: PixelFormat::Nv12,
            data,
            color: self.stream.color,
            ready_at: read.received_at,
        }))
    }
}

impl VideoSource for MediaFoundationSource {
    fn info(&self) -> &SourceInfo {
        &self.info
    }

    fn next_frame(&mut self) -> Result<Option<Frame>, SourceError> {
        if !self.read_pending {
            self.request_sample()?;
        }
        match self.messages.recv_timeout(FRAME_WAIT) {
            Ok(ReaderMessage::Sample(read)) => self.handle_sample(read),
            // Only expected during shutdown.
            Ok(ReaderMessage::Flushed) => Ok(None),
            Err(RecvTimeoutError::Timeout) => Ok(None),
            Err(RecvTimeoutError::Disconnected) => Err(SourceError::Device(
                "the source reader callback went away".into(),
            )),
        }
    }

    fn log_summary(&self) {
        let s = &self.stats;
        let ms = |d: Option<Duration>| d.map(|d| format!("{:.2}", d.as_secs_f64() * 1000.0));
        tracing::info!(
            frames = s.frames,
            stream_ticks = s.stream_ticks,
            bad_samples = s.bad_samples,
            copy_avg_ms = ?ms(s.copy_time.mean()),
            copy_max_ms = ?ms(s.copy_time.max()),
            sample_interval_min_ms = ?ms(s.sample_interval.min()),
            sample_interval_max_ms = ?ms(s.sample_interval.max()),
            layout = ?s.layout,
            "capture device statistics"
        );
    }
}

impl Drop for MediaFoundationSource {
    fn drop(&mut self) {
        // Cancel the outstanding read and wait until the reader confirms, so
        // no callback runs while MF shuts down. A late callback would still
        // be memory-safe: the callback object is reference-counted and its
        // channel send just fails.
        tracing::debug!("drop: flushing the source reader");
        // SAFETY: flush on a live reader.
        match unsafe { self.reader.Flush(ALL_STREAMS) } {
            Ok(()) => {
                let deadline = Instant::now() + FLUSH_WAIT;
                loop {
                    let left = deadline.saturating_duration_since(Instant::now());
                    match self.messages.recv_timeout(left) {
                        Ok(ReaderMessage::Flushed) => {
                            tracing::debug!("drop: flush confirmed");
                            break;
                        }
                        Ok(ReaderMessage::Sample(_)) => continue,
                        Err(_) => {
                            tracing::warn!("source reader did not confirm the flush in time");
                            break;
                        }
                    }
                }
            }
            Err(err) => tracing::debug!(%err, "IMFSourceReader::Flush failed"),
        }
        tracing::debug!("drop: releasing the source reader");
        // Fields drop after this: reader, then `device` (shuts the source
        // down), then the MF session.
    }
}

/// Activated device; shuts the media source down when dropped, also on
/// error paths during `open`.
struct ActiveDevice {
    activate: IMFActivate,
    source: IMFMediaSource,
}

impl Drop for ActiveDevice {
    fn drop(&mut self) {
        tracing::debug!("drop: shutting down the media source");
        // SAFETY: shutting down the source we activated. The source reader
        // may have shut it down already when it was released; a second
        // Shutdown just reports MF_E_SHUTDOWN.
        unsafe {
            if let Err(err) = self.source.Shutdown() {
                tracing::debug!(%err, "IMFMediaSource::Shutdown");
            }
            if let Err(err) = self.activate.ShutdownObject() {
                tracing::debug!(%err, "IMFActivate::ShutdownObject");
            }
        }
        tracing::debug!("drop: media source shut down");
    }
}

enum ReaderMessage {
    Sample(ReadResult),
    Flushed,
}

struct ReadResult {
    status: HRESULT,
    flags: u32,
    /// Sample time in 100 ns units.
    timestamp: i64,
    sample: Option<MtaSample>,
    /// `Instant::now()` when the callback started.
    received_at: Instant,
    /// `MFGetSystemTime()` at the same moment (100 ns units).
    received_mf_time: i64,
}

/// An `IMFSample` moved from the MF callback thread to the capture thread.
struct MtaSample(IMFSample);

// SAFETY: COM lets threads of the multithreaded apartment use an interface
// pointer directly, without marshaling. The callback runs on a Media
// Foundation work-queue thread (MTA), and the receiving capture thread joined
// the MTA in MfSession::start before creating the reader. The sample is only
// moved, never shared.
unsafe impl Send for MtaSample {}

#[implement(IMFSourceReaderCallback)]
struct ReaderCallback {
    tx: SyncSender<ReaderMessage>,
}

impl ReaderCallback {
    fn send(&self, message: ReaderMessage) {
        match self.tx.try_send(message) {
            // Disconnected: the source is being dropped; nothing to do.
            Ok(()) | Err(TrySendError::Disconnected(_)) => {}
            Err(TrySendError::Full(_)) => {
                tracing::error!("reader callback queue full, message dropped (protocol violated)");
            }
        }
    }
}

impl IMFSourceReaderCallback_Impl for ReaderCallback_Impl {
    fn OnReadSample(
        &self,
        hrstatus: HRESULT,
        _stream_index: u32,
        stream_flags: u32,
        timestamp: i64,
        sample: Ref<IMFSample>,
    ) -> windows::core::Result<()> {
        let received_at = Instant::now();
        // SAFETY: no preconditions beyond a started MF, which the reader
        // calling us implies.
        let received_mf_time = unsafe { MFGetSystemTime() };
        self.send(ReaderMessage::Sample(ReadResult {
            status: hrstatus,
            flags: stream_flags,
            timestamp,
            sample: sample.cloned().map(MtaSample),
            received_at,
            received_mf_time,
        }));
        Ok(())
    }

    fn OnFlush(&self, _stream_index: u32) -> windows::core::Result<()> {
        self.send(ReaderMessage::Flushed);
        Ok(())
    }

    fn OnEvent(&self, _stream_index: u32, _event: Ref<IMFMediaEvent>) -> windows::core::Result<()> {
        Ok(())
    }
}

fn create_reader(
    source: &IMFMediaSource,
    callback: &IMFSourceReaderCallback,
    low_latency: bool,
) -> windows::core::Result<IMFSourceReader> {
    let mut attributes: Option<IMFAttributes> = None;
    // SAFETY: valid out-pointer; on success it receives an owned interface.
    unsafe { MFCreateAttributes(&mut attributes, 3) }?;
    let attributes = attributes.ok_or_else(|| windows::core::Error::from(E_POINTER))?;
    // SAFETY: attribute writes with valid keys; the store keeps its own
    // reference to the callback. MF_LOW_LATENCY is a hint to the pipeline.
    unsafe {
        attributes.SetUnknown(&MF_SOURCE_READER_ASYNC_CALLBACK, callback)?;
        attributes.SetUINT32(&MF_READWRITE_DISABLE_CONVERTERS, 1)?;
        if low_latency {
            attributes.SetUINT32(&MF_LOW_LATENCY, 1)?;
        }
        MFCreateSourceReaderFromMediaSource(source, &attributes)
    }
}

fn select_device(
    activates: Vec<IMFActivate>,
    selector: &DeviceSelector,
) -> Result<(usize, IMFActivate), SourceError> {
    let described: Vec<(String, String)> = activates
        .iter()
        .map(|a| {
            (
                allocated_string(a, &MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME).unwrap_or_default(),
                allocated_string(a, &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK)
                    .unwrap_or_default(),
            )
        })
        .collect();
    let index = match_device(&described, selector).map_err(SourceError::Device)?;
    let activate = activates
        .into_iter()
        .nth(index)
        .expect("match_device returns a valid index");
    Ok((index, activate))
}

/// Picks one device from `(friendly name, symbolic link)` pairs.
///
/// A number that is not a valid device index must appear as a whole word in
/// a friendly name, so `--device 25854` finds "UGREEN 25854". Plain
/// substring matching would let a mistyped index open whichever device has
/// that digit somewhere in its USB id.
fn match_device(devices: &[(String, String)], selector: &DeviceSelector) -> Result<usize, String> {
    let list = || {
        if devices.is_empty() {
            return "no video capture devices found".to_string();
        }
        let names: Vec<String> = devices
            .iter()
            .enumerate()
            .map(|(i, (name, _))| format!("[{i}] {name}"))
            .collect();
        format!("devices: {}", names.join(", "))
    };
    let by_name = |pattern: &str| {
        let needle = pattern.to_lowercase();
        devices
            .iter()
            .enumerate()
            .filter(|(_, (name, link))| {
                name.to_lowercase().contains(&needle) || link.to_lowercase().contains(&needle)
            })
            .map(|(i, _)| i)
            .collect::<Vec<usize>>()
    };
    match selector {
        DeviceSelector::Index(index) if *index < devices.len() => Ok(*index),
        DeviceSelector::Index(index) => {
            let word = index.to_string();
            let hits: Vec<usize> = devices
                .iter()
                .enumerate()
                .filter(|(_, (name, _))| {
                    name.split(|c: char| !c.is_alphanumeric())
                        .any(|w| w == word)
                })
                .map(|(i, _)| i)
                .collect();
            match hits.as_slice() {
                [hit] => Ok(*hit),
                _ => Err(format!(
                    "there is no device #{index} and no single device with {index} in its name; {}",
                    list()
                )),
            }
        }
        DeviceSelector::Name(pattern) => match by_name(pattern).as_slice() {
            [index] => Ok(*index),
            [] => Err(format!("no device matches {pattern:?}; {}", list())),
            _ => Err(format!(
                "{pattern:?} matches several devices, use a longer name or the index; {}",
                list()
            )),
        },
    }
}

fn select_native_type(
    reader: &IMFSourceReader,
    selector: &ModeSelector,
    allow_any_format: bool,
) -> Result<(u32, IMFMediaType), SourceError> {
    let mut types = Vec::new();
    for index in 0.. {
        // SAFETY: plain query on a live reader; ends with MF_E_NO_MORE_TYPES.
        match unsafe { reader.GetNativeMediaType(FIRST_VIDEO, index) } {
            Ok(media_type) => types.push(media_type),
            Err(err) if err.code() == MF_E_NO_MORE_TYPES => break,
            Err(err) => return Err(device_error("cannot read the device's media types", &err)),
        }
    }
    let infos: Vec<MediaTypeInfo> = types.iter().map(describe).collect();
    let index = match_native_type(&infos, selector, allow_any_format)
        .map_err(SourceError::UnsupportedMode)?;
    let media_type = types.swap_remove(index);
    Ok((index as u32, media_type))
}

/// Picks one of the reported native types. Only NV12 can be captured;
/// `allow_any_format` accepts any type by index (count-only probe).
fn match_native_type(
    types: &[MediaTypeInfo],
    selector: &ModeSelector,
    allow_any_format: bool,
) -> Result<usize, String> {
    let nv12_list = || {
        let modes: Vec<String> = types
            .iter()
            .enumerate()
            .filter(|(_, t)| t.subtype == Some(MFVideoFormat_NV12))
            .map(|(i, t)| format!("#{i} {}", short_mode(t)))
            .collect();
        if modes.is_empty() {
            "the device reports no NV12 modes".to_string()
        } else {
            format!("NV12 modes the device reports: {}", modes.join(", "))
        }
    };
    let index = match selector {
        ModeSelector::Index(index) => {
            let index = *index as usize;
            if index >= types.len() {
                return Err(format!(
                    "mode #{index} does not exist, the device reports {} modes (see --list-devices)",
                    types.len()
                ));
            }
            index
        }
        ModeSelector::Match(mode) => {
            if mode.format != PixelFormat::Nv12 {
                return Err(format!(
                    "capturing {} is not implemented, only NV12; {}",
                    mode.format.name(),
                    nv12_list()
                ));
            }
            types
                .iter()
                .position(|t| {
                    t.subtype == Some(MFVideoFormat_NV12)
                        && t.frame_size == Some((mode.width, mode.height))
                        && t.frame_rate.is_some_and(|(n, d)| {
                            u64::from(n) * u64::from(mode.frame_rate.denominator)
                                == u64::from(mode.frame_rate.numerator) * u64::from(d)
                        })
                })
                .ok_or_else(|| format!("the device does not report {mode}; {}", nv12_list()))?
        }
    };
    let chosen = &types[index];
    if !allow_any_format && chosen.subtype != Some(MFVideoFormat_NV12) {
        let subtype = chosen.subtype.map_or_else(|| "?".into(), subtype_name);
        return Err(format!(
            "mode #{index} is {subtype}; capturing it is not implemented, only NV12; {}",
            nv12_list()
        ));
    }
    Ok(index)
}

fn short_mode(t: &MediaTypeInfo) -> String {
    let size = t
        .frame_size
        .map_or_else(|| "?x?".into(), |(w, h)| format!("{w}x{h}"));
    let fps = match t.frame_rate {
        Some((n, d)) if d != 0 && n % d == 0 => format!("{}", n / d),
        Some((n, d)) if d != 0 => format!("{:.3}", f64::from(n) / f64::from(d)),
        _ => "?".into(),
    };
    format!("{size}@{fps}")
}

/// What the capture path needs from the negotiated media type.
#[derive(Debug, Clone, Copy)]
struct StreamFormat {
    /// NV12, or any subtype in count-only mode.
    subtype: GUID,
    width: u32,
    height: u32,
    frame_rate: FrameRate,
    color: ColorSpace,
    /// Whether matrix and range came from the media type (false: assumed).
    color_reported: bool,
    /// MF_MT_DEFAULT_STRIDE, used for buffers without a 2D interface.
    default_stride: Option<i32>,
}

impl StreamFormat {
    /// `allow_any_format`: accept non-NV12 types (count-only probe).
    fn from_media_type(
        media_type: &IMFMediaType,
        allow_any_format: bool,
    ) -> Result<Self, SourceError> {
        let split = |v: u64| ((v >> 32) as u32, v as u32);
        // SAFETY: attribute reads on a live media type with valid keys.
        let (subtype, size, rate, matrix, range, stride) = unsafe {
            (
                media_type.GetGUID(&MF_MT_SUBTYPE).ok(),
                media_type.GetUINT64(&MF_MT_FRAME_SIZE).ok().map(split),
                media_type.GetUINT64(&MF_MT_FRAME_RATE).ok().map(split),
                media_type.GetUINT32(&MF_MT_YUV_MATRIX).ok(),
                media_type.GetUINT32(&MF_MT_VIDEO_NOMINAL_RANGE).ok(),
                media_type.GetUINT32(&MF_MT_DEFAULT_STRIDE).ok(),
            )
        };
        let subtype = subtype.ok_or_else(|| {
            SourceError::UnsupportedMode("the negotiated type has no subtype".into())
        })?;
        let nv12 = subtype == MFVideoFormat_NV12;
        if !nv12 && !allow_any_format {
            return Err(SourceError::UnsupportedMode(format!(
                "the negotiated type is {}, expected NV12",
                subtype_name(subtype)
            )));
        }
        let (width, height) = size
            .filter(|&(w, h)| {
                if nv12 {
                    PixelFormat::Nv12.frame_len(w, h).is_some()
                } else {
                    w > 0 && h > 0
                }
            })
            .ok_or_else(|| {
                SourceError::UnsupportedMode(format!(
                    "invalid {} frame size {size:?}",
                    subtype_name(subtype)
                ))
            })?;
        let frame_rate = rate
            .and_then(|(n, d)| FrameRate::new(n, d))
            .ok_or_else(|| SourceError::UnsupportedMode(format!("invalid frame rate {rate:?}")))?;
        let (color, color_reported) = color_space(matrix, range, height);
        Ok(Self {
            subtype,
            width,
            height,
            frame_rate,
            color,
            color_reported,
            default_stride: stride.map(|s| s as i32),
        })
    }
}

/// YUV matrix and range from the media type's `MF_MT_YUV_MATRIX` and
/// `MF_MT_VIDEO_NOMINAL_RANGE`. Missing or unsupported values fall back to
/// the usual video convention (BT.601 up to 576 lines, BT.709 above;
/// limited range); the second value says whether both were reported.
fn color_space(matrix: Option<u32>, range: Option<u32>, height: u32) -> (ColorSpace, bool) {
    let reported_matrix = match matrix.map(|m| m as i32) {
        Some(m) if m == MFVideoTransferMatrix_BT709.0 => Some(YuvMatrix::Bt709),
        Some(m) if m == MFVideoTransferMatrix_BT601.0 => Some(YuvMatrix::Bt601),
        _ => None,
    };
    let reported_range = match range.map(|r| r as i32) {
        Some(r) if r == MFNominalRange_0_255.0 => Some(YuvRange::Full),
        Some(r) if r == MFNominalRange_16_235.0 => Some(YuvRange::Limited),
        _ => None,
    };
    let color = ColorSpace {
        matrix: reported_matrix.unwrap_or(if height <= 576 {
            YuvMatrix::Bt601
        } else {
            YuvMatrix::Bt709
        }),
        range: reported_range.unwrap_or(YuvRange::Limited),
    };
    (color, reported_matrix.is_some() && reported_range.is_some())
}

/// Copies an NV12 sample into the dense `Frame` layout. Returns the data and
/// a description of the buffer layout.
fn copy_nv12_sample(
    sample: &IMFSample,
    format: &StreamFormat,
) -> Result<(Vec<u8>, String), String> {
    let err = |what: &str, e: windows::core::Error| format!("{what}: {e}");
    // SAFETY: plain queries on a live sample.
    let buffer: IMFMediaBuffer = unsafe {
        match sample.GetBufferCount() {
            Ok(1) => sample.GetBufferByIndex(0),
            _ => sample.ConvertToContiguousBuffer(),
        }
    }
    .map_err(|e| err("cannot get the sample buffer", e))?;

    if let Ok(buffer_2d) = buffer.cast::<IMF2DBuffer2>() {
        let lock = Locked2D::lock(&buffer_2d).map_err(|e| err("Lock2DSize failed", e))?;
        let layout = Nv12Layout::new(format.width, format.height, lock.pitch, lock.available)?;
        let data = layout.copy(lock.bytes());
        Ok((
            data,
            format!("IMF2DBuffer2, {layout}, {} bytes", lock.available),
        ))
    } else {
        let lock = Locked1D::lock(&buffer).map_err(|e| err("IMFMediaBuffer::Lock failed", e))?;
        let pitch = format.default_stride.unwrap_or(format.width as i32);
        let layout = Nv12Layout::new(format.width, format.height, pitch, lock.len)?;
        let data = layout.copy(lock.bytes());
        Ok((
            data,
            format!("contiguous buffer, {layout}, {} bytes", lock.len),
        ))
    }
}

/// A 2D buffer locked for reading; unlocked on drop.
struct Locked2D<'a> {
    buffer: &'a IMF2DBuffer2,
    scanline0: *const u8,
    pitch: i32,
    /// Bytes from scanline 0 to the end of the buffer (0 for bottom-up
    /// images, which Nv12Layout rejects).
    available: usize,
}

impl<'a> Locked2D<'a> {
    fn lock(buffer: &'a IMF2DBuffer2) -> windows::core::Result<Self> {
        let mut scanline0 = std::ptr::null_mut();
        let mut pitch = 0;
        let mut start = std::ptr::null_mut();
        let mut len = 0u32;
        // SAFETY: valid out-pointers. On success the buffer stays locked,
        // and the pointers valid, until Unlock2D in Drop.
        unsafe {
            buffer.Lock2DSize(
                MF2DBuffer_LockFlags_Read,
                &mut scanline0,
                &mut pitch,
                &mut start,
                &mut len,
            )
        }?;
        let available = if pitch > 0 {
            (scanline0 as usize)
                .checked_sub(start as usize)
                .and_then(|offset| (len as usize).checked_sub(offset))
                .unwrap_or(0)
        } else {
            0
        };
        Ok(Self {
            buffer,
            scanline0,
            pitch,
            available,
        })
    }

    fn bytes(&self) -> &[u8] {
        if self.available == 0 {
            return &[];
        }
        // SAFETY: while locked, [scanline0, scanline0 + available) lies
        // inside the buffer [start, start + len) that Lock2DSize returned
        // (checked in `lock`), and a read lock means nobody writes to it.
        unsafe { std::slice::from_raw_parts(self.scanline0, self.available) }
    }
}

impl Drop for Locked2D<'_> {
    fn drop(&mut self) {
        // SAFETY: balances the successful Lock2DSize in `lock`.
        if let Err(err) = unsafe { self.buffer.Unlock2D() } {
            tracing::warn!(%err, "Unlock2D failed");
        }
    }
}

/// A contiguous media buffer locked for reading; unlocked on drop.
struct Locked1D<'a> {
    buffer: &'a IMFMediaBuffer,
    data: *const u8,
    len: usize,
}

impl<'a> Locked1D<'a> {
    fn lock(buffer: &'a IMFMediaBuffer) -> windows::core::Result<Self> {
        let mut data = std::ptr::null_mut();
        let mut len = 0u32;
        // SAFETY: valid out-pointers. On success `data` points at `len`
        // valid bytes until Unlock in Drop.
        unsafe { buffer.Lock(&mut data, None, Some(&mut len)) }?;
        Ok(Self {
            buffer,
            data,
            len: len as usize,
        })
    }

    fn bytes(&self) -> &[u8] {
        if self.len == 0 || self.data.is_null() {
            return &[];
        }
        // SAFETY: Lock returned `len` valid bytes at `data`, valid until
        // Unlock (Drop).
        unsafe { std::slice::from_raw_parts(self.data, self.len) }
    }
}

impl Drop for Locked1D<'_> {
    fn drop(&mut self) {
        // SAFETY: balances the successful Lock in `lock`.
        if let Err(err) = unsafe { self.buffer.Unlock() } {
            tracing::warn!(%err, "IMFMediaBuffer::Unlock failed");
        }
    }
}

/// Where the planes of an NV12 image lie in a locked buffer, counted from
/// scanline 0.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Nv12Layout {
    width: usize,
    height: usize,
    /// Bytes from one row to the next, the same in both planes.
    pitch: usize,
    /// Offset of the CbCr plane from scanline 0.
    chroma_offset: usize,
}

impl Nv12Layout {
    /// `available`: bytes from scanline 0 to the end of the buffer.
    ///
    /// The CbCr plane follows the Y plane. Decoders often allocate more Y
    /// rows than the visible height (1088 for 1080) and put CbCr after all
    /// of them. That padded row count is derived from the buffer size when
    /// the buffer holds exactly such a layout; otherwise CbCr is assumed to
    /// start right after the visible rows.
    fn new(width: u32, height: u32, pitch: i32, available: usize) -> Result<Self, String> {
        let (w, h) = (width as usize, height as usize);
        if w == 0 || h == 0 || !w.is_multiple_of(2) || !h.is_multiple_of(2) {
            return Err(format!("invalid NV12 size {w}x{h}"));
        }
        let pitch = usize::try_from(pitch)
            .ok()
            .filter(|&p| p > 0)
            .ok_or_else(|| format!("pitch {pitch}: bottom-up NV12 is not supported"))?;
        if pitch < w {
            return Err(format!("pitch {pitch} is smaller than the width {w}"));
        }
        let padded_rows = available * 2 / (pitch * 3);
        let rows = if padded_rows > h
            && padded_rows.is_multiple_of(2)
            && padded_rows - h <= MAX_ROW_PADDING
            && padded_rows * pitch * 3 / 2 == available
        {
            padded_rows
        } else {
            h
        };
        let chroma_offset = rows * pitch;
        let needed = chroma_offset + (h / 2 - 1) * pitch + w;
        if needed > available {
            return Err(format!(
                "buffer too small: {available} bytes, NV12 {w}x{h} with pitch {pitch} needs {needed}"
            ));
        }
        Ok(Self {
            width: w,
            height: h,
            pitch,
            chroma_offset,
        })
    }

    /// Copies the visible image out of `src` into dense planes. `src` must be
    /// at least the `available` bytes the layout was built for.
    fn copy(&self, src: &[u8]) -> Vec<u8> {
        let (w, h, pitch) = (self.width, self.height, self.pitch);
        if pitch == w && self.chroma_offset == w * h {
            return src[..w * h * 3 / 2].to_vec();
        }
        let mut out = Vec::with_capacity(w * h * 3 / 2);
        for row in 0..h {
            let start = row * pitch;
            out.extend_from_slice(&src[start..start + w]);
        }
        for row in 0..h / 2 {
            let start = self.chroma_offset + row * pitch;
            out.extend_from_slice(&src[start..start + w]);
        }
        out
    }
}

impl std::fmt::Display for Nv12Layout {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "pitch {} bytes, CbCr plane at byte {} ({} luma rows allocated)",
            self.pitch,
            self.chroma_offset,
            self.chroma_offset / self.pitch
        )
    }
}

/// Turns device timestamps into sequence numbers, so frames the device did
/// not deliver show up as gaps (`DROPS SOURCE` in the overlay).
struct SequenceClock {
    /// Frame period in 100 ns units.
    period: f64,
    last: Option<i64>,
    sequence: u64,
}

impl SequenceClock {
    fn new(rate: FrameRate) -> Self {
        Self {
            period: 10_000_000.0 * f64::from(rate.denominator) / f64::from(rate.numerator),
            last: None,
            sequence: 0,
        }
    }

    /// Sequence number for a frame with this timestamp. A step of up to 1.5
    /// periods is the next frame (jitter); longer steps skip numbers. Jumps
    /// beyond [`MAX_GAP_100NS`] or backwards are discontinuities and count
    /// as one step.
    fn next(&mut self, timestamp: i64) -> u64 {
        if let Some(last) = self.last {
            let delta = timestamp - last;
            let steps = if delta <= 0 || delta > MAX_GAP_100NS {
                if delta != 0 {
                    tracing::debug!(delta_100ns = delta, "timestamp discontinuity");
                }
                1
            } else {
                ((delta as f64 / self.period).round() as u64).max(1)
            };
            self.sequence += steps;
        }
        self.last = Some(timestamp);
        self.sequence
    }
}

fn hns_to_duration(value: i64) -> Duration {
    Duration::from_nanos(u64::try_from(value).unwrap_or(0).saturating_mul(100))
}

fn device_error(context: &str, err: &windows::core::Error) -> SourceError {
    let code = err.code();
    let hint = if code == MF_E_VIDEO_RECORDING_DEVICE_INVALIDATED {
        " (device unplugged or disabled?)"
    } else if code == MF_E_VIDEO_RECORDING_DEVICE_PREEMPTED {
        " (another app took over the device)"
    } else if code == MF_E_HW_MFT_FAILED_START_STREAMING {
        " (device busy? close other apps that use it, e.g. OBS or the Camera app)"
    } else if code == E_ACCESSDENIED {
        " (camera access blocked? Windows Settings > Privacy & security > Camera > let desktop apps access your camera)"
    } else {
        ""
    };
    SourceError::Device(format!("{context}: {err}{hint}"))
}

impl From<windows::core::Error> for SourceError {
    fn from(err: windows::core::Error) -> Self {
        device_error("Media Foundation", &err)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn nv12(w: u32, h: u32, pitch: i32, available: usize) -> Result<Nv12Layout, String> {
        Nv12Layout::new(w, h, pitch, available)
    }

    #[test]
    fn tight_layout() {
        let layout = nv12(1920, 1080, 1920, 1920 * 1080 * 3 / 2).unwrap();
        assert_eq!(layout.chroma_offset, 1920 * 1080);
    }

    #[test]
    fn padded_rows_are_detected_from_the_buffer_size() {
        // Decoder output allocated for 1088 rows.
        let layout = nv12(1920, 1080, 1920, 1920 * 1088 * 3 / 2).unwrap();
        assert_eq!(layout.chroma_offset, 1920 * 1088);
    }

    #[test]
    fn trailing_bytes_without_a_padded_layout_keep_the_visible_rows() {
        let layout = nv12(1920, 1080, 1920, 1920 * 1080 * 3 / 2 + 100).unwrap();
        assert_eq!(layout.chroma_offset, 1920 * 1080);
    }

    #[test]
    fn invalid_layouts_are_rejected() {
        assert!(nv12(1920, 1080, -1920, 1920 * 1080 * 3 / 2).is_err());
        assert!(nv12(1920, 1080, 1900, 1920 * 1080 * 3 / 2).is_err());
        assert!(nv12(1920, 1080, 1920, 1920 * 1080).is_err());
        assert!(nv12(1921, 1080, 2048, 2048 * 1080 * 3 / 2).is_err());
    }

    #[test]
    fn copy_removes_pitch_and_padding() {
        // 4x2 image, pitch 6, Y plane allocated with 4 rows (2 padding rows).
        let (w, h, pitch, rows) = (4usize, 2usize, 6usize, 4usize);
        let mut src = vec![0xEEu8; pitch * rows * 3 / 2];
        for y in 0..h {
            for x in 0..w {
                src[y * pitch + x] = (10 * y + x) as u8;
            }
        }
        for x in 0..w {
            src[rows * pitch + x] = 100 + x as u8;
        }
        let layout = nv12(w as u32, h as u32, pitch as i32, src.len()).unwrap();
        assert_eq!(layout.chroma_offset, rows * pitch);
        assert_eq!(
            layout.copy(&src),
            vec![0, 1, 2, 3, 10, 11, 12, 13, 100, 101, 102, 103]
        );
    }

    #[test]
    fn sequence_clock_counts_gaps() {
        let mut clock = SequenceClock::new(FrameRate::new(60, 1).unwrap());
        let period = 166_667i64;
        assert_eq!(clock.next(1_000_000), 0);
        assert_eq!(clock.next(1_000_000 + period), 1);
        // Jitter of a third of a period is still the next frame.
        assert_eq!(clock.next(1_000_000 + 2 * period + period / 3), 2);
        // Two periods later: one frame missing.
        assert_eq!(clock.next(1_000_000 + 4 * period + period / 3), 4);
        // Backwards and huge jumps count as one step.
        assert_eq!(clock.next(0), 5);
        assert_eq!(clock.next(60 * 10_000_000), 6);
    }

    #[test]
    fn colour_space_from_media_type_values() {
        let bt709 = MFVideoTransferMatrix_BT709.0 as u32;
        let bt601 = MFVideoTransferMatrix_BT601.0 as u32;
        let full = MFNominalRange_0_255.0 as u32;
        let limited = MFNominalRange_16_235.0 as u32;
        assert_eq!(
            color_space(Some(bt709), Some(limited), 1080),
            (ColorSpace::BT709_LIMITED, true)
        );
        assert_eq!(
            color_space(Some(bt601), Some(full), 1080),
            (
                ColorSpace {
                    matrix: YuvMatrix::Bt601,
                    range: YuvRange::Full
                },
                true
            )
        );
        // Not reported: BT.709 for HD, BT.601 for SD, limited range.
        assert_eq!(
            color_space(None, None, 1080),
            (ColorSpace::BT709_LIMITED, false)
        );
        assert_eq!(
            color_space(None, Some(full), 480).0.matrix,
            YuvMatrix::Bt601
        );
    }

    fn info(subtype: windows::core::GUID, w: u32, h: u32, fps: u32) -> MediaTypeInfo {
        MediaTypeInfo {
            subtype: Some(subtype),
            frame_size: Some((w, h)),
            frame_rate: Some((fps, 1)),
        }
    }

    #[test]
    fn native_type_selection() {
        use windows::Win32::Media::MediaFoundation::MFVideoFormat_MJPG;
        let types = [
            info(MFVideoFormat_NV12, 1920, 1080, 60),
            info(MFVideoFormat_MJPG, 1920, 1080, 60),
            info(MFVideoFormat_NV12, 1920, 1080, 50),
        ];
        let mode = |w, h, fps| {
            ModeSelector::Match(VideoMode {
                width: w,
                height: h,
                format: PixelFormat::Nv12,
                frame_rate: FrameRate::new(fps, 1).unwrap(),
            })
        };
        assert_eq!(
            match_native_type(&types, &mode(1920, 1080, 60), false),
            Ok(0)
        );
        assert_eq!(
            match_native_type(&types, &mode(1920, 1080, 50), false),
            Ok(2)
        );
        assert_eq!(
            match_native_type(&types, &ModeSelector::Index(2), false),
            Ok(2)
        );
        let err = match_native_type(&types, &mode(1280, 720, 60), false).unwrap_err();
        assert!(
            err.contains("#0 1920x1080@60") && err.contains("#2 1920x1080@50"),
            "{err}"
        );
        let err = match_native_type(&types, &ModeSelector::Index(1), false).unwrap_err();
        assert!(err.contains("MJPG"), "{err}");
        assert!(match_native_type(&types, &ModeSelector::Index(3), false).is_err());
        // Count-only probe: any reported type by index.
        assert_eq!(
            match_native_type(&types, &ModeSelector::Index(1), true),
            Ok(1)
        );
    }

    #[test]
    fn device_selection() {
        let devices = vec![
            (
                "UGREEN Camera 4K".to_string(),
                r"\\?\usb#vid_eba4&pid_6579".to_string(),
            ),
            (
                "C505 HD Webcam".to_string(),
                r"\\?\usb#vid_046d&pid_08e3".to_string(),
            ),
            (
                "UGREEN 25854".to_string(),
                r"\\?\usb#vid_2b89&pid_5854".to_string(),
            ),
        ];
        let name = |s: &str| DeviceSelector::Name(s.into());
        assert_eq!(match_device(&devices, &name("25854")), Ok(2));
        // A number that is no valid index is matched as text.
        assert_eq!(match_device(&devices, &DeviceSelector::Index(25854)), Ok(2));
        assert!(match_device(&devices, &DeviceSelector::Index(9)).is_err());
        // ... but only as a whole word: "C505" is no match for 505 or 50.
        assert!(match_device(&devices, &DeviceSelector::Index(505)).is_err());
        assert!(match_device(&devices, &DeviceSelector::Index(50)).is_err());
        assert_eq!(match_device(&devices, &name("c505")), Ok(1));
        assert_eq!(match_device(&devices, &name("VID_2B89")), Ok(2));
        assert_eq!(match_device(&devices, &DeviceSelector::Index(0)), Ok(0));
        assert!(
            match_device(&devices, &name("ugreen"))
                .unwrap_err()
                .contains("several")
        );
        assert!(match_device(&devices, &name("elgato")).is_err());
        assert!(match_device(&devices, &DeviceSelector::Index(3)).is_err());
    }
}
