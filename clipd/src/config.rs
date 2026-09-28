//! Settings, and the folders clipd works in.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

/// Whose encoder records. `Auto` tries NVIDIA, then AMD, at every start, and
/// the capture only ever sees the card that answered.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Gpu {
    Auto,
    Nvidia,
    Amd,
}

impl Gpu {
    pub fn label(self) -> &'static str {
        match self {
            Gpu::Auto => "automatisch",
            Gpu::Nvidia => "NVIDIA NVENC",
            Gpu::Amd => "AMD AMF",
        }
    }
}

/// The hardware encoders clipd drives, both on the graphics card. AV1 is not
/// among them: the ring is an MPEG-TS stream, and ffmpeg can write AV1 into
/// MPEG-TS but not read it back out.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Codec {
    H264,
    Hevc,
}

impl Codec {
    pub fn nvenc(self) -> &'static str {
        match self {
            Codec::H264 => "h264_nvenc",
            Codec::Hevc => "hevc_nvenc",
        }
    }

    pub fn amf(self) -> &'static str {
        match self {
            Codec::H264 => "h264_amf",
            Codec::Hevc => "hevc_amf",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Codec::H264 => "H.264",
            Codec::Hevc => "HEVC",
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Settings {
    /// Which desktop to record, counted as the Desktop Duplication API counts
    /// them. `clipd monitors` lists them.
    pub monitor: u32,
    pub fps: u32,
    /// How far back a clip may reach. The buffer on disk holds this much.
    pub buffer_secs: u32,
    /// Seconds between keyframes: a clip starts on one, so this is how
    /// precisely its length is kept. Shorter costs a little quality.
    pub segment_secs: u32,
    /// How much a hotkey press saves, at most `buffer_secs`.
    pub clip_secs: u32,
    pub gpu: Gpu,
    pub codec: Codec,
    /// Constant quality, 0 (huge) to 51 (poor). 22 is a good starting point.
    pub quality: u8,
    /// nvenc preset p1 (fastest) to p7 (best). p5 costs little and looks good.
    /// AMF only knows three speeds, see [`crate::ffmpeg::amf_quality`].
    pub preset: String,
    pub draw_mouse: bool,
    /// Records what the speakers play. Off means picture only.
    pub audio: bool,
    /// AAC bitrate in kbit/s for the recorded sound.
    pub audio_kbit: u32,
    /// Part of the name of the playback device to record. Empty means the
    /// default one — which is not always one that can do loopback, so
    /// `clipd audio` exists to find a working one.
    pub audio_device: String,
    /// Records the microphone as a second sound track, so the editor can
    /// mute it or turn it down without touching the game.
    pub mic: bool,
    /// Part of the name of the microphone. Empty means the default one.
    pub mic_device: String,
    /// Saves the last `clip_secs`.
    pub hotkey: String,
    /// Starts and stops a recording of any length. Empty means none.
    pub record_hotkey: String,
    /// Files every clip under the game that was in front, `clips/<Spiel>/…`.
    pub game_folders: bool,
    /// A short sound when a clip is saved, because a game in front hides
    /// every other sign of it.
    pub save_sound: bool,
    /// A short note in the top right corner when a clip is saved.
    pub overlay: bool,
    /// Where finished clips land. Empty means `<base>/clips`.
    pub out_dir: PathBuf,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            monitor: 0,
            fps: 60,
            buffer_secs: 120,
            segment_secs: 1,
            clip_secs: 30,
            gpu: Gpu::Auto,
            // H.264, because it plays everywhere a clip ends up: the window's
            // own player (WebView2 cannot decode HEVC), Discord, browsers.
            codec: Codec::H264,
            quality: 22,
            preset: "p5".into(),
            draw_mouse: false,
            audio: true,
            audio_kbit: 160,
            audio_device: String::new(),
            mic: false,
            mic_device: String::new(),
            hotkey: "Ctrl+Alt+C".into(),
            record_hotkey: "Ctrl+Alt+R".into(),
            game_folders: true,
            save_sound: true,
            overlay: true,
            out_dir: PathBuf::new(),
        }
    }
}

