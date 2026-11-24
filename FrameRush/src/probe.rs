//! `--probe`: headless capture diagnostics for one device and mode.
//!
//! Opens the device exactly like the viewer does, reads frames for a fixed
//! time without a window and prints what was negotiated and measured: every
//! attribute of the current media type, the buffer layout, frame counts and
//! intervals, and the value ranges of the last frame (useful to tell limited
//! from full range). All timing is software timing of this process.

use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use crate::capture::media_foundation::{MediaFoundationSource, ReaderOptions};
use crate::capture::{Frame, PixelFormat, STOP_TIMEOUT, SourceError, VideoSource};
use crate::cli::ProbeConfig;
use crate::error::AppError;
use crate::metrics::DurationStats;

/// Extra time for opening the device on top of the capture duration.
const OPEN_ALLOWANCE: Duration = Duration::from_secs(10);

/// Runs the probe on its own thread. Closing a device has been seen to
/// block inside Media Foundation (docs/hardware-probe-2026-11-24.md); the
/// main thread waits for that only up to [`STOP_TIMEOUT`] and then reports
/// it instead of hanging silently.
pub fn run(config: &ProbeConfig) -> Result<(), AppError> {
    let (report_tx, report_rx) = mpsc::channel::<Result<(), SourceError>>();
    let (closed_tx, closed_rx) = mpsc::channel::<Duration>();
    let worker_config = config.clone();
    thread::Builder::new()
        .name("probe".into())
        .spawn(move || {
            let (result, source) = capture_and_report(&worker_config);
            let _ = report_tx.send(result);
            let close_start = Instant::now();
            drop(source);
            let _ = closed_tx.send(close_start.elapsed());
        })
        .map_err(|e| AppError::DeviceProbe(format!("cannot start the probe thread: {e}")))?;

    let result = match report_rx.recv_timeout(config.duration + OPEN_ALLOWANCE) {
        Ok(result) => result,
        Err(_) => {
            println!("\nthe probe did not finish (opening or reading the device hangs)");
            return Err(AppError::Source(SourceError::Device(
                "not responding; the process may only fully exit after the device is \
                 replugged or Windows restarts"
                    .into(),
            )));
        }
    };
    match closed_rx.recv_timeout(STOP_TIMEOUT) {
        Ok(d) => println!("device closed in {:.1} ms", ms(d)),
        Err(_) => println!(
            "closing the device did not finish within {:.0} s (Media Foundation or the driver \
             is stuck). The process may only fully exit after the device is replugged or \
             Windows restarts.",
            STOP_TIMEOUT.as_secs_f64()
        ),
    }
    result.map_err(AppError::Source)
}

