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
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, mpsc};
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
    /// interleaved CbCr plane. Matrix and range: [`Frame::color`].
    Nv12,
}

/// Y'CbCr → R'G'B' matrix of a YUV frame.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum YuvMatrix {
    Bt601,
    Bt709,
}

/// Value range of a YUV frame.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum YuvRange {
    /// Studio range: Y 16..235, CbCr 16..240.
    Limited,
    /// Full range: Y and CbCr 0..255 (typical for JPEG-derived video).
    Full,
}

/// How to interpret YUV samples. Ignored for RGB formats.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ColorSpace {
    pub matrix: YuvMatrix,
    pub range: YuvRange,
}

impl ColorSpace {
    pub const BT709_LIMITED: Self = Self {
        matrix: YuvMatrix::Bt709,
        range: YuvRange::Limited,
    };
}

impl fmt::Display for ColorSpace {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let matrix = match self.matrix {
            YuvMatrix::Bt601 => "BT.601",
            YuvMatrix::Bt709 => "BT.709",
        };
        let range = match self.range {
            YuvRange::Limited => "limited",
            YuvRange::Full => "full",
        };
        write!(f, "{matrix} {range}")
    }
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

/// Which capture device to open.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DeviceSelector {
    /// Position in the order `--list-devices` prints. That order is not
    /// guaranteed to stay the same across replugs or reboots. A number that
    /// is no valid position is matched against names and ids instead.
    Index(usize),
    /// Case-insensitive part of the friendly name or the symbolic link.
    Name(String),
}

impl fmt::Display for DeviceSelector {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Index(i) => write!(f, "device #{i}"),
            Self::Name(name) => write!(f, "device {name:?}"),
        }
    }
}

/// Which of a device's reported media types to use.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ModeSelector {
    /// The best NV12 mode the device reports: highest frame rate up to 60,
    /// then the largest picture (1920×1080 @ 60 on the UGREEN 25854).
    Best,
    /// Index into the native media types, as `--list-devices` prints them.
    Index(u32),
    /// Exactly this size, pixel format and frame rate.
    Match(VideoMode),
}

impl fmt::Display for ModeSelector {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Best => write!(f, "best NV12 mode"),
            Self::Index(i) => write!(f, "mode #{i}"),
            Self::Match(mode) => write!(f, "{mode}"),
        }
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
    /// YUV matrix and range (ignored for RGB formats).
    pub color: ColorSpace,
    /// Software timestamp taken when the frame became available to the
    /// application. This is *not* the time the image left the HDMI source.
    pub ready_at: Instant,
}

#[derive(Debug)]
pub enum SourceError {
    /// The requested mode cannot be produced by this source.
    UnsupportedMode(String),
    /// No device matches the selection (not plugged in?). Cheap to retry:
    /// nothing was opened.
    NotFound(String),
    /// The device is held by another app or a stuck process.
    Busy(String),
    /// The device could not be opened or read (unplugged while running,
    /// driver error).
    Device(String),
}

impl fmt::Display for SourceError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::UnsupportedMode(msg) => write!(f, "unsupported video mode: {msg}"),
            Self::NotFound(msg) => write!(f, "capture device not found: {msg}"),
            Self::Busy(msg) => write!(f, "capture device busy: {msg}"),
            Self::Device(msg) => write!(f, "capture device: {msg}"),
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

    /// Blocks until the next frame is available and returns it, or returns
    /// `Ok(None)` if none arrived within a short bounded wait (a few hundred
    /// milliseconds at most), so the capture thread can notice a stop request
    /// even when a device delivers nothing (e.g. no HDMI signal).
    fn next_frame(&mut self) -> Result<Option<Frame>, SourceError>;

    /// Called once when capture stops, e.g. to log source-specific counters.
    fn log_summary(&self) {}
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

/// How long [`CaptureHandle::stop`] waits for the capture thread, including
/// closing the device.
pub const STOP_TIMEOUT: Duration = Duration::from_secs(2);

/// Owns the capture thread; stopping happens on drop.
pub struct CaptureHandle {
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
    /// Closed (sender dropped) when the capture thread has finished,
    /// including the source's teardown.
    finished: mpsc::Receiver<()>,
}

impl CaptureHandle {
    /// Asks the capture thread to stop and waits up to [`STOP_TIMEOUT`].
    ///
    /// Closing a capture device can block inside the driver (seen with
    /// Media Foundation on 2026-11-24, docs/hardware-probe-2026-11-24.md).
    /// The window must not freeze because of that, so after the timeout the
    /// thread is left behind with an error in the log. Returns whether the
    /// thread finished.
    pub fn stop(&mut self) -> bool {
        self.stop.store(true, Ordering::Relaxed);
        let Some(thread) = self.thread.take() else {
            return true;
        };
        match self.finished.recv_timeout(STOP_TIMEOUT) {
            Err(mpsc::RecvTimeoutError::Timeout) => {
                tracing::error!(
                    timeout_s = STOP_TIMEOUT.as_secs_f64(),
                    "capture thread did not stop in time (device or driver not responding); \
                     leaving it behind. The process may only fully exit after the device \
                     is replugged or Windows restarts"
                );
                false
            }
            // Disconnected: the thread finished (or panicked) and dropped the
            // sender, so joining returns at once.
            Ok(()) | Err(mpsc::RecvTimeoutError::Disconnected) => {
                if thread.join().is_err() {
                    tracing::error!("capture thread panicked");
                }
                true
            }
        }
    }