impl Settings {
    pub fn load() -> Self {
        let path = config_path();
        let Ok(text) = std::fs::read_to_string(&path) else { return Self::default() };
        match toml::from_str(&text) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("clipd: {} ist unbrauchbar ({e}), es gelten die Standardwerte", path.display());
                Self::default()
            }
        }
    }

    pub fn save(&self) -> Result<()> {
        let path = config_path();
        let text = toml::to_string_pretty(self).context("Einstellungen lassen sich nicht schreiben")?;
        std::fs::write(&path, text).with_context(|| format!("{} lässt sich nicht schreiben", path.display()))
    }

    /// Number of keyframe intervals that cover `buffer_secs`, at least one.
    pub fn ring_len(&self) -> usize {
        div_ceil(self.buffer_secs, self.segment_secs).max(1) as usize
    }

    /// Number of keyframe intervals a clip of `secs` needs. One more than the
    /// plain division, because the newest one is only partly there — but never
    /// more than the ring holds.
    pub fn clip_len(&self, secs: u32) -> usize {
        let secs = secs.min(self.buffer_secs);
        (div_ceil(secs, self.segment_secs).max(1) as usize + 1).min(self.ring_len() + 1)
    }

    /// Distance between keyframes. A clip can only begin on one, so this is
    /// how finely its start is placed.
    pub fn gop(&self) -> u32 {
        (self.fps * self.segment_secs).max(1)
    }

    pub fn clips_dir(&self) -> PathBuf {
        if self.out_dir.as_os_str().is_empty() { base_dir().join("clips") } else { self.out_dir.clone() }
    }

    /// Complains about values that would produce a broken recording instead of
    /// letting ffmpeg fail later with something cryptic.
    pub fn check(&self) -> Result<()> {
        anyhow::ensure!(self.fps >= 1 && self.fps <= 480, "fps muss zwischen 1 und 480 liegen, nicht {}", self.fps);
        anyhow::ensure!(self.segment_secs >= 1, "segment_secs muss mindestens 1 sein");
        anyhow::ensure!(self.buffer_secs >= self.segment_secs, "buffer_secs darf nicht kleiner als segment_secs sein");
        anyhow::ensure!(self.clip_secs >= 1, "clip_secs muss mindestens 1 sein");
        anyhow::ensure!(self.quality <= 51, "quality muss zwischen 0 und 51 liegen, nicht {}", self.quality);
        anyhow::ensure!(
            (32..=512).contains(&self.audio_kbit),
            "audio_kbit muss zwischen 32 und 512 liegen, nicht {}",
            self.audio_kbit
        );
        let ok_preset = self.preset.len() == 2
            && self.preset.starts_with('p')
            && self.preset[1..].parse::<u8>().is_ok_and(|n| (1..=7).contains(&n));
        anyhow::ensure!(ok_preset, "preset muss p1 bis p7 sein, nicht {:?}", self.preset);
        let clip = crate::hotkey::parse(&self.hotkey)?;
        if !self.record_hotkey.trim().is_empty() {
            let record = crate::hotkey::parse(&self.record_hotkey)?;
            anyhow::ensure!(record != clip, "hotkey und record_hotkey dürfen nicht dieselbe Taste sein");
        }
        Ok(())
    }
}

fn div_ceil(a: u32, b: u32) -> u32 {
    if b == 0 { a } else { a.div_ceil(b) }
}

/// Where clipd keeps its settings, the buffer and the clips:
///
/// - `CLIPD_HOME` if set;
/// - during development (exe inside `target/{debug,release}`) the Cargo project
///   root, so one buffer and one config are shared between builds;
/// - otherwise next to the .exe, so a copied folder stays portable.
pub fn base_dir() -> PathBuf {
    let exe_dir =
        std::env::current_exe().ok().and_then(|p| p.parent().map(PathBuf::from)).unwrap_or_else(|| PathBuf::from("."));
    let dir = locate_base(&exe_dir, &|k| std::env::var_os(k).map(PathBuf::from));
    if dir != exe_dir {
        let _ = std::fs::create_dir_all(&dir);
    }
    dir
}

fn locate_base(exe_dir: &Path, var: &dyn Fn(&str) -> Option<PathBuf>) -> PathBuf {
    if let Some(home) = var("CLIPD_HOME").filter(|p| !p.as_os_str().is_empty()) {
        return home;
    }
    // target/debug/clipd.exe -> the folder holding Cargo.toml.
    if matches!(exe_dir.file_name().and_then(|n| n.to_str()), Some("debug" | "release"))
        && exe_dir.parent().is_some_and(|p| p.file_name().and_then(|n| n.to_str()) == Some("target"))
        && let Some(root) = exe_dir.parent().and_then(|p| p.parent())
    {
        return root.to_path_buf();
    }
    exe_dir.to_path_buf()
}

pub fn config_path() -> PathBuf {
    base_dir().join("config.toml")
}

