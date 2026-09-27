//! Finding ffmpeg and putting its command lines together.

use crate::config::{Codec, Settings};
use anyhow::{Context, Result, bail};
use std::path::{Path, PathBuf};
use std::process::Command;

/// Suppresses the console window an ffmpeg child would otherwise flash up.
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// ffmpeg as clipd starts it: the copy in `<base>/bin` first, so a portable
/// folder stays self-contained, then whatever is on PATH.
pub fn find() -> Result<PathBuf> {
    let own = crate::config::base_dir().join("bin").join(exe("ffmpeg"));
    if own.is_file() {
        return Ok(own);
    }
    if let Some(found) = on_path("ffmpeg") {
        return Ok(found);
    }
    bail!("ffmpeg fehlt. Lege es nach {} oder in den PATH.", crate::config::base_dir().join("bin").display())
}

/// ffprobe next to the ffmpeg that was found.
pub fn probe_tool(ffmpeg: &Path) -> PathBuf {
    ffmpeg.with_file_name(exe("ffprobe"))
}

fn exe(name: &str) -> String {
    format!("{name}{}", std::env::consts::EXE_SUFFIX)
}

fn on_path(name: &str) -> Option<PathBuf> {
    let file = exe(name);
    std::env::split_paths(&std::env::var_os("PATH")?).map(|d| d.join(&file)).find(|p| p.is_file())
}

/// A command that writes no console window and reads no stdin, so it cannot
/// steal the terminal or block on a prompt.
pub fn command(ffmpeg: &Path) -> Command {
    let mut cmd = Command::new(ffmpeg);
    cmd.args(["-hide_banner", "-nostdin"]);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(CREATE_NO_WINDOW);
    }
    cmd
}

/// The `ddagrab` source: the Desktop Duplication API hands over frames that
/// already live on the graphics card, so nothing crosses the PCIe bus twice.
pub fn source(s: &Settings) -> String {
    format!("ddagrab=output_idx={}:framerate={}:draw_mouse={}", s.monitor, s.fps, u8::from(s.draw_mouse))
}

/// The capture that keeps the buffer full. Writes numbered segments into `dir`.
///
/// Two details decide whether this works at all, both learned the hard way:
/// `-g` must match the segment length, because the muxer can only open a new
/// file on a keyframe, and the encoder is fed the BGRA frames ddagrab produces
/// so nvenc does the conversion to yuv420p itself, on the chip.
///
/// With `audio`, ffmpeg reads raw samples from its stdin as a second input;
/// `crate::audio` keeps that pipe fed.
pub fn capture_args(s: &Settings, dir: &Path, audio: Option<&crate::audio::Format>) -> Result<Vec<String>> {
    fn push(a: &mut Vec<String>, args: &[&str]) {
        a.extend(args.iter().map(|x| x.to_string()));
    }
    let pattern = dir.join(format!("seg%08d.{}", s.codec.segment_ext()));
    let a = &mut Vec::new();
    push(a, &["-loglevel", "error"]);
    push(a, &["-f", "lavfi", "-i", &source(s)]);
    if let Some(format) = audio {
        a.extend(format.input_args()?);
        // Without a queue of its own the pipe would stall the whole capture
        // whenever the encoder is busy.
        push(a, &["-thread_queue_size", "1024", "-i", "pipe:0"]);
        push(a, &["-map", "0:v:0", "-map", "1:a:0"]);
        push(a, &["-c:a", "aac", "-b:a", &format!("{}k", s.audio_kbit)]);
    }
    push(a, &["-c:v", s.codec.encoder()]);
    push(a, &["-preset", &s.preset]);
    // Low latency, so a frame does not sit in the encoder while the buffer ages.
    push(a, &["-tune", "ll"]);
    // Constant quality. nvenc only honours -cq once the bitrate cap is lifted.
    push(a, &["-rc", "vbr", "-cq", &s.quality.to_string(), "-b:v", "0"]);
    push(a, &["-g", &s.gop().to_string()]);
    push(a, &["-f", "segment"]);
    push(a, &["-segment_time", &s.segment_secs.to_string()]);
    push(a, &["-segment_format", s.codec.segment_format()]);
    push(a, &["-reset_timestamps", "1"]);
    // Hands every packet straight to the output layer. That layer still
    // collects 256 KiB before it writes, so this does not make an open segment
    // readable right away — it only shortens the wait.
    push(a, &["-flush_packets", "1"]);
    a.push(pattern.to_string_lossy().into_owned());
    Ok(std::mem::take(a))
}

