//! Finding ffmpeg and putting its command lines together.

use crate::config::{Gpu, Settings};
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

/// Where clipd fetches ffmpeg from when there is none: BtbN's current build
/// with shared libraries — it has ddagrab, NVENC and AMF, and is half the
/// size of the static one.
#[cfg(windows)]
pub const DOWNLOAD: &str =
    "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl-shared.zip";

/// ffmpeg, fetched into `<base>/bin` first if there is none anywhere.
/// `progress` hears bytes so far and the total, when the server says it.
///
/// Uses curl.exe and tar.exe, which every Windows since 10 1803 brings, so
/// clipd needs no HTTP or ZIP code of its own for a one-time download.
#[cfg(windows)]
pub fn ensure(progress: &mut dyn FnMut(u64, Option<u64>)) -> Result<PathBuf> {
    use std::os::windows::process::CommandExt;
    if let Ok(found) = find() {
        return Ok(found);
    }
    let bin = crate::config::base_dir().join("bin");
    std::fs::create_dir_all(&bin).with_context(|| format!("{} lässt sich nicht anlegen", bin.display()))?;
    let zip = bin.join("ffmpeg.zip");
    let quiet = |mut c: Command| {
        c.creation_flags(CREATE_NO_WINDOW);
        c
    };

    // The size first, so the progress can say how far along it is.
    let mut head = quiet(Command::new("curl.exe"));
    head.args(["-sIL", DOWNLOAD]);
    let total = head.output().ok().and_then(|o| content_length(&String::from_utf8_lossy(&o.stdout)));

    let mut get = quiet(Command::new("curl.exe"));
    get.args(["-sSL", "--fail", "--retry", "3", "-o"]).arg(&zip).arg(DOWNLOAD);
    let mut child = get.stderr(std::process::Stdio::piped()).spawn().context("curl.exe lässt sich nicht starten")?;
    let status = loop {
        if let Some(status) = child.try_wait()? {
            break status;
        }
        progress(std::fs::metadata(&zip).map_or(0, |m| m.len()), total);
        std::thread::sleep(std::time::Duration::from_millis(250));
    };
    if !status.success() {
        let _ = std::fs::remove_file(&zip);
        let mut why = String::new();
        let _ = std::io::Read::read_to_string(&mut child.stderr.take().context("curl")?, &mut why);
        bail!("ffmpeg ließ sich nicht laden: {}", why.trim());
    }
    progress(total.unwrap_or(0), total);

    // Only the bin folder, without the folder the zip wraps it in. Unpacked
    // aside first and ffmpeg.exe moved in last: an ffmpeg.exe without its
    // DLLs would count as found and never be fetched again.
    let unpacked = bin.join("neu");
    let _ = std::fs::remove_dir_all(&unpacked);
    std::fs::create_dir_all(&unpacked).with_context(|| format!("{} lässt sich nicht anlegen", unpacked.display()))?;
    let mut untar = quiet(Command::new("tar.exe"));
    untar.args(["-xf"]).arg(&zip).args(["--strip-components", "2", "-C"]).arg(&unpacked).arg("*/bin/*");
    let out = untar.output().context("tar.exe lässt sich nicht starten")?;
    let _ = std::fs::remove_file(&zip);
    if !out.status.success() {
        let _ = std::fs::remove_dir_all(&unpacked);
        bail!("ffmpeg ließ sich nicht entpacken: {}", String::from_utf8_lossy(&out.stderr).trim());
    }
    let _ = std::fs::remove_file(unpacked.join(exe("ffplay")));
    let mut files: Vec<_> = std::fs::read_dir(&unpacked)?.filter_map(|e| e.ok()).map(|e| e.path()).collect();
    files.sort_by_key(|p| p.file_name().is_some_and(|n| n == exe("ffmpeg").as_str()));
    for file in files {
        let to = bin.join(file.file_name().context("Dateiname")?);
        std::fs::rename(&file, &to).with_context(|| format!("{} lässt sich nicht anlegen", to.display()))?;
    }
    let _ = std::fs::remove_dir_all(&unpacked);
    find()
}

#[cfg(not(windows))]
pub fn ensure(_progress: &mut dyn FnMut(u64, Option<u64>)) -> Result<PathBuf> {
    find()
}

