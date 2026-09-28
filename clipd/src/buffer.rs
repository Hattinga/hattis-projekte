//! The rolling buffer: an ffmpeg that writes numbered segments, and the
//! housekeeping that throws the old ones away.

use crate::config::Settings;
use crate::ffmpeg;
use anyhow::{Context, Result, bail};
use std::path::{Path, PathBuf};
use std::process::{Child, Stdio};
use std::time::Duration;

/// One MPEG-TS packet. A segment that is still being written usually ends in
/// the middle of one, and cutting back to a whole packet keeps the clip clean.
pub const TS_PACKET: u64 = 188;

pub struct Buffer {
    pub dir: PathBuf,
    child: Child,
    /// The playback device the sound is taken from, if there is sound.
    pub audio_device: Option<String>,
    /// The microphone on the second sound track, if there is one.
    pub mic_device: Option<String>,
}

impl Buffer {
    /// Empties the buffer folder and starts the capture. Whatever an earlier
    /// run left behind is worthless, because its timeline has no relation to
    /// the new one.
    ///
    /// If the sound cannot be opened, the recording carries on without it: a
    /// clip without sound still beats no clip at all.
    pub fn start(ffmpeg_bin: &Path, s: &Settings) -> Result<Self> {
        let dir = crate::config::buffer_dir();
        std::fs::create_dir_all(&dir).with_context(|| format!("{} lässt sich nicht anlegen", dir.display()))?;
        clear(&dir);
        if s.audio {
            match with_audio(ffmpeg_bin, s, &dir) {
                Ok((child, format)) => {
                    let (audio_device, mic_device) = (Some(format.describe()), format.mic_device);
                    return Ok(Self { dir, child, audio_device, mic_device });
                }
                Err(e) => eprintln!("clipd: Aufnahme ohne Ton — {e:#}"),
            }
        }
        let child = spawn(ffmpeg_bin, s, &dir, None)?.0;
        Ok(Self { dir, child, audio_device: None, mic_device: None })
    }

    /// Waits until the first segment shows up, so a capture that fails straight
    /// away (wrong monitor, encoder in use) is reported instead of leaving a
    /// silently empty buffer behind.
    pub fn wait_until_recording(&mut self, s: &Settings, timeout: Duration) -> Result<()> {
        let deadline = std::time::Instant::now() + timeout;
        loop {
            if let Some(status) = self.child.try_wait().context("ffmpeg lässt sich nicht abfragen")? {
                bail!("ffmpeg hat die Aufnahme sofort beendet ({status}) — siehe die Meldung darüber");
            }
            if !segments(&self.dir, s).is_empty() {
                return Ok(());
            }
            if std::time::Instant::now() >= deadline {
                bail!("Nach {:?} liegt noch kein Segment im Buffer — läuft die Aufnahme?", timeout);
            }
            std::thread::sleep(Duration::from_millis(50));
        }
    }

    /// How ffmpeg ended, if it has.
    pub fn exited(&mut self) -> Option<std::process::ExitStatus> {
        self.child.try_wait().ok().flatten()
    }
}

