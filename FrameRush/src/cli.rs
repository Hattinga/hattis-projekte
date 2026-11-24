//! Command-line parsing (hand-rolled; there are only a few flags).

use std::time::Duration;

use crate::capture::{DeviceSelector, FrameRate, ModeSelector, PixelFormat, VideoMode};

pub const USAGE: &str = "\
FrameRush - low-latency capture viewer

USAGE:
    framerush                                remembered capture device, or a
                                             device chooser on first start
    framerush --device <DEVICE> [OPTIONS]    this capture device
    framerush --synthetic [OPTIONS]          test pattern, no device
    framerush --list-devices                 video and audio devices
    framerush --device <DEVICE> --probe      video diagnostics, no window
    framerush --device <DEVICE> --probe-audio
                                             audio diagnostics, no window

SOURCE:
    --device <N | NAME>      Capture from this device: its number in
                             --list-devices or part of its name. A number
                             that is no device number must be a word of the
                             name, e.g. --device 25854 for \"UGREEN 25854\".
                             The choice is remembered.
    --mode <N>               Native mode number from --list-devices
                             [default: best NV12 mode, 1080p60 if offered]
    --size <WxH>             Frame size (device: mode to match)
    --fps <N | N/D>          Frame rate (device: mode to match)
    --format <nv12|bgra>     Pixel format (device: nv12 only)
    --synthetic              Show a test pattern instead of a device
                             [default: 1920x1080 nv12 @ 60]
    --probe                  With --device: capture for --exit-after seconds
                             (default 5) without a window and print the
                             negotiated media type, timing and value ranges
    --probe-audio            With --device: play the device's audio for
                             --exit-after seconds and print the audio status

AUDIO:
    --no-audio               Do not play the capture device's audio
    --audio                  Play it again (after --no-audio)
    --audio-output <NAME>    Output device (part of its name, see
                             --list-devices); \"default\" follows Windows

DISPLAY:
    --present-mode <MODE>    fifo | mailbox | immediate      [default: fifo]
    --frame-latency <1-3>    Max. frames queued for display  [default: 1]
    --fullscreen             Start in borderless fullscreen
    --overlay / --no-overlay Show / hide the statistics overlay
    --exit-after <SECONDS>   Quit after this time and log final statistics

OTHER:
    --list-devices           List video capture devices with the modes they
                             report, and the audio devices, then exit
    -h, --help               Show this help

KEYS:
    F11, Alt+Enter           Toggle borderless fullscreen (Esc leaves it)
    M                        Mute / unmute
    + / -  (also Up / Down)  Volume
    O                        Statistics overlay
    D                        Choose another capture device
    R                        Reconnect now
    F1                       Show the keys

Settings are remembered in %APPDATA%\\FrameRush\\settings.ini (delete it to
reset), the log is written to %LOCALAPPDATA%\\FrameRush\\framerush.log.
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

/// Where frames come from.
#[derive(Debug, Clone, PartialEq)]
pub enum SourceChoice {
    /// The remembered device, or the in-window chooser if there is none.
    Auto { mode: ModeSelector },
    /// The synthetic test pattern in `ViewerConfig::mode`.
    Synthetic,
    /// A Media Foundation capture device.
    Device {
        device: DeviceSelector,
        mode: ModeSelector,
    },
}

/// Viewer options. `Option` fields override the remembered settings.
#[derive(Debug, Clone, PartialEq)]
pub struct ViewerConfig {
    pub source: SourceChoice,
    /// Mode of the synthetic source.
    pub mode: VideoMode,
    pub present_mode: PresentModeChoice,
    pub frame_latency: u32,
    pub fullscreen: Option<bool>,
    pub overlay: Option<bool>,
    pub audio: Option<bool>,
    /// `Some(None)`: Windows default output.
    pub audio_output: Option<Option<String>>,
    pub exit_after: Option<Duration>,
}

impl Default for ViewerConfig {
    fn default() -> Self {
        Self {
            source: SourceChoice::Auto {
                mode: ModeSelector::Best,
            },
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
            fullscreen: None,
            overlay: None,
            audio: None,
            audio_output: None,
            exit_after: None,
        }
    }
}

/// Headless capture diagnostics (`--probe`).
#[derive(Debug, Clone, PartialEq)]
pub struct ProbeConfig {
    pub device: DeviceSelector,
    pub mode: ModeSelector,
    pub duration: Duration,
}