/// The size of the last response in `curl -I -L` output, after all redirects.
fn content_length(headers: &str) -> Option<u64> {
    headers
        .lines()
        .filter_map(|l| l.split_once(':'))
        .filter(|(k, _)| k.trim().eq_ignore_ascii_case("content-length"))
        .filter_map(|(_, v)| v.trim().parse::<u64>().ok())
        .rfind(|&n| n > 0)
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
    let mut cmd = hidden(Command::new(ffmpeg));
    cmd.args(["-hide_banner", "-nostdin"]);
    cmd
}

/// `cmd` without a console window: the app has none of its own, so every
/// child would open one, and over a game that can cost it its fullscreen.
pub fn hidden(mut cmd: Command) -> Command {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(CREATE_NO_WINDOW);
    }
    cmd
}

fn push(a: &mut Vec<String>, args: &[&str]) {
    a.extend(args.iter().map(|x| x.to_string()));
}

/// The `ddagrab` source: the Desktop Duplication API hands over frames that
/// already live on the graphics card, so nothing crosses the PCIe bus twice.
/// nvenc takes its BGRA as it is and makes yuv420p itself, on the chip.
pub fn ddagrab(s: &Settings) -> String {
    format!("ddagrab=output_idx={}:framerate={}:draw_mouse={}", s.monitor, s.fps, u8::from(s.draw_mouse))
}

/// One window instead of the screen, through Windows Graphics Capture. It
/// only delivers a frame when the window changes, so `fps` makes the rate
/// steady again for the keyframe spacing; the size is rounded to even numbers,
/// which H.264 needs, and kept when the window is resized.
pub fn gfxcapture(s: &Settings, hwnd: u64) -> String {
    format!(
        "gfxcapture=hwnd={hwnd}:max_framerate={fps}:capture_cursor={mouse}:width=-2:height=-2:resize_mode=scale_aspect,fps={fps}",
        fps = s.fps,
        mouse = u8::from(s.draw_mouse)
    )
}

/// The picture source: the chosen window, or the screen.
fn grab(s: &Settings) -> String {
    match s.window {
        Some(hwnd) => gfxcapture(s, hwnd),
        None => ddagrab(s),
    }
}

/// ddagrab for an AMD card. AMF's encoders refuse ddagrab's BGRA textures
/// (`SubmitInput` error 18), but `vpp_amf` takes them and makes nv12 on the
/// chip, so the picture still never leaves the graphics card.
///
/// AMF's own capture, `vsrc_amf`, looks like the obvious choice and is not:
/// its first frame at times takes 5 to 30 seconds, it never draws the
/// pointer, and it records the first monitor rather than fail on a missing
/// one. The CPU way round costs five times the time.
pub fn ddagrab_amf(s: &Settings) -> String {
    format!("{},vpp_amf=format=nv12:color_profile=bt709:out_color_range=studio", grab(s))
}

/// AMF knows three speeds where nvenc has seven presets; p5, the default,
/// lands on the middle one.
pub fn amf_quality(preset: &str) -> &'static str {
    match preset {
        "p1" | "p2" => "speed",
        "p6" | "p7" => "quality",
        _ => "balanced",
    }
}

/// The picture half of the capture: the lavfi source and the encoder
/// arguments. The capture and the trial in [`pick_gpu`] both come from here,
/// so the trial tests exactly what will run.
///
/// `-g` must match the segment length on either card, because the muxer can
/// only open a new file on a keyframe.
fn video(s: &Settings) -> Result<(String, Vec<String>)> {
    let q = s.quality.to_string();
    let gop = s.gop().to_string();
    let e = &mut Vec::new();
    let source = match s.gpu {
        Gpu::Nvidia => {
            push(e, &["-c:v", s.codec.nvenc(), "-preset", &s.preset]);
            // Low latency, so a frame does not sit in the encoder while the buffer ages.
            push(e, &["-tune", "ll"]);
            // Constant quality. nvenc only honours -cq once the bitrate cap is lifted.
            push(e, &["-rc", "vbr", "-cq", &q, "-b:v", "0"]);
            push(e, &["-g", &gop]);
            grab(s)
        }
        Gpu::Amd => {
            push(e, &["-c:v", s.codec.amf(), "-usage", "lowlatency", "-quality", amf_quality(&s.preset)]);
            // Constant QP, which every AMF chip can do and which costs the
            // least. QVBR would be the closer match to nvenc's -cq, but its
            // pre-analysis alone falls behind real time on a laptop chip.
            push(e, &["-rc", "cqp", "-qp_i", &q, "-qp_p", &q]);
            push(e, &["-g", &gop, "-forced_idr", "1"]);
            ddagrab_amf(s)
        }
        Gpu::Auto => bail!("Welche Grafikkarte aufnimmt, steht noch nicht fest"),
    };
    Ok((source, std::mem::take(e)))
}

