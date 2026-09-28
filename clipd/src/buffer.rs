//! The rolling buffer, in memory: ffmpeg writes one MPEG-TS stream to its
//! stdout, and clipd keeps the last minutes of it, cut at video keyframes.
//!
//! This used to be a ring of one-second files on disk. ffmpeg hands its file
//! output to the file system in blocks of 256 KiB, so the segment being
//! written was either empty or a quarter megabyte behind, and a clip ended up
//! to a second before the key press. Through a pipe the stream arrives in
//! small pieces as it is written, so a clip now reaches the key press.
//!
//! A slice of an MPEG-TS stream that starts at a keyframe is itself a valid
//! stream — PAT and PMT repeat every 0.1 s and the encoder repeats its headers
//! with every keyframe — so a clip is simply the newest few segments, end to
//! end, handed to ffmpeg to put into an MP4 without encoding anything.

use crate::config::Settings;
use crate::ffmpeg;
use anyhow::{Context, Result, bail};
use std::collections::VecDeque;
use std::io::{BufWriter, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Stdio};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::Duration;

pub const TS_PACKET: usize = 188;
/// ffmpeg's MPEG-TS muxer numbers the streams from 0x100, and the picture is
/// always mapped first.
pub const VIDEO_PID: u16 = 0x100;

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

fn pid(pkt: &[u8]) -> u16 {
    (u16::from(pkt[1] & 0x1f) << 8) | u16::from(pkt[2])
}

/// Whether `pkt` begins a video keyframe. ffmpeg marks those packets with the
/// random access indicator in the adaptation field.
pub fn is_keyframe(pkt: &[u8]) -> bool {
    pkt.len() >= 6
        && pkt[0] == 0x47
        && pid(pkt) == VIDEO_PID
        && pkt[1] & 0x40 != 0 // payload unit start
        && pkt[3] & 0x20 != 0 // adaptation field present
        && pkt[4] > 0
        && pkt[5] & 0x40 != 0 // random access indicator
}

/// The last minutes of the stream, one entry per keyframe interval.
pub struct Ring {
    state: Mutex<State>,
    /// When the first keyframe came out of ffmpeg; the sound lines up on it.
    pub first_keyframe: crate::audio::PictureStart,
    /// Finished segments to keep; the growing one comes on top.
    keep: usize,
}

#[derive(Default)]
struct State {
    /// Finished keyframe intervals, oldest first. Shared rather than copied,
    /// so saving a clip holds the lock for a moment only and the stream
    /// reader never waits.
    segments: VecDeque<Arc<Vec<u8>>>,
    /// The interval being written now; `None` before the first keyframe.
    current: Option<Vec<u8>>,
    /// The start of a packet whose end has not arrived yet.
    carry: Vec<u8>,
    recording: Option<Recording>,
}

/// A recording started by hand: everything from a keyframe on also goes into
/// a file, so it can outlast the ring.
struct Recording {
    path: PathBuf,
    file: BufWriter<std::fs::File>,
    failed: Option<std::io::Error>,
}

impl Ring {
    pub fn new(keep: usize) -> Self {
        Self { state: Mutex::new(State::default()), first_keyframe: Default::default(), keep: keep.max(1) }
    }

    /// Takes the next piece of ffmpeg's output, which may end mid-packet.
    pub fn push(&self, data: &[u8]) {
        let mut st = lock(&self.state);
        let st = &mut *st;
        let mut buf = std::mem::take(&mut st.carry);
        buf.extend_from_slice(data);
        let whole = buf.len() - buf.len() % TS_PACKET;
        for pkt in buf[..whole].as_chunks::<TS_PACKET>().0 {
            if pkt[0] != 0x47 {
                // ffmpeg writes whole packets, so this would be a bug
                // upstream; skipping keeps the ring usable.
                continue;
            }
            if is_keyframe(pkt) {
                let _ = self.first_keyframe.set(std::time::Instant::now());
                let size = st.current.as_ref().map_or(64 * 1024, |c| c.len() + c.len() / 4);
                if let Some(mut done) = st.current.replace(Vec::with_capacity(size)) {
                    // Growing by doubling leaves up to half of it unused;
                    // for the minutes a segment is kept that adds up.
                    done.shrink_to_fit();
                    st.segments.push_back(Arc::new(done));
                    while st.segments.len() > self.keep {
                        st.segments.pop_front();
                    }
                }
            }
            // Before the first keyframe nothing can be decoded, so nothing is kept.
            if let Some(current) = st.current.as_mut() {
                current.extend_from_slice(pkt);
            }
            if let Some(rec) = st.recording.as_mut().filter(|r| r.failed.is_none())
                && let Err(e) = rec.file.write_all(pkt)
            {
                rec.failed = Some(e);
            }
        }
        st.carry = buf[whole..].to_vec();
    }

