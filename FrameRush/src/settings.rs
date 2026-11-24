//! Remembered settings: `%APPDATA%\FrameRush\settings.ini`.
//!
//! A small `key = value` file, hand-parsed (a handful of keys do not justify
//! a serialization dependency). Unknown keys and bad values are ignored with
//! a warning, so a damaged file never stops FrameRush from starting; delete
//! the file to reset everything.

use std::fs;
use std::path::PathBuf;

/// Window position and size in physical pixels.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WindowGeometry {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Settings {
    /// Friendly name of the capture device to open.
    pub device: Option<String>,
    /// Audio output device name; `None` follows the Windows default.
    pub audio_output: Option<String>,
    /// Play the capture device's audio.
    pub audio: bool,
    /// Playback volume in percent (0..=100).
    pub volume: u8,
    pub muted: bool,
    /// Statistics overlay visible.
    pub overlay: bool,
    pub fullscreen: bool,
    pub window: Option<WindowGeometry>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            device: None,
            audio_output: None,
            audio: true,
            volume: 100,
            muted: false,
            overlay: false,
            fullscreen: false,
            window: None,
        }
    }
}

const HEADER: &str = "# FrameRush settings. Delete this file to reset everything.\n";

impl Settings {
    pub fn path() -> Option<PathBuf> {
        std::env::var_os("APPDATA")
            .map(|dir| PathBuf::from(dir).join("FrameRush").join("settings.ini"))
    }

    /// Loads the settings file; missing or unreadable files give defaults.
    pub fn load() -> Self {
        let Some(path) = Self::path() else {
            tracing::warn!("APPDATA is not set; settings are not remembered");
            return Self::default();
        };
        match fs::read_to_string(&path) {
            Ok(text) => {
                let (settings, warnings) = Self::parse(&text);
                for warning in warnings {
                    tracing::warn!(path = %path.display(), "settings: {warning}");
                }
                settings
            }
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => Self::default(),
            Err(err) => {
                tracing::warn!(path = %path.display(), %err, "cannot read settings, using defaults");
                Self::default()
            }
        }
    }

    /// Writes the settings file (via a temporary file, so a crash never
    /// leaves half a file). Errors are logged, not fatal.
    pub fn save(&self) {
        let Some(path) = Self::path() else {
            return;
        };
        let result = (|| {
            if let Some(dir) = path.parent() {
                fs::create_dir_all(dir)?;
            }
            let tmp = path.with_extension("ini.tmp");
            fs::write(&tmp, self.to_text())?;
            fs::rename(&tmp, &path)
        })();
        match result {
            Ok(()) => tracing::debug!(path = %path.display(), "settings saved"),
            Err(err) => tracing::warn!(path = %path.display(), %err, "cannot save settings"),
        }
    }

    /// Parses the file format; returns the settings and one warning per
    /// line that could not be used.
    pub fn parse(text: &str) -> (Self, Vec<String>) {
        let mut s = Self::default();
        let mut warnings = Vec::new();
        for (number, raw) in text.lines().enumerate() {
            let line = raw.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let Some((key, value)) = line.split_once('=') else {
                warnings.push(format!("line {}: expected key = value", number + 1));
                continue;
            };
            let (key, value) = (key.trim(), value.trim());
            let ok = match key {
                "device" => {
                    s.device = non_empty(value);
                    true
                }
                "audio_output" => {
                    s.audio_output = non_empty(value);
                    true
                }
                "audio" => parse_bool(value).map(|v| s.audio = v).is_some(),
                "volume" => value
                    .parse::<u8>()
                    .ok()
                    .filter(|v| *v <= 100)
                    .map(|v| s.volume = v)
                    .is_some(),
                "muted" => parse_bool(value).map(|v| s.muted = v).is_some(),
                "overlay" => parse_bool(value).map(|v| s.overlay = v).is_some(),
                "fullscreen" => parse_bool(value).map(|v| s.fullscreen = v).is_some(),
                "window" if value.is_empty() => {
                    s.window = None;
                    true
                }
                "window" => parse_window(value).map(|w| s.window = Some(w)).is_some(),
                _ => {
                    warnings.push(format!("line {}: unknown key {key:?}", number + 1));
                    continue;
                }
            };
            if !ok {
                warnings.push(format!(
                    "line {}: invalid value for {key}: {value:?}",
                    number + 1
                ));
            }
        }
        (s, warnings)
    }

    pub fn to_text(&self) -> String {
        let window = self.window.map_or_else(String::new, |w| {
            format!("{},{},{},{}", w.x, w.y, w.width, w.height)
        });
        format!(
            "{HEADER}device = {}\naudio = {}\naudio_output = {}\nvolume = {}\nmuted = {}\noverlay = {}\nfullscreen = {}\nwindow = {window}\n",
            self.device.as_deref().unwrap_or(""),
            self.audio,
            self.audio_output.as_deref().unwrap_or(""),
            self.volume,
            self.muted,
            self.overlay,
            self.fullscreen,
        )
    }
}

fn non_empty(value: &str) -> Option<String> {
    (!value.is_empty()).then(|| value.to_string())
}

fn parse_bool(value: &str) -> Option<bool> {
    match value.to_ascii_lowercase().as_str() {
        "true" | "1" | "yes" | "on" => Some(true),
        "false" | "0" | "no" | "off" => Some(false),
        _ => None,
    }
}

fn parse_window(value: &str) -> Option<WindowGeometry> {
    let parts: Vec<&str> = value.split(',').map(str::trim).collect();
    let [x, y, width, height] = parts.as_slice() else {
        return None;
    };
    let geometry = WindowGeometry {
        x: x.parse().ok()?,
        y: y.parse().ok()?,
        width: width.parse().ok()?,
        height: height.parse().ok()?,
    };
    (geometry.width >= 100
        && geometry.height >= 100
        && geometry.width <= 16384
        && geometry.height <= 16384)
        .then_some(geometry)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip() {
        let settings = Settings {
            device: Some("UGREEN 25854".into()),
            audio_output: Some("Lautsprecher (PRO X 2 LIGHTSPEED)".into()),
            audio: false,
            volume: 70,
            muted: true,
            overlay: true,
            fullscreen: true,
            window: Some(WindowGeometry {
                x: -1920,
                y: 40,
                width: 1280,
                height: 720,
            }),
        };
        let (parsed, warnings) = Settings::parse(&settings.to_text());
        assert!(warnings.is_empty(), "{warnings:?}");
        assert_eq!(parsed, settings);
        let (parsed, warnings) = Settings::parse(&Settings::default().to_text());
        assert!(warnings.is_empty(), "{warnings:?}");
        assert_eq!(parsed, Settings::default());
    }

    #[test]
    fn damaged_file_keeps_defaults_and_reports_lines() {
        let text = "device = Cam\nvolume = 400\nmuted = maybe\nwhatever\ncolour = red\nwindow = 1,2\noverlay = on\n";
        let (s, warnings) = Settings::parse(text);
        assert_eq!(s.device.as_deref(), Some("Cam"));
        assert_eq!(s.volume, 100);
        assert!(!s.muted);
        assert!(s.overlay);
        assert_eq!(s.window, None);
        assert_eq!(warnings.len(), 5, "{warnings:?}");
    }

    #[test]
    fn values_may_contain_equals_and_spaces() {
        let (s, warnings) = Settings::parse("device =  Camera = 2  \n");
        assert!(warnings.is_empty());
        assert_eq!(s.device.as_deref(), Some("Camera = 2"));
    }
}