/// Stitching buffer segments into the finished clip. Copies the streams, so no
/// second encode happens and a clip is ready in well under a second.
pub fn concat_args(list: &Path, out: &Path) -> Vec<String> {
    vec![
        "-loglevel".into(),
        "error".into(),
        "-f".into(),
        "concat".into(),
        // The list holds absolute paths, which concat refuses to trust by default.
        "-safe".into(),
        "0".into(),
        "-i".into(),
        list.to_string_lossy().into_owned(),
        "-c".into(),
        "copy".into(),
        "-movflags".into(),
        "+faststart".into(),
        "-y".into(),
        out.to_string_lossy().into_owned(),
    ]
}

/// The list file the concat demuxer reads. Written without a byte order mark,
/// which the demuxer would report as an unknown keyword, and with forward
/// slashes so no backslash is read as an escape.
pub fn concat_list(segments: &[PathBuf]) -> String {
    let mut out = String::new();
    for seg in segments {
        let path = seg.to_string_lossy().replace('\\', "/").replace('\'', r"'\''");
        out.push_str(&format!("file '{path}'\n"));
    }
    out
}

/// Asks ddagrab which desktops it can see, by grabbing a single frame from each
/// index until one fails. That is the only answer that matches what the capture
/// will really do.
pub fn monitors(ffmpeg: &Path) -> Vec<(u32, String)> {
    let mut found = Vec::new();
    for idx in 0..16 {
        let out = command(ffmpeg)
            .args(["-loglevel", "error", "-f", "lavfi", "-i", &format!("ddagrab=output_idx={idx}")])
            .args(["-frames:v", "1", "-f", "null", "-"])
            .output();
        match out {
            Ok(o) if o.status.success() => found.push((idx, size_of(ffmpeg, idx).unwrap_or_else(|| "?".into()))),
            _ => break,
        }
    }
    found
}

/// Resolution of one desktop, read back from a single captured frame.
fn size_of(ffmpeg: &Path, idx: u32) -> Option<String> {
    let out = command(ffmpeg)
        .args(["-loglevel", "info", "-f", "lavfi", "-i", &format!("ddagrab=output_idx={idx}")])
        .args(["-frames:v", "1", "-f", "null", "-"])
        .output()
        .ok()?;
    // ffmpeg describes the input stream on stderr: "... d3d11, 1920x1080 ...".
    let text = String::from_utf8_lossy(&out.stderr).into_owned();
    let at = text.find("d3d11,")?;
    let rest = &text[at + "d3d11,".len()..];
    let word = rest.split_whitespace().next()?;
    let (w, h) = word.split_once('x')?;
    (w.parse::<u32>().is_ok() && h.parse::<u32>().is_ok()).then(|| format!("{w}x{h}"))
}

/// Length of a finished file in seconds, for reporting a saved clip.
pub fn duration(ffprobe: &Path, file: &Path) -> Option<f64> {
    let out = Command::new(ffprobe)
        .args(["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0"])
        .arg(file)
        .output()
        .ok()?;
    String::from_utf8_lossy(&out.stdout).trim().parse().ok()
}