impl Drop for Buffer {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

/// Starts ffmpeg. With `audio`, its stdin becomes the pipe the sound goes
/// into and `format` tells it how to read those raw samples.
fn spawn(
    ffmpeg_bin: &Path,
    s: &Settings,
    dir: &Path,
    audio: Option<&crate::audio::Format>,
) -> Result<(Child, Option<std::process::ChildStdin>)> {
    let mut child = ffmpeg::command(ffmpeg_bin)
        .args(ffmpeg::capture_args(s, dir, audio)?)
        .stdin(if audio.is_some() { Stdio::piped() } else { Stdio::null() })
        // ffmpeg's own complaints belong on our console.
        .stderr(Stdio::inherit())
        .stdout(Stdio::null())
        .spawn()
        .with_context(|| format!("{} lässt sich nicht starten", ffmpeg_bin.display()))?;
    let stdin = child.stdin.take();
    Ok((child, stdin))
}

/// Starts the capture with sound. The device comes first: only it knows the
/// sample format, and ffmpeg has to be told that format on its command line.
fn with_audio(ffmpeg_bin: &Path, s: &Settings, dir: &Path) -> Result<(Child, crate::audio::Format)> {
    let audio = crate::audio::open(&s.audio_device, s.mic.then_some(s.mic_device.as_str()))?;
    let format = audio.format.clone();
    let (mut child, stdin) = spawn(ffmpeg_bin, s, dir, Some(&audio.format))?;
    let Some(stdin) = stdin else {
        let _ = child.kill();
        anyhow::bail!("ffmpeg gibt keine Eingabe für den Ton her");
    };
    // Without the pipe ffmpeg would sit and wait forever, so a failure here
    // has to take it down again.
    if let Err(e) = audio.attach(stdin) {
        let _ = child.kill();
        let _ = child.wait();
        return Err(e);
    }
    Ok((child, format))
}

/// The buffer segments, oldest first. The names are zero padded, so sorting
/// them as text is the same as sorting them by time.
pub fn segments(dir: &Path, s: &Settings) -> Vec<PathBuf> {
    let ext = s.codec.segment_ext();
    let Ok(entries) = std::fs::read_dir(dir) else { return Vec::new() };
    let mut found: Vec<PathBuf> = entries
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.extension().is_some_and(|x| x == ext)
                && p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.starts_with("seg"))
        })
        .collect();
    found.sort();
    found
}

/// Deletes everything beyond the newest `keep` segments — except `spare` and
/// what came after it, the part a running recording still needs.
pub fn prune(dir: &Path, s: &Settings, keep: usize, spare: Option<&Path>) {
    let all = segments(dir, s);
    for old in drop_newest(&all, keep) {
        if spare.is_some_and(|first| old.as_path() >= first) {
            break;
        }
        let _ = std::fs::remove_file(old);
    }
}

/// `first` and every segment after it, oldest first.
pub fn since<'a>(all: &'a [PathBuf], first: &Path) -> &'a [PathBuf] {
    let at = all.iter().position(|p| p.as_path() >= first).unwrap_or(all.len());
    &all[at..]
}

/// The segments that have fallen out of the ring.
fn drop_newest(all: &[PathBuf], keep: usize) -> &[PathBuf] {
    &all[..all.len().saturating_sub(keep)]
}

/// The newest `n` segments, oldest first.
pub fn newest(all: &[PathBuf], n: usize) -> &[PathBuf] {
    &all[all.len().saturating_sub(n)..]
}

/// Throws out everything in the buffer folder. It belongs to clipd alone, and
/// after a restart none of it lines up with the new recording any more.
fn clear(dir: &Path) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    for entry in entries.filter_map(|e| e.ok()) {
        if entry.file_type().is_ok_and(|t| t.is_file()) {
            let _ = std::fs::remove_file(entry.path());
        }
    }
}

/// Reads a file that another program is still writing to. Windows only allows
/// this if we explicitly grant the writer its access, which plain `read` does
/// not do — it would fail with a sharing violation.
pub fn read_shared(path: &Path) -> std::io::Result<Vec<u8>> {
    #[cfg(windows)]
    {
        use std::io::Read;
        use std::os::windows::fs::OpenOptionsExt;
        const FILE_SHARE_READ_WRITE_DELETE: u32 = 0x1 | 0x2 | 0x4;
        let mut file = std::fs::OpenOptions::new().read(true).share_mode(FILE_SHARE_READ_WRITE_DELETE).open(path)?;
        let mut buf = Vec::new();
        file.read_to_end(&mut buf)?;
        Ok(buf)
    }
    #[cfg(not(windows))]
    std::fs::read(path)
}