/// Headless audio diagnostics (`--probe-audio`).
#[derive(Debug, Clone, PartialEq)]
pub struct AudioProbeConfig {
    pub device: DeviceSelector,
    pub output: Option<String>,
    pub duration: Duration,
}

/// Duration of `--probe` and `--probe-audio` without `--exit-after`.
const DEFAULT_PROBE_DURATION: Duration = Duration::from_secs(5);

#[derive(Debug, PartialEq)]
pub enum Command {
    Run(ViewerConfig),
    Probe(ProbeConfig),
    ProbeAudio(AudioProbeConfig),
    ListDevices,
    Help,
}

pub fn parse(args: impl IntoIterator<Item = String>) -> Result<Command, String> {
    let mut config = ViewerConfig::default();
    let mut list_devices = false;
    let mut probe = false;
    let mut probe_audio = false;
    let mut synthetic = false;
    let mut device = None;
    let mut mode_index = None;
    let mut mode_options = false;
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        let mut value = |name: &str| args.next().ok_or_else(|| format!("{name} needs a value"));
        match arg.as_str() {
            "-h" | "--help" => return Ok(Command::Help),
            "--list-devices" => list_devices = true,
            "--probe" => probe = true,
            "--probe-audio" => probe_audio = true,
            "--synthetic" => synthetic = true,
            "--fullscreen" => config.fullscreen = Some(true),
            "--overlay" => config.overlay = Some(true),
            "--no-overlay" => config.overlay = Some(false),
            "--audio" => config.audio = Some(true),
            "--no-audio" => config.audio = Some(false),
            "--audio-output" => {
                let v = value("--audio-output")?;
                let v = v.trim();
                config.audio_output = Some(
                    (!v.is_empty() && !v.eq_ignore_ascii_case("default")).then(|| v.to_string()),
                );
            }
            "--device" => {
                let v = value("--device")?;
                let v = v.trim();
                if v.is_empty() {
                    return Err("--device needs a number or a name".into());
                }
                device = Some(match v.parse() {
                    Ok(index) => DeviceSelector::Index(index),
                    Err(_) => DeviceSelector::Name(v.to_string()),
                });
            }
            "--mode" => {
                let v = value("--mode")?;
                mode_index = Some(v.trim().trim_start_matches('#').parse().map_err(|_| {
                    format!("invalid --mode {v:?}, expected a number from --list-devices")
                })?);
            }
            "--size" => {
                mode_options = true;
                let v = value("--size")?;
                let (w, h) = parse_size(&v)
                    .ok_or_else(|| format!("invalid --size {v:?}, expected e.g. 1920x1080"))?;
                config.mode.width = w;
                config.mode.height = h;
            }
            "--fps" => {
                mode_options = true;
                let v = value("--fps")?;
                config.mode.frame_rate = parse_frame_rate(&v).ok_or_else(|| {
                    format!("invalid --fps {v:?}, expected e.g. 60 or 60000/1001")
                })?;
            }
            "--format" => {
                mode_options = true;
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
    if list_devices {
        return Ok(Command::ListDevices);
    }
    if mode_index.is_some() && mode_options && !synthetic {
        return Err("use either --mode or --size/--fps/--format, not both".into());
    }
    if synthetic {
        if device.is_some() || mode_index.is_some() || probe || probe_audio {
            return Err("--synthetic cannot be combined with --device, --mode or a probe".into());
        }
        config.source = SourceChoice::Synthetic;
        return Ok(Command::Run(config));
    }
    let mode = match (mode_index, mode_options) {
        (Some(index), _) => ModeSelector::Index(index),
        (None, true) => ModeSelector::Match(config.mode),
        (None, false) => ModeSelector::Best,
    };
    let duration = config.exit_after.unwrap_or(DEFAULT_PROBE_DURATION);
    let Some(device) = device else {
        if probe || probe_audio {
            return Err("--probe and --probe-audio need --device".into());
        }
        config.source = SourceChoice::Auto { mode };
        return Ok(Command::Run(config));
    };
    if probe && probe_audio {
        return Err("use either --probe or --probe-audio".into());
    }
    if probe {
        return Ok(Command::Probe(ProbeConfig {
            device,
            mode,
            duration,
        }));
    }
    if probe_audio {
        return Ok(Command::ProbeAudio(AudioProbeConfig {
            device,
            output: config.audio_output.flatten(),
            duration,
        }));
    }
    config.source = SourceChoice::Device { device, mode };
    Ok(Command::Run(config))
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

    fn run(args: &[&str]) -> ViewerConfig {
        match parse_args(args).unwrap() {
            Command::Run(config) => config,
            other => panic!("expected Run, got {other:?}"),
        }
    }

    #[test]
    fn no_arguments_means_remembered_device_and_best_mode() {
        let config = run(&[]);
        assert_eq!(config, ViewerConfig::default());
        assert_eq!(
            config.source,
            SourceChoice::Auto {
                mode: ModeSelector::Best
            }
        );
        assert_eq!(config.overlay, None, "the settings decide");
    }

    #[test]
    fn synthetic_with_all_display_options() {
        let config = run(&[
            "--synthetic",
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
            "--overlay",
            "--exit-after",
            "2.5",
        ]);
        assert_eq!(config.source, SourceChoice::Synthetic);
        assert_eq!((config.mode.width, config.mode.height), (1280, 720));
        assert_eq!(config.mode.frame_rate, FrameRate::new(60000, 1001).unwrap());
        assert_eq!(config.mode.format, PixelFormat::Bgra8);
        assert_eq!(config.present_mode, PresentModeChoice::Mailbox);
        assert_eq!(config.frame_latency, 2);
        assert_eq!(config.fullscreen, Some(true));
        assert_eq!(config.overlay, Some(true));
        assert_eq!(config.exit_after, Some(Duration::from_millis(2500)));
    }

    #[test]
    fn audio_options() {
        let config = run(&["--no-audio", "--audio-output", "PRO X"]);
        assert_eq!(config.audio, Some(false));
        assert_eq!(config.audio_output, Some(Some("PRO X".into())));
        let config = run(&["--audio-output", "default"]);
        assert_eq!(config.audio_output, Some(None));
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
    fn device_by_index_or_name() {
        assert_eq!(
            run(&["--device", "2"]).source,
            SourceChoice::Device {
                device: DeviceSelector::Index(2),
                mode: ModeSelector::Best,
            }
        );
        assert_eq!(
            run(&["--device", "UGREEN 25854", "--mode", "#6"]).source,
            SourceChoice::Device {
                device: DeviceSelector::Name("UGREEN 25854".into()),
                mode: ModeSelector::Index(6),
            }
        );
    }

    #[test]
    fn device_mode_follows_size_and_fps() {
        let SourceChoice::Device {
            mode: ModeSelector::Match(mode),
            ..
        } = run(&["--device", "25854", "--size", "1280x720", "--fps", "50"]).source
        else {
            panic!("expected a device with a mode to match");
        };
        assert_eq!((mode.width, mode.height), (1280, 720));
        assert_eq!(mode.frame_rate, FrameRate::new(50, 1).unwrap());
        // Without --device the remembered device gets the mode.
        assert!(matches!(
            run(&["--mode", "3"]).source,
            SourceChoice::Auto {
                mode: ModeSelector::Index(3)
            }
        ));
    }

    #[test]
    fn probes() {
        assert_eq!(
            parse_args(&["--device", "25854", "--probe"]).unwrap(),
            Command::Probe(ProbeConfig {
                device: DeviceSelector::Index(25854),
                mode: ModeSelector::Best,
                duration: Duration::from_secs(5),
            })
        );
        assert_eq!(
            parse_args(&[
                "--probe-audio",
                "--device",
                "UGREEN 25854",
                "--audio-output",
                "PRO X",
                "--exit-after",
                "2",
            ])
            .unwrap(),
            Command::ProbeAudio(AudioProbeConfig {
                device: DeviceSelector::Name("UGREEN 25854".into()),
                output: Some("PRO X".into()),
                duration: Duration::from_secs(2),
            })
        );
    }

    #[test]
    fn invalid_source_combinations() {
        for args in [
            &["--probe"][..],
            &["--probe-audio"],
            &["--device", "0", "--probe", "--probe-audio"],
            &["--device", "0", "--mode", "3", "--fps", "30"],
            &["--device", "0", "--mode", "x"],
            &["--device", " "],
            &["--synthetic", "--device", "0"],
        ] {
            assert!(parse_args(args).is_err(), "{args:?} should fail");
        }
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
        assert!(parse_args(&["--synthetic", "--size", "1921x1080", "--format", "bgra"]).is_ok());
    }
}
