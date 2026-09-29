//! Game sound, straight from the speakers, and the microphone beside it.
//!
//! ffmpeg cannot record what Windows plays: DirectShow only offers
//! microphones, and there is no loopback device unless the sound card happens
//! to provide "Stereo Mix". So clipd taps WASAPI itself, in loopback mode on
//! the default playback device, and feeds raw samples into ffmpeg's stdin.
//!
//! Three things need care.
//!
//! **The format is the device's, not ours.** Asking WASAPI to convert to a
//! fixed 48 kHz stereo float stream makes `IAudioClient::Initialize` hang on
//! some virtual devices (SteelSeries Sonar, for one). clipd therefore takes
//! the device's own mix format and tells ffmpeg to expect exactly that. Which
//! means the device has to be opened before ffmpeg starts — hence the
//! handshake in [`open`] and [`Audio::attach`].
//!
//! **Silence still has to be written.** WASAPI hands out nothing at all while
//! the device is idle, so simply forwarding what arrives would make the sound
//! track shorter than the picture and the two would drift apart. The writer
//! follows the clock, not the device: every tick it tops the stream up to the
//! number of samples that should exist by now, with silence if there is
//! nothing else.
//!
//! **The microphone shares the pipe.** ffmpeg has only one stdin, so the
//! microphone travels in the same raw stream as two extra channels behind the
//! game's, and ffmpeg splits them into a track of their own. The microphone is
//! opened in the game device's rate and sample format, which WASAPI converts
//! for a capture device without complaint, and one clock drives both — they
//! cannot drift apart from each other either.

use anyhow::{Context, Result, anyhow, bail};
use std::collections::VecDeque;
use std::io::Write;
use std::sync::mpsc;
use std::time::{Duration, Instant};

/// How long to wait for the sound device, and for ffmpeg to hand over its
/// pipe. Opening a virtual device can take a moment.
const HANDSHAKE: Duration = Duration::from_secs(10);

/// The raw stream the devices deliver and ffmpeg has to be told about: each
/// frame holds the game's channels, then the microphone's.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Format {
    pub rate: u32,
    /// The game's channels, as the playback device mixes them.
    pub channels: u16,
    pub bits: u16,
    pub float: bool,
    pub device: String,
    /// 2 with a microphone, 0 without.
    pub mic_channels: u16,
    pub mic_device: Option<String>,
}

impl Format {
    /// ffmpeg's name for these samples. Raw audio carries no header, so
    /// getting this wrong turns the sound track into noise.
    pub fn sample_fmt(&self) -> Result<&'static str> {
        Ok(match (self.float, self.bits) {
            (true, 32) => "f32le",
            (true, 64) => "f64le",
            (false, 16) => "s16le",
            (false, 32) => "s32le",
            _ => bail!("Unbekanntes Tonformat: {} bit {}", self.bits, if self.float { "Gleitkomma" } else { "ganzzahlig" }),
        })
    }

    pub fn game_frame(&self) -> usize {
        self.bits as usize / 8 * self.channels as usize
    }

    pub fn mic_frame(&self) -> usize {
        self.bits as usize / 8 * self.mic_channels as usize
    }

    pub fn bytes_per_frame(&self) -> usize {
        self.game_frame() + self.mic_frame()
    }

    pub fn bytes_per_sec(&self) -> u64 {
        self.bytes_per_frame() as u64 * self.rate as u64
    }

    /// How ffmpeg has to read the pipe.
    pub fn input_args(&self) -> Result<Vec<String>> {
        let channels = (self.channels + self.mic_channels).to_string();
        Ok(["-f", self.sample_fmt()?, "-ar", &self.rate.to_string(), "-ac", &channels]
            .iter()
            .map(|s| s.to_string())
            .collect())
    }

    pub fn describe(&self) -> String {
        format!("{} ({} Hz, {} Kanäle)", self.device, self.rate, self.channels)
    }
}