/// Checks that this ffmpeg can actually do what clipd needs, so a missing
/// encoder is reported at start instead of silently leaving the buffer empty.
pub fn check(ffmpeg: &Path, codec: Codec) -> Result<()> {
    let out =
        command(ffmpeg).args(["-loglevel", "quiet", "-encoders"]).output().context("ffmpeg lässt sich nicht starten")?;
    let list = String::from_utf8_lossy(&out.stdout);
    if !list.contains(codec.encoder()) {
        bail!("Dieses ffmpeg kennt {} nicht — ist es ein Build ohne NVENC?", codec.encoder());
    }
    let out =
        command(ffmpeg).args(["-loglevel", "quiet", "-filters"]).output().context("ffmpeg lässt sich nicht starten")?;
    if !String::from_utf8_lossy(&out.stdout).contains("ddagrab") {
        bail!("Dieses ffmpeg kennt ddagrab nicht — es ist zu alt oder kein Windows-Build.");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn settings() -> Settings {
        Settings { fps: 60, segment_secs: 2, quality: 20, monitor: 1, ..Default::default() }
    }

    fn stereo() -> crate::audio::Format {
        crate::audio::Format { rate: 48_000, channels: 2, bits: 32, float: true, device: "Test".into() }
    }

    fn args(s: &Settings, audio: Option<&crate::audio::Format>) -> Vec<String> {
        capture_args(s, Path::new(r"C:\buf"), audio).expect("Argumente")
    }

    /// Der Keyframe-Abstand muss zur Segmentlänge passen, sonst entsteht eine
    /// einzige endlose Datei statt eines Rings.
    #[test]
    fn capture_keeps_gop_and_segment_together() {
        let a = args(&settings(), None);
        let at = |flag: &str| a.iter().position(|x| x == flag).map(|i| a[i + 1].clone());
        assert_eq!(at("-g").as_deref(), Some("120"), "60 fps * 2 s");
        assert_eq!(at("-segment_time").as_deref(), Some("2"));
        assert_eq!(at("-segment_format").as_deref(), Some("mpegts"));
        assert_eq!(at("-c:v").as_deref(), Some("hevc_nvenc"));
        assert_eq!(at("-cq").as_deref(), Some("20"));
        assert_eq!(at("-b:v").as_deref(), Some("0"), "ohne das greift -cq nicht");
        assert!(a.contains(&"-flush_packets".to_string()), "sonst fehlt dem Clip das Ende");
        assert!(a.last().unwrap().ends_with(r"buf\seg%08d.ts"));
    }

    /// Die Quelle muss den gewählten Monitor und die Bildrate nennen.
    #[test]
    fn source_names_monitor_and_framerate() {
        assert_eq!(source(&settings()), "ddagrab=output_idx=1:framerate=60:draw_mouse=0");
        let s = Settings { draw_mouse: true, ..settings() };
        assert!(source(&s).ends_with("draw_mouse=1"));
    }

    /// AV1 landet in Matroska, weil MPEG-TS es nicht trägt.
    #[test]
    fn av1_uses_matroska_segments() {
        let s = Settings { codec: Codec::Av1, ..settings() };
        let a = args(&s, None);
        assert!(a.contains(&"matroska".to_string()));
        assert!(a.last().unwrap().ends_with(".mkv"));
    }

    /// Mit Ton liest ffmpeg die Samples aus der eigenen Eingabe und muss
    /// beide Spuren ausdrücklich übernehmen — ohne -map nähme es nur eine.
    #[test]
    fn audio_comes_from_the_pipe_and_both_tracks_are_mapped() {
        let s = Settings { audio_kbit: 192, ..settings() };
        let a = args(&s, Some(&stereo()));
        let at = |flag: &str| a.iter().position(|x| x == flag).map(|i| a[i + 1].clone());
        assert_eq!(at("-i").as_deref(), Some(source(&s).as_str()), "Bild bleibt Eingang 0");
        assert!(a.windows(2).any(|w| w[0] == "-i" && w[1] == "pipe:0"), "Ton als Eingang 1");
        assert_eq!(at("-f").as_deref(), Some("lavfi"));
        assert!(a.windows(2).any(|w| w[0] == "-map" && w[1] == "0:v:0"));
        assert!(a.windows(2).any(|w| w[0] == "-map" && w[1] == "1:a:0"));
        assert_eq!(at("-c:a").as_deref(), Some("aac"));
        assert_eq!(at("-b:a").as_deref(), Some("192k"));
        assert!(a.contains(&"f32le".to_string()), "rohes Format genannt");
        assert!(a.contains(&"-thread_queue_size".to_string()), "sonst blockiert die Pipe die Aufnahme");
    }

    /// Ohne Ton darf keine Spur gemappt und kein Tonkodierer genannt werden.
    #[test]
    fn without_audio_nothing_audio_is_named() {
        let a = args(&settings(), None);
        assert!(!a.contains(&"-map".to_string()));
        assert!(!a.contains(&"aac".to_string()));
        assert!(!a.contains(&"pipe:0".to_string()));
    }

    /// Die Liste braucht Schrägstriche und darf kein BOM bekommen; Apostrophe
    /// im Pfad müssen maskiert werden.
    #[test]
    fn concat_list_is_demuxer_safe() {
        let segs = [PathBuf::from(r"C:\buf\seg1.ts"), PathBuf::from(r"C:\Hattis Clips\seg2.ts")];
        let text = concat_list(&segs);
        assert_eq!(text, "file 'C:/buf/seg1.ts'\nfile 'C:/Hattis Clips/seg2.ts'\n");
        assert!(!text.starts_with('\u{feff}'), "kein BOM");
        let odd = concat_list(&[PathBuf::from(r"C:\Peter's\a.ts")]);
        assert_eq!(odd, "file 'C:/Peter'\\''s/a.ts'\n");
    }

    /// Ein Clip darf nicht neu kodiert werden, sonst dauert das Speichern lange.
    #[test]
    fn concat_copies_the_streams() {
        let a = concat_args(Path::new(r"C:\buf\list.txt"), Path::new(r"C:\clips\a.mp4"));
        let at = |flag: &str| a.iter().position(|x| x == flag).map(|i| a[i + 1].clone());
        assert_eq!(at("-c").as_deref(), Some("copy"));
        assert_eq!(at("-safe").as_deref(), Some("0"), "absolute Pfade in der Liste");
        assert_eq!(a.last().unwrap(), r"C:\clips\a.mp4");
    }
}
