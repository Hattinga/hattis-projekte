//! FrameRush: low-latency capture viewer for Windows.
//!
//! Current state (milestone M2): GPU viewer for a synthetic test pattern or a
//! Media Foundation capture device (NV12), device listing and a headless
//! capture probe. See README.md and docs/ARCHITECTURE.md.

mod app;
mod capture;
mod cli;
mod error;
mod font;
mod metrics;
#[cfg(windows)]
mod probe;
mod render;

use std::process::ExitCode;

use tracing_subscriber::EnvFilter;

use crate::cli::Command;
use crate::error::AppError;

fn main() -> ExitCode {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("error: {err}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<(), AppError> {
    match cli::parse(std::env::args().skip(1)).map_err(AppError::Usage)? {
        Command::Help => {
            print!("{}", cli::USAGE);
            Ok(())
        }
        Command::ListDevices => list_devices(),
        Command::Probe(config) => probe(&config),
        Command::Run(config) => {
            match &config.source {
                cli::SourceChoice::Synthetic => {
                    tracing::info!(mode = %config.mode, present_mode = config.present_mode.name(), "starting viewer, synthetic source");
                }
                cli::SourceChoice::Device { device, mode } => {
                    tracing::info!(%device, %mode, present_mode = config.present_mode.name(), "starting viewer, capture device");
                }
            }
            app::run(config)
        }
    }
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
fn list_devices() -> Result<(), AppError> {
    let devices = capture::media_foundation::list_video_devices().map_err(AppError::DeviceProbe)?;
    if devices.is_empty() {
        println!("No video capture devices found by Media Foundation.");
        println!(
            "Check that the capture card is plugged in and shows up under \"Cameras\" in Device Manager."
        );
        return Ok(());
    }
    println!(
        "{} video capture device(s) found by Media Foundation:\n",
        devices.len()
    );
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
    println!("These are the formats the driver *reports*. FrameRush captures NV12 modes");
    println!("(--device N --mode M); --probe shows what a mode actually delivers.");
    Ok(())
}

#[cfg(not(windows))]
fn list_devices() -> Result<(), AppError> {
    Err(AppError::DeviceProbe(
        "Media Foundation is only available on Windows".into(),
    ))
}
