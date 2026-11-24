//! Window, input and the glue between capture, mailbox and renderer.
//!
//! Threads:
//! * **main / event loop** (this file): window events, GPU upload and
//!   present. Woken by the capture thread through winit's event-loop proxy.
//! * **capture**: runs the [`VideoSource`] and publishes into the mailbox.
//!   It never waits for the renderer.

use std::sync::Arc;
use std::time::{Duration, Instant};

use winit::application::ApplicationHandler;
use winit::dpi::LogicalSize;
use winit::event::{ElementState, WindowEvent};
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop, EventLoopProxy};
use winit::keyboard::{Key, NamedKey};
use winit::window::{Fullscreen, Window, WindowId};

use crate::capture::synthetic::SyntheticSource;
use crate::capture::{
    CaptureEvent, CaptureHandle, Frame, Mailbox, SourceFactory, SourceInfo, VideoSource,
    spawn_capture,
};
use crate::cli::{SourceChoice, ViewerConfig};
use crate::error::AppError;
use crate::metrics::{DurationStats, Snapshot, ViewerMetrics};
use crate::render::{Renderer, RendererOptions};

/// Statistics window and overlay refresh interval.
const STATS_INTERVAL: Duration = Duration::from_secs(1);
/// Every n-th statistics window is also written to the log at info level.
const LOG_EVERY: u32 = 5;
/// Re-present for overlay updates only if no frame was shown for this long,
/// so overlay refreshes never compete with live frames for a vsync slot.
const IDLE_REDRAW_AFTER: Duration = Duration::from_millis(250);
/// The overlay warns when an opened source delivered nothing for this long.
const NO_FRAMES_WARNING_AFTER: Duration = Duration::from_secs(1);

pub fn run(config: ViewerConfig) -> Result<(), AppError> {
    let event_loop = EventLoop::<CaptureEvent>::with_user_event().build()?;
    let mut app = App::new(config, event_loop.create_proxy());
    event_loop.run_app(&mut app)?;
    match app.fatal.take() {
        Some(err) => Err(err),
        None => Ok(()),
    }
}

struct App {
    config: ViewerConfig,
    proxy: EventLoopProxy<CaptureEvent>,
    mailbox: Arc<Mailbox<Frame>>,
    window: Option<Arc<Window>>,
    renderer: Option<Renderer>,
    capture: Option<CaptureHandle>,
    source: Option<SourceInfo>,
    source_error: Option<String>,
    /// When the source opened, and when it last delivered a frame.
    source_opened_at: Option<Instant>,
    last_frame_at: Option<Instant>,
    metrics: ViewerMetrics,
    last_snapshot: Option<Snapshot>,
    stats_windows: u32,
    overlay_visible: bool,
    alt_down: bool,
    started: Instant,
    next_tick: Instant,
    last_present: Option<Instant>,
    fatal: Option<AppError>,
}

impl App {
    fn new(config: ViewerConfig, proxy: EventLoopProxy<CaptureEvent>) -> Self {
        let now = Instant::now();
        Self {
            overlay_visible: config.overlay,
            config,
            proxy,
            mailbox: Arc::new(Mailbox::new()),
            window: None,
            renderer: None,
            capture: None,
            source: None,
            source_error: None,
            source_opened_at: None,
            last_frame_at: None,
            metrics: ViewerMetrics::new(now),
            last_snapshot: None,
            stats_windows: 0,
            alt_down: false,
            started: now,
            next_tick: now + STATS_INTERVAL,
            last_present: None,
            fatal: None,
        }
    }

