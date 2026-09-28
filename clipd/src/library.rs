//! The saved clips: listing them, what is in them, and turning one into a
//! shorter clip or something small enough for Discord.

use crate::config::{Codec, Settings};
use crate::ffmpeg;
use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use std::io::BufRead;
use std::path::{Path, PathBuf};
use std::process::Stdio;

/// Discord's upload limit without Nitro.
pub const DISCORD_BYTES: u64 = 10_000_000;

#[derive(Clone, Debug, Serialize)]
pub struct Entry {
    pub path: PathBuf,
    /// The folder the clip lies in, which is the game's name; empty for clips
    /// directly in the clips folder.
    pub game: String,
    pub name: String,
    pub bytes: u64,
    /// Seconds since 1970, for sorting and showing a date.
    pub modified: u64,
}

/// Every clip, newest first: those in the clips folder and one level down,
/// in the game folders.
pub fn list(clips: &Path) -> Vec<Entry> {
    let mut out = Vec::new();
    collect(clips, "", &mut out);
    if let Ok(dirs) = std::fs::read_dir(clips) {
        for dir in dirs.filter_map(|d| d.ok()).filter(|d| d.file_type().is_ok_and(|t| t.is_dir())) {
            collect(&dir.path(), &dir.file_name().to_string_lossy(), &mut out);
        }
    }
    out.sort_by(|a, b| b.modified.cmp(&a.modified).then_with(|| b.name.cmp(&a.name)));
    out
}

fn collect(dir: &Path, game: &str, out: &mut Vec<Entry>) {
    let Ok(files) = std::fs::read_dir(dir) else { return };
    for f in files.filter_map(|f| f.ok()) {
        let path = f.path();
        if !path.extension().is_some_and(|e| e.eq_ignore_ascii_case("mp4")) {
            continue;
        }
        let Ok(meta) = f.metadata() else { continue };
        let modified =
            meta.modified().ok().and_then(|m| m.duration_since(std::time::UNIX_EPOCH).ok()).map_or(0, |d| d.as_secs());
        let name = path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
        out.push(Entry { path, game: game.to_string(), name, bytes: meta.len(), modified });
    }
}

/// What is in a clip, read once and kept next to its thumbnail.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Meta {
    pub duration: f64,
    pub width: u32,
    pub height: u32,
    /// 1: the game; 2: the game, then the microphone.
    pub audio_tracks: u32,
    pub thumb: PathBuf,
}

/// The clip's [`Meta`], from the cache if the file has not changed since.
pub fn meta(ffmpeg_bin: &Path, clip: &Path) -> Result<Meta> {
    let dir = crate::config::base_dir().join("cache");
    std::fs::create_dir_all(&dir).with_context(|| format!("{} lässt sich nicht anlegen", dir.display()))?;
    let key = cache_key(clip)?;
    let (json, thumb) = (dir.join(format!("{key}.json")), dir.join(format!("{key}.jpg")));
    if let Some(m) = std::fs::read_to_string(&json).ok().and_then(|t| serde_json::from_str::<Meta>(&t).ok())
        && m.thumb.is_file()
    {
        return Ok(m);
    }
    let (duration, width, height, audio_tracks) = probe(&ffmpeg::probe_tool(ffmpeg_bin), clip)?;
    let at = (duration / 3.0).min(1.0).to_string();
    let out = ffmpeg::command(ffmpeg_bin)
        .args(["-loglevel", "error", "-y", "-ss", &at, "-i"])
        .arg(clip)
        .args(["-frames:v", "1", "-vf", "scale=480:-2", "-q:v", "4"])
        .arg(&thumb)
        .output()
        .context("ffmpeg lässt sich nicht starten")?;
    if !out.status.success() {
        bail!("Kein Vorschaubild: {}", String::from_utf8_lossy(&out.stderr).trim());
    }
    let m = Meta { duration, width, height, audio_tracks, thumb };
    let _ = std::fs::write(&json, serde_json::to_string(&m)?);
    Ok(m)
}

/// Path, size and time of change: a clip that is replaced gets a new entry.
fn cache_key(clip: &Path) -> Result<String> {
    use std::hash::{Hash, Hasher};
    let meta = std::fs::metadata(clip).with_context(|| format!("{} fehlt", clip.display()))?;
    let mut h = std::collections::hash_map::DefaultHasher::new();
    clip.hash(&mut h);
    meta.len().hash(&mut h);
    meta.modified().ok().hash(&mut h);
    Ok(format!("{:016x}", h.finish()))
}