/// Number of bytes that should have been written after `elapsed`, rounded down
/// to a whole frame so a sample never gets cut in half.
pub fn target_bytes(elapsed: Duration, bytes_per_sec: u64, bytes_per_frame: usize) -> u64 {
    let raw = (elapsed.as_nanos() * bytes_per_sec as u128 / 1_000_000_000) as u64;
    raw - raw % bytes_per_frame as u64
}

/// Builds `frames` frames of the shared stream: the game's part from `game`,
/// the microphone's from `mic`, silence wherever a device has nothing yet.
pub fn interleave(frames: usize, game: &mut VecDeque<u8>, g: usize, mic: &mut VecDeque<u8>, m: usize) -> Vec<u8> {
    let mut out = Vec::with_capacity(frames * (g + m));
    let take_game = frames.min(game.len() / g.max(1)) * g;
    let take_mic = frames.min(mic.len().checked_div(m).unwrap_or(0)) * m;
    // In one piece, so whole frames are copied as slices rather than byte by
    // byte; this runs 200 times a second.
    let (gs, ms) = (&game.make_contiguous()[..take_game], &mic.make_contiguous()[..take_mic]);
    if m == 0 {
        out.extend_from_slice(gs);
        out.resize(frames * g, 0);
    } else {
        for i in 0..frames {
            for (from, n) in [(gs, g), (ms, m)] {
                match from.get(i * n..(i + 1) * n) {
                    Some(frame) => out.extend_from_slice(frame),
                    None => out.resize(out.len() + n, 0),
                }
            }
        }
    }
    game.drain(..take_game);
    mic.drain(..take_mic);
    out
}

/// Keeps at most half a second in a queue; a backlog would only push the
/// sound further behind the picture.
fn cap(queue: &mut VecDeque<u8>, frame: usize, rate: u32) {
    let limit = rate as usize / 2 * frame;
    if frame > 0 && queue.len() > limit {
        let drop = queue.len() - limit;
        queue.drain(..drop - drop % frame);
    }
}

/// When the picture began: ffmpeg's first keyframe arrived at `at`, and it
/// was captured `lead` earlier.
pub type PictureStart = std::sync::Arc<std::sync::OnceLock<Instant>>;

/// Sound devices that are open and running, waiting for somewhere to put their
/// samples.
pub struct Audio {
    pub format: Format,
    sink: mpsc::Sender<(std::process::ChildStdin, PictureStart, Duration)>,
}

impl Audio {
    /// Hands ffmpeg's pipe to the capture, which starts writing immediately.
    ///
    /// ffmpeg starts the sound and the picture each at 0, but the sound flows
    /// from the moment the pipe opens while the first picture takes a few
    /// hundred milliseconds to set up the capture. Left alone, everything
    /// after would be off by that much. So once `picture` knows when the first
    /// keyframe came out (captured about `lead` before), the writer moves the
    /// start of its clock there and drops the sound that came before it.
    pub fn attach(self, sink: std::process::ChildStdin, picture: PictureStart, lead: Duration) -> Result<()> {
        self.sink.send((sink, picture, lead)).map_err(|_| anyhow!("Die Tonaufnahme ist nicht mehr da"))
    }
}

/// Where the sound's clock has to start so that it lines up with the
/// picture: the first frame's capture time, never earlier than the sound's
/// own start.
pub fn aligned_start(sound: Instant, keyframe_seen: Instant, lead: Duration) -> Instant {
    keyframe_seen.checked_sub(lead).unwrap_or(keyframe_seen).max(sound)
}

/// Opens a playback device for loopback, and a microphone if `mic` names one
/// (empty: the default microphone), and reports what they deliver. The capture
/// runs from here on, but throws its samples away until [`Audio::attach`]
/// gives it ffmpeg's pipe.
///
/// `want` picks the playback device by a part of its name; empty means the
/// default one. That choice matters: some virtual devices never return from
/// `IAudioClient::Initialize` in loopback mode, and `clipd audio` shows which
/// ones actually work. A microphone that fails only costs the microphone.
#[cfg(windows)]
pub fn open(want: &str, mic: Option<&str>) -> Result<Audio> {
    open_within(want, mic, HANDSHAKE)
}