/// Opens, captures and prints. Returns the source so the caller can time
/// (and bound) closing it.
fn capture_and_report(
    config: &ProbeConfig,
) -> (Result<(), SourceError>, Option<MediaFoundationSource>) {
    // MediaFoundationSource initializes COM (MTA) on this thread, which runs
    // no window, so the apartment is free to choose.
    let options = ReaderOptions {
        allow_any_format: true,
        ..ReaderOptions::from_env()
    };
    let open_start = Instant::now();
    let mut source = match MediaFoundationSource::open(&config.device, &config.mode, options) {
        Ok(source) => source,
        Err(err) => return (Err(err), None),
    };
    let opened_at = Instant::now();
    let info = source.info().clone();
    let (color, color_reported) = source.color();

    println!("device   [{}] {}", source.device_index(), info.name);
    println!("id       {}", source.symbolic_link());
    println!(
        "mode     #{} {}",
        source.native_index(),
        source.format_description()
    );
    println!("reader   MF_LOW_LATENCY {}", on_off(options.low_latency));
    println!(
        "colour   {color} ({})",
        if color_reported {
            "reported by the media type"
        } else {
            "NOT reported, assumed"
        }
    );
    println!(
        "open     {:.1} ms",
        ms(opened_at.duration_since(open_start))
    );
    println!("\nnegotiated media type:");
    for (key, value) in source.current_type_attributes() {
        println!("  {key:<34} {value}");
    }

    println!(
        "\ncapturing for {:.1} s without a window ...",
        config.duration.as_secs_f64()
    );
    let deadline = opened_at + config.duration;
    let mut arrival_interval = DurationStats::default();
    let mut last_arrival: Option<Instant> = None;
    let mut first_sequence = None;
    let mut last_frame: Option<Frame> = None;
    let mut failure = None;
    while Instant::now() < deadline {
        match source.next_frame() {
            Ok(Some(frame)) => {
                if let Some(last) = last_arrival {
                    arrival_interval.record(frame.ready_at.saturating_duration_since(last));
                }
                last_arrival = Some(frame.ready_at);
                first_sequence.get_or_insert(frame.sequence);
                last_frame = Some(frame);
            }
            Ok(None) => {}
            Err(err) => {
                failure = Some(err);
                break;
            }
        }
    }
    let elapsed = opened_at.elapsed();
    let stats = source.stats().clone();

    println!("\nresult:");
    if let Some(err) = &failure {
        println!("  capture failed       {err}");
    }
    match stats.first_sample_at {
        Some(t) => println!(
            "  first sample after   {:.1} ms (after open)",
            ms(t.saturating_duration_since(opened_at))
        ),
        None => {
            println!(
                "  first sample after   - (none in {:.1} s)",
                elapsed.as_secs_f64()
            );
            println!(
                "                       Blocked by security software (e.g. Kaspersky camera/program \
                 protection)? In use by another app? See README, troubleshooting."
            );
        }
    }
    println!(
        "  samples              {} in {:.2} s = {:.2} per s (any format, by arrival)",
        stats.samples,
        elapsed.as_secs_f64(),
        stats.samples as f64 / elapsed.as_secs_f64()
    );
    println!("  NV12 frames          {}", stats.frames);
    if let (Some(first), Some(frame)) = (first_sequence, &last_frame) {
        let expected = frame.sequence - first + 1;
        println!(
            "  missing by timestamp {} of {} expected at the nominal rate",
            expected.saturating_sub(stats.frames),
            expected
        );
    }
    println!("  stream ticks (gaps)  {}", stats.stream_ticks);
    println!("  skipped samples      {}", stats.bad_samples);
    println!(
        "  device interval      {} (sample timestamps)",
        min_avg_max(&stats.sample_interval)
    );
    println!(
        "  arrival interval     {} (callback times, NV12 frames)",
        min_avg_max(&arrival_interval)
    );
    println!("  copy into frame      {}", min_avg_max(&stats.copy_time));
    if stats.device_to_callback.mean().is_some() || stats.device_time_after_callback > 0 {
        println!(
            "  device ref -> callback {} ({} samples with the reference time after the callback)",
            min_avg_max(&stats.device_to_callback),
            stats.device_time_after_callback
        );
        println!(
            "                       MFSampleExtension_DeviceReferenceSystemTime vs MFGetSystemTime;"
        );
        println!(
            "                       what the driver stamps is driver-specific, not HDMI input time"
        );
    } else {
        println!(
            "  device ref -> callback - (driver sets no MFSampleExtension_DeviceReferenceSystemTime)"
        );
    }
    if let Some(layout) = &stats.layout {
        println!("  buffer layout        {layout}");
    }
    if let Some(frame) = &last_frame {
        print_value_ranges(frame);
    }
    println!("\nSoftware timing only; no HDMI-to-photon latency is measured here.");
    let result = match failure {
        Some(err) => Err(err),
        None => Ok(()),
    };
    (result, Some(source))
}

fn on_off(value: bool) -> &'static str {
    if value { "on" } else { "off" }
}

/// Min/max/mean of the planes of an NV12 frame and how much of Y lies
/// outside the limited range, which hints at full-range content.
fn print_value_ranges(frame: &Frame) {
    if frame.format != PixelFormat::Nv12 {
        return;
    }
    let luma_len = frame.width as usize * frame.height as usize;
    let (luma, chroma) = frame.data.split_at(luma_len);
    let cb: Vec<u8> = chroma.iter().step_by(2).copied().collect();
    let cr: Vec<u8> = chroma.iter().skip(1).step_by(2).copied().collect();
    println!("  last frame (#{}):", frame.sequence);
    for (name, plane) in [("Y", luma), ("Cb", &cb[..]), ("Cr", &cr[..])] {
        let (min, max, mean) = plane_stats(plane);
        println!("    {name:<3} min {min:>3}  max {max:>3}  mean {mean:>6.1}");
    }
    let below = luma.iter().filter(|&&v| v < 16).count();
    let above = luma.iter().filter(|&&v| v > 235).count();
    println!(
        "    Y below 16: {:.2} %, above 235: {:.2} % (non-zero suggests full-range data)",
        100.0 * below as f64 / luma.len() as f64,
        100.0 * above as f64 / luma.len() as f64
    );
}

fn plane_stats(plane: &[u8]) -> (u8, u8, f64) {
    let min = plane.iter().copied().min().unwrap_or(0);
    let max = plane.iter().copied().max().unwrap_or(0);
    let sum: u64 = plane.iter().map(|&v| u64::from(v)).sum();
    (min, max, sum as f64 / plane.len().max(1) as f64)
}

fn ms(d: Duration) -> f64 {
    d.as_secs_f64() * 1000.0
}

fn min_avg_max(s: &DurationStats) -> String {
    match (s.min(), s.mean(), s.max()) {
        (Some(min), Some(mean), Some(max)) => format!(
            "min {:.2}  avg {:.2}  max {:.2} ms",
            ms(min),
            ms(mean),
            ms(max)
        ),
        _ => "-".into(),
    }
}

#[cfg(test)]
mod tests {
    use super::plane_stats;

    #[test]
    fn plane_statistics() {
        assert_eq!(plane_stats(&[16, 235, 128, 129]), (16, 235, 127.0));
        assert_eq!(plane_stats(&[]), (0, 0, 0.0));
    }
}