    /// Whether a first keyframe has arrived.
    pub fn is_empty(&self) -> bool {
        lock(&self.state).current.is_none()
    }

    pub fn bytes(&self) -> usize {
        let st = lock(&self.state);
        st.segments.iter().map(|s| s.len()).sum::<usize>() + st.current.as_ref().map_or(0, Vec::len)
    }

    /// The newest `n` segments end to end — the last one reaching up to what
    /// ffmpeg wrote a moment ago. Only the growing segment is copied while
    /// the lock is held; the finished ones are shared and joined after.
    pub fn last(&self, n: usize) -> Vec<u8> {
        let (finished, current) = {
            let st = lock(&self.state);
            let Some(current) = st.current.clone() else { return Vec::new() };
            let from = st.segments.len().saturating_sub(n.saturating_sub(1));
            (st.segments.range(from..).cloned().collect::<Vec<_>>(), current)
        };
        let mut out = Vec::with_capacity(finished.iter().map(|s| s.len()).sum::<usize>() + current.len());
        for s in &finished {
            out.extend_from_slice(s);
        }
        out.extend_from_slice(&current);
        out
    }

    /// Starts copying the stream into `path`, beginning with the segment
    /// being written now, so at most one keyframe interval early.
    pub fn start_recording(&self, path: &Path) -> Result<()> {
        let mut st = lock(&self.state);
        if st.recording.is_some() {
            bail!("Es läuft schon eine Aufnahme");
        }
        let Some(current) = st.current.as_ref() else { bail!("Der Buffer ist noch leer") };
        let file = std::fs::File::create(path).with_context(|| format!("{} lässt sich nicht anlegen", path.display()))?;
        let mut file = BufWriter::with_capacity(1 << 20, file);
        file.write_all(current).with_context(|| format!("{} lässt sich nicht schreiben", path.display()))?;
        st.recording = Some(Recording { path: path.to_path_buf(), file, failed: None });
        Ok(())
    }

    /// Ends the recording and returns its file.
    pub fn stop_recording(&self) -> Result<PathBuf> {
        let Some(mut rec) = lock(&self.state).recording.take() else { bail!("Es läuft keine Aufnahme") };
        if let Some(e) = rec.failed.take() {
            bail!("Die Aufnahme ließ sich nicht schreiben: {e}");
        }
        rec.file.flush().with_context(|| format!("{} lässt sich nicht schreiben", rec.path.display()))?;
        Ok(rec.path)
    }

    pub fn is_recording(&self) -> bool {
        lock(&self.state).recording.is_some()
    }
}

pub struct Buffer {
    child: Child,
    pub ring: Arc<Ring>,
    /// The playback device the sound is taken from, if there is sound.
    pub audio_device: Option<String>,
    /// The microphone on the second sound track, if there is one.
    pub mic_device: Option<String>,
    /// ffmpeg's last complaints, for saying why it stopped.
    stderr: Arc<Mutex<VecDeque<String>>>,
    reader: Option<std::thread::JoinHandle<()>>,
}

impl Buffer {
    /// Starts the capture. If the sound cannot be opened, the recording
    /// carries on without it: a clip without sound still beats no clip at all.
    pub fn start(ffmpeg_bin: &Path, s: &Settings) -> Result<Self> {
        let dir = crate::config::buffer_dir();
        std::fs::create_dir_all(&dir).with_context(|| format!("{} lässt sich nicht anlegen", dir.display()))?;
        clear(&dir);
        let ring = Arc::new(Ring::new(s.ring_len()));
        if s.audio {
            match with_audio(ffmpeg_bin, s, &ring) {
                Ok((child, format)) => {
                    let (audio_device, mic_device) = (Some(format.describe()), format.mic_device.clone());
                    return Ok(Self::watch(child, ring, audio_device, mic_device));
                }
                Err(e) => eprintln!("clipd: Aufnahme ohne Ton — {e:#}"),
            }
        }
        let child = spawn(ffmpeg_bin, s, None)?.0;
        Ok(Self::watch(child, ring, None, None))
    }