#[cfg(windows)]
pub fn open_within(want: &str, mic: Option<&str>, timeout: Duration) -> Result<Audio> {
    let (info_tx, info_rx) = mpsc::channel();
    let (sink_tx, sink_rx) = mpsc::channel();
    let want = want.to_string();
    let mic = mic.map(str::to_string);
    std::thread::Builder::new()
        .name("clipd-audio".into())
        .spawn(move || {
            if let Err(e) = capture(&want, mic.as_deref(), &info_tx, sink_rx) {
                // If the handshake already went through, nobody is listening
                // any more and the message only belongs on the console.
                if info_tx.send(Err(format!("{e:#}"))).is_err() {
                    eprintln!("clipd: Der Ton ist ausgefallen: {e:#}");
                }
            }
        })
        .context("Der Ton-Thread lässt sich nicht starten")?;
    match info_rx.recv_timeout(timeout) {
        Ok(Ok(format)) => Ok(Audio { format, sink: sink_tx }),
        Ok(Err(e)) => Err(anyhow!(e)),
        // Initialize can hang for good on some virtual devices, so this is a
        // real outcome and not just a slow start. A virus scanner looks just
        // the same: Kaspersky holds Initialize until someone answers its
        // prompt, and every new build is a new program to ask about.
        Err(_) => Err(anyhow!(
            "Das Gerät antwortet nicht — hält ein Virenscanner den Zugriff an? (`clipd audio` zeigt, welche Geräte gehen)"
        )),
    }
}

/// The playback devices Windows knows, with the default one first.
#[cfg(windows)]
pub fn devices() -> Result<Vec<String>> {
    list(wasapi::Direction::Render)
}

/// The microphones Windows knows, with the default one first.
#[cfg(windows)]
pub fn microphones() -> Result<Vec<String>> {
    list(wasapi::Direction::Capture)
}

#[cfg(windows)]
fn list(direction: wasapi::Direction) -> Result<Vec<String>> {
    // COM has to be set up on whatever thread asks, so this gets its own.
    std::thread::spawn(move || -> Result<Vec<String>> {
        wasapi::initialize_mta().ok().map_err(|e| anyhow!("COM lässt sich nicht starten: {e}"))?;
        let enumerator = wasapi::DeviceEnumerator::new().map_err(|e| anyhow!("Keine Geräteliste: {e}"))?;
        let default = enumerator.get_default_device(&direction).ok().and_then(|d| d.get_friendlyname().ok());
        let collection = enumerator.get_device_collection(&direction).map_err(|e| anyhow!("Keine Geräteliste: {e}"))?;
        let count = collection.get_nbr_devices().map_err(|e| anyhow!("Geräte nicht zählbar: {e}"))?;
        let mut names: Vec<String> =
            (0..count).filter_map(|i| collection.get_device_at_index(i).ok()?.get_friendlyname().ok()).collect();
        if let Some(d) = default {
            names.sort_by_key(|n| *n != d);
        }
        Ok(names)
    })
    .join()
    .map_err(|_| anyhow!("Die Geräteliste ist abgestürzt"))?
}

/// Volume and mute of the default playback device. Loopback taps the sound
/// behind the volume control, so at 0 % or muted every clip is silent.
#[cfg(windows)]
pub fn playback_volume() -> Option<(f32, bool)> {
    use windows::Win32::Media::Audio::Endpoints::IAudioEndpointVolume;
    use windows::Win32::Media::Audio::{IMMDeviceEnumerator, MMDeviceEnumerator, eConsole, eRender};
    use windows::Win32::System::Com::{CLSCTX_ALL, COINIT_MULTITHREADED, CoCreateInstance, CoInitializeEx};
    std::thread::spawn(|| {
        // SAFETY: COM is set up on this thread before any interface is used,
        // and every interface stays on it.
        unsafe {
            let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
            let e: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL).ok()?;
            let device = e.GetDefaultAudioEndpoint(eRender, eConsole).ok()?;
            let volume: IAudioEndpointVolume = device.Activate(CLSCTX_ALL, None).ok()?;
            Some((volume.GetMasterVolumeLevelScalar().ok()?, volume.GetMute().ok()?.as_bool()))
        }
    })
    .join()
    .ok()?
}

