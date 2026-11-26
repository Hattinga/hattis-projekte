//! Audio monitoring: plays the capture device's audio on a PC output.
//!
//! ```text
//! audio thread (one thread, COM MTA)
//!   capture endpoint ──event──► drain packets ──► PlayoutBuffer ──► render endpoint
//!   "Digitale Audioschnittstelle      (f32 stereo, target ~30 ms,      (Windows default
//!    (UGREEN 25854)"                    drift: ±1 frame / 500)            or chosen output)
//! ```
//!
//! * **No microphone monitoring by accident:** the input is only ever the
//!   capture endpoint whose name contains the video device's name. There is
//!   no fallback to the default recording device (on the development PC that
//!   is one of several microphones). No match means no audio.
//! * **Clock drift:** the card's audio clock and the headset's clock differ
//!   slightly, so the buffer would slowly fill up (latency) or run dry
//!   (crackles). [`PlayoutBuffer`] keeps it near a target level by dropping or
//!   repeating single frames, at most one in 500 (0.2 %, inaudible).
//! * Both WASAPI streams use the same format (32-bit float stereo at the
//!   output's mix rate); Windows converts (`AUTOCONVERTPCM`), so there is no
//!   resampler here.
//! * The thread reconnects on its own (unplug, output change) and stops
//!   within a bounded time, like the capture thread.

#[cfg(windows)]
mod wasapi;

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Mutex, PoisonError, mpsc};
use std::thread::{self, JoinHandle};
use std::time::Duration;

/// How long [`AudioHandle::stop`] waits for the audio thread.
const STOP_TIMEOUT: Duration = Duration::from_secs(2);

/// What to play and where.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AudioOptions {
    /// Name of the video capture device. The audio input is the recording
    /// endpoint whose name contains it, e.g. "Digitale Audioschnittstelle
    /// (UGREEN 25854)" for "UGREEN 25854".
    pub video_device: String,
    /// Output endpoint name (or part of it); `None` = Windows default.
    pub output: Option<String>,
    pub volume: u8,
    pub muted: bool,
}

/// What the audio thread is doing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AudioState {
    Starting,
    Playing {
        input: String,
        output: String,
        sample_rate: u32,
    },
    /// No recording endpoint matches the video device.
    NoInput {
        wanted: String,
    },
    /// Opening or running failed; retrying.
    Retrying(String),
}

/// Snapshot for the overlay and the log.
#[derive(Debug, Clone, PartialEq)]
pub struct AudioStatus {
    pub state: AudioState,
    pub buffer_ms: f32,
    pub stats: PlayoutStats,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct PlayoutStats {
    /// The buffer ran dry while playing (heard as a gap).
    pub underruns: u64,
    /// Single frames dropped / repeated to follow clock drift.
    pub dropped: u64,
    pub inserted: u64,
    /// Frames discarded at once after a stall left too much audio queued.
    pub trimmed: u64,
}

/// State shared between the UI thread and the audio thread.
struct Shared {
    stop: AtomicBool,
    /// Gain as `f32` bits.
    gain: AtomicU32,
    muted: AtomicBool,
    status: Mutex<AudioStatus>,
}

impl Shared {
    fn gain(&self) -> f32 {
        if self.muted.load(Ordering::Relaxed) {
            0.0
        } else {
            f32::from_bits(self.gain.load(Ordering::Relaxed))
        }
    }

    fn set_status(&self, update: impl FnOnce(&mut AudioStatus)) {
        update(&mut self.status.lock().unwrap_or_else(PoisonError::into_inner));
    }
}

/// Perceived loudness grows roughly with the square of the amplitude
/// setting, so a squared curve makes the volume steps feel even.
pub fn volume_to_gain(percent: u8) -> f32 {
    let v = f32::from(percent.min(100)) / 100.0;
    v * v
}

/// Owns the audio thread. Dropping it asks the thread to stop without
/// waiting; [`AudioHandle::stop`] waits (bounded).
pub struct AudioHandle {
    shared: Arc<Shared>,
    thread: Option<JoinHandle<()>>,
    finished: mpsc::Receiver<()>,
}

impl AudioHandle {
    pub fn start(options: AudioOptions) -> std::io::Result<Self> {
        let shared = Arc::new(Shared {
            stop: AtomicBool::new(false),
            gain: AtomicU32::new(volume_to_gain(options.volume).to_bits()),
            muted: AtomicBool::new(options.muted),
            status: Mutex::new(AudioStatus {
                state: AudioState::Starting,
                buffer_ms: 0.0,
                stats: PlayoutStats::default(),
            }),
        });
        let (finished_tx, finished) = mpsc::channel::<()>();
        let thread = {
            let shared = Arc::clone(&shared);
            thread::Builder::new().name("audio".into()).spawn(move || {
                run(&shared, &options);
                drop(finished_tx);
            })?
        };
        Ok(Self {
            shared,
            thread: Some(thread),
            finished,
        })
    }