/// Cuts a length back to whole MPEG-TS packets.
pub fn whole_packets(len: u64) -> u64 {
    len - len % TS_PACKET
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Codec;

    fn paths(names: &[&str]) -> Vec<PathBuf> {
        names.iter().map(PathBuf::from).collect()
    }

    /// Nur die ältesten Segmente dürfen weg, und nur wenn der Ring voll ist.
    #[test]
    fn prune_keeps_the_newest() {
        let all = paths(&["seg1.ts", "seg2.ts", "seg3.ts", "seg4.ts"]);
        assert_eq!(drop_newest(&all, 2), paths(&["seg1.ts", "seg2.ts"]).as_slice());
        assert_eq!(drop_newest(&all, 4), &[] as &[PathBuf], "voll, aber nicht übervoll");
        assert_eq!(drop_newest(&all, 9), &[] as &[PathBuf], "noch nicht voll");
        assert_eq!(drop_newest(&[], 2), &[] as &[PathBuf]);
    }

    /// Eine laufende Aufnahme braucht ihre Segmente noch, auch wenn sie aus dem
    /// Ring gefallen sind.
    #[test]
    fn a_recording_spares_its_segments() {
        let dir = std::env::temp_dir().join(format!("clipd-spare-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        for n in 1..=6 {
            std::fs::write(dir.join(format!("seg0000000{n}.ts")), b"x").unwrap();
        }
        let s = Settings::default();
        prune(&dir, &s, 2, Some(&dir.join("seg00000003.ts")));
        let left: Vec<_> =
            segments(&dir, &s).iter().map(|p| p.file_name().unwrap().to_string_lossy().into_owned()).collect();
        std::fs::remove_dir_all(&dir).ok();
        assert_eq!(left, ["seg00000003.ts", "seg00000004.ts", "seg00000005.ts", "seg00000006.ts"]);
    }

    #[test]
    fn since_starts_at_the_first_segment() {
        let all = paths(&["seg1.ts", "seg2.ts", "seg3.ts"]);
        assert_eq!(since(&all, Path::new("seg2.ts")), paths(&["seg2.ts", "seg3.ts"]).as_slice());
        assert_eq!(since(&all, Path::new("seg9.ts")), &[] as &[PathBuf]);
    }

    /// Ein Clip nimmt die jüngsten Segmente, in zeitlicher Reihenfolge.
    #[test]
    fn newest_returns_them_in_order() {
        let all = paths(&["seg1.ts", "seg2.ts", "seg3.ts"]);
        assert_eq!(newest(&all, 2), paths(&["seg2.ts", "seg3.ts"]).as_slice());
        assert_eq!(newest(&all, 99), all.as_slice(), "mehr als da ist");
        assert_eq!(newest(&all, 0), &[] as &[PathBuf]);
    }

    /// Achtstellige Namen sortieren als Text genauso wie nach der Zeit — das
    /// ist die Annahme, auf der die ganze Reihenfolge beruht.
    #[test]
    fn padded_names_sort_chronologically() {
        let mut names = paths(&["seg00000010.ts", "seg00000002.ts", "seg00000001.ts"]);
        names.sort();
        assert_eq!(names, paths(&["seg00000001.ts", "seg00000002.ts", "seg00000010.ts"]));
    }

    #[test]
    fn trims_to_whole_ts_packets() {
        assert_eq!(whole_packets(188), 188);
        assert_eq!(whole_packets(200), 188, "halbes Paket abschneiden");
        assert_eq!(whole_packets(187), 0);
        // Der 256-KiB-Block, den ffmpeg am Stück schreibt, endet mitten im Paket.
        assert_eq!(whole_packets(262_144), 262_072, "188 * 1394, die 72 Restbytes fallen weg");
    }

    /// Im Buffer liegen auch die Liste und die Kopie des laufenden Segments;
    /// gezählt werden darf nur, was ffmpeg geschrieben hat.
    #[test]
    fn only_segments_are_listed() {
        let dir = std::env::temp_dir().join(format!("clipd-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        for name in ["seg00000001.ts", "seg00000002.ts", "concat.txt", "live.ts", "seg00000001.mkv"] {
            std::fs::write(dir.join(name), b"x").unwrap();
        }
        let s = Settings { codec: Codec::Hevc, ..Default::default() };
        let got: Vec<_> = segments(&dir, &s).iter().map(|p| p.file_name().unwrap().to_string_lossy().into_owned()).collect();
        std::fs::remove_dir_all(&dir).ok();
        assert_eq!(got, ["seg00000001.ts", "seg00000002.ts"], "kein live.ts, keine Liste, kein .mkv");
    }
}
