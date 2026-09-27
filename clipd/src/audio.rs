//! Game sound, straight from the speakers.
//!
//! ffmpeg cannot record what Windows plays: DirectShow only offers
//! microphones, and there is no loopback device unless the sound card happens
//! to provide "Stereo Mix". So clipd taps WASAPI itself, in loopback mode on
//! the default playback device, and feeds raw samples into ffmpeg's stdin.
//!
//! Two things need care.
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

use anyhow::{Context, Result, anyhow, bail};
use std::io::Write;
use std::sync::mpsc;
use std::time::{Duration, Instant};

/// How long to wait for the sound device, and for ffmpeg to hand over its
/// pipe. Opening a virtual device can take a moment.
const HANDSHAKE: Duration = Duration::from_secs(10);

/// The raw stream the device delivers and ffmpeg has to be told about.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Format {
    pub rate: u32,
    pub channels: u16,
    pub bits: u16,
    pub float: bool,
    pub device: String,
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

    pub fn bytes_per_frame(&self) -> usize {
        self.bits as usize / 8 * self.channels as usize
    }

    pub fn bytes_per_sec(&self) -> u64 {
        self.bytes_per_frame() as u64 * self.rate as u64
    }

    /// How ffmpeg has to read the pipe.
    pub fn input_args(&self) -> Result<Vec<String>> {
        Ok(["-f", self.sample_fmt()?, "-ar", &self.rate.to_string(), "-ac", &self.channels.to_string()]
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

/// A sound device that is open and running, waiting for somewhere to put its
/// samples.
pub struct Audio {
    pub format: Format,
    sink: mpsc::Sender<std::process::ChildStdin>,
}

impl Audio {
    /// Hands ffmpeg's pipe to the capture, which starts writing immediately.
    pub fn attach(self, sink: std::process::ChildStdin) -> Result<()> {
        self.sink.send(sink).map_err(|_| anyhow!("Die Tonaufnahme ist nicht mehr da"))
    }
}

/// Opens a playback device for loopback and reports what it delivers. The
/// capture runs from here on, but throws its samples away until
/// [`Audio::attach`] gives it ffmpeg's pipe.
///
/// `want` picks the device by a part of its name; empty means the default
/// one. That choice matters: some virtual devices never return from
/// `IAudioClient::Initialize` in loopback mode, and `clipd audio` shows which
/// ones actually work.
#[cfg(windows)]
pub fn open(want: &str) -> Result<Audio> {
    open_within(want, HANDSHAKE)
}

#[cfg(windows)]
pub fn open_within(want: &str, timeout: Duration) -> Result<Audio> {
    let (info_tx, info_rx) = mpsc::channel();
    let (sink_tx, sink_rx) = mpsc::channel();
    let want = want.to_string();
    std::thread::Builder::new()
        .name("clipd-audio".into())
        .spawn(move || {
            if let Err(e) = capture(&want, &info_tx, sink_rx) {
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
        // real outcome and not just a slow start.
        Err(_) => Err(anyhow!("Das Gerät antwortet nicht (`clipd audio` zeigt, welche Geräte gehen)")),
    }
}

/// The playback devices Windows knows, with the default one first.
#[cfg(windows)]
pub fn devices() -> Result<Vec<String>> {
    // COM has to be set up on whatever thread asks, so this gets its own.
    std::thread::spawn(|| -> Result<Vec<String>> {
        use wasapi::Direction;
        wasapi::initialize_mta().ok().map_err(|e| anyhow!("COM lässt sich nicht starten: {e}"))?;
        let enumerator = wasapi::DeviceEnumerator::new().map_err(|e| anyhow!("Keine Geräteliste: {e}"))?;
        let default = enumerator.get_default_device(&Direction::Render).ok().and_then(|d| d.get_friendlyname().ok());
        let collection =
            enumerator.get_device_collection(&Direction::Render).map_err(|e| anyhow!("Keine Geräteliste: {e}"))?;
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

#[cfg(windows)]
fn capture(
    want: &str,
    info: &mpsc::Sender<Result<Format, String>>,
    sink_rx: mpsc::Receiver<std::process::ChildStdin>,
) -> Result<()> {
    use wasapi::{Direction, SampleType, StreamMode};

    // COM belongs to this thread, and the capture never touches a window.
    wasapi::initialize_mta().ok().map_err(|e| anyhow!("COM lässt sich nicht starten: {e}"))?;
    let enumerator = wasapi::DeviceEnumerator::new().map_err(|e| anyhow!("Keine Geräteliste: {e}"))?;
    // A playback device opened for reading is what loopback means.
    let device = pick(&enumerator, want)?;
    let name = device.get_friendlyname().unwrap_or_else(|_| "Wiedergabegerät".into());
    let mut client = device.get_iaudioclient().map_err(|e| anyhow!("Gerät lässt sich nicht öffnen: {e}"))?;

    // The device's own format. Asking for a different one and letting WASAPI
    // convert is what hangs on some virtual devices.
    let mix = client.get_mixformat().map_err(|e| anyhow!("Kein Tonformat zu bekommen: {e}"))?;
    let format = Format {
        rate: mix.get_samplespersec(),
        channels: mix.get_nchannels(),
        bits: mix.get_bitspersample(),
        float: matches!(mix.get_subformat(), Ok(SampleType::Float)),
        device: name,
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
    let capture = client.get_audiocaptureclient().map_err(|e| anyhow!("Kein Aufnahmezugriff: {e}"))?;
    client.start_stream().map_err(|e| anyhow!("Der Mitschnitt startet nicht: {e}"))?;

    // From here on there is sound to be had; the caller may start ffmpeg.
    let _ = info.send(Ok(format.clone()));
    let mut sink = sink_rx.recv_timeout(HANDSHAKE).context("ffmpeg hat keine Eingabe für den Ton geliefert")?;

    let frame = format.bytes_per_frame();
    let per_sec = format.bytes_per_sec();
    let mut queue: std::collections::VecDeque<u8> = std::collections::VecDeque::new();
    let silence = vec![0u8; 8192 - 8192 % frame.max(1)];
    // Only now, so the wait for ffmpeg does not count as recorded time.
    let start = Instant::now();
    let mut written: u64 = 0;
    loop {
        while capture.get_next_packet_size().is_ok_and(|n| n.is_some_and(|n| n > 0)) {
            if capture.read_from_device_to_deque(&mut queue).is_err() {
                break;
            }
        }
        // Never hoard more than a moment; a backlog would only push the sound
        // further behind the picture.
        let cap = per_sec as usize / 2;
        if queue.len() > cap {
            let drop = queue.len() - cap;
            queue.drain(..drop - drop % frame);
        }

        let target = target_bytes(start.elapsed(), per_sec, frame);
        while written < target {
            let need = (target - written) as usize - (target - written) as usize % frame;
            if need == 0 {
                break;
            }
            let from_device = (queue.len() - queue.len() % frame).min(need);
            let n = if from_device > 0 {
                let chunk: Vec<u8> = queue.drain(..from_device).collect();
                sink.write_all(&chunk).context("ffmpeg nimmt keinen Ton mehr an")?;
                from_device
            } else {
                let fill = need.min(silence.len());
                sink.write_all(&silence[..fill]).context("ffmpeg nimmt keinen Ton mehr an")?;
                fill
            };
            written += n as u64;
        }
        sink.flush().context("ffmpeg nimmt keinen Ton mehr an")?;
        std::thread::sleep(Duration::from_millis(5));
    }
}

/// The device whose name contains `want`, or the default one when `want` is
/// empty.
#[cfg(windows)]
fn pick(enumerator: &wasapi::DeviceEnumerator, want: &str) -> Result<wasapi::Device> {
    use wasapi::Direction;
    if want.trim().is_empty() {
        return enumerator.get_default_device(&Direction::Render).map_err(|e| anyhow!("Kein Wiedergabegerät: {e}"));
    }
    let collection = enumerator.get_device_collection(&Direction::Render).map_err(|e| anyhow!("Keine Geräteliste: {e}"))?;
    let count = collection.get_nbr_devices().map_err(|e| anyhow!("Geräte nicht zählbar: {e}"))?;
    let needle = want.to_lowercase();
    (0..count)
        .filter_map(|i| collection.get_device_at_index(i).ok())
        .find(|d| d.get_friendlyname().is_ok_and(|n| n.to_lowercase().contains(&needle)))
        .ok_or_else(|| anyhow!("Kein Wiedergabegerät heißt so etwas wie {want:?}"))
}

#[cfg(not(windows))]
pub fn open(_want: &str) -> Result<Audio> {
    bail!("Ton nimmt clipd nur unter Windows auf")
}

#[cfg(not(windows))]
pub fn open_within(_want: &str, _timeout: Duration) -> Result<Audio> {
    bail!("Ton nimmt clipd nur unter Windows auf")
}

#[cfg(not(windows))]
pub fn devices() -> Result<Vec<String>> {
    bail!("Ton nimmt clipd nur unter Windows auf")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn stereo_float() -> Format {
        Format { rate: 48_000, channels: 2, bits: 32, float: true, device: "Test".into() }
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
    /// und fünf Kanälen, wo nichts glatt aufgeht.
    #[test]
    fn target_never_splits_a_frame() {
        let odd = Format { rate: 44_100, channels: 5, bits: 32, float: true, device: "Test".into() };
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
        let cd = Format { rate: 44_100, channels: 2, bits: 16, float: false, device: "Test".into() };
        assert_eq!(cd.input_args().unwrap(), ["-f", "s16le", "-ar", "44100", "-ac", "2"]);
    }

    /// Ein Format, das ffmpeg nicht lesen könnte, muss auffallen, bevor die
    /// Aufnahme läuft — sonst nimmt clipd stillschweigend Rauschen auf.
    #[test]
    fn strange_formats_are_rejected() {
        let odd = Format { rate: 48_000, channels: 2, bits: 24, float: false, device: "Test".into() };
        assert!(odd.sample_fmt().is_err());
        assert!(odd.input_args().is_err());
    }

    #[test]
    fn frame_size_follows_bits_and_channels() {
        assert_eq!(stereo_float().bytes_per_frame(), 8);
        let surround = Format { rate: 48_000, channels: 6, bits: 16, float: false, device: "T".into() };
        assert_eq!(surround.bytes_per_frame(), 12);
        assert_eq!(surround.bytes_per_sec(), 48_000 * 12);
    }
}