/// Why every clip would be silent right now, if it would: loopback records
/// behind the volume control of the default playback device.
pub fn silence_warning() -> Option<String> {
    match playback_volume()? {
        (_, true) => Some("Der Ton ist stumm geschaltet — die Clips werden stumm.".into()),
        (level, _) if level <= 0.0 => Some("Die Lautstärke steht auf 0 % — die Clips werden stumm.".into()),
        _ => None,
    }
}

/// A device that is open and delivering, kept together so neither half is
/// dropped while the other is still in use.
#[cfg(windows)]
struct Open {
    _client: wasapi::AudioClient,
    capture: wasapi::AudioCaptureClient,
}

#[cfg(windows)]
impl Open {
    /// Moves whatever the device has into `queue`.
    fn drain_into(&self, queue: &mut VecDeque<u8>) {
        while self.capture.get_next_packet_size().is_ok_and(|n| n.is_some_and(|n| n > 0)) {
            if self.capture.read_from_device_to_deque(queue).is_err() {
                break;
            }
        }
    }
}

#[cfg(windows)]
fn capture(
    want: &str,
    mic: Option<&str>,
    info: &mpsc::Sender<Result<Format, String>>,
    sink_rx: mpsc::Receiver<(std::process::ChildStdin, PictureStart, Duration)>,
) -> Result<()> {
    use wasapi::{Direction, SampleType, StreamMode};

    // COM belongs to this thread, and the capture never touches a window.
    wasapi::initialize_mta().ok().map_err(|e| anyhow!("COM lässt sich nicht starten: {e}"))?;
    let enumerator = wasapi::DeviceEnumerator::new().map_err(|e| anyhow!("Keine Geräteliste: {e}"))?;
    // A playback device opened for reading is what loopback means.
    let device = pick(&enumerator, want, Direction::Render)?;
    let name = device.get_friendlyname().unwrap_or_else(|_| "Wiedergabegerät".into());
    let mut client = device.get_iaudioclient().map_err(|e| anyhow!("Gerät lässt sich nicht öffnen: {e}"))?;

    // The device's own format. Asking for a different one and letting WASAPI
    // convert is what hangs on some virtual devices.
    let mix = client.get_mixformat().map_err(|e| anyhow!("Kein Tonformat zu bekommen: {e}"))?;
    let sample_type = mix.get_subformat().map_err(|e| anyhow!("Unbekanntes Tonformat: {e}"))?;
    let mut format = Format {
        rate: mix.get_samplespersec(),
        channels: mix.get_nchannels(),
        bits: mix.get_bitspersample(),
        float: matches!(sample_type, SampleType::Float),
        device: name,
        mic_channels: 0,
        mic_device: None,
    };
    // Fails early for a format ffmpeg could not read anyway.
    format.sample_fmt()?;

    // Polling, not events: in loopback an idle device never signals the event,
    // and the writer below has its own clock anyway. A buffer duration of 0
    // leaves the size to the audio engine, which is what it copes with best.
    let mode = StreamMode::PollingShared { autoconvert: false, buffer_duration_hns: 0 };
    client
        .initialize_client(&mix, &Direction::Capture, &mode)
        .map_err(|e| anyhow!("Mitschnitt lässt sich nicht einrichten: {e}"))?;
    let game_capture = client.get_audiocaptureclient().map_err(|e| anyhow!("Kein Aufnahmezugriff: {e}"))?;
    client.start_stream().map_err(|e| anyhow!("Der Mitschnitt startet nicht: {e}"))?;
    let game = Open { _client: client, capture: game_capture };

    let microphone = match mic {
        None => None,
        Some(want) => match open_mic(&enumerator, want, &format, &sample_type) {
            Ok((open, name)) => {
                format.mic_channels = 2;
                format.mic_device = Some(name);
                Some(open)
            }
            Err(e) => {
                eprintln!("clipd: Aufnahme ohne Mikrofon — {e:#}");
                None
            }
        },
    };

    // From here on there is sound to be had; the caller may start ffmpeg.
    let _ = info.send(Ok(format.clone()));
    let (mut sink, picture, lead) = match sink_rx.recv_timeout(HANDSHAKE) {
        Ok(handed) => handed,
        // Whoever opened the device only wanted to know that it works
        // (`clipd audio`) and has let go of it again.
        Err(mpsc::RecvTimeoutError::Disconnected) => return Ok(()),
        Err(mpsc::RecvTimeoutError::Timeout) => bail!("ffmpeg hat keine Eingabe für den Ton geliefert"),
    };

    let (g, m, frame) = (format.game_frame(), format.mic_frame(), format.bytes_per_frame());
    let per_sec = format.bytes_per_sec();
    let (mut game_q, mut mic_q) = (VecDeque::new(), VecDeque::new());
    // Only now, so the wait for ffmpeg does not count as recorded time.
    let mut start = Instant::now();
    let mut aligned = false;
    let mut written: u64 = 0;
    loop {
        game.drain_into(&mut game_q);
        if let Some(mic) = &microphone {
            mic.drain_into(&mut mic_q);
        }
        cap(&mut game_q, g, format.rate);
        cap(&mut mic_q, m, format.rate);

        if !aligned && let Some(&seen) = picture.get() {
            start = aligned_start(start, seen, lead);
            aligned = true;
        }
        let target = target_bytes(start.elapsed(), per_sec, frame);
        // Ahead of the clock (just after lining up with the picture): what
        // the devices deliver meanwhile has no picture to go with, and kept
        // it would put the sound behind for good.
        if written > target + per_sec / 100 {
            game_q.clear();
            mic_q.clear();
        }
        if written < target {
            let chunk = interleave(((target - written) / frame as u64) as usize, &mut game_q, g, &mut mic_q, m);
            // A closed pipe means ffmpeg has ended, which whoever watches
            // ffmpeg reports; there is nothing to add here.
            if sink.write_all(&chunk).and_then(|_| sink.flush()).is_err() {
                return Ok(());
            }
            written += chunk.len() as u64;
        }
        std::thread::sleep(Duration::from_millis(5));
    }
}

