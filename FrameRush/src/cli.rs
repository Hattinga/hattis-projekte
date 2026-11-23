//! Command-line parsing (hand-rolled; there are only a few flags).

use std::time::Duration;

use crate::capture::{FrameRate, PixelFormat, VideoMode};

pub const USAGE: &str = "\
FrameRush - low-latency capture viewer (prototype, synthetic source)

USAGE:
    framerush [OPTIONS]
    framerush --list-devices

OPTIONS:
    --size <WxH>             Synthetic frame size            [default: 1920x1080]
    --fps <N | N/D>          Synthetic frame rate            [default: 60]
    --format <nv12|bgra>     Synthetic pixel format          [default: nv12]
    --present-mode <MODE>    fifo | mailbox | immediate      [default: fifo]
    --frame-latency <1-3>    Max. frames queued for display  [default: 1]
    --fullscreen             Start in borderless fullscreen
    --no-overlay             Start with the statistics overlay hidden
    --exit-after <SECONDS>   Quit after this time and log final statistics
    --list-devices           List Media Foundation video capture devices and
                             the media types they report, then exit
    -h, --help               Show this help

KEYS:
    F11                      Toggle borderless fullscreen
    Esc                      Leave fullscreen
    O                        Toggle statistics overlay

LOGGING:
    RUST_LOG=debug framerush   (default level: info)
";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PresentModeChoice {
    /// VSync: wait for the next vertical blank. No tearing.
    Fifo,
    /// Newest frame replaces a queued one; no tearing, no vsync wait in the
    /// app (support depends on backend/driver).
    Mailbox,
    /// Present immediately; may tear (support depends on backend/driver).
    Immediate,
}