    /// Feeds ffmpeg's stdout into the ring and keeps its last words.
    fn watch(mut child: Child, ring: Arc<Ring>, audio_device: Option<String>, mic_device: Option<String>) -> Self {
        let stderr = Arc::new(Mutex::new(VecDeque::new()));
        if let Some(err) = child.stderr.take() {
            let lines = stderr.clone();
            std::thread::spawn(move || {
                use std::io::BufRead;
                for line in std::io::BufReader::new(err).lines().map_while(Result::ok) {
                    eprintln!("{line}");
                    let mut l = lock(&lines);
                    l.push_back(line);
                    if l.len() > 6 {
                        l.pop_front();
                    }
                }
            });
        }
        let reader = child.stdout.take().map(|mut out| {
            let ring = ring.clone();
            std::thread::Builder::new()
                .name("clipd-stream".into())
                .spawn(move || {
                    let mut buf = vec![0u8; 64 * 1024];
                    while let Ok(n) = out.read(&mut buf) {
                        if n == 0 {
                            break;
                        }
                        ring.push(&buf[..n]);
                    }
                })
                .expect("Thread für den Datenstrom")
        });
        Self { child, ring, audio_device, mic_device, stderr, reader }
    }

    /// Waits for the first keyframe, so a capture that fails straight away
    /// (wrong monitor, encoder in use) is reported instead of leaving a
    /// silently empty buffer behind.
    pub fn wait_until_recording(&mut self, timeout: Duration) -> Result<()> {
        let deadline = std::time::Instant::now() + timeout;
        loop {
            if let Some(status) = self.child.try_wait().context("ffmpeg lässt sich nicht abfragen")? {
                std::thread::sleep(Duration::from_millis(100));
                bail!("ffmpeg hat die Aufnahme sofort beendet ({status}){}", self.last_words());
            }
            if !self.ring.is_empty() {
                return Ok(());
            }
            if std::time::Instant::now() >= deadline {
                bail!("Nach {timeout:?} kommt noch kein Bild — läuft die Aufnahme?");
            }
            std::thread::sleep(Duration::from_millis(50));
        }
    }

    /// How ffmpeg ended, if it has.
    pub fn exited(&mut self) -> Option<std::process::ExitStatus> {
        self.child.try_wait().ok().flatten()
    }

    /// ": <what ffmpeg said last>", or nothing.
    pub fn last_words(&self) -> String {
        let l = lock(&self.stderr);
        l.back().map(|w| format!(": {w}")).unwrap_or_default()
    }
}

impl Drop for Buffer {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        if let Some(r) = self.reader.take() {
            let _ = r.join();
        }
    }
}