/// Length, size and number of sound tracks.
fn probe(ffprobe: &Path, clip: &Path) -> Result<(f64, u32, u32, u32)> {
    #[derive(Deserialize)]
    struct Stream {
        codec_type: String,
        width: Option<u32>,
        height: Option<u32>,
    }
    #[derive(Deserialize)]
    struct Format {
        duration: Option<String>,
    }
    #[derive(Deserialize)]
    struct Probe {
        streams: Vec<Stream>,
        format: Format,
    }
    let mut cmd = std::process::Command::new(ffprobe);
    cmd.args(["-v", "error", "-show_entries", "stream=codec_type,width,height:format=duration", "-of", "json"]).arg(clip);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0800_0000);
    }
    let out = cmd.output().context("ffprobe lässt sich nicht starten")?;
    let p: Probe = serde_json::from_slice(&out.stdout).context("ffprobe liefert Unverständliches")?;
    let video = p.streams.iter().find(|s| s.codec_type == "video");
    let audio = p.streams.iter().filter(|s| s.codec_type == "audio").count() as u32;
    let duration = p.format.duration.and_then(|d| d.parse().ok()).unwrap_or(0.0);
    Ok((duration, video.and_then(|v| v.width).unwrap_or(0), video.and_then(|v| v.height).unwrap_or(0), audio))
}

/// Gives a clip a new name in the same folder.
pub fn rename(clip: &Path, name: &str) -> Result<PathBuf> {
    let name = crate::game::folder_name(name);
    let to = clip.with_file_name(format!("{name}.mp4"));
    if to == clip {
        return Ok(to);
    }
    if to.exists() {
        bail!("Es gibt schon einen Clip namens {name}");
    }
    std::fs::rename(clip, &to).with_context(|| format!("{} lässt sich nicht umbenennen", clip.display()))?;
    Ok(to)
}

/// What to keep of a clip.
#[derive(Clone, Debug, Deserialize)]
pub struct Edit {
    pub start: f64,
    pub end: f64,
    /// 0 mutes the track, 1 leaves it, up to 2 makes it louder.
    pub game_volume: f32,
    pub mic_volume: f32,
}

#[derive(Clone, Copy, Debug, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum Target {
    /// Same codec and quality, both sound tracks kept apart.
    Trim,
    /// H.264 with one mixed sound track, under [`DISCORD_BYTES`].
    Discord,
}

/// How a Discord export fits its length into the limit.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Budget {
    pub video_kbps: u32,
    pub audio_kbps: u32,
    /// Smaller than the source only when the bitrate would not carry it.
    pub height: Option<u32>,
    /// 30 instead of the source's rate when even that is too much.
    pub fps: Option<u32>,
}

/// Splits `limit` bytes over `secs` seconds, with a tenth held back because a
/// hardware encoder only roughly keeps a bitrate.
pub fn budget(secs: f64, limit: u64, src_height: u32) -> Budget {
    let total = (limit as f64 * 8.0 / 1000.0 / secs.max(0.1) * 0.9) as u32;
    let audio_kbps = if total < 600 { 64 } else { 96 };
    let video_kbps = total.saturating_sub(audio_kbps).clamp(150, 12_000);
    let fit = match video_kbps {
        k if k >= 5_000 => 1080,
        k if k >= 2_500 => 720,
        k if k >= 1_200 => 540,
        _ => 480,
    };
    let height = (src_height > fit).then_some(fit);
    let fps = (video_kbps < 1_500).then_some(30);
    Budget { video_kbps, audio_kbps, height, fps }
}

/// Writes the part of `src` that `edit` keeps into a new file next to it and
/// returns that file. `progress` hears how far it is, from 0 to 1.
///
/// Cutting frame-exact means encoding again, which the graphics card does in
/// a few seconds; `s.gpu` must be settled.
pub fn export(
    ffmpeg_bin: &Path,
    s: &Settings,
    src: &Path,
    edit: &Edit,
    target: Target,
    progress: &mut dyn FnMut(f32),
) -> Result<PathBuf> {
    let (duration, _, height, tracks) = probe(&ffmpeg::probe_tool(ffmpeg_bin), src)?;
    let start = edit.start.clamp(0.0, duration);
    let end = edit.end.clamp(start, duration);
    let secs = end - start;
    anyhow::ensure!(secs >= 0.2, "Das Stück ist zu kurz");
    let stem = src.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_else(|| "clip".into());
    let suffix = if target == Target::Trim { "geschnitten" } else { "Discord" };
    let out = free(src.with_file_name(format!("{stem} ({suffix}).mp4")));

    let mut factor = 1.0;
    loop {
        let args = export_args(s, src, &out, start, secs, tracks, height, edit, target, factor)?;
        run(ffmpeg_bin, &args, secs, progress)?;
        let bytes = std::fs::metadata(&out).map(|m| m.len()).unwrap_or(0);
        if target == Target::Trim || bytes <= DISCORD_BYTES || factor < 0.5 {
            anyhow::ensure!(bytes <= DISCORD_BYTES || target == Target::Trim, "Der Clip passt nicht unter 10 MB");
            return Ok(out);
        }
        // The encoder overshot; the next try aims lower by the same ratio.
        factor *= DISCORD_BYTES as f64 / bytes as f64 * 0.95;
    }
}

