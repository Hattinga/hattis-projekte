//! FrameRush: low-latency capture viewer for Windows.
//!
//! Shows an HDMI capture card (Media Foundation, NV12) with its audio
//! (WASAPI), remembers the device and window, reconnects after unplugging.
//! See README.md and docs/ARCHITECTURE.md.

// Release builds are a windowed app without a console window; when started
// from a terminal they attach to it (see `platform::attach_parent_console`).
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod app;
mod audio;
mod capture;
mod cli;
mod error;
mod font;
mod metrics;
mod platform;
#[cfg(windows)]
mod probe;
mod render;
mod settings;

use std::fs::File;
use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::Mutex;

use tracing_subscriber::EnvFilter;
use tracing_subscriber::fmt::writer::MakeWriterExt;

use crate::cli::Command;
use crate::error::AppError;

fn main() -> ExitCode {
    // Release: no console window. Commands that print (help, lists, probes)
    // still reach the terminal they were started from.
    let console = cfg!(debug_assertions) || platform::attach_parent_console();
    let log_path = init_logging(console);
    install_panic_hook(log_path.clone(), console);

    let command = cli::parse(std::env::args().skip(1));
    let opens_window = matches!(command, Ok(Command::Run(_)));
    match command.map_err(AppError::Usage).and_then(run) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            tracing::error!(%err, "exiting with an error");
            eprintln!("error: {err}");
            // Without a console the user would see nothing at all.
            if opens_window || !console {
                let log =
                    log_path.map_or_else(String::new, |p| format!("\n\nLog: {}", p.display()));
                platform::error_box(&format!("FrameRush could not start:\n\n{err}{log}"));
            }
            ExitCode::FAILURE
        }
    }
}

fn run(command: Command) -> Result<(), AppError> {
    match command {
        Command::Help => {
            print!("{}", cli::USAGE);
            Ok(())
        }
        Command::ListDevices => list_devices(),
        Command::Probe(config) => probe(&config),
        Command::ProbeAudio(config) => probe_audio(&config),
        Command::Run(config) => {
            tracing::info!(
                version = env!("CARGO_PKG_VERSION"),
                source = ?config.source,
                present_mode = config.present_mode.name(),
                "starting viewer"
            );
            app::run(config)
        }
    }
}

/// Logs to the console (if any) and to `%LOCALAPPDATA%\FrameRush\
/// framerush.log`. The previous run's log is kept as `framerush.old.log`
/// (useful after a crash or a failed reconnect). Returns the log file path.
fn init_logging(console: bool) -> Option<PathBuf> {
    let filter = || EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));
    let path = std::env::var_os("LOCALAPPDATA")
        .map(|dir| PathBuf::from(dir).join("FrameRush").join("framerush.log"));
    let file = path.as_ref().and_then(|p| {
        std::fs::create_dir_all(p.parent()?).ok()?;
        // Best effort: a second FrameRush still writing it keeps it.
        let _ = std::fs::rename(p, p.with_file_name("framerush.old.log"));
        File::create(p).ok()
    });
    match (file, console) {
        (Some(file), true) => tracing_subscriber::fmt()
            .with_env_filter(filter())
            .with_writer(std::io::stderr.and(Mutex::new(file)))
            .with_ansi(false)
            .init(),
        (Some(file), false) => tracing_subscriber::fmt()
            .with_env_filter(filter())
            .with_writer(Mutex::new(file))
            .with_ansi(false)
            .init(),
        (None, _) => tracing_subscriber::fmt().with_env_filter(filter()).init(),
    }
    path
}

/// Panics go to the log, and without a console also to a dialog.
fn install_panic_hook(log_path: Option<PathBuf>, console: bool) {
    let default = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        tracing::error!("panic: {info}");
        if console {
            default(info);
        } else {
            let log = log_path
                .as_ref()
                .map_or_else(String::new, |p| format!("\n\nLog: {}", p.display()));
            platform::error_box(&format!("FrameRush crashed:\n\n{info}{log}"));
        }
    }));
}

#[cfg(windows)]
fn probe(config: &cli::ProbeConfig) -> Result<(), AppError> {
    probe::run(config)
}

#[cfg(not(windows))]
fn probe(_config: &cli::ProbeConfig) -> Result<(), AppError> {
    Err(AppError::DeviceProbe(
        "Media Foundation is only available on Windows".into(),
    ))
}

#[cfg(windows)]
fn probe_audio(config: &cli::AudioProbeConfig) -> Result<(), AppError> {
    probe::run_audio(config)
}

#[cfg(not(windows))]
fn probe_audio(_config: &cli::AudioProbeConfig) -> Result<(), AppError> {
    Err(AppError::DeviceProbe(
        "WASAPI is only available on Windows".into(),
    ))
}

#[cfg(windows)]
fn list_devices() -> Result<(), AppError> {
    let devices = capture::media_foundation::list_video_devices().map_err(AppError::DeviceProbe)?;
    if devices.is_empty() {
        println!("No video capture devices found by Media Foundation.");
        println!(
            "Check that the capture card is plugged in and shows up under \"Cameras\" in Device Manager."
        );
    } else {
        println!(
            "{} video capture device(s) found by Media Foundation:\n",
            devices.len()
        );
    }
    for (index, device) in devices.iter().enumerate() {
        println!("[{index}] {}", device.name);
        println!("    id: {}", device.symbolic_link);
        match &device.media_types {
            Ok(types) => {
                println!(
                    "    native media types reported by the driver ({}):",
                    types.len()
                );
                for (i, t) in types.iter().enumerate() {
                    println!("      #{i:<3} {t}");
                }
            }
            Err(err) => {
                println!("    could not read media types: {err} (device in use by another app?)")
            }
        }
        println!();
    }
    if !devices.is_empty() {
        println!("These are the formats the driver *reports*. FrameRush captures NV12 modes");
        println!("(--device N --mode M); --probe shows what a mode actually delivers.\n");
    }
    match audio::endpoint_names() {
        Ok((inputs, outputs)) => {
            println!("Audio inputs (FrameRush uses the one named after the video device):");
            for name in inputs {
                println!("    {name}");
            }
            println!("Audio outputs (--audio-output <part of the name>):");
            for name in outputs {
                println!("    {name}");
            }
        }
        Err(err) => println!("Audio devices could not be listed: {err}"),
    }
    Ok(())
}

#[cfg(not(windows))]
fn list_devices() -> Result<(), AppError> {
    Err(AppError::DeviceProbe(
        "Media Foundation is only available on Windows".into(),
    ))
}