    /// Asks the capture thread to stop without waiting for it.
    pub fn request_stop(&self) {
        self.stop.store(true, Ordering::Relaxed);
    }

    /// Joins the thread if it has finished; never blocks. Returns whether it
    /// is gone.
    pub fn try_join(&mut self) -> bool {
        if self.thread.is_none() {
            return true;
        }
        match self.finished.try_recv() {
            Err(mpsc::TryRecvError::Empty) => false,
            Ok(()) | Err(mpsc::TryRecvError::Disconnected) => {
                if let Some(thread) = self.thread.take()
                    && thread.join().is_err()
                {
                    tracing::error!("capture thread panicked");
                }
                true
            }
        }
    }
}

impl Drop for CaptureHandle {
    /// Never blocks: a thread that has not finished is asked to stop and
    /// left behind. Use [`CaptureHandle::stop`] to wait (bounded).
    fn drop(&mut self) {
        self.request_stop();
        if !self.try_join() {
            tracing::debug!("capture thread still closing its device; detached");
        }
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
    let (finished_tx, finished) = mpsc::channel();
    let thread = {
        let stop = Arc::clone(&stop);
        thread::Builder::new()
            .name("capture".into())
            .spawn(move || {
                // The source (and with it the device) is dropped inside
                // capture_loop, so this signal means "fully closed".
                capture_loop(factory, &mailbox, &stop, &notify);
                drop(finished_tx);
            })?
    };
    Ok(CaptureHandle {
        stop,
        thread: Some(thread),
        finished,
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
            Ok(Some(frame)) => {
                if mailbox.publish(frame).needs_wake() && !notify(CaptureEvent::FrameReady) {
                    break;
                }
            }
            Ok(None) => {}
            Err(err) => {
                tracing::error!(%err, "capture failed");
                notify(CaptureEvent::Failed(err));
                break;
            }
        }
    }
    source.log_summary();
    tracing::info!("capture stopped");
}

#[cfg(test)]
mod tests {
    use super::*;

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
        fn next_frame(&mut self) -> Result<Option<Frame>, SourceError> {
            std::thread::sleep(Duration::from_millis(1));
            self.next += 1;
            // Every third call simulates "nothing arrived in time".
            if self.next.is_multiple_of(3) {
                return Ok(None);
            }
            Ok(Some(Frame {
                sequence: self.next,
                width: 2,
                height: 2,
                format: PixelFormat::Bgra8,
                data: vec![0; 16],
                color: ColorSpace::BT709_LIMITED,
                ready_at: Instant::now(),
            }))
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

    /// A source whose teardown blocks longer than STOP_TIMEOUT, like a
    /// device whose driver hangs on close.
    struct HangsOnDrop(Counting);

    impl VideoSource for HangsOnDrop {
        fn info(&self) -> &SourceInfo {
            self.0.info()
        }
        fn next_frame(&mut self) -> Result<Option<Frame>, SourceError> {
            self.0.next_frame()
        }
    }

    impl Drop for HangsOnDrop {
        fn drop(&mut self) {
            thread::sleep(STOP_TIMEOUT + Duration::from_millis(500));
        }
    }

    #[test]
    fn stop_gives_up_on_a_hanging_teardown() {
        let factory: SourceFactory = Box::new(|| {
            let Ok(inner) = counting_factory()() else {
                unreachable!("counting factory never fails")
            };
            let info = inner.info().clone();
            Ok(Box::new(HangsOnDrop(Counting { info, next: 0 })) as Box<dyn VideoSource>)
        });
        let mailbox = Arc::new(Mailbox::new());
        let (tx, rx) = mpsc::channel();
        let mut handle =
            spawn_capture(factory, mailbox, move |event| tx.send(event).is_ok()).unwrap();
        assert!(matches!(rx.recv().unwrap(), CaptureEvent::Opened(_)));
        let start = Instant::now();
        assert!(!handle.stop(), "stop should report the timeout");
        let waited = start.elapsed();
        assert!(
            waited >= STOP_TIMEOUT,
            "returned before the timeout: {waited:?}"
        );
        assert!(
            waited < STOP_TIMEOUT + Duration::from_millis(400),
            "waited for the hanging teardown: {waited:?}"
        );
    }
}