    pub fn set_volume(&self, percent: u8) {
        self.shared
            .gain
            .store(volume_to_gain(percent).to_bits(), Ordering::Relaxed);
    }

    pub fn set_muted(&self, muted: bool) {
        self.shared.muted.store(muted, Ordering::Relaxed);
    }

    pub fn status(&self) -> AudioStatus {
        self.shared
            .status
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clone()
    }

    /// Stops the thread, waiting at most [`STOP_TIMEOUT`]. Returns whether it
    /// finished.
    pub fn stop(&mut self) -> bool {
        self.shared.stop.store(true, Ordering::Relaxed);
        let Some(thread) = self.thread.take() else {
            return true;
        };
        match self.finished.recv_timeout(STOP_TIMEOUT) {
            Err(mpsc::RecvTimeoutError::Timeout) => {
                tracing::error!("audio thread did not stop in time; leaving it behind");
                false
            }
            Ok(()) | Err(mpsc::RecvTimeoutError::Disconnected) => {
                if thread.join().is_err() {
                    tracing::error!("audio thread panicked");
                }
                true
            }
        }
    }
}

impl Drop for AudioHandle {
    fn drop(&mut self) {
        self.shared.stop.store(true, Ordering::Relaxed);
    }
}

#[cfg(windows)]
fn run(shared: &Shared, options: &AudioOptions) {
    wasapi::run(shared, options);
}

/// Names of the active (recording, playback) endpoints.
#[cfg(windows)]
pub fn endpoint_names() -> Result<(Vec<String>, Vec<String>), String> {
    wasapi::endpoint_names()
}

#[cfg(not(windows))]
fn run(shared: &Shared, _options: &AudioOptions) {
    shared.set_status(|s| s.state = AudioState::Retrying("audio needs WASAPI (Windows)".into()));
}

/// Interleaved sample queue between capture and render, with drift control.
///
/// Playback starts once [`PlayoutBuffer::target`] frames are queued. While
/// playing, a smoothed fill level above `target + tolerance` drops one frame
/// per [`CORRECTION_INTERVAL`] output frames; below `target - tolerance` it
/// repeats one. An empty buffer is an underrun: silence, and playback waits
/// for the target level again. More than `max` queued frames (after a stall)
/// are trimmed back to the target at once.
pub struct PlayoutBuffer {
    channels: usize,
    samples: VecDeque<f32>,
    target: usize,
    tolerance: usize,
    max: usize,
    playing: bool,
    level_ema: f64,
    since_correction: u32,
    stats: PlayoutStats,
}

/// Output frames between two single-frame drift corrections (0.2 %).
const CORRECTION_INTERVAL: u32 = 500;
/// Weight of the newest level in the smoothed level (per `pull`).
const LEVEL_SMOOTHING: f64 = 0.05;

impl PlayoutBuffer {
    /// Buffer for `channels` interleaved channels at `sample_rate`, aiming at
    /// `target_ms` of queued audio.
    pub fn new(channels: usize, sample_rate: u32, target_ms: u32) -> Self {
        let frames_per_ms = (sample_rate / 1000).max(1) as usize;
        let target = frames_per_ms * target_ms as usize;
        Self {
            channels: channels.max(1),
            samples: VecDeque::with_capacity(target * 8 * channels.max(1)),
            target,
            tolerance: target / 3,
            max: target * 5,
            playing: false,
            level_ema: 0.0,
            since_correction: 0,
            stats: PlayoutStats::default(),
        }
    }

    #[cfg(test)]
    pub fn target(&self) -> usize {
        self.target
    }

    /// Queued frames.
    pub fn level(&self) -> usize {
        self.samples.len() / self.channels
    }

    pub fn stats(&self) -> PlayoutStats {
        self.stats
    }

    /// Appends interleaved samples (whole frames).
    pub fn push(&mut self, interleaved: &[f32]) {
        self.samples.extend(interleaved);
    }

    pub fn push_silence(&mut self, frames: usize) {
        self.samples
            .extend(std::iter::repeat_n(0.0, frames * self.channels));
    }