    fn start(&mut self, event_loop: &ActiveEventLoop) -> Result<(), AppError> {
        let attributes = Window::default_attributes()
            .with_title("FrameRush")
            .with_inner_size(LogicalSize::new(1280.0, 720.0))
            .with_min_inner_size(LogicalSize::new(320.0, 180.0))
            .with_fullscreen(
                self.config
                    .fullscreen
                    .then_some(Fullscreen::Borderless(None)),
            );
        let window = Arc::new(event_loop.create_window(attributes)?);
        let renderer = Renderer::new(
            Arc::clone(&window),
            &RendererOptions {
                present_mode: self.config.present_mode,
                frame_latency: self.config.frame_latency,
            },
        )?;
        self.window = Some(window);
        self.renderer = Some(renderer);
        self.refresh_overlay();

        let factory = source_factory(&self.config);
        let proxy = self.proxy.clone();
        let capture = spawn_capture(factory, Arc::clone(&self.mailbox), move |event| {
            proxy.send_event(event).is_ok()
        })
        .map_err(AppError::CaptureThread)?;
        self.capture = Some(capture);
        self.started = Instant::now();
        self.metrics = ViewerMetrics::new(self.started);
        self.next_tick = self.started + STATS_INTERVAL;
        Ok(())
    }

    /// New frame in the mailbox: acquire → take newest → upload → present.
    fn on_frame_ready(&mut self) {
        // Per the mailbox contract every wake-up takes exactly once, also on
        // paths that cannot present, so the next frame triggers a new wake.
        let Some(renderer) = self.renderer.as_mut() else {
            drop(self.mailbox.take());
            return;
        };
        let target = renderer.acquire();
        let taken_at = Instant::now();
        let Some(frame) = self.mailbox.take() else {
            tracing::warn!("wake-up without a frame (mailbox contract violated)");
            return;
        };
        self.last_frame_at = Some(taken_at);
        renderer.upload_frame(&frame);
        match target {
            Some(target) => {
                renderer.draw_and_present(target, self.overlay_visible);
                let presented_at = Instant::now();
                self.metrics
                    .record_shown(frame.sequence, frame.ready_at, taken_at, presented_at);
                self.last_present = Some(presented_at);
            }
            None => self.metrics.record_not_shown(frame.sequence),
        }
    }

    /// Re-presents the current texture (resize, expose, overlay toggle).
    /// Does not touch the mailbox.
    fn redraw(&mut self) {
        if let Some(renderer) = self.renderer.as_mut()
            && let Some(target) = renderer.acquire()
        {
            renderer.draw_and_present(target, self.overlay_visible);
            self.last_present = Some(Instant::now());
        }
    }

    fn tick(&mut self, now: Instant) {
        let snapshot = self.metrics.snapshot(now, self.mailbox.stats());
        self.stats_windows += 1;
        let line = log_line(&snapshot);
        if self.stats_windows.is_multiple_of(LOG_EVERY) {
            tracing::info!("{line}");
        } else {
            tracing::debug!("{line}");
        }
        if let Some(window) = &self.window {
            window.set_title(&format!(
                "FrameRush - in {:.1} fps / shown {:.1} fps",
                snapshot.input_fps, snapshot.shown_fps
            ));
        }
        self.last_snapshot = Some(snapshot);
        self.refresh_overlay();
        let idle = self
            .last_present
            .is_none_or(|t| now.saturating_duration_since(t) > IDLE_REDRAW_AFTER);
        if idle && self.overlay_visible {
            self.redraw();
        }
    }

    fn refresh_overlay(&mut self) {
        let silent_for = self
            .last_frame_at
            .or(self.source_opened_at)
            .map(|since| since.elapsed())
            .filter(|d| *d >= NO_FRAMES_WARNING_AFTER && self.source_error.is_none());
        let lines = overlay_lines(
            self.source.as_ref(),
            self.source_error.as_deref(),
            silent_for,
            self.last_snapshot.as_ref(),
            self.renderer.as_ref(),
        );
        if let Some(renderer) = self.renderer.as_mut() {
            renderer.set_overlay_text(&lines);
        }
    }

    fn toggle_fullscreen(&self) {
        if let Some(window) = &self.window {
            let next = match window.fullscreen() {
                Some(_) => None,
                None => Some(Fullscreen::Borderless(None)),
            };
            tracing::info!(fullscreen = next.is_some(), "toggle fullscreen");
            window.set_fullscreen(next);
        }
    }

