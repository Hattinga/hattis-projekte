//! Turning a piece of the stream into a finished clip.

use crate::ffmpeg;
use anyhow::{Context, Result, bail};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Stdio;

pub struct Saved {
    pub path: PathBuf,
    /// Length of the clip, as ffprobe reads it back.
    pub secs: Option<f64>,
}

/// Writes `ts`, a piece of the stream that starts at a keyframe, into a new
/// MP4 in `out_dir`. The streams are copied, so this costs no encoding time
/// and finishes in a fraction of a second.
pub fn save(ffmpeg_bin: &Path, ts: &[u8], out_dir: &Path) -> Result<Saved> {
    if ts.is_empty() {
        bail!("Der Buffer ist noch leer — läuft die Aufnahme erst gerade an?");
    }
    let out = target(out_dir)?;
    let mut child = ffmpeg::command(ffmpeg_bin)
        .args(ffmpeg::remux_args("pipe:0", &out))
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .context("ffmpeg lässt sich nicht starten")?;
    let mut stdin = child.stdin.take().context("ffmpeg nimmt keine Eingabe an")?;
    // Written from a thread, so ffmpeg can talk on stderr meanwhile without
    // the two blocking each other.
    let data = ts.to_vec();
    let writer = std::thread::spawn(move || stdin.write_all(&data));
    let done = child.wait_with_output().context("ffmpeg lässt sich nicht abfragen")?;
    let _ = writer.join();
    finish(ffmpeg_bin, out, &done)
}

/// Turns a recording file (MPEG-TS) into an MP4 in `out_dir` and removes it.
pub fn save_file(ffmpeg_bin: &Path, ts: &Path, out_dir: &Path) -> Result<Saved> {
    let out = target(out_dir)?;
    let done = ffmpeg::command(ffmpeg_bin)
        .args(ffmpeg::remux_args(&ts.to_string_lossy(), &out))
        .output()
        .context("ffmpeg lässt sich nicht starten")?;
    let saved = finish(ffmpeg_bin, out, &done)?;
    let _ = std::fs::remove_file(ts);
    Ok(saved)
}

fn target(out_dir: &Path) -> Result<PathBuf> {
    std::fs::create_dir_all(out_dir).with_context(|| format!("{} lässt sich nicht anlegen", out_dir.display()))?;
    Ok(unique(out_dir, &stamp(), "mp4"))
}

fn finish(ffmpeg_bin: &Path, out: PathBuf, done: &std::process::Output) -> Result<Saved> {
    if !done.status.success() {
        let _ = std::fs::remove_file(&out);
        bail!("Der Clip lässt sich nicht schreiben: {}", String::from_utf8_lossy(&done.stderr).trim());
    }
    let secs = ffmpeg::duration(&ffmpeg::probe_tool(ffmpeg_bin), &out);
    Ok(Saved { path: out, secs })
}

/// One line about a saved clip.
pub fn describe(done: &Saved) -> String {
    let len = done.secs.map(|v| format!("{v:.2} s")).unwrap_or_else(|| "?".into());
    format!("Clip: {} ({len})", done.path.display())
}

fn stamp() -> String {
    chrono::Local::now().format("clip-%Y-%m-%d_%H-%M-%S").to_string()
}

/// `<dir>/<name>.<ext>`, with a counter appended if that is taken, so a second
/// clip in the same second does not overwrite the first.
fn unique(dir: &Path, name: &str, ext: &str) -> PathBuf {
    let first = dir.join(format!("{name}.{ext}"));
    if !first.exists() {
        return first;
    }
    (2..).map(|n| dir.join(format!("{name}-{n}.{ext}"))).find(|p| !p.exists()).unwrap_or(first)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Der Zeitstempel muss sortierbar und als Dateiname erlaubt sein.
    #[test]
    fn stamp_is_a_sortable_filename() {
        let s = stamp();
        assert!(s.starts_with("clip-"), "{s}");
        assert_eq!(s.len(), "clip-2026-09-27_14-31-05".len(), "{s}");
        assert!(!s.contains(':'), "Doppelpunkte sind in Windows-Namen verboten: {s}");
    }

    /// Zwei Clips in derselben Sekunde dürfen sich nicht überschreiben.
    #[test]
    fn second_clip_in_the_same_second_gets_a_counter() {
        let dir = std::env::temp_dir().join(format!("clipd-unique-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let first = unique(&dir, "clip-x", "mp4");
        assert_eq!(first.file_name().unwrap(), "clip-x.mp4");
        std::fs::write(&first, b"x").unwrap();
        let second = unique(&dir, "clip-x", "mp4");
        assert_eq!(second.file_name().unwrap(), "clip-x-2.mp4");
        std::fs::write(&second, b"x").unwrap();
        assert_eq!(unique(&dir, "clip-x", "mp4").file_name().unwrap(), "clip-x-3.mp4");
        std::fs::remove_dir_all(&dir).ok();
    }
}