/// Opens a microphone in the game device's rate and sample format, stereo.
/// Unlike loopback, a capture device converts without trouble.
#[cfg(windows)]
fn open_mic(
    enumerator: &wasapi::DeviceEnumerator,
    want: &str,
    game: &Format,
    sample_type: &wasapi::SampleType,
) -> Result<(Open, String)> {
    use wasapi::{Direction, StreamMode, WaveFormat};
    let device = pick(enumerator, want, Direction::Capture)?;
    let name = device.get_friendlyname().unwrap_or_else(|_| "Mikrofon".into());
    let mut client = device.get_iaudioclient().map_err(|e| anyhow!("Mikrofon lässt sich nicht öffnen: {e}"))?;
    let bits = game.bits as usize;
    let wanted = WaveFormat::new(bits, bits, sample_type, game.rate as usize, 2, None);
    let mode = StreamMode::PollingShared { autoconvert: true, buffer_duration_hns: 0 };
    client
        .initialize_client(&wanted, &Direction::Capture, &mode)
        .map_err(|e| anyhow!("Mikrofon lässt sich nicht einrichten: {e}"))?;
    let capture = client.get_audiocaptureclient().map_err(|e| anyhow!("Kein Zugriff aufs Mikrofon: {e}"))?;
    client.start_stream().map_err(|e| anyhow!("Das Mikrofon startet nicht: {e}"))?;
    Ok((Open { _client: client, capture }, name))
}

