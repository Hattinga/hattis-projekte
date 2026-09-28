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
    /// Starred: kept when the clips are tidied up.
    pub favorite: bool,
}

/// Every clip, newest first: those in the clips folder and one level down,
/// in the game folders.
pub fn list(clips: &Path) -> Vec<Entry> {
    let favorites = favorites();
    let mut out = Vec::new();
    collect(clips, "", &mut out);
    if let Ok(dirs) = std::fs::read_dir(clips) {
        for dir in dirs.filter_map(|d| d.ok()).filter(|d| d.file_type().is_ok_and(|t| t.is_dir())) {
            collect(&dir.path(), &dir.file_name().to_string_lossy(), &mut out);
        }
    }
    for e in &mut out {
        e.favorite = favorites.contains(&e.path);
    }
    out.sort_by(|a, b| b.modified.cmp(&a.modified).then_with(|| b.name.cmp(&a.name)));
    out
}

/// The starred clips, kept as a list of paths beside the settings.
pub fn favorites() -> std::collections::BTreeSet<PathBuf> {
    std::fs::read_to_string(favorites_path()).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default()
}

fn favorites_path() -> PathBuf {
    crate::config::base_dir().join("favorites.json")
}

fn write_favorites(set: &std::collections::BTreeSet<PathBuf>) -> Result<()> {
    let path = favorites_path();
    std::fs::write(&path, serde_json::to_string_pretty(set)?)
        .with_context(|| format!("{} lässt sich nicht schreiben", path.display()))
}

/// Stars or unstars a clip.
pub fn set_favorite(clip: &Path, on: bool) -> Result<()> {
    let mut set = favorites();
    if on {
        set.insert(clip.to_path_buf());
    } else {
        set.remove(clip);
    }
    write_favorites(&set)
}

/// Keeps a star on a clip that moved, or drops it for one that went away.
pub fn favorite_moved(from: &Path, to: Option<&Path>) {
    let mut set = favorites();
    if set.remove(from) {
        if let Some(to) = to {
            set.insert(to.to_path_buf());
        }
        let _ = write_favorites(&set);
    }
}

/// Deletes a clip for good — used when tidying up, where the point is the
/// space. The window's own delete goes to the recycle bin instead.
pub fn forget(clip: &Path) -> Result<()> {
    std::fs::remove_file(clip).with_context(|| format!("{} lässt sich nicht löschen", clip.display()))?;
    favorite_moved(clip, None);
    Ok(())
}

/// What tidying up would remove, oldest first: clips older than `keep_days`,
/// then the oldest until the rest fits into `max_gb`. Starred clips stay;
/// 0 turns either rule off.
pub fn to_tidy(clips: &[Entry], keep_days: u32, max_gb: u32, now: u64) -> Vec<PathBuf> {
    let mut candidates: Vec<&Entry> = clips.iter().filter(|c| !c.favorite).collect();
    candidates.sort_by_key(|c| c.modified);
    let mut gone = Vec::new();
    let mut total: u64 = clips.iter().map(|c| c.bytes).sum();
    let limit = u64::from(max_gb) * 1_000_000_000;
    for c in candidates {
        let too_old = keep_days > 0 && now.saturating_sub(c.modified) > u64::from(keep_days) * 86_400;
        let too_much = max_gb > 0 && total > limit;
        if too_old || too_much {
            total -= c.bytes;
            gone.push(c.path.clone());
        }
    }
    gone
}

/// Applies [`to_tidy`] to the clips folder and says how many clips went.
pub fn tidy(clips_dir: &Path, keep_days: u32, max_gb: u32) -> usize {
    if keep_days == 0 && max_gb == 0 {
        return 0;
    }
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs());
    to_tidy(&list(clips_dir), keep_days, max_gb, now).iter().filter(|p| forget(p).is_ok()).count()
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
        out.push(Entry { path, game: game.to_string(), name, bytes: meta.len(), modified, favorite: false });
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

