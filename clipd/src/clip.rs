//! Turning the buffer into a finished clip.

use crate::buffer;
use crate::config::Settings;
use crate::ffmpeg;
use anyhow::{Context, Result, bail};
use std::path::{Path, PathBuf};

/// Name of the copy of the segment that is still being written.
const LIVE: &str = "live";
const LIST: &str = "concat.txt";

pub struct Saved {
    pub path: PathBuf,
    /// Length of the clip, as ffprobe reads it back.
    pub secs: Option<f64>,
    pub segments: usize,
    /// How much of the segment that was still being written made it in. Zero
    /// means the clip ends at the last finished segment instead of at the key
    /// press, so it is worth seeing.
    pub live_bytes: usize,
}

/// Writes the last `clip_secs` seconds to a file. The streams are copied, so
/// this costs no encoding time and finishes in a fraction of a second.
pub fn save(ffmpeg_bin: &Path, s: &Settings, dir: &Path) -> Result<Saved> {
    let all = buffer::segments(dir, s);
    let chosen = buffer::newest(&all, s.clip_len());
    let Some((live, earlier)) = chosen.split_last() else {
        bail!("Der Buffer ist noch leer — läuft die Aufnahme erst gerade an?");
    };

    let mut list: Vec<PathBuf> = earlier.to_vec();
    let mut live_bytes = 0;
    // Take what is already on disk of the segment ffmpeg is still writing, so
    // the clip reaches past the last finished segment.
    //
    // This is a bonus, not a guarantee: ffmpeg hands its output to the file
    // system in blocks of 256 KiB, and neither -flush_packets nor
    // -avioflags direct changes that. So an open segment is either still
    // completely empty or already 256 KiB long, and a clip ends somewhere
    // between the last finished segment and the key press.
    if s.codec.tolerates_partial_segment()
        && let Some((copy, len)) = copy_live(live, dir)?
    {
        list.push(copy);
        live_bytes = len;
    }
    if list.is_empty() {
        bail!("Der Buffer ist noch zu kurz für einen Clip — gib ihm einen Moment.");
    }

    let clips = s.clips_dir();
    std::fs::create_dir_all(&clips).with_context(|| format!("{} lässt sich nicht anlegen", clips.display()))?;
    let out = unique(&clips, &stamp(), "mp4");

    let list_file = dir.join(LIST);
    std::fs::write(&list_file, ffmpeg::concat_list(&list))
        .with_context(|| format!("{} lässt sich nicht schreiben", list_file.display()))?;

    let done = ffmpeg::command(ffmpeg_bin)
        .args(ffmpeg::concat_args(&list_file, &out))
        .output()
        .context("ffmpeg lässt sich nicht starten")?;
    let _ = std::fs::remove_file(&list_file);
    let _ = std::fs::remove_file(dir.join(format!("{LIVE}.{}", s.codec.segment_ext())));
    if !done.status.success() {
        let why = String::from_utf8_lossy(&done.stderr);
        bail!("Der Clip lässt sich nicht schreiben: {}", why.trim());
    }

    let secs = ffmpeg::duration(&ffmpeg::probe_tool(ffmpeg_bin), &out);
    Ok(Saved { path: out, secs, segments: list.len(), live_bytes })
}

/// One line about a saved clip. Names the part taken from the segment that was
/// still being written, because that is what decides whether the clip reaches
/// the key press or stops up to one segment short of it.
pub fn describe(done: &Saved) -> String {
    let len = done.secs.map(|v| format!("{v:.2} s")).unwrap_or_else(|| "?".into());
    let live = match done.live_bytes {
        0 => "ohne das laufende Segment".to_string(),
        n => format!("davon {} KiB aus dem laufenden Segment", n / 1024),
    };
    format!("Clip: {} ({len}, {} Segmente, {live})", done.path.display(), done.segments)
}

/// Copies the segment ffmpeg is still writing, cut back to whole MPEG-TS
/// packets. Returns nothing if there is not yet a single packet in it.
fn copy_live(live: &Path, dir: &Path) -> Result<Option<(PathBuf, usize)>> {
    let ext = live.extension().and_then(|e| e.to_str()).unwrap_or("ts");
    let mut data = buffer::read_shared(live).with_context(|| format!("{} lässt sich nicht lesen", live.display()))?;
    data.truncate(buffer::whole_packets(data.len() as u64) as usize);
    if data.is_empty() {
        return Ok(None);
    }
    let len = data.len();
    let copy = dir.join(format!("{LIVE}.{ext}"));
    std::fs::write(&copy, data).with_context(|| format!("{} lässt sich nicht schreiben", copy.display()))?;
    Ok(Some((copy, len)))
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