    fn shutdown(&mut self) {
        if let Some(mut capture) = self.capture.take() {
            capture.stop();
            let s = self.metrics.snapshot(Instant::now(), self.mailbox.stats());
            tracing::info!(
                runtime_s = format!("{:.1}", self.started.elapsed().as_secs_f64()),
                published = s.total_published,
                shown = s.total_shown,
                dropped_mailbox = s.dropped_mailbox,
                dropped_source = s.dropped_source,
                not_shown = s.not_shown,
                "final statistics"
            );
        }
    }
}

impl ApplicationHandler<CaptureEvent> for App {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.window.is_some() {
            return;
        }
        if let Err(err) = self.start(event_loop) {
            self.fatal = Some(err);
            event_loop.exit();
        }
    }

    fn user_event(&mut self, _event_loop: &ActiveEventLoop, event: CaptureEvent) {
        match event {
            CaptureEvent::FrameReady => self.on_frame_ready(),
            CaptureEvent::Opened(info) => {
                self.source = Some(info);
                self.source_error = None;
                self.source_opened_at = Some(Instant::now());
                self.refresh_overlay();
            }
            CaptureEvent::Failed(err) => {
                tracing::error!(%err, "video source failed");
                self.source_error = Some(err.to_string());
                self.refresh_overlay();
                self.redraw();
            }
        }
    }

    fn window_event(&mut self, event_loop: &ActiveEventLoop, _id: WindowId, event: WindowEvent) {
        match event {
            WindowEvent::CloseRequested => event_loop.exit(),
            WindowEvent::Resized(size) => {
                if let Some(renderer) = self.renderer.as_mut() {
                    renderer.resize(size);
                }
                self.redraw();
            }
            WindowEvent::RedrawRequested => self.redraw(),
            WindowEvent::ModifiersChanged(modifiers) => self.alt_down = modifiers.state().alt_key(),
            WindowEvent::KeyboardInput { event, .. }
                if event.state == ElementState::Pressed && !event.repeat =>
            {
                match &event.logical_key {
                    Key::Named(NamedKey::F11) => self.toggle_fullscreen(),
                    Key::Named(NamedKey::Enter) if self.alt_down => self.toggle_fullscreen(),
                    Key::Named(NamedKey::Escape) => {
                        if let Some(window) = &self.window
                            && window.fullscreen().is_some()
                        {
                            window.set_fullscreen(None);
                        }
                    }
                    Key::Character(c) if c.eq_ignore_ascii_case("o") => {
                        self.overlay_visible = !self.overlay_visible;
                        self.redraw();
                    }
                    _ => {}
                }
            }
            _ => {}
        }
    }

    fn about_to_wait(&mut self, event_loop: &ActiveEventLoop) {
        if event_loop.exiting() {
            return;
        }
        let now = Instant::now();
        let deadline = self.config.exit_after.map(|limit| self.started + limit);
        if deadline.is_some_and(|d| now >= d) {
            tracing::info!("--exit-after reached");
            event_loop.exit();
            return;
        }
        if now >= self.next_tick {
            self.tick(now);
            self.next_tick = now + STATS_INTERVAL;
        }
        let wake = deadline.map_or(self.next_tick, |d| d.min(self.next_tick));
        event_loop.set_control_flow(ControlFlow::WaitUntil(wake));
    }

    fn exiting(&mut self, _event_loop: &ActiveEventLoop) {
        self.shutdown();
    }
}