/// `count` small frames spread over the clip, for the trim bar; kept in the
/// cache like the thumbnail.
pub fn strip(ffmpeg_bin: &Path, clip: &Path, count: u32) -> Result<Vec<PathBuf>> {
    let dir = crate::config::base_dir().join("cache").join(format!("{}-strip", cache_key(clip)?));
    let frames = |d: &Path| -> Vec<PathBuf> {
        let mut v: Vec<PathBuf> = std::fs::read_dir(d)
            .map(|r| {
                r.filter_map(|e| e.ok()).map(|e| e.path()).filter(|p| p.extension().is_some_and(|x| x == "jpg")).collect()
            })
            .unwrap_or_default();
        v.sort();
        v
    };
    let have = frames(&dir);
    if have.len() as u32 >= count {
        return Ok(have);
    }
    std::fs::create_dir_all(&dir).with_context(|| format!("{} lässt sich nicht anlegen", dir.display()))?;
    let (duration, ..) = probe(&ffmpeg::probe_tool(ffmpeg_bin), clip)?;
    // One seek per frame is far quicker than decoding the whole clip.
    for i in 0..count {
        let at = format!("{:.3}", duration * (i as f64 + 0.5) / count as f64);
        let out = dir.join(format!("{i:02}.jpg"));
        let _ = ffmpeg::command(ffmpeg_bin)
            .args(["-loglevel", "error", "-y", "-ss", &at, "-i"])
            .arg(clip)
            .args(["-frames:v", "1", "-vf", "scale=-2:72", "-q:v", "6"])
            .arg(&out)
            .output();
    }
    Ok(frames(&dir))
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
    favorite_moved(clip, Some(&to));
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
    /// An animated GIF, 15 frames a second and 480 pixels wide, no sound.
    Gif,
    /// 9:16 from the middle of the picture, 1080×1920, for TikTok and Shorts.
    Vertical,
}

impl Target {
    /// What goes into the new file's name, and its extension.
    fn suffix(self) -> (&'static str, &'static str) {
        match self {
            Target::Trim => ("geschnitten", "mp4"),
            Target::Discord => ("Discord", "mp4"),
            Target::Gif => ("GIF", "gif"),
            Target::Vertical => ("Hochformat", "mp4"),
        }
    }
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
    let (suffix, ext) = target.suffix();
    let out = free(src.with_file_name(format!("{stem} ({suffix}).{ext}")));

    let mut factor = 1.0;
    loop {
        let args = export_args(s, src, &out, start, secs, tracks, height, edit, target, factor)?;
        run(ffmpeg_bin, &args, secs, progress)?;
        let bytes = std::fs::metadata(&out).map(|m| m.len()).unwrap_or(0);
        if target != Target::Discord || bytes <= DISCORD_BYTES || factor < 0.5 {
            anyhow::ensure!(bytes <= DISCORD_BYTES || target != Target::Discord, "Der Clip passt nicht unter 10 MB");
            return Ok(out);
        }
        // The encoder overshot; the next try aims lower by the same ratio.
        factor *= DISCORD_BYTES as f64 / bytes as f64 * 0.95;
    }
}

/// Whether `url` is a Discord webhook — the file goes nowhere else.
pub fn webhook_ok(url: &str) -> bool {
    let Some(rest) = url.trim().strip_prefix("https://") else { return false };
    let host = rest.split('/').next().unwrap_or_default();
    let discord = ["discord.com", "discordapp.com"].iter().any(|d| host == *d || host.ends_with(&format!(".{d}")));
    discord && rest[host.len()..].starts_with("/api/webhooks/")
}

/// Posts `file` into the Discord channel behind `webhook`, with curl.exe,
/// which every Windows since 10 brings along.
pub fn send_to_discord(webhook: &str, file: &Path) -> Result<()> {
    anyhow::ensure!(webhook_ok(webhook), "Das ist kein Discord-Webhook (https://discord.com/api/webhooks/…)");
    let mut cmd = std::process::Command::new(if cfg!(windows) { "curl.exe" } else { "curl" });
    cmd.args(["-sS", "--fail-with-body", "-F"]).arg(format!("files[0]=@{}", file.display())).arg(webhook.trim());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0800_0000);
    }
    let out = cmd.output().context("curl lässt sich nicht starten")?;
    if !out.status.success() {
        let why = String::from_utf8_lossy(&out.stdout);
        let why = if why.trim().is_empty() { String::from_utf8_lossy(&out.stderr) } else { why };
        bail!("Discord hat den Clip nicht angenommen: {}", why.trim());
    }
    Ok(())
}

