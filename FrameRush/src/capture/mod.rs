//! Video sources and frame delivery.
//!
//! A [`VideoSource`] produces frames on its own thread ([`spawn_capture`]).
//! Frames are handed to the renderer through a single-slot [`Mailbox`]: the
//! renderer always gets the newest frame and stale ones are dropped instead of
//! queued.

pub mod mailbox;
#[cfg(windows)]
pub mod media_foundation;
pub mod synthetic;

use std::fmt;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

pub use mailbox::Mailbox;

/// Pixel layout of [`Frame::data`]. Planes are tightly packed (no row
/// padding); a source with padded rows must repack before publishing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PixelFormat {
    /// 8-bit B, G, R, A per pixel; sRGB-encoded colour, alpha ignored.
    Bgra8,
    /// 4:2:0: full-resolution 8-bit Y plane followed by a half-resolution
    /// interleaved CbCr plane. BT.709, limited (studio) range.
    Nv12,
}

impl PixelFormat {
    pub fn name(self) -> &'static str {
        match self {
            Self::Bgra8 => "BGRA8",
            Self::Nv12 => "NV12",
        }
    }

    /// Size in bytes of one tightly packed frame. `None` if the dimensions are
    /// invalid for the format (zero, or odd for 4:2:0 subsampling).
    pub fn frame_len(self, width: u32, height: u32) -> Option<usize> {
        if width == 0 || height == 0 {
            return None;
        }
        let (w, h) = (width as usize, height as usize);
        match self {
            Self::Bgra8 => Some(w * h * 4),
            Self::Nv12 if width.is_multiple_of(2) && height.is_multiple_of(2) => {
                Some(w * h + w * h / 2)
            }
            Self::Nv12 => None,
        }
    }
}

/// Frames per second as an exact ratio (e.g. 60/1 or 60000/1001).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FrameRate {
    pub numerator: u32,
    pub denominator: u32,
}

impl FrameRate {
    pub fn new(numerator: u32, denominator: u32) -> Option<Self> {
        (numerator > 0 && denominator > 0).then_some(Self {
            numerator,
            denominator,
        })
    }

    pub fn as_f64(self) -> f64 {
        f64::from(self.numerator) / f64::from(self.denominator)
    }

    /// Exact presentation time of frame `index` relative to frame 0. Computed
    /// from the index each time so rounding never accumulates into drift.
    pub fn time_of_frame(self, index: u64) -> Duration {
        let nanos = u128::from(index) * u128::from(self.denominator) * 1_000_000_000
            / u128::from(self.numerator);
        Duration::from_nanos(u64::try_from(nanos).unwrap_or(u64::MAX))
    }

    /// Index of the frame slot that contains `elapsed` (floor).
    pub fn frame_at(self, elapsed: Duration) -> u64 {
        let index = elapsed.as_nanos() * u128::from(self.numerator)
            / (u128::from(self.denominator) * 1_000_000_000);
        u64::try_from(index).unwrap_or(u64::MAX)
    }
}

impl fmt::Display for FrameRate {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.denominator == 1 {
            write!(f, "{}", self.numerator)
        } else {
            write!(f, "{:.3}", self.as_f64())
        }
    }
}

/// Resolution, pixel format and frame rate of a stream.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VideoMode {
    pub width: u32,
    pub height: u32,
    pub format: PixelFormat,
    pub frame_rate: FrameRate,
}

impl fmt::Display for VideoMode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}x{} {} @ {} fps",
            self.width,
            self.height,
            self.format.name(),
            self.frame_rate
        )
    }
}

/// Describes an opened source.
#[derive(Debug, Clone)]
pub struct SourceInfo {
    pub name: String,
    pub mode: VideoMode,
}

/// One video frame owned by the pipeline.
pub struct Frame {
    /// Monotonic per-source counter. Gaps mean the source itself skipped
    /// frames (as opposed to the mailbox dropping them).
    pub sequence: u64,
    pub width: u32,
    pub height: u32,
    pub format: PixelFormat,
    /// Tightly packed planes, `format.frame_len(width, height)` bytes.
    pub data: Vec<u8>,
    /// Software timestamp taken when the frame became available to the
    /// application. This is *not* the time the image left the HDMI source.
    pub ready_at: Instant,
}

#[derive(Debug)]
pub enum SourceError {
    /// The requested mode cannot be produced by this source.
    UnsupportedMode(String),
}

impl fmt::Display for SourceError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::UnsupportedMode(msg) => write!(f, "unsupported video mode: {msg}"),
        }
    }
}

impl std::error::Error for SourceError {}

/// A producer of video frames.
///
/// Implementations are created *on* the capture thread (see
/// [`SourceFactory`]), so they do not need to be `Send`. That matters for
/// Media Foundation, whose COM objects belong to the thread's apartment.
pub trait VideoSource {
    fn info(&self) -> &SourceInfo;

    /// Blocks until the next frame is available and returns it. Must return
    /// within roughly one frame period so the capture thread can notice a
    /// stop request.
    fn next_frame(&mut self) -> Result<Frame, SourceError>;
}

/// Creates the source on the capture thread.
pub type SourceFactory = Box<dyn FnOnce() -> Result<Box<dyn VideoSource>, SourceError> + Send>;

/// Notifications from the capture thread. The receiver returns `false` when
/// it is gone, which stops the thread.
#[derive(Debug)]
pub enum CaptureEvent {
    Opened(SourceInfo),
    /// A frame went into an empty mailbox; the consumer should take it.
    FrameReady,
    Failed(SourceError),
}

/// Owns the capture thread; stopping and joining happens on drop.
pub struct CaptureHandle {
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl CaptureHandle {
    pub fn stop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(thread) = self.thread.take()
            && thread.join().is_err()
        {
            tracing::error!("capture thread panicked");
        }
    }
}