/// Creates the configured source on the capture thread.
fn source_factory(config: &ViewerConfig) -> SourceFactory {
    match &config.source {
        SourceChoice::Synthetic => {
            let mode = config.mode;
            Box::new(move || Ok(Box::new(SyntheticSource::new(mode)?) as Box<dyn VideoSource>))
        }
        #[cfg(windows)]
        SourceChoice::Device { device, mode } => {
            let (device, mode) = (device.clone(), mode.clone());
            Box::new(move || {
                use crate::capture::media_foundation::{MediaFoundationSource, ReaderOptions};
                let source =
                    MediaFoundationSource::open(&device, &mode, ReaderOptions::from_env())?;
                Ok(Box::new(source) as Box<dyn VideoSource>)
            })
        }
        #[cfg(not(windows))]
        SourceChoice::Device { .. } => Box::new(|| {
            Err(crate::capture::SourceError::Device(
                "capture devices need Media Foundation (Windows)".into(),
            ))
        }),
    }
}

fn ms(d: Option<Duration>) -> String {
    d.map_or_else(
        || "-".into(),
        |d| format!("{:.1}", d.as_secs_f64() * 1000.0),
    )
}

fn avg_max(s: &DurationStats) -> String {
    format!("AVG {} MAX {} MS", ms(s.mean()), ms(s.max()))
}

fn log_line(s: &Snapshot) -> String {
    format!(
        "in {:.1} fps, shown {:.1} fps | drops: mailbox {} source {} not-shown {} | ready->present avg {} max {} ms | present interval min {} max {} ms",
        s.input_fps,
        s.shown_fps,
        s.dropped_mailbox,
        s.dropped_source,
        s.not_shown,
        ms(s.ready_to_present.mean()),
        ms(s.ready_to_present.max()),
        ms(s.present_interval.min()),
        ms(s.present_interval.max()),
    )
}

fn overlay_lines(
    source: Option<&SourceInfo>,
    source_error: Option<&str>,
    silent_for: Option<Duration>,
    snapshot: Option<&Snapshot>,
    renderer: Option<&Renderer>,
) -> Vec<String> {
    let mut lines = vec![match source {
        Some(info) => format!("{}  {}", info.name, info.mode),
        None => "WAITING FOR SOURCE".into(),
    }];
    if let Some(err) = source_error {
        lines.push(format!("SOURCE ERROR: {err}"));
    }
    if let Some(d) = silent_for {
        // Order of likelihood seen so far: security software blocking the
        // camera stream, another app holding the device. The UGREEN 25854
        // sends a "No Signal" picture without HDMI input, so a missing
        // signal does not stop frames on that card.
        lines.push(format!(
            "NO FRAMES FOR {} S - BLOCKED BY SECURITY SOFTWARE (CAMERA PROTECTION)?",
            d.as_secs()
        ));
        lines.push("  OR IN USE BY ANOTHER APP? NO HDMI SIGNAL?".into());
    }
    match snapshot {
        Some(s) => {
            lines.push(format!(
                "IN {:.1} FPS   SHOWN {:.1} FPS",
                s.input_fps, s.shown_fps
            ));
            lines.push(format!(
                "DROPS  MAILBOX {}  SOURCE {}  NOT SHOWN {}",
                s.dropped_mailbox, s.dropped_source, s.not_shown
            ));
            lines.push(format!("READY>TAKE     {}", avg_max(&s.ready_to_take)));
            lines.push(format!("READY>PRESENT  {}", avg_max(&s.ready_to_present)));
            lines.push(format!(
                "PRESENT INTERVAL MIN {} MAX {} MS",
                ms(s.present_interval.min()),
                ms(s.present_interval.max())
            ));
        }
        None => lines.push("MEASURING...".into()),
    }
    if let Some(r) = renderer {
        let info = r.info();
        lines.push(format!(
            "{} {:?} LATENCY {} {:?}  {}",
            info.backend, info.present_mode, info.frame_latency, info.surface_format, info.adapter
        ));
    }
    lines.push("SOFTWARE TIMING ONLY, NOT HDMI-TO-PHOTON LATENCY".into());
    lines.push("F11 FULLSCREEN   ESC LEAVE   O OVERLAY".into());
    lines.into_iter().map(|l| l.to_ascii_uppercase()).collect()
}