/// `path`, or the first `path (2)`, `path (3)`, … that is still free.
fn free(path: PathBuf) -> PathBuf {
    if !path.exists() {
        return path;
    }
    let stem = path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
    let ext = path.extension().map(|e| e.to_string_lossy().into_owned()).unwrap_or_default();
    (2..).map(|n| path.with_file_name(format!("{stem} ({n}).{ext}"))).find(|p| !p.exists()).unwrap_or(path)
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
        (_, 0) | (Target::Gif, _) => {}
        (_, 1) => {
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
        (Target::Discord | Target::Vertical, _) => {
            graph.push(format!("[0:a:0]volume={gv}[g];[0:a:1]volume={mv}[m];[g][m]amix=inputs=2:normalize=0[a0]"));
            maps.push("[a0]".into());
        }
    }

    let budget = budget(secs, DISCORD_BYTES, src_height);
    if target == Target::Gif {
        // Its own palette per clip, or GIF's 256 colours turn to blotches.
        graph.push(
            "[0:v:0]fps=15,scale=480:-2:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=diff[p];\
             [s1][p]paletteuse=dither=bayer:bayer_scale=4[v]"
                .into(),
        );
        maps[0] = "[v]".into();
    }
    if target == Target::Vertical {
        graph.push("[0:v:0]crop=ih*9/16:ih,scale=1080:1920:flags=lanczos[v]".into());
        maps[0] = "[v]".into();
    }
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
        Target::Gif => {
            a.extend(["-an", "-loop", "0"].map(String::from));
            a.push(out.to_string_lossy().into_owned());
            return Ok(a);
        }
        Target::Vertical => {
            let h264 = Settings { codec: Codec::H264, ..s.clone() };
            a.extend(ffmpeg::encoder_args(&h264)?);
            a.extend(["-c:a".into(), "aac".into(), "-b:a".into(), format!("{}k", s.audio_kbit), "-ac".into(), "2".into()]);
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

    fn entry(name: &str, days_old: u64, gb: f64, favorite: bool) -> Entry {
        Entry {
            path: PathBuf::from(name),
            game: String::new(),
            name: name.into(),
            bytes: (gb * 1e9) as u64,
            modified: 100 * 86_400 - days_old * 86_400,
            favorite,
        }
    }

    /// Weg kommt, was zu alt ist, dann das Älteste, bis der Rest passt —
    /// Favoriten nie.
    #[test]
    fn tidying_spares_favorites() {
        let now = 100 * 86_400;
        let clips = [entry("alt", 40, 1.0, false), entry("alt-fav", 50, 1.0, true), entry("neu", 1, 1.0, false)];
        assert_eq!(to_tidy(&clips, 30, 0, now), [PathBuf::from("alt")]);
        assert_eq!(to_tidy(&clips, 0, 2, now), [PathBuf::from("alt")], "3 GB, 2 erlaubt: das älteste Nicht-Favorit");
        assert_eq!(to_tidy(&clips, 0, 1, now), [PathBuf::from("alt"), PathBuf::from("neu")], "der Favorit bleibt");
        assert!(to_tidy(&clips, 0, 0, now).is_empty(), "0 schaltet beides ab");
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
        let s = Settings { gpu: crate::config::Gpu::Amd, codec: Codec::Hevc, ..Default::default() };
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

    /// Ein GIF hat keinen Ton und eine eigene Palette.
    #[test]
    fn a_gif_has_a_palette_and_no_sound() {
        let a = args(Target::Gif, 2, &edit());
        let at = |flag: &str| a.iter().position(|x| x == flag).map(|i| a[i + 1].clone());
        let graph = at("-filter_complex").unwrap();
        assert!(graph.contains("palettegen") && graph.contains("paletteuse"), "{graph}");
        assert!(!graph.contains("[0:a"), "kein Ton im GIF");
        assert!(a.contains(&"-an".to_string()));
        assert!(!a.contains(&"-c:v".to_string()), "GIF braucht keinen Hardware-Kodierer");
    }

    /// Hochformat: Mitte ausschneiden, H.264, eine gemischte Spur.
    #[test]
    fn vertical_crops_the_middle() {
        let a = args(Target::Vertical, 2, &edit());
        let at = |flag: &str| a.iter().position(|x| x == flag).map(|i| a[i + 1].clone());
        let graph = at("-filter_complex").unwrap();
        assert!(graph.contains("crop=ih*9/16:ih,scale=1080:1920"), "{graph}");
        assert!(graph.contains("amix=inputs=2"));
        assert_eq!(at("-c:v").as_deref(), Some("h264_amf"));
    }

    #[test]
    fn discord_webhooks_are_checked() {
        assert!(webhook_ok("https://discord.com/api/webhooks/123/abc"));
        assert!(webhook_ok("https://discordapp.com/api/webhooks/1/x"));
        assert!(webhook_ok("https://canary.discord.com/api/webhooks/1/x"));
        assert!(!webhook_ok("https://example.com/api/webhooks/1/x"));
        assert!(!webhook_ok("http://discord.com/api/webhooks/1/x"), "nur https");
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