/// The rolling buffer. Its contents are worthless after a restart, so `run`
/// empties it on start.
pub fn buffer_dir() -> PathBuf {
    base_dir().join("buffer")
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Die Voreinstellungen müssen für sich schon ein brauchbares Setup sein.
    #[test]
    fn defaults_are_usable() {
        Settings::default().check().expect("Standardwerte sind gültig");
    }

    /// Unsinnige Werte sollen vor dem Start auffallen, nicht mitten in ffmpeg.
    #[test]
    fn bad_values_are_rejected() {
        let bad = |f: fn(&mut Settings)| {
            let mut s = Settings::default();
            f(&mut s);
            assert!(s.check().is_err(), "hätte auffallen müssen: {s:?}");
        };
        bad(|s| s.fps = 0);
        bad(|s| s.segment_secs = 0);
        bad(|s| s.quality = 52);
        bad(|s| s.preset = "p9".into());
        bad(|s| s.preset = "schnell".into());
        bad(|s| s.hotkey = "Strg+Ü".into());
        bad(|s| s.record_hotkey = "Strg+Alt+C".into());
        bad(|s| {
            s.buffer_secs = 2;
            s.segment_secs = 10;
        });
    }

    /// Der Ring muss den gewünschten Zeitraum abdecken, auch wenn die
    /// Segmentlänge nicht glatt aufgeht.
    #[test]
    fn ring_covers_the_buffer() {
        let s = |buffer, segment| Settings { buffer_secs: buffer, segment_secs: segment, ..Default::default() };
        assert_eq!(s(120, 1).ring_len(), 120);
        assert_eq!(s(120, 2).ring_len(), 60);
        assert_eq!(s(10, 3).ring_len(), 4, "aufgerundet");
        assert_eq!(s(1, 1).ring_len(), 1);
    }

    /// Ein Clip nimmt ein Segment mehr mit, weil das neueste erst teilweise
    /// gefüllt ist — aber nie mehr, als der Ring hergibt.
    #[test]
    fn clip_takes_one_segment_extra() {
        let s = |clip, segment, buffer| Settings {
            clip_secs: clip,
            segment_secs: segment,
            buffer_secs: buffer,
            ..Default::default()
        };
        assert_eq!(s(30, 1, 120).clip_len(30), 31);
        assert_eq!(s(30, 2, 120).clip_len(30), 16);
        assert_eq!(s(30, 1, 120).clip_len(10), 11, "kürzer auf Wunsch");
        assert_eq!(s(120, 1, 120).clip_len(120), 121, "vom Ring begrenzt");
        assert_eq!(s(999, 1, 120).clip_len(999), 121, "länger als der Buffer geht nicht");
    }

    /// Alle segment_secs Sekunden ein Keyframe.
    #[test]
    fn gop_matches_the_segment_length() {
        let s = Settings { fps: 60, segment_secs: 2, ..Default::default() };
        assert_eq!(s.gop(), 120);
    }

    #[test]
    fn base_dir_prefers_clipd_home() {
        let exe = Path::new(r"C:\Programme\clipd");
        let env = |vars: Vec<(&'static str, &'static str)>| {
            move |k: &str| vars.iter().find(|(n, _)| *n == k).map(|(_, v)| PathBuf::from(v))
        };
        assert_eq!(locate_base(exe, &env(vec![("CLIPD_HOME", r"D:\clipd")])), Path::new(r"D:\clipd"));
        assert_eq!(locate_base(exe, &env(vec![])), exe, "sonst portabel neben der .exe");
    }

    /// Aus target/debug heraus liegt alles im Projektordner, damit Debug- und
    /// Release-Build denselben Buffer und dieselbe config.toml benutzen.
    #[test]
    fn base_dir_during_development() {
        let none = |_: &str| None;
        assert_eq!(locate_base(Path::new(r"C:\code\clipd\target\debug"), &none), Path::new(r"C:\code\clipd"));
        assert_eq!(locate_base(Path::new(r"C:\code\clipd\target\release"), &none), Path::new(r"C:\code\clipd"));
        let other = Path::new(r"C:\code\clipd\anderes\debug");
        assert_eq!(locate_base(other, &none), other, "nur unter target/");
    }

    /// Die Einstellungen müssen den Weg durch TOML unverändert überleben.
    #[test]
    fn settings_survive_toml() {
        let s = Settings { codec: Codec::Hevc, gpu: Gpu::Amd, out_dir: PathBuf::from(r"D:\Clips"), ..Default::default() };
        let text = toml::to_string_pretty(&s).unwrap();
        assert!(text.contains(r#"gpu = "amd""#), "{text}");
        let back: Settings = toml::from_str(&text).unwrap();
        assert_eq!(back.codec, Codec::Hevc);
        assert_eq!(back.gpu, Gpu::Amd);
        assert_eq!(back.out_dir, PathBuf::from(r"D:\Clips"));
        assert_eq!(back.hotkey, s.hotkey);
    }
}