    /// Fills `out` (interleaved, whole frames) and applies `gain`.
    pub fn pull(&mut self, out: &mut [f32], gain: f32) {
        let ch = self.channels;
        if self.level() > self.max {
            let excess = self.level() - self.target;
            self.samples.drain(..excess * ch);
            self.stats.trimmed += excess as u64;
        }
        if !self.playing {
            if self.level() < self.target {
                out.fill(0.0);
                return;
            }
            self.playing = true;
            self.level_ema = self.level() as f64;
        }
        self.level_ema += (self.level() as f64 - self.level_ema) * LEVEL_SMOOTHING;
        let high = (self.target + self.tolerance) as f64;
        let low = self.target.saturating_sub(self.tolerance) as f64;

        for frame in out.chunks_exact_mut(ch) {
            if self.level() == 0 {
                frame.fill(0.0);
                if self.playing {
                    self.playing = false;
                    self.stats.underruns += 1;
                }
                continue;
            }
            self.since_correction += 1;
            let due = self.since_correction >= CORRECTION_INTERVAL;
            if due && self.level_ema > high && self.level() >= 2 {
                // Running ahead: skip one frame.
                self.samples.drain(..ch);
                self.stats.dropped += 1;
                self.since_correction = 0;
            }
            for (slot, sample) in frame.iter_mut().zip(self.samples.iter()) {
                *slot = sample * gain;
            }
            if due && self.level_ema < low {
                // Running dry: play this frame twice (keep it queued).
                self.stats.inserted += 1;
                self.since_correction = 0;
            } else {
                self.samples.drain(..ch);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 1 kHz rate: 1 frame per ms keeps the numbers readable.
    fn buffer() -> PlayoutBuffer {
        PlayoutBuffer::new(2, 1000, 30)
    }

    fn ramp(frames: usize, start: f32) -> Vec<f32> {
        (0..frames)
            .flat_map(|i| {
                let v = start + i as f32;
                [v, -v]
            })
            .collect()
    }

    #[test]
    fn waits_for_the_target_level_then_plays_in_order() {
        let mut b = buffer();
        assert_eq!(b.target(), 30);
        b.push(&ramp(20, 1.0));
        let mut out = vec![9.0; 10 * 2];
        b.pull(&mut out, 1.0);
        assert!(out.iter().all(|&s| s == 0.0), "silence before the target");
        assert_eq!(b.level(), 20, "nothing consumed while prefilling");

        b.push(&ramp(10, 21.0));
        b.pull(&mut out, 0.5);
        assert_eq!(&out[..4], &[0.5, -0.5, 1.0, -1.0]);
        assert_eq!(b.level(), 20);
    }

    #[test]
    fn underrun_gives_silence_and_restarts_prefill() {
        let mut b = buffer();
        b.push(&ramp(30, 1.0));
        let mut out = vec![0.0; 40 * 2];
        b.pull(&mut out, 1.0);
        assert_eq!(out[58], 30.0, "frame 30 played");
        assert!(out[60..].iter().all(|&s| s == 0.0), "then silence");
        assert_eq!(b.stats().underruns, 1);
        // Not playing again until the target is reached.
        b.push(&ramp(5, 1.0));
        let mut out = vec![1.0; 5 * 2];
        b.pull(&mut out, 1.0);
        assert!(out.iter().all(|&s| s == 0.0));
        assert_eq!(b.stats().underruns, 1);
    }

    /// Pushes 10 frames per pull of 10, plus `drift` frames on average
    /// (positive: source clock fast), for `rounds` rounds.
    fn run_drift(b: &mut PlayoutBuffer, drift: f64, rounds: usize) {
        let mut out = vec![0.0; 10 * 2];
        let mut carry = 0.0f64;
        for _ in 0..rounds {
            carry += drift;
            let mut frames = 10i64;
            if carry >= 1.0 {
                carry -= 1.0;
                frames += 1;
            } else if carry <= -1.0 {
                carry += 1.0;
                frames -= 1;
            }
            b.push(&vec![0.25; frames as usize * 2]);
            b.pull(&mut out, 1.0);
        }
    }

    /// A source clock 0.1 % fast (real devices are usually well below that)
    /// must not let the queue, i.e. the latency, grow.
    #[test]
    fn fast_source_is_corrected_by_dropping_frames() {
        let mut b = buffer();
        run_drift(&mut b, 0.01, 5000);
        assert!(b.stats().dropped > 20, "{:?}", b.stats());
        assert!(b.level() < 60, "level {}", b.level());
        assert_eq!(b.stats().trimmed, 0);
        assert_eq!(b.stats().underruns, 0);
    }

    #[test]
    fn slow_source_is_corrected_by_repeating_frames() {
        let mut b = buffer();
        b.push(&vec![0.25; 30 * 2]);
        run_drift(&mut b, -0.01, 5000);
        assert!(b.stats().inserted > 20, "{:?}", b.stats());
        assert_eq!(b.stats().underruns, 0, "{:?}", b.stats());
    }

    #[test]
    fn backlog_after_a_stall_is_trimmed_to_the_target() {
        let mut b = buffer();
        b.push(&vec![0.1; 400 * 2]);
        let mut out = vec![0.0; 10 * 2];
        b.pull(&mut out, 1.0);
        assert_eq!(b.stats().trimmed, 370);
        assert_eq!(b.level(), 20);
    }

    #[test]
    fn volume_curve() {
        assert_eq!(volume_to_gain(0), 0.0);
        assert_eq!(volume_to_gain(100), 1.0);
        assert!((volume_to_gain(50) - 0.25).abs() < 1e-6);
        assert_eq!(volume_to_gain(250), 1.0);
    }
}