/// Starts ffmpeg. With `audio`, its stdin becomes the pipe the sound goes
/// into and `format` tells it how to read those raw samples.
fn spawn(
    ffmpeg_bin: &Path,
    s: &Settings,
    audio: Option<&crate::audio::Format>,
) -> Result<(Child, Option<std::process::ChildStdin>)> {
    let mut child = ffmpeg::command(ffmpeg_bin)
        .args(ffmpeg::capture_args(s, audio)?)
        .stdin(if audio.is_some() { Stdio::piped() } else { Stdio::null() })
        .stderr(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .with_context(|| format!("{} lässt sich nicht starten", ffmpeg_bin.display()))?;
    let stdin = child.stdin.take();
    Ok((child, stdin))
}

/// Starts the capture with sound. The device comes first: only it knows the
/// sample format, and ffmpeg has to be told that format on its command line.
fn with_audio(ffmpeg_bin: &Path, s: &Settings, ring: &Ring) -> Result<(Child, crate::audio::Format)> {
    let audio = crate::audio::open(&s.audio_device, s.mic.then_some(s.mic_device.as_str()))?;
    let format = audio.format.clone();
    let (mut child, stdin) = spawn(ffmpeg_bin, s, Some(&audio.format))?;
    let Some(stdin) = stdin else {
        let _ = child.kill();
        anyhow::bail!("ffmpeg gibt keine Eingabe für den Ton her");
    };
    // Without the pipe ffmpeg would sit and wait forever, so a failure here
    // has to take it down again.
    // Capturing and encoding a frame takes about two frames' time before its
    // keyframe comes out of ffmpeg.
    let lead = Duration::from_secs_f64(2.0 / s.fps.max(1) as f64);
    if let Err(e) = audio.attach(stdin, ring.first_keyframe.clone(), lead) {
        let _ = child.kill();
        let _ = child.wait();
        return Err(e);
    }
    Ok((child, format))
}

/// Throws out what an earlier run left in the buffer folder: half-written
/// recordings belong to a stream that no longer exists.
fn clear(dir: &Path) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    for entry in entries.filter_map(|e| e.ok()) {
        if entry.file_type().is_ok_and(|t| t.is_file()) {
            let _ = std::fs::remove_file(entry.path());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Ein TS-Paket: Video oder Ton, auf Wunsch als Keyframe markiert, mit
    /// einer Kennung im Rest, um es wiederzuerkennen.
    fn packet(pid: u16, key: bool, tag: u8) -> Vec<u8> {
        let mut p = vec![tag; TS_PACKET];
        p[0] = 0x47;
        p[1] = ((pid >> 8) as u8 & 0x1f) | if key { 0x40 } else { 0 };
        p[2] = pid as u8;
        p[3] = if key { 0x30 } else { 0x10 };
        p[4] = if key { 7 } else { tag };
        p[5] = if key { 0x40 } else { tag };
        p
    }

    #[test]
    fn recognises_keyframes() {
        assert!(is_keyframe(&packet(VIDEO_PID, true, 1)));
        assert!(!is_keyframe(&packet(VIDEO_PID, false, 1)));
        assert!(!is_keyframe(&packet(0x101, true, 1)), "nur das Bild zählt, nicht der Ton");
        // Ein echter Keyframe aus hevc_amf/h264_amf-Aufnahmen: 47 41 00 30 07 50 …
        let real = [0x47, 0x41, 0x00, 0x30, 0x07, 0x50];
        assert!(is_keyframe(&real));
    }

    fn stream(pkts: &[Vec<u8>]) -> Vec<u8> {
        pkts.concat()
    }

    /// Vor dem ersten Keyframe lässt sich nichts dekodieren, also bleibt
    /// davon nichts im Ring; danach beginnt jedes Segment mit einem Keyframe.
    #[test]
    fn segments_start_at_keyframes() {
        let ring = Ring::new(10);
        ring.push(&stream(&[packet(0x101, false, 1), packet(VIDEO_PID, true, 2), packet(0x101, false, 3)]));
        ring.push(&stream(&[packet(VIDEO_PID, true, 4), packet(VIDEO_PID, false, 5)]));
        let all = ring.last(99);
        assert_eq!(all.len(), 4 * TS_PACKET, "das Tonpaket vor dem ersten Keyframe fällt weg");
        assert!(is_keyframe(&all[..TS_PACKET]));
        assert_eq!(ring.last(1), stream(&[packet(VIDEO_PID, true, 4), packet(VIDEO_PID, false, 5)]));
    }

    /// Pakete, die über zwei Lesevorgänge verteilt ankommen, werden
    /// zusammengesetzt statt verworfen.
    #[test]
    fn packets_may_arrive_in_pieces() {
        let ring = Ring::new(10);
        let data = stream(&[packet(VIDEO_PID, true, 1), packet(0x101, false, 2), packet(VIDEO_PID, false, 3)]);
        for piece in data.chunks(50) {
            ring.push(piece);
        }
        assert_eq!(ring.last(1), data);
    }

    /// Der Ring hält so viele fertige Segmente wie verlangt, plus das
    /// wachsende.
    #[test]
    fn the_ring_forgets_old_segments() {
        let ring = Ring::new(2);
        for k in 1..=5 {
            ring.push(&packet(VIDEO_PID, true, k));
        }
        assert_eq!(
            ring.last(99),
            stream(&[packet(VIDEO_PID, true, 3), packet(VIDEO_PID, true, 4), packet(VIDEO_PID, true, 5)])
        );
    }

    /// Eine Aufnahme beginnt mit dem laufenden Segment und schreibt alles
    /// Weitere mit, auch über den Ring hinaus.
    #[test]
    fn a_recording_outlasts_the_ring() {
        let dir = std::env::temp_dir().join(format!("clipd-rec-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("a.ts");
        let ring = Ring::new(1);
        ring.push(&stream(&[packet(VIDEO_PID, true, 1), packet(0x101, false, 2)]));
        ring.start_recording(&path).unwrap();
        assert!(ring.start_recording(&path).is_err(), "nur eine zugleich");
        for k in 3..=6 {
            ring.push(&packet(VIDEO_PID, true, k));
        }
        let done = ring.stop_recording().unwrap();
        let got = std::fs::read(&done).unwrap();
        std::fs::remove_dir_all(&dir).ok();
        let mut want = stream(&[packet(VIDEO_PID, true, 1), packet(0x101, false, 2)]);
        for k in 3..=6 {
            want.extend(packet(VIDEO_PID, true, k));
        }
        assert_eq!(got, want);
        assert!(ring.stop_recording().is_err());
    }

    #[test]
    fn an_empty_ring_cannot_record() {
        let ring = Ring::new(3);
        assert!(ring.is_empty());
        assert!(ring.start_recording(Path::new("egal.ts")).is_err());
    }
}