/// The encoder half of [`video`], for encoding a clip again at the quality
/// it was recorded with.
pub fn encoder_args(s: &Settings) -> Result<Vec<String>> {
    Ok(video(s)?.1)
}

/// The card's encoder aiming at a bitrate instead of a quality, for a file
/// that has to stay under a size.
pub fn bitrate_args(s: &Settings, kbps: u32) -> Result<Vec<String>> {
    let (b, max, buf) = (format!("{kbps}k"), format!("{}k", kbps * 13 / 10), format!("{}k", kbps * 2));
    let e = &mut Vec::new();
    match s.gpu {
        Gpu::Nvidia => push(e, &["-c:v", s.codec.nvenc(), "-preset", "p6", "-rc", "vbr"]),
        Gpu::Amd => push(e, &["-c:v", s.codec.amf(), "-usage", "transcoding", "-quality", "quality", "-rc", "vbr_peak"]),
        Gpu::Auto => bail!("Welche Grafikkarte kodiert, steht noch nicht fest"),
    }
    push(e, &["-b:v", &b, "-maxrate", &max, "-bufsize", &buf, "-pix_fmt", "yuv420p"]);
    Ok(std::mem::take(e))
}

/// The capture that keeps the buffer full: one MPEG-TS stream on stdout,
/// which `crate::buffer` keeps in memory.
///
/// With `audio`, ffmpeg reads raw samples from its stdin as a second input;
/// `crate::audio` keeps that pipe fed.
pub fn capture_args(s: &Settings, audio: Option<&crate::audio::Format>) -> Result<Vec<String>> {
    let (source, encoder) = video(s)?;
    let a = &mut Vec::new();
    push(a, &["-loglevel", "error"]);
    push(a, &["-f", "lavfi", "-i", &source]);
    if let Some(format) = audio {
        a.extend(format.input_args()?);
        // No -thread_queue_size: current ffmpeg reads every input on a thread
        // of its own and refuses the option on an input. Should the pipe back
        // up anyway, the writer in `crate::audio` follows the clock, so a
        // stall costs a gap in the sound but never pushes it off the picture.
        push(a, &["-i", "pipe:0"]);
        push(a, &["-map", "0:v:0"]);
        if format.mic_channels == 0 {
            push(a, &["-map", "1:a:0"]);
        } else {
            // The pipe carries the game's channels and then the microphone's;
            // two tracks of their own let the editor mute one of them.
            push(
                a,
                &["-filter_complex", &split_mic(format.channels, format.mic_channels), "-map", "[game]", "-map", "[mic]"],
            );
            push(a, &["-metadata:s:a:0", "title=Spiel", "-metadata:s:a:1", "title=Mikrofon"]);
        }
        push(a, &["-c:a", "aac", "-b:a", &format!("{}k", s.audio_kbit)]);
    }
    a.extend(encoder);
    // Every packet goes down the pipe as soon as it is muxed, so the ring is
    // never more than a frame behind. The muxer would otherwise gather the
    // sound into PES packets of about 3 KB — a sixth of a second — and a clip
    // would end with that much silence.
    push(a, &["-f", "mpegts", "-pes_payload_size", "0", "-flush_packets", "1", "pipe:1"]);
    Ok(std::mem::take(a))
}

/// Splits the shared sound input into the game's channels and the
/// microphone's, which follow them.
pub fn split_mic(game: u16, mic: u16) -> String {
    let pan = |from: u16, n: u16| (0..n).map(|c| format!("|c{c}=c{}", from + c)).collect::<String>();
    format!("[1:a]asplit[a0][a1];[a0]pan={game}c{}[game];[a1]pan={mic}c{}[mic]", pan(0, game), pan(game, mic))
}