/// `path`, or the first `path (2)`, `path (3)`, … that is still free.
fn free(path: PathBuf) -> PathBuf {
    if !path.exists() {
        return path;
    }
    let stem = path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
    (2..).map(|n| path.with_file_name(format!("{stem} ({n}).mp4"))).find(|p| !p.exists()).unwrap_or(path)
}

#[allow(clippy::too_many_arguments)]
fn export_args(
    s: &Settings,
    src: &Path,
    out: &Path,
    start: f64,
    secs: f64,
    tracks: u32,
    src_height: u32,
    edit: &Edit,
    target: Target,
    factor: f64,
) -> Result<Vec<String>> {
    let mut a: Vec<String> = ["-loglevel", "error", "-nostats", "-progress", "pipe:1", "-y"].map(String::from).to_vec();
    // Decoding on the card too; ffmpeg falls back to the CPU where it cannot.
    a.extend(["-hwaccel", "d3d11va"].map(String::from));
    a.extend(["-ss".into(), format!("{start:.3}"), "-t".into(), format!("{secs:.3}"), "-i".into()]);
    a.push(src.to_string_lossy().into_owned());

    let (gv, mv) = (edit.game_volume.clamp(0.0, 2.0), edit.mic_volume.clamp(0.0, 2.0));
    let mut graph = Vec::new();
    let mut maps = vec!["0:v:0".to_string()];
    match (target, tracks) {
        (_, 0) => {}
        (Target::Trim, 1) | (Target::Discord, 1) => {
            graph.push(format!("[0:a:0]volume={gv}[a0]"));
            maps.push("[a0]".into());
        }
        (Target::Trim, _) => {
            graph.push(format!("[0:a:0]volume={gv}[a0]"));
            maps.push("[a0]".into());
            // A muted microphone is left out rather than kept as silence.
            if mv > 0.0 {
                graph.push(format!("[0:a:1]volume={mv}[a1]"));
                maps.push("[a1]".into());
            }
        }
        (Target::Discord, _) => {
            graph.push(format!("[0:a:0]volume={gv}[g];[0:a:1]volume={mv}[m];[g][m]amix=inputs=2:normalize=0[a0]"));
            maps.push("[a0]".into());
        }
    }

    let budget = budget(secs, DISCORD_BYTES, src_height);
    if target == Target::Discord {
        let mut v = Vec::new();
        if let Some(h) = budget.height {
            v.push(format!("scale=-2:{h}"));
        }
        if let Some(fps) = budget.fps {
            v.push(format!("fps={fps}"));
        }
        if !v.is_empty() {
            graph.push(format!("[0:v:0]{}[v]", v.join(",")));
            maps[0] = "[v]".into();
        }
    }
    if !graph.is_empty() {
        a.extend(["-filter_complex".into(), graph.join(";")]);
    }
    for m in maps {
        a.extend(["-map".into(), m]);
    }

    match target {
        Target::Trim => {
            a.extend(ffmpeg::encoder_args(s)?);
            a.extend(["-c:a".into(), "aac".into(), "-b:a".into(), format!("{}k", s.audio_kbit)]);
        }
        Target::Discord => {
            let h264 = Settings { codec: Codec::H264, ..s.clone() };
            a.extend(ffmpeg::bitrate_args(&h264, (budget.video_kbps as f64 * factor) as u32)?);
            a.extend([
                "-c:a".into(),
                "aac".into(),
                "-b:a".into(),
                format!("{}k", budget.audio_kbps),
                "-ac".into(),
                "2".into(),
            ]);
        }
    }
    a.extend(["-movflags", "+faststart"].map(String::from));
    a.push(out.to_string_lossy().into_owned());
    Ok(a)
}