impl Drop for CaptureHandle {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Starts a capture thread that opens the source via `factory` and publishes
/// every frame into `mailbox`.
///
/// The thread never blocks on the renderer: publishing is a short critical
/// section, and `notify(FrameReady)` is only sent on the mailbox's empty→full
/// transition, so at most one wake-up is outstanding (see [`mailbox`]).
pub fn spawn_capture(
    factory: SourceFactory,
    mailbox: Arc<Mailbox<Frame>>,
    notify: impl Fn(CaptureEvent) -> bool + Send + 'static,
) -> std::io::Result<CaptureHandle> {
    let stop = Arc::new(AtomicBool::new(false));
    let thread = {
        let stop = Arc::clone(&stop);
        thread::Builder::new()
            .name("capture".into())
            .spawn(move || capture_loop(factory, &mailbox, &stop, &notify))?
    };
    Ok(CaptureHandle {
        stop,
        thread: Some(thread),
    })
}

fn capture_loop(
    factory: SourceFactory,
    mailbox: &Mailbox<Frame>,
    stop: &AtomicBool,
    notify: &dyn Fn(CaptureEvent) -> bool,
) {
    let mut source = match factory() {
        Ok(source) => source,
        Err(err) => {
            notify(CaptureEvent::Failed(err));
            return;
        }
    };
    tracing::info!(source = %source.info().name, mode = %source.info().mode, "capture started");
    if !notify(CaptureEvent::Opened(source.info().clone())) {
        return;
    }
    while !stop.load(Ordering::Relaxed) {
        match source.next_frame() {
            Ok(frame) => {
                if mailbox.publish(frame).needs_wake() && !notify(CaptureEvent::FrameReady) {
                    break;
                }
            }
            Err(err) => {
                tracing::error!(%err, "capture failed");
                notify(CaptureEvent::Failed(err));
                break;
            }
        }
    }
    tracing::info!("capture stopped");
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;

    #[test]
    fn frame_len_matches_plane_layout() {
        assert_eq!(
            PixelFormat::Bgra8.frame_len(1920, 1080),
            Some(1920 * 1080 * 4)
        );
        assert_eq!(
            PixelFormat::Nv12.frame_len(1920, 1080),
            Some(1920 * 1080 * 3 / 2)
        );
        assert_eq!(PixelFormat::Nv12.frame_len(1921, 1080), None);
        assert_eq!(PixelFormat::Bgra8.frame_len(0, 1080), None);
    }

    #[test]
    fn frame_times_do_not_drift() {
        let ntsc = FrameRate::new(60_000, 1001).unwrap();
        // 60000 frames at 59.94 fps take exactly 1001 seconds.
        assert_eq!(ntsc.time_of_frame(60_000), Duration::from_secs(1001));
        let sixty = FrameRate::new(60, 1).unwrap();
        assert_eq!(sixty.time_of_frame(60), Duration::from_secs(1));
        assert_eq!(sixty.time_of_frame(1), Duration::from_nanos(16_666_666));
        assert_eq!(sixty.frame_at(Duration::from_millis(1000)), 60);
        assert_eq!(sixty.frame_at(Duration::from_millis(16)), 0);
        assert_eq!(sixty.frame_at(Duration::from_millis(17)), 1);
        assert!(FrameRate::new(0, 1).is_none());
    }

    struct Counting {
        info: SourceInfo,
        next: u64,
    }

    impl VideoSource for Counting {
        fn info(&self) -> &SourceInfo {
            &self.info
        }
        fn next_frame(&mut self) -> Result<Frame, SourceError> {
            std::thread::sleep(Duration::from_millis(1));
            self.next += 1;
            Ok(Frame {
                sequence: self.next,
                width: 2,
                height: 2,
                format: PixelFormat::Bgra8,
                data: vec![0; 16],
                ready_at: Instant::now(),
            })
        }
    }

    fn counting_factory() -> SourceFactory {
        Box::new(|| {
            Ok(Box::new(Counting {
                info: SourceInfo {
                    name: "counting".into(),
                    mode: VideoMode {
                        width: 2,
                        height: 2,
                        format: PixelFormat::Bgra8,
                        frame_rate: FrameRate::new(1000, 1).unwrap(),
                    },
                },
                next: 0,
            }) as Box<dyn VideoSource>)
        })
    }

    #[test]
    fn capture_thread_reports_open_then_frames_and_stops_cleanly() {
        let mailbox = Arc::new(Mailbox::new());
        let (tx, rx) = mpsc::channel();
        let mut handle = spawn_capture(counting_factory(), Arc::clone(&mailbox), move |event| {
            tx.send(event).is_ok()
        })
        .unwrap();

        assert!(matches!(rx.recv().unwrap(), CaptureEvent::Opened(_)));
        assert!(matches!(rx.recv().unwrap(), CaptureEvent::FrameReady));
        let first = mailbox.take().expect("wake without frame").sequence;
        assert!(matches!(rx.recv().unwrap(), CaptureEvent::FrameReady));
        let second = mailbox.take().expect("wake without frame").sequence;
        assert!(second > first);

        handle.stop();
        let stats = mailbox.stats();
        assert_eq!(
            stats.published,
            stats.taken + stats.replaced + u64::from(stats.pending)
        );
    }

    #[test]
    fn factory_error_is_reported() {
        let mailbox = Arc::new(Mailbox::new());
        let (tx, rx) = mpsc::channel();
        let factory: SourceFactory = Box::new(|| Err(SourceError::UnsupportedMode("test".into())));
        let _handle = spawn_capture(factory, mailbox, move |event| tx.send(event).is_ok()).unwrap();
        assert!(matches!(rx.recv().unwrap(), CaptureEvent::Failed(_)));
    }
}