/// Puts a piece of the MPEG-TS stream into an MP4. Copies the streams, so no
/// second encode happens and a clip is ready in well under a second.
pub fn remux_args(input: &str, out: &Path) -> Vec<String> {
    let mut a: Vec<String> = ["-loglevel", "error", "-f", "mpegts", "-i", input].map(String::from).to_vec();
    // Every stream: without this ffmpeg keeps one sound track and drops the
    // microphone's.
    a.extend(["-map", "0", "-c", "copy"].map(String::from));
    // The piece starts wherever the stream happened to be; the clip starts at 0.
    a.extend(["-avoid_negative_ts", "make_zero", "-movflags", "+faststart", "-y"].map(String::from));
    a.push(out.to_string_lossy().into_owned());
    a
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
    let out = hidden(Command::new(ffprobe))
        .args(["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0"])
        .arg(file)
        .output()
        .ok()?;
    String::from_utf8_lossy(&out.stdout).trim().parse().ok()
}

/// Settles which card records, so a missing encoder is reported at start
/// instead of silently leaving the buffer empty. `Auto` tries NVIDIA first,
/// then AMD; a card named in the settings is only checked.
///
/// Each try encodes one frame exactly the way the capture will. Nothing less
/// is a real answer: the usual Windows builds list NVENC and AMF whether or
/// not the machine has either card, and only opening the encoder tells.
pub fn pick_gpu(ffmpeg: &Path, s: &Settings) -> Result<Gpu> {
    let listed = |what: &str| -> Result<String> {
        let out = command(ffmpeg).args(["-loglevel", "quiet", what]).output().context("ffmpeg lässt sich nicht starten")?;
        Ok(String::from_utf8_lossy(&out.stdout).into_owned())
    };
    let (encoders, filters) = (listed("-encoders")?, listed("-filters")?);
    let tries: &[Gpu] = match s.gpu {
        Gpu::Auto => &[Gpu::Nvidia, Gpu::Amd],
        Gpu::Nvidia => &[Gpu::Nvidia],
        Gpu::Amd => &[Gpu::Amd],
    };
    let mut why = Vec::new();
    for &gpu in tries {
        let trial = Settings { gpu, ..s.clone() };
        let outcome = match build_lacks(&encoders, &filters, &trial) {
            Some(missing) => Err(missing),
            None => try_frame(ffmpeg, &trial),
        };
        match outcome {
            Ok(()) => return Ok(gpu),
            Err(e) => why.push(format!("{}: {e}", gpu.label())),
        }
    }
    bail!("Keine Grafikkarte nimmt hier {} auf:\n  {}", s.codec.label(), why.join("\n  "))
}

/// What this ffmpeg build is missing for the card in `s`, judged from its
/// `-encoders` and `-filters` lists.
fn build_lacks(encoders: &str, filters: &str, s: &Settings) -> Option<String> {
    let (encoder, sources): (_, &[&str]) = match s.gpu {
        Gpu::Nvidia => (s.codec.nvenc(), &["ddagrab"]),
        Gpu::Amd => (s.codec.amf(), &["ddagrab", "vpp_amf"]),
        Gpu::Auto => return None,
    };
    let lists = |text: &str, name: &str| text.split_whitespace().any(|w| w == name);
    if !lists(encoders, encoder) {
        return Some(format!("dieses ffmpeg kennt {encoder} nicht"));
    }
    let missing = sources.iter().find(|f| !lists(filters, f))?;
    Some(format!("dieses ffmpeg kennt {missing} nicht — es ist zu alt oder kein Windows-Build"))
}

/// Encodes a single frame the way the capture will.
fn try_frame(ffmpeg: &Path, s: &Settings) -> Result<(), String> {
    let (source, encoder) = video(s).map_err(|e| e.to_string())?;
    let out = command(ffmpeg)
        .args(["-loglevel", "error", "-f", "lavfi", "-i", &source, "-frames:v", "1"])
        .args(&encoder)
        .args(["-f", "null", "-"])
        .output()
        .map_err(|e| format!("ffmpeg lässt sich nicht starten: {e}"))?;
    if out.status.success() { Ok(()) } else { Err(complaint(&String::from_utf8_lossy(&out.stderr))) }
}