/// Runs ffmpeg and turns its `-progress` lines into a fraction of `secs`.
fn run(ffmpeg_bin: &Path, args: &[String], secs: f64, progress: &mut dyn FnMut(f32)) -> Result<()> {
    let mut child = ffmpeg::command(ffmpeg_bin)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context("ffmpeg lässt sich nicht starten")?;
    let stdout = child.stdout.take().context("ffmpeg gibt keinen Fortschritt her")?;
    for line in std::io::BufReader::new(stdout).lines().map_while(Result::ok) {
        if let Some(us) = line.strip_prefix("out_time_us=").and_then(|v| v.parse::<f64>().ok()) {
            progress((us / 1e6 / secs).clamp(0.0, 1.0) as f32);
        }
    }
    let out = child.wait_with_output().context("ffmpeg lässt sich nicht abfragen")?;
    if !out.status.success() {
        bail!("Der Export ist gescheitert: {}", String::from_utf8_lossy(&out.stderr).trim());
    }
    progress(1.0);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Kurze Clips behalten ihre Auflösung, lange werden kleiner und
    /// langsamer, damit sie unter 10 MB passen.
    #[test]
    fn the_budget_fits_the_limit() {
        let short = budget(10.0, DISCORD_BYTES, 1080);
        assert_eq!(short.height, None, "{short:?}");
        assert_eq!(short.fps, None);
        let long = budget(120.0, DISCORD_BYTES, 1080);
        assert_eq!(long.height, Some(480), "{long:?}");
        assert_eq!(long.fps, Some(30));
        for secs in [1.0, 5.0, 30.0, 60.0, 300.0] {
            let b = budget(secs, DISCORD_BYTES, 1200);
            let bytes = (b.video_kbps + b.audio_kbps) as f64 * 1000.0 / 8.0 * secs;
            assert!(bytes <= DISCORD_BYTES as f64 || b.video_kbps == 150, "{secs} s: {bytes} Bytes");
        }
    }

    /// Nie größer als die Quelle.
    #[test]
    fn the_budget_never_upscales() {
        assert_eq!(budget(120.0, DISCORD_BYTES, 360).height, None);
    }

    fn edit() -> Edit {
        Edit { start: 2.0, end: 7.5, game_volume: 1.0, mic_volume: 0.5 }
    }

    fn args(target: Target, tracks: u32, e: &Edit) -> Vec<String> {
        let s = Settings { gpu: crate::config::Gpu::Amd, ..Default::default() };
        export_args(&s, Path::new(r"C:\c\a.mp4"), Path::new(r"C:\c\b.mp4"), 2.0, 5.5, tracks, 1200, e, target, 1.0).unwrap()
    }

    /// Beim Zuschneiden bleiben Spiel und Mikrofon getrennte Spuren.
    #[test]
    fn trim_keeps_both_tracks() {
        let a = args(Target::Trim, 2, &edit());
        let at = |flag: &str| a.iter().position(|x| x == flag).map(|i| a[i + 1].clone());
        assert_eq!(at("-ss").as_deref(), Some("2.000"));
        assert_eq!(at("-t").as_deref(), Some("5.500"));
        assert_eq!(at("-filter_complex").as_deref(), Some("[0:a:0]volume=1[a0];[0:a:1]volume=0.5[a1]"));
        assert!(a.contains(&"hevc_amf".to_string()), "gleicher Codec wie die Aufnahme");
    }

    /// Ein stumm geschaltetes Mikrofon fällt ganz weg.
    #[test]
    fn a_muted_microphone_is_dropped() {
        let a = args(Target::Trim, 2, &Edit { mic_volume: 0.0, ..edit() });
        assert!(!a.iter().any(|x| x.contains("[0:a:1]")));
    }

    /// Für Discord gibt es eine gemischte Spur und H.264.
    #[test]
    fn discord_mixes_and_uses_h264() {
        let a = args(Target::Discord, 2, &edit());
        let at = |flag: &str| a.iter().position(|x| x == flag).map(|i| a[i + 1].clone());
        assert!(at("-filter_complex").unwrap().contains("amix=inputs=2"));
        assert_eq!(at("-c:v").as_deref(), Some("h264_amf"));
        assert_eq!(at("-ac").as_deref(), Some("2"));
        assert!(at("-b:v").is_some());
    }

    #[test]
    fn names_are_never_taken_twice() {
        let dir = std::env::temp_dir().join(format!("clipd-free-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let first = dir.join("a (Discord).mp4");
        assert_eq!(free(first.clone()), first);
        std::fs::write(&first, b"x").unwrap();
        assert_eq!(free(first.clone()).file_name().unwrap(), "a (Discord) (2).mp4");
        std::fs::remove_dir_all(&dir).ok();
    }
}