/// The device whose name contains `want`, or the default one when `want` is
/// empty.
#[cfg(windows)]
fn pick(enumerator: &wasapi::DeviceEnumerator, want: &str, direction: wasapi::Direction) -> Result<wasapi::Device> {
    let kind = if direction == wasapi::Direction::Render { "Wiedergabegerät" } else { "Mikrofon" };
    if want.trim().is_empty() {
        return enumerator.get_default_device(&direction).map_err(|e| anyhow!("Kein {kind}: {e}"));
    }
    let collection = enumerator.get_device_collection(&direction).map_err(|e| anyhow!("Keine Geräteliste: {e}"))?;
    let count = collection.get_nbr_devices().map_err(|e| anyhow!("Geräte nicht zählbar: {e}"))?;
    let needle = want.to_lowercase();
    (0..count)
        .filter_map(|i| collection.get_device_at_index(i).ok())
        .find(|d| d.get_friendlyname().is_ok_and(|n| n.to_lowercase().contains(&needle)))
        .ok_or_else(|| anyhow!("Kein {kind} heißt so etwas wie {want:?}"))
}

#[cfg(not(windows))]
pub fn open(_want: &str, _mic: Option<&str>) -> Result<Audio> {
    bail!("Ton nimmt clipd nur unter Windows auf")
}

#[cfg(not(windows))]
pub fn open_within(_want: &str, _mic: Option<&str>, _timeout: Duration) -> Result<Audio> {
    bail!("Ton nimmt clipd nur unter Windows auf")
}

#[cfg(not(windows))]
pub fn devices() -> Result<Vec<String>> {
    bail!("Ton nimmt clipd nur unter Windows auf")
}

#[cfg(not(windows))]
pub fn microphones() -> Result<Vec<String>> {
    bail!("Ton nimmt clipd nur unter Windows auf")
}