/// The first thing ffmpeg complained about, without the `[hevc_amf @ 0x…]`
/// tags in front of it.
fn complaint(stderr: &str) -> String {
    let Some(mut line) = stderr.lines().map(str::trim).find(|l| !l.is_empty()) else {
        return "ffmpeg ist ohne Meldung gescheitert".into();
    };
    while let Some((_, rest)) = line.strip_prefix('[').and_then(|l| l.split_once("] ")) {
        line = rest;
    }
    line.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Codec;

    fn settings() -> Settings {
        Settings {
            fps: 60,
            segment_secs: 2,
            quality: 20,
            monitor: 1,
            gpu: Gpu::Nvidia,
            codec: Codec::Hevc,
            ..Default::default()
        }
    }

    fn stereo() -> crate::audio::Format {
        crate::audio::Format {
            rate: 48_000,
            channels: 2,
            bits: 32,
            float: true,
            device: "Test".into(),
            mic_channels: 0,
            mic_device: None,
        }
    }

    fn args(s: &Settings, audio: Option<&crate::audio::Format>) -> Vec<String> {
        capture_args(s, audio).expect("Argumente")
    }

    /// Alle segment_secs ein Keyframe, und der Strom geht Paket für Paket in
    /// die Pipe, damit der Ring nie hinterherhängt.
    #[test]
    fn capture_streams_to_stdout_with_regular_keyframes() {
        let a = args(&settings(), None);
        let at = |flag: &str| a.iter().position(|x| x == flag).map(|i| a[i + 1].clone());
        assert_eq!(at("-g").as_deref(), Some("120"), "60 fps * 2 s");
        assert_eq!(at("-f").as_deref(), Some("lavfi"));
        assert!(a.ends_with(&["-flush_packets".to_string(), "1".into(), "pipe:1".into()]));
        assert!(a.windows(2).any(|w| w[0] == "-pes_payload_size" && w[1] == "0"), "sonst fehlt dem Clip der Ton am Ende");
        assert_eq!(at("-c:v").as_deref(), Some("hevc_nvenc"));
        assert_eq!(at("-cq").as_deref(), Some("20"));
        assert_eq!(at("-b:v").as_deref(), Some("0"), "ohne das greift -cq nicht");
    }

    /// Ein einzelnes Fenster kommt über Windows Graphics Capture, mit fester
    /// Bildrate und geraden Maßen; bei AMD folgt trotzdem vpp_amf.
    #[test]
    fn a_window_replaces_the_screen() {
        let s = Settings { window: Some(4242), ..settings() };
        let a = args(&s, None);
        let at = |flag: &str| a.iter().position(|x| x == flag).map(|i| a[i + 1].clone());
        let source = at("-i").unwrap();
        assert!(source.starts_with("gfxcapture=hwnd=4242:max_framerate=60:"), "{source}");
        assert!(source.contains("width=-2:height=-2"));
        assert!(source.ends_with(",fps=60"), "{source}");
        let amd = Settings { gpu: Gpu::Amd, ..s };
        let a = args(&amd, None);
        assert!(a.iter().any(|x| x.starts_with("gfxcapture=") && x.ends_with("out_color_range=studio")));
    }

    /// Die Quelle muss den gewählten Monitor und die Bildrate nennen.
    #[test]
    fn source_names_monitor_and_framerate() {
        assert_eq!(ddagrab(&settings()), "ddagrab=output_idx=1:framerate=60:draw_mouse=0");
        let s = Settings { draw_mouse: true, ..settings() };
        assert!(ddagrab(&s).ends_with("draw_mouse=1"));
    }

    /// Mit Ton liest ffmpeg die Samples aus der eigenen Eingabe und muss
    /// beide Spuren ausdrücklich übernehmen — ohne -map nähme es nur eine.
    #[test]
    fn audio_comes_from_the_pipe_and_both_tracks_are_mapped() {
        let s = Settings { audio_kbit: 192, ..settings() };
        let a = args(&s, Some(&stereo()));
        let at = |flag: &str| a.iter().position(|x| x == flag).map(|i| a[i + 1].clone());
        assert_eq!(at("-i").as_deref(), Some(ddagrab(&s).as_str()), "Bild bleibt Eingang 0");
        assert!(a.windows(2).any(|w| w[0] == "-i" && w[1] == "pipe:0"), "Ton als Eingang 1");
        assert_eq!(at("-f").as_deref(), Some("lavfi"));
        assert!(a.windows(2).any(|w| w[0] == "-map" && w[1] == "0:v:0"));
        assert!(a.windows(2).any(|w| w[0] == "-map" && w[1] == "1:a:0"));
        assert_eq!(at("-c:a").as_deref(), Some("aac"));
        assert_eq!(at("-b:a").as_deref(), Some("192k"));
        assert!(a.contains(&"f32le".to_string()), "rohes Format genannt");
        assert!(!a.contains(&"-thread_queue_size".to_string()), "neue ffmpeg-Builds lehnen das an einer Eingabe ab");
    }

    /// Mit Mikrofon entstehen zwei Tonspuren aus der einen Pipe: erst die
    /// Kanäle des Spiels, dann die des Mikrofons.
    #[test]
    fn microphone_becomes_a_second_track() {
        let f = crate::audio::Format { mic_channels: 2, ..stereo() };
        let a = args(&settings(), Some(&f));
        let at = |flag: &str| a.iter().position(|x| x == flag).map(|i| a[i + 1].clone());
        assert_eq!(
            at("-filter_complex").as_deref(),
            Some("[1:a]asplit[a0][a1];[a0]pan=2c|c0=c0|c1=c1[game];[a1]pan=2c|c0=c2|c1=c3[mic]")
        );
        assert!(a.windows(2).any(|w| w[0] == "-map" && w[1] == "[game]"));
        assert!(a.windows(2).any(|w| w[0] == "-map" && w[1] == "[mic]"));
        assert!(!a.windows(2).any(|w| w[0] == "-map" && w[1] == "1:a:0"));
        assert!(a.contains(&"-ac".to_string()) && a.contains(&"4".to_string()));
    }

    #[test]
    fn surround_game_keeps_its_channels() {
        assert_eq!(
            split_mic(6, 2),
            "[1:a]asplit[a0][a1];[a0]pan=6c|c0=c0|c1=c1|c2=c2|c3=c3|c4=c4|c5=c5[game];[a1]pan=2c|c0=c6|c1=c7[mic]"
        );
    }

    /// Ohne Ton darf keine Spur gemappt und kein Tonkodierer genannt werden.
    #[test]
    fn without_audio_nothing_audio_is_named() {
        let a = args(&settings(), None);
        assert!(!a.contains(&"-map".to_string()));
        assert!(!a.contains(&"aac".to_string()));
        assert!(!a.contains(&"pipe:0".to_string()));
    }

    /// Ein Clip wird nicht neu kodiert, behält jede Spur und beginnt bei 0.
    #[test]
    fn remux_copies_every_stream() {
        let a = remux_args("pipe:0", Path::new(r"C:\clips.mp4"));
        let at = |flag: &str| a.iter().position(|x| x == flag).map(|i| a[i + 1].clone());
        assert_eq!(at("-c").as_deref(), Some("copy"));
        assert_eq!(at("-map").as_deref(), Some("0"), "sonst fehlt die Mikrofonspur");
        assert_eq!(at("-i").as_deref(), Some("pipe:0"));
        assert_eq!(at("-avoid_negative_ts").as_deref(), Some("make_zero"));
        assert_eq!(a.last().unwrap(), r"C:\clips.mp4");
    }

    /// AMD nimmt wie NVIDIA mit ddagrab auf und wandelt auf dem Chip um;
    /// Keyframe-Abstand und Qualität gelten genauso.
    #[test]
    fn amd_captures_and_converts_on_the_chip() {
        let s = Settings { gpu: Gpu::Amd, ..settings() };
        let a = args(&s, None);
        let at = |flag: &str| a.iter().position(|x| x == flag).map(|i| a[i + 1].clone());
        let source = at("-i").unwrap();
        assert!(source.starts_with("ddagrab=output_idx=1:framerate=60:draw_mouse=0,"), "{source}");
        assert!(source.contains(",vpp_amf=format=nv12"), "ohne vpp_amf nimmt AMF die BGRA-Bilder nicht an");
        assert_eq!(at("-c:v").as_deref(), Some("hevc_amf"));
        assert_eq!(at("-rc").as_deref(), Some("cqp"));
        assert_eq!(at("-qp_i").as_deref(), Some("20"));
        assert_eq!(at("-qp_p").as_deref(), Some("20"));
        assert_eq!(at("-g").as_deref(), Some("120"), "60 fps * 2 s");
        assert_eq!(at("-quality").as_deref(), Some("balanced"), "p5");
        assert!(a.contains(&"pipe:1".to_string()));
    }

    /// nvenc-Optionen hätten bei AMF eine andere Bedeutung oder wären ungültig
    /// (`-preset p5` kennt AMF nicht).
    #[test]
    fn amd_gets_no_nvenc_options() {
        let a = args(&Settings { gpu: Gpu::Amd, ..settings() }, None);
        for flag in ["-preset", "-tune", "-cq"] {
            assert!(!a.contains(&flag.to_string()), "{flag} gehört zu nvenc");
        }
        assert!(!a.iter().any(|x| x.contains("nvenc") || x.contains("vsrc_amf")));
    }

    #[test]
    fn amd_codecs_use_amf_encoders() {
        for (codec, enc) in [(Codec::H264, "h264_amf"), (Codec::Hevc, "hevc_amf")] {
            let a = args(&Settings { gpu: Gpu::Amd, codec, ..settings() }, None);
            assert!(a.contains(&enc.to_string()), "{enc}");
        }
    }

    #[test]
    fn amf_speed_follows_the_preset() {
        assert_eq!(amf_quality("p1"), "speed");
        assert_eq!(amf_quality("p5"), "balanced");
        assert_eq!(amf_quality("p7"), "quality");
    }

    /// Ohne entschiedene Karte darf keine Aufnahme starten, sonst würde still
    /// irgendein Kodierer geraten.
    #[test]
    fn auto_must_be_settled_first() {
        let s = Settings { gpu: Gpu::Auto, ..settings() };
        assert!(capture_args(&s, None).is_err());
    }

    /// Was einem ffmpeg-Build fehlt, soll beim Namen genannt werden.
    #[test]
    fn names_what_the_build_lacks() {
        let encoders = " V....D hevc_nvenc  NVIDIA NVENC hevc encoder (codec hevc)\n V....D hevc_amf  AMD AMF HEVC encoder";
        let filters =
            " ... ddagrab  |->V  Grab Windows Desktop images using Desktop Duplication API\n ... vsrc_amf  |->V  AMD";
        let nvidia = Settings { gpu: Gpu::Nvidia, ..settings() };
        let amd = Settings { gpu: Gpu::Amd, ..settings() };
        assert_eq!(build_lacks(encoders, filters, &nvidia), None);
        assert!(build_lacks(encoders, filters, &amd).is_some_and(|m| m.contains("vpp_amf")), "vpp_amf fehlt");
        let h264 = Settings { codec: Codec::H264, ..nvidia.clone() };
        assert!(build_lacks(encoders, filters, &h264).is_some_and(|m| m.contains("h264_nvenc")));
        let hevc_only = " V....D hevc_nvenc_extra";
        assert!(build_lacks(hevc_only, filters, &nvidia).is_some(), "nur ganze Namen zählen");
    }

    /// Nach allen Weiterleitungen zählt die Größe der letzten Antwort; die
    /// Weiterleitung selbst meldet 0.
    #[test]
    fn reads_the_size_after_redirects() {
        let headers = "HTTP/1.1 302 Found
Location: x
Content-Length: 0

HTTP/1.1 200 OK
content-length: 87037354
";
        assert_eq!(content_length(headers), Some(87_037_354));
        assert_eq!(
            content_length(
                "HTTP/1.1 200 OK
"
            ),
            None
        );
    }

    /// Aus ffmpegs Meldungen bleibt der Satz übrig, der den Grund nennt.
    #[test]
    fn complaint_drops_the_tags() {
        let nvenc = "[hevc_nvenc @ 0000018077293840] Cannot load nvcuda.dll\n\
                     [vost#0:0/hevc_nvenc @ 00000180] [enc:hevc_nvenc @ 000001] Error while opening encoder\n";
        assert_eq!(complaint(nvenc), "Cannot load nvcuda.dll");
        let nested = "\n[vost#0:0/hevc_nvenc @ 01] [enc:hevc_nvenc @ 02] Error while opening encoder";
        assert_eq!(complaint(nested), "Error while opening encoder");
        assert_eq!(complaint(""), "ffmpeg ist ohne Meldung gescheitert");
    }
}