impl PresentModeChoice {
    pub fn name(self) -> &'static str {
        match self {
            Self::Fifo => "FIFO",
            Self::Mailbox => "MAILBOX",
            Self::Immediate => "IMMEDIATE",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ViewerConfig {
    pub mode: VideoMode,
    pub present_mode: PresentModeChoice,
    pub frame_latency: u32,
    pub fullscreen: bool,
    pub overlay: bool,
    pub exit_after: Option<Duration>,
}

impl Default for ViewerConfig {
    fn default() -> Self {
        Self {
            mode: VideoMode {
                width: 1920,
                height: 1080,
                format: PixelFormat::Nv12,
                frame_rate: FrameRate {
                    numerator: 60,
                    denominator: 1,
                },
            },
            present_mode: PresentModeChoice::Fifo,
            frame_latency: 1,
            fullscreen: false,
            overlay: true,
            exit_after: None,
        }
    }
}

#[derive(Debug, PartialEq)]
pub enum Command {
    Run(ViewerConfig),
    ListDevices,
    Help,
}

pub fn parse(args: impl IntoIterator<Item = String>) -> Result<Command, String> {
    let mut config = ViewerConfig::default();
    let mut list_devices = false;
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        let mut value = |name: &str| args.next().ok_or_else(|| format!("{name} needs a value"));
        match arg.as_str() {
            "-h" | "--help" => return Ok(Command::Help),
            "--list-devices" => list_devices = true,
            "--fullscreen" => config.fullscreen = true,
            "--no-overlay" => config.overlay = false,
            "--size" => {
                let v = value("--size")?;
                let (w, h) = parse_size(&v)
                    .ok_or_else(|| format!("invalid --size {v:?}, expected e.g. 1920x1080"))?;
                config.mode.width = w;
                config.mode.height = h;
            }
            "--fps" => {
                let v = value("--fps")?;
                config.mode.frame_rate = parse_frame_rate(&v).ok_or_else(|| {
                    format!("invalid --fps {v:?}, expected e.g. 60 or 60000/1001")
                })?;
            }
            "--format" => {
                config.mode.format = match value("--format")?.to_ascii_lowercase().as_str() {
                    "nv12" => PixelFormat::Nv12,
                    "bgra" | "bgra8" => PixelFormat::Bgra8,
                    other => {
                        return Err(format!("unknown --format {other:?}, expected nv12 or bgra"));
                    }
                }
            }
            "--present-mode" => {
                config.present_mode = match value("--present-mode")?.to_ascii_lowercase().as_str() {
                    "fifo" | "vsync" => PresentModeChoice::Fifo,
                    "mailbox" => PresentModeChoice::Mailbox,
                    "immediate" => PresentModeChoice::Immediate,
                    other => {
                        return Err(format!(
                            "unknown --present-mode {other:?}, expected fifo, mailbox or immediate"
                        ));
                    }
                }
            }
            "--frame-latency" => {
                let v = value("--frame-latency")?;
                config.frame_latency = v
                    .parse()
                    .ok()
                    .filter(|n| (1..=3).contains(n))
                    .ok_or_else(|| format!("invalid --frame-latency {v:?}, expected 1, 2 or 3"))?;
            }
            "--exit-after" => {
                let v = value("--exit-after")?;
                let secs: f64 = v
                    .parse()
                    .ok()
                    .filter(|s: &f64| s.is_finite() && *s > 0.0)
                    .ok_or_else(|| format!("invalid --exit-after {v:?}, expected seconds > 0"))?;
                config.exit_after = Some(Duration::from_secs_f64(secs));
            }
            other => return Err(format!("unknown argument {other:?} (see --help)")),
        }
    }
    if config
        .mode
        .format
        .frame_len(config.mode.width, config.mode.height)
        .is_none()
    {
        return Err(format!(
            "{}x{} is not valid for {} (NV12 needs even width and height)",
            config.mode.width,
            config.mode.height,
            config.mode.format.name()
        ));
    }
    Ok(if list_devices {
        Command::ListDevices
    } else {
        Command::Run(config)
    })
}

fn parse_size(s: &str) -> Option<(u32, u32)> {
    let (w, h) = s.split_once(['x', 'X'])?;
    let (w, h) = (w.trim().parse().ok()?, h.trim().parse().ok()?);
    (w > 0 && h > 0 && w <= 8192 && h <= 8192).then_some((w, h))
}

fn parse_frame_rate(s: &str) -> Option<FrameRate> {
    let (n, d) = match s.split_once('/') {
        Some((n, d)) => (n.trim().parse().ok()?, d.trim().parse().ok()?),
        None => (s.trim().parse().ok()?, 1),
    };
    let rate = FrameRate::new(n, d)?;
    (rate.as_f64() <= 1000.0).then_some(rate)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_args(args: &[&str]) -> Result<Command, String> {
        parse(args.iter().map(|s| s.to_string()))
    }

    #[test]
    fn defaults_are_1080p60_nv12_fifo() {
        let Command::Run(config) = parse_args(&[]).unwrap() else {
            panic!("expected Run");
        };
        assert_eq!(config, ViewerConfig::default());
        assert_eq!(config.mode.width, 1920);
        assert_eq!(config.mode.height, 1080);
        assert_eq!(config.mode.frame_rate, FrameRate::new(60, 1).unwrap());
    }

    #[test]
    fn all_options() {
        let Command::Run(config) = parse_args(&[
            "--size",
            "1280x720",
            "--fps",
            "60000/1001",
            "--format",
            "bgra",
            "--present-mode",
            "mailbox",
            "--frame-latency",
            "2",
            "--fullscreen",
            "--no-overlay",
            "--exit-after",
            "2.5",
        ])
        .unwrap() else {
            panic!("expected Run");
        };
        assert_eq!((config.mode.width, config.mode.height), (1280, 720));
        assert_eq!(config.mode.frame_rate, FrameRate::new(60000, 1001).unwrap());
        assert_eq!(config.mode.format, PixelFormat::Bgra8);
        assert_eq!(config.present_mode, PresentModeChoice::Mailbox);
        assert_eq!(config.frame_latency, 2);
        assert!(config.fullscreen);
        assert!(!config.overlay);
        assert_eq!(config.exit_after, Some(Duration::from_millis(2500)));
    }

    #[test]
    fn list_devices_and_help() {
        assert_eq!(
            parse_args(&["--list-devices"]).unwrap(),
            Command::ListDevices
        );
        assert_eq!(parse_args(&["--fps", "30", "-h"]).unwrap(), Command::Help);
    }

    #[test]
    fn invalid_input_is_rejected_with_a_message() {
        for args in [
            &["--size", "1920"][..],
            &["--size", "0x1080"],
            &["--fps", "0"],
            &["--fps", "60/0"],
            &["--format", "mjpeg"],
            &["--present-mode", "tearing"],
            &["--frame-latency", "0"],
            &["--exit-after", "-1"],
            &["--size"],
            &["--size", "1921x1080"],
            &["--bogus"],
        ] {
            assert!(parse_args(args).is_err(), "{args:?} should fail");
        }
        assert!(parse_args(&["--size", "1921x1080", "--format", "bgra"]).is_ok());
    }
}