#[cfg(not(windows))]
pub fn playback_volume() -> Option<(f32, bool)> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn stereo_float() -> Format {
        Format { rate: 48_000, channels: 2, bits: 32, float: true, device: "Test".into(), mic_channels: 0, mic_device: None }
    }

    /// Der Ton muss echtzeitgenau nachgefüllt werden, sonst laufen Bild und
    /// Ton auseinander.
    #[test]
    fn target_follows_the_clock() {
        let f = stereo_float();
        let (ps, bf) = (f.bytes_per_sec(), f.bytes_per_frame());
        assert_eq!(ps, 48_000 * 8);
        assert_eq!(target_bytes(Duration::from_secs(1), ps, bf), ps);
        assert_eq!(target_bytes(Duration::ZERO, ps, bf), 0);
        assert_eq!(target_bytes(Duration::from_millis(500), ps, bf), ps / 2);
        assert_eq!(target_bytes(Duration::from_secs(30), ps, bf), 30 * ps);
    }

    /// Ein angeschnittenes Sample darf nie entstehen, auch nicht bei 44,1 kHz
    /// und fünf Kanälen plus Mikrofon, wo nichts glatt aufgeht.
    #[test]
    fn target_never_splits_a_frame() {
        let odd = Format { rate: 44_100, channels: 5, mic_channels: 2, ..stereo_float() };
        for f in [stereo_float(), odd] {
            let (ps, bf) = (f.bytes_per_sec(), f.bytes_per_frame());
            for ms in [1, 7, 13, 99, 1234, 5000] {
                let n = target_bytes(Duration::from_millis(ms), ps, bf);
                assert_eq!(n % bf as u64, 0, "{ms} ms ergibt {n} Bytes bei {bf} je Frame");
            }
        }
    }

    /// ffmpeg bekommt rohe Samples ohne Kopf und muss das Format genannt
    /// bekommen, sonst rauscht die Tonspur.
    #[test]
    fn tells_ffmpeg_the_device_format() {
        assert_eq!(stereo_float().input_args().unwrap(), ["-f", "f32le", "-ar", "48000", "-ac", "2"]);
        let cd = Format { rate: 44_100, bits: 16, float: false, ..stereo_float() };
        assert_eq!(cd.input_args().unwrap(), ["-f", "s16le", "-ar", "44100", "-ac", "2"]);
    }

    /// Mit Mikrofon trägt die Pipe dessen zwei Kanäle hinter denen des Spiels.
    #[test]
    fn the_microphone_adds_two_channels() {
        let f = Format { mic_channels: 2, ..stereo_float() };
        assert_eq!(f.input_args().unwrap(), ["-f", "f32le", "-ar", "48000", "-ac", "4"]);
        assert_eq!((f.game_frame(), f.mic_frame(), f.bytes_per_frame()), (8, 8, 16));
    }

    /// Ein Format, das ffmpeg nicht lesen könnte, muss auffallen, bevor die
    /// Aufnahme läuft — sonst nimmt clipd stillschweigend Rauschen auf.
    #[test]
    fn strange_formats_are_rejected() {
        let odd = Format { bits: 24, float: false, ..stereo_float() };
        assert!(odd.sample_fmt().is_err());
        assert!(odd.input_args().is_err());
    }

    #[test]
    fn frame_size_follows_bits_and_channels() {
        assert_eq!(stereo_float().bytes_per_frame(), 8);
        let surround = Format { channels: 6, bits: 16, float: false, ..stereo_float() };
        assert_eq!(surround.bytes_per_frame(), 12);
        assert_eq!(surround.bytes_per_sec(), 48_000 * 12);
    }

    /// Jeder Frame trägt erst das Spiel, dann das Mikrofon; wo ein Gerät
    /// nichts geliefert hat, steht Stille, und nichts verrutscht.
    #[test]
    fn interleaves_game_and_microphone() {
        let mut game: VecDeque<u8> = [1, 1, 2, 2, 3, 3].into_iter().collect();
        let mut mic: VecDeque<u8> = [9].into_iter().collect();
        let out = interleave(4, &mut game, 2, &mut mic, 1);
        assert_eq!(out, [1, 1, 9, 2, 2, 0, 3, 3, 0, 0, 0, 0]);
        assert!(game.is_empty() && mic.is_empty());
    }

    /// Ohne Mikrofon ist der Strom einfach der des Spiels.
    #[test]
    fn without_microphone_only_the_game() {
        let mut game: VecDeque<u8> = [1, 2, 3, 4, 5].into_iter().collect();
        let out = interleave(2, &mut game, 2, &mut VecDeque::new(), 0);
        assert_eq!(out, [1, 2, 3, 4]);
        assert_eq!(game.len(), 1, "ein halber Frame bleibt liegen");
    }

    /// Der Ton beginnt dort, wo das erste Bild aufgenommen wurde — nie vor
    /// dem eigenen Anfang.
    #[test]
    fn sound_starts_with_the_picture() {
        let sound = Instant::now();
        let seen = sound + Duration::from_millis(400);
        assert_eq!(aligned_start(sound, seen, Duration::from_millis(33)), seen - Duration::from_millis(33));
        assert_eq!(aligned_start(sound, sound + Duration::from_millis(10), Duration::from_millis(33)), sound);
    }

    /// Auch wenn die Warteschlange im Kreis herumläuft, kommen die Frames in
    /// der richtigen Reihenfolge heraus.
    #[test]
    fn interleaves_a_wrapped_queue() {
        let mut game: VecDeque<u8> = VecDeque::with_capacity(8);
        game.extend([0, 0, 0, 0, 0, 0]);
        game.drain(..6);
        game.extend([1, 1, 2, 2, 3]);
        let mut mic: VecDeque<u8> = [7, 8].into_iter().collect();
        let out = interleave(3, &mut game, 2, &mut mic, 1);
        assert_eq!(out, [1, 1, 7, 2, 2, 8, 0, 0, 0]);
        assert_eq!(game, [3], "ein halber Frame bleibt liegen");
        assert!(mic.is_empty());
    }

    /// Ein Rückstau wird gekappt, und zwar nur in ganzen Frames.
    #[test]
    fn cap_keeps_half_a_second_of_whole_frames() {
        let mut q: VecDeque<u8> = std::iter::repeat_n(0u8, 1000 * 8 + 3).collect();
        cap(&mut q, 8, 1000);
        assert!(q.len() <= 500 * 8 + 7);
        assert_eq!((1000 * 8 + 3 - q.len()) % 8, 0);
    }
}
