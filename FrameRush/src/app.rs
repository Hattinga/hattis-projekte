//! Window, input and the glue between capture, mailbox, renderer and audio.
//!
//! Threads:
//! * **main / event loop** (this file): window events, GPU upload and
//!   present, connection state. Woken by the capture thread through winit's
//!   event-loop proxy.
//! * **capture**: runs the [`VideoSource`] and publishes into the mailbox.
//!   It never waits for the renderer. A new one is started for every
//!   (re)connect; each carries a generation number so events of an old one
//!   cannot disturb the current connection.
//! * **audio**: see [`crate::audio`].

use std::sync::Arc;
use std::time::{Duration, Instant};

use winit::application::ApplicationHandler;
use winit::dpi::{LogicalSize, PhysicalPosition, PhysicalSize};
use winit::event::{ElementState, WindowEvent};
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop, EventLoopProxy};
use winit::keyboard::{Key, NamedKey};
use winit::monitor::MonitorHandle;
use winit::window::{Fullscreen, Window, WindowId};

use crate::audio::{AudioHandle, AudioOptions, AudioState, AudioStatus};
use crate::capture::synthetic::SyntheticSource;
use crate::capture::{
    CaptureEvent, CaptureHandle, DeviceSelector, Frame, Mailbox, ModeSelector, SourceError,
    SourceFactory, SourceInfo, VideoMode, VideoSource, spawn_capture,
};
use crate::cli::{SourceChoice, ViewerConfig};
use crate::error::AppError;
use crate::metrics::{DurationStats, Snapshot, ViewerMetrics};
use crate::platform;
use crate::render::{Renderer, RendererOptions};
use crate::settings::{Settings, WindowGeometry};

/// Statistics window and overlay refresh interval.
const STATS_INTERVAL: Duration = Duration::from_secs(1);
/// Every n-th statistics window is also written to the log at info level.
const LOG_EVERY: u32 = 5;
/// Re-present for overlay updates only if no frame was shown for this long,
/// so overlay refreshes never compete with live frames for a vsync slot.
const IDLE_REDRAW_AFTER: Duration = Duration::from_millis(250);
/// The overlay warns when an opened source delivered nothing for this long.
const NO_FRAMES_WARNING_AFTER: Duration = Duration::from_secs(2);
/// How long a toast (mute, volume, ...) stays visible.
const TOAST_DURATION: Duration = Duration::from_millis(2500);
/// Fullscreen hides the mouse pointer after it rested this long.
const CURSOR_HIDE_AFTER: Duration = Duration::from_secs(2);
/// Retry cadence while the device is not plugged in (cheap: opens nothing).
const NOT_FOUND_RETRY: Duration = Duration::from_secs(2);
/// "Busy" failures in a row after which retrying stops until R is pressed.
/// Each attempt on a blocked device can leave a stuck thread behind.
const MAX_BUSY_FAILURES: u32 = 3;
/// A connection that delivered frames this long resets the retry backoff.
const STABLE_AFTER: Duration = Duration::from_secs(10);
const VOLUME_STEP: u8 = 10;

pub fn run(config: ViewerConfig) -> Result<(), AppError> {
    let mut settings = Settings::load();
    if let Some(overlay) = config.overlay {
        settings.overlay = overlay;
    }
    if let Some(fullscreen) = config.fullscreen {
        settings.fullscreen = fullscreen;
    }
    if let Some(audio) = config.audio {
        settings.audio = audio;
    }
    if let Some(output) = &config.audio_output {
        settings.audio_output.clone_from(output);
    }
    let event_loop = EventLoop::<AppEvent>::with_user_event().build()?;
    let mut app = App::new(config, settings, event_loop.create_proxy());
    event_loop.run_app(&mut app)?;
    match app.fatal.take() {
        Some(err) => Err(err),
        None => Ok(()),
    }
}

/// A capture event tagged with the capture thread that sent it.
#[derive(Debug)]
pub struct AppEvent {
    generation: u64,
    event: CaptureEvent,
}

/// What the viewer tries to show.
#[derive(Debug, Clone)]
enum Target {
    Synthetic(VideoMode),
    Device {
        selector: DeviceSelector,
        mode: ModeSelector,
    },
}

/// Connection state of the current target.
#[derive(Debug)]
enum Link {
    /// Nothing to show (device chooser open, nothing selected).
    Idle,
    /// Capture thread started, device not open yet.
    Connecting,
    /// Device open; `since` = when it opened.
    Live { since: Instant },
    /// Waiting to reconnect.
    Retrying {
        at: Instant,
        error: SourceErrorKind,
        message: String,
    },
    /// Gave up after repeated failures; R tries again.
    Stuck { message: String },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SourceErrorKind {
    NotFound,
    Busy,
    Other,
}

struct App {
    config: ViewerConfig,
    settings: Settings,
    proxy: EventLoopProxy<AppEvent>,
    mailbox: Arc<Mailbox<Frame>>,
    window: Option<Arc<Window>>,
    renderer: Option<Renderer>,

    target: Option<Target>,
    capture: Option<CaptureHandle>,
    /// Stopped capture threads still closing their device.
    retiring: Vec<CaptureHandle>,
    generation: u64,
    link: Link,
    attempts: u32,
    busy_failures: u32,
    source: Option<SourceInfo>,
    last_frame_at: Option<Instant>,

    audio: Option<AudioHandle>,
    /// Video device name the running audio belongs to.
    audio_for: Option<String>,
    last_audio_state: Option<AudioState>,

    /// Device names while the chooser is open.
    chooser: Option<Vec<String>>,
    toast: Option<(Vec<String>, Instant)>,
    /// Last position and size outside fullscreen, for the settings.
    windowed: Option<WindowGeometry>,
    cursor_hidden: bool,
    last_mouse_move: Instant,
    alt_down: bool,

    metrics: ViewerMetrics,
    last_snapshot: Option<Snapshot>,
    stats_windows: u32,
    started: Instant,
    next_tick: Instant,
    last_present: Option<Instant>,
    fatal: Option<AppError>,
}

impl App {
    fn new(config: ViewerConfig, settings: Settings, proxy: EventLoopProxy<AppEvent>) -> Self {
        let now = Instant::now();
        Self {
            config,
            windowed: settings.window,
            settings,
            proxy,
            mailbox: Arc::new(Mailbox::new()),
            window: None,
            renderer: None,
            target: None,
            capture: None,
            retiring: Vec::new(),
            generation: 0,
            link: Link::Idle,
            attempts: 0,
            busy_failures: 0,
            source: None,
            last_frame_at: None,
            audio: None,
            audio_for: None,
            last_audio_state: None,
            chooser: None,
            toast: None,
            cursor_hidden: false,
            last_mouse_move: now,
            alt_down: false,
            metrics: ViewerMetrics::new(now),
            last_snapshot: None,
            stats_windows: 0,
            started: now,
            next_tick: now + STATS_INTERVAL,
            last_present: None,
            fatal: None,
        }
    }

    fn start(&mut self, event_loop: &ActiveEventLoop) -> Result<(), AppError> {
        let mut attributes = Window::default_attributes()
            .with_title("FrameRush")
            .with_inner_size(LogicalSize::new(1280.0, 720.0))
            .with_min_inner_size(LogicalSize::new(320.0, 180.0));
        // Restore the last window position only if it is still on a monitor
        // (monitors may have been rearranged or unplugged).
        let saved_monitor = self
            .settings
            .window
            .and_then(|g| monitor_at(event_loop, g.x, g.y).map(|m| (g, m)));
        if let Some((g, _)) = &saved_monitor {
            attributes = attributes
                .with_position(PhysicalPosition::new(g.x, g.y))
                .with_inner_size(PhysicalSize::new(g.width, g.height));
        }
        attributes = attributes.with_maximized(self.settings.maximized);
        if self.settings.fullscreen {
            let monitor = saved_monitor.map(|(_, m)| m);
            attributes = attributes.with_fullscreen(Some(Fullscreen::Borderless(monitor)));
        }
        let window = Arc::new(event_loop.create_window(attributes)?);
        platform::set_window_icon(&window);
        let renderer = Renderer::new(
            Arc::clone(&window),
            &RendererOptions {
                present_mode: self.config.present_mode,
                frame_latency: self.config.frame_latency,
            },
        )?;
        self.cursor_hidden = window.fullscreen().is_some();
        window.set_cursor_visible(!self.cursor_hidden);
        self.window = Some(window);
        self.renderer = Some(renderer);
        platform::keep_display_awake(true);

        self.target = match &self.config.source {
            SourceChoice::Synthetic => Some(Target::Synthetic(self.config.mode)),
            SourceChoice::Device { device, mode } => Some(Target::Device {
                selector: device.clone(),
                mode: mode.clone(),
            }),
            SourceChoice::Auto { mode } => {
                self.settings.device.clone().map(|name| Target::Device {
                    selector: DeviceSelector::Name(name),
                    mode: mode.clone(),
                })
            }
        };
        if self.target.is_some() {
            self.connect();
        } else {
            self.open_chooser();
        }
        self.started = Instant::now();
        self.metrics = ViewerMetrics::new(self.started);
        self.next_tick = self.started + STATS_INTERVAL;
        self.overlay_changed();
        Ok(())
    }

    /// Starts a capture thread for the current target (replacing any).
    fn connect(&mut self) {
        let Some(target) = self.target.clone() else {
            return;
        };
        self.retire_capture();
        self.generation += 1;
        let generation = self.generation;
        let proxy = self.proxy.clone();
        let notify = move |event| proxy.send_event(AppEvent { generation, event }).is_ok();
        match spawn_capture(source_factory(&target), Arc::clone(&self.mailbox), notify) {
            Ok(handle) => {
                self.capture = Some(handle);
                self.link = Link::Connecting;
            }
            Err(err) => {
                tracing::error!(%err, "cannot start the capture thread");
                self.schedule_retry(
                    SourceErrorKind::Other,
                    format!("cannot start capture: {err}"),
                );
            }
        }
        self.source = None;
        self.last_frame_at = None;
        if let Some(window) = &self.window {
            window.set_title(&format!("FrameRush - {}", target_label(&target)));
        }
        self.overlay_changed();
    }

    fn retire_capture(&mut self) {
        if let Some(handle) = self.capture.take() {
            handle.request_stop();
            self.retiring.push(handle);
        }
    }

    fn schedule_retry(&mut self, kind: SourceErrorKind, message: String) {
        let delay = match kind {
            SourceErrorKind::NotFound => NOT_FOUND_RETRY,
            SourceErrorKind::Busy | SourceErrorKind::Other => {
                self.attempts += 1;
                // 2, 4, 8, 10, 10, ... seconds
                Duration::from_secs((2u64 << self.attempts.min(3).saturating_sub(1)).min(10))
            }
        };
        self.link = Link::Retrying {
            at: Instant::now() + delay,
            error: kind,
            message,
        };
    }

    fn on_source_failed(&mut self, err: SourceError) {
        tracing::error!(%err, "video source failed");
        self.retire_capture();
        self.source = None;
        let message = short(&err.to_string(), 110);
        match err {
            SourceError::NotFound(_) => {
                self.busy_failures = 0;
                self.schedule_retry(SourceErrorKind::NotFound, message);
            }
            SourceError::Busy(_) => {
                self.busy_failures += 1;
                if self.busy_failures >= MAX_BUSY_FAILURES {
                    self.link = Link::Stuck { message };
                } else {
                    self.schedule_retry(SourceErrorKind::Busy, message);
                }
            }
            // Retrying cannot fix a mode the device does not offer.
            SourceError::UnsupportedMode(_) => self.link = Link::Stuck { message },
            SourceError::Device(_) => self.schedule_retry(SourceErrorKind::Other, message),
        }
        self.overlay_changed();
    }

    fn on_source_opened(&mut self, info: SourceInfo) {
        tracing::info!(name = %info.name, mode = %info.mode, "source opened");
        self.link = Link::Live {
            since: Instant::now(),
        };
        self.busy_failures = 0;
        if matches!(self.target, Some(Target::Device { .. })) {
            if self.settings.device.as_deref() != Some(info.name.as_str()) {
                self.settings.device = Some(info.name.clone());
                self.settings.save();
            }
            self.ensure_audio(&info.name);
            if let Some(window) = &self.window {
                window.set_title(&format!("FrameRush - {}", info.name));
            }
        }
        self.show_toast(vec![format!("{}  {}", info.name, info.mode)]);
        self.source = Some(info);
    }

    /// (Re)starts audio monitoring for `device` if enabled and not running.
    fn ensure_audio(&mut self, device: &str) {
        if !self.settings.audio || self.audio_for.as_deref() == Some(device) {
            return;
        }
        self.stop_audio();
        match AudioHandle::start(AudioOptions {
            video_device: device.to_string(),
            output: self.settings.audio_output.clone(),
            volume: self.settings.volume,
            muted: self.settings.muted,
        }) {
            Ok(handle) => {
                self.audio = Some(handle);
                self.audio_for = Some(device.to_string());
            }
            Err(err) => tracing::error!(%err, "cannot start the audio thread"),
        }
    }

    fn stop_audio(&mut self) {
        // Dropping asks the thread to stop without blocking the window.
        self.audio = None;
        self.audio_for = None;
        self.last_audio_state = None;
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
        // No swapchain image (e.g. minimized): drop the frame without
        // uploading it; nothing would show it.
        match target {
            Some(target) => {
                renderer.upload_frame(&frame);
                renderer.draw_and_present(target, true);
                let presented_at = Instant::now();
                self.metrics
                    .record_shown(frame.sequence, frame.ready_at, taken_at, presented_at);
                self.last_present = Some(presented_at);
            }
            None => self.metrics.record_not_shown(frame.sequence),
        }
    }

    /// Re-presents the current texture (resize, expose, overlay change).
    /// Does not touch the mailbox.
    fn redraw(&mut self) {
        if let Some(renderer) = self.renderer.as_mut()
            && let Some(target) = renderer.acquire()
        {
            renderer.draw_and_present(target, true);
            self.last_present = Some(Instant::now());
        }
    }

    /// Rebuilds the overlay; presents it at once unless live frames will.
    fn overlay_changed(&mut self) {
        self.refresh_overlay();
        let idle = self
            .last_present
            .is_none_or(|t| t.elapsed() > IDLE_REDRAW_AFTER);
        if idle {
            self.redraw();
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
        self.last_snapshot = Some(snapshot);

        self.retiring.retain_mut(|handle| !handle.try_join());
        if let Link::Live { since } = self.link
            && since.elapsed() >= STABLE_AFTER
            && self
                .last_frame_at
                .is_some_and(|t| t.elapsed() < STABLE_AFTER)
        {
            self.attempts = 0;
        }
        if self.toast.as_ref().is_some_and(|(_, until)| now >= *until) {
            self.toast = None;
        }
        self.watch_audio();
        if self.cursor_hidden != self.should_hide_cursor(now) {
            self.cursor_hidden = !self.cursor_hidden;
            if let Some(window) = &self.window {
                window.set_cursor_visible(!self.cursor_hidden);
            }
        }
        self.overlay_changed();
    }

    /// Toasts audio problems once, when the state changes.
    fn watch_audio(&mut self) {
        let Some(status) = self.audio.as_ref().map(AudioHandle::status) else {
            return;
        };
        if self.last_audio_state.as_ref() == Some(&status.state) {
            return;
        }
        match &status.state {
            AudioState::NoInput { wanted } => self.show_toast(vec![format!(
                "NO AUDIO INPUT FOUND FOR {wanted} - VIDEO ONLY"
            )]),
            AudioState::Playing { output, .. } => {
                self.show_toast(vec![format!("AUDIO TO {output}")]);
            }
            AudioState::Retrying(_) | AudioState::Starting => {}
        }
        self.last_audio_state = Some(status.state);
    }

    fn should_hide_cursor(&self, now: Instant) -> bool {
        let fullscreen = self
            .window
            .as_ref()
            .is_some_and(|w| w.fullscreen().is_some());
        fullscreen && now.saturating_duration_since(self.last_mouse_move) >= CURSOR_HIDE_AFTER
    }

    fn refresh_overlay(&mut self) {
        let lines = self.overlay_lines();
        if let Some(renderer) = self.renderer.as_mut() {
            renderer.set_overlay_text(&lines);
        }
    }

    fn overlay_lines(&self) -> Vec<String> {
        let mut lines = Vec::new();
        if let Some(names) = &self.chooser {
            lines.extend(chooser_lines(names, self.target.is_some()));
            lines.push(String::new());
        }
        lines.extend(self.status_lines());
        if let Some((toast, _)) = &self.toast {
            lines.extend(toast.iter().cloned());
        }
        if self.settings.overlay {
            if !lines.is_empty() {
                lines.push(String::new());
            }
            lines.extend(stats_lines(
                self.source.as_ref(),
                self.last_snapshot.as_ref(),
                self.renderer.as_ref(),
                audio_line(
                    self.audio.as_ref().map(AudioHandle::status).as_ref(),
                    &self.settings,
                    matches!(self.target, Some(Target::Device { .. })),
                ),
            ));
        }
        lines
            .into_iter()
            .map(|l| short(&l, 120).to_ascii_uppercase())
            .collect()
    }

    /// Connection problems; always visible, also with the overlay off.
    fn status_lines(&self) -> Vec<String> {
        let name = self.target.as_ref().map_or_else(String::new, target_label);
        match &self.link {
            Link::Idle => Vec::new(),
            Link::Connecting => vec![format!("CONNECTING TO {name} ...")],
            Link::Retrying {
                error: SourceErrorKind::NotFound,
                ..
            } => vec![
                format!("WAITING FOR {name} - NOT CONNECTED"),
                "PLUG IN THE CAPTURE CARD, OR PRESS D TO CHOOSE ANOTHER DEVICE".into(),
            ],
            Link::Retrying { at, message, .. } => vec![
                format!(
                    "RECONNECTING IN {} S  (R: NOW)",
                    at.saturating_duration_since(Instant::now()).as_secs() + 1
                ),
                message.clone(),
            ],
            Link::Stuck { message } => vec![
                message.clone(),
                "CLOSE OTHER APPS THAT USE THE DEVICE (CAMERA APP, OBS, DISCORD CAMERA), THEN PRESS R.".into(),
                "IF THAT DOES NOT HELP: REPLUG THE DEVICE OR RESTART WINDOWS.".into(),
            ],
            Link::Live { since } => {
                let silent = self
                    .last_frame_at
                    .unwrap_or(*since)
                    .elapsed();
                if silent >= NO_FRAMES_WARNING_AFTER {
                    // Seen so far: security software blocking the camera
                    // stream. The UGREEN 25854 sends a "No Signal" picture
                    // without HDMI input, so a missing signal does not stop
                    // frames on that card.
                    vec![
                        format!("NO PICTURE FROM {name} FOR {} S", silent.as_secs()),
                        "BLOCKED BY SECURITY SOFTWARE (CAMERA PROTECTION)? IN USE BY ANOTHER APP?".into(),
                    ]
                } else {
                    Vec::new()
                }
            }
        }
    }

    fn show_toast(&mut self, lines: Vec<String>) {
        self.toast = Some((lines, Instant::now() + TOAST_DURATION));
        self.overlay_changed();
    }

    fn open_chooser(&mut self) {
        #[cfg(windows)]
        let names = crate::capture::media_foundation::list_device_names().unwrap_or_else(|err| {
            tracing::error!(%err, "cannot list capture devices");
            Vec::new()
        });
        #[cfg(not(windows))]
        let names = Vec::new();
        self.chooser = Some(names);
        self.overlay_changed();
    }

    fn choose(&mut self, index: usize) {
        let Some(name) = self
            .chooser
            .as_ref()
            .and_then(|names| names.get(index).cloned())
        else {
            return;
        };
        self.chooser = None;
        let mode = match &self.config.source {
            SourceChoice::Auto { mode } | SourceChoice::Device { mode, .. } => mode.clone(),
            SourceChoice::Synthetic => ModeSelector::Best,
        };
        self.target = Some(Target::Device {
            selector: DeviceSelector::Name(name.clone()),
            mode,
        });
        if self.audio_for.as_deref() != Some(name.as_str()) {
            self.stop_audio();
        }
        self.attempts = 0;
        self.busy_failures = 0;
        self.connect();
    }

    fn toggle_fullscreen(&mut self) {
        let Some(window) = &self.window else {
            return;
        };
        let next = match window.fullscreen() {
            Some(_) => None,
            None => Some(Fullscreen::Borderless(None)),
        };
        tracing::info!(fullscreen = next.is_some(), "toggle fullscreen");
        self.settings.fullscreen = next.is_some();
        self.cursor_hidden = next.is_some();
        window.set_cursor_visible(!self.cursor_hidden);
        window.set_fullscreen(next);
    }

    fn set_volume(&mut self, volume: u8) {
        self.settings.volume = volume.min(100);
        self.settings.muted = false;
        if let Some(audio) = &self.audio {
            audio.set_muted(false);
            audio.set_volume(self.settings.volume);
        }
        self.show_toast(vec![format!("VOLUME {} %", self.settings.volume)]);
    }

    fn toggle_mute(&mut self) {
        self.settings.muted = !self.settings.muted;
        if let Some(audio) = &self.audio {
            audio.set_muted(self.settings.muted);
        }
        let text = if self.settings.muted {
            "MUTED (M: SOUND ON)".to_string()
        } else {
            format!("SOUND ON, VOLUME {} %", self.settings.volume)
        };
        self.show_toast(vec![text]);
    }

    fn on_key(&mut self, key: &Key, repeat: bool) {
        let digit = match key {
            Key::Character(c) => c.chars().next().and_then(|c| c.to_digit(10)),
            _ => None,
        };
        if let (Some(d), true) = (digit, self.chooser.is_some())
            && d >= 1
            && !repeat
        {
            self.choose(d as usize - 1);
            return;
        }
        let character = |s: &str| matches!(key, Key::Character(c) if c.eq_ignore_ascii_case(s));
        match key {
            Key::Named(NamedKey::ArrowUp) => {
                self.set_volume(self.settings.volume.saturating_add(VOLUME_STEP));
            }
            Key::Named(NamedKey::ArrowDown) => {
                self.set_volume(self.settings.volume.saturating_sub(VOLUME_STEP));
            }
            _ if character("+") || character("=") => {
                self.set_volume(self.settings.volume.saturating_add(VOLUME_STEP));
            }
            _ if character("-") => {
                self.set_volume(self.settings.volume.saturating_sub(VOLUME_STEP));
            }
            _ if repeat => {}
            Key::Named(NamedKey::F11) => self.toggle_fullscreen(),
            Key::Named(NamedKey::Enter) if self.alt_down => self.toggle_fullscreen(),
            Key::Named(NamedKey::Escape) => {
                if self.chooser.is_some() && self.target.is_some() {
                    self.chooser = None;
                    self.overlay_changed();
                } else if self
                    .window
                    .as_ref()
                    .is_some_and(|w| w.fullscreen().is_some())
                {
                    self.toggle_fullscreen();
                }
            }
            Key::Named(NamedKey::F1) => self.show_toast(help_lines()),
            _ if character("m") => self.toggle_mute(),
            _ if character("o") => {
                self.settings.overlay = !self.settings.overlay;
                self.overlay_changed();
            }
            _ if character("d") => self.open_chooser(),
            _ if character("r") => {
                if matches!(self.link, Link::Retrying { .. } | Link::Stuck { .. }) {
                    self.busy_failures = 0;
                    self.connect();
                }
            }
            _ => {}
        }
    }

    fn shutdown(&mut self) {
        if let Some(window) = &self.window
            && window.fullscreen().is_none()
        {
            // Maximized: keep the normal geometry for un-maximizing later.
            self.settings.maximized = window.is_maximized();
            if !self.settings.maximized
                && let (Ok(pos), size) = (window.outer_position(), window.inner_size())
            {
                self.windowed = Some(WindowGeometry {
                    x: pos.x,
                    y: pos.y,
                    width: size.width,
                    height: size.height,
                });
            }
        }
        self.settings.window = self.windowed;
        self.settings.save();

        if let Some(mut audio) = self.audio.take() {
            audio.stop();
        }
        if let Some(mut capture) = self.capture.take() {
            capture.stop();
        }
        for handle in &self.retiring {
            handle.request_stop();
        }
        platform::keep_display_awake(false);
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

    /// When the event loop must wake up next.
    fn next_wake(&self) -> Instant {
        let mut wake = self.next_tick;
        if let Link::Retrying { at, .. } = self.link {
            wake = wake.min(at);
        }
        if let Some((_, until)) = &self.toast {
            wake = wake.min(*until);
        }
        wake
    }
}

impl ApplicationHandler<AppEvent> for App {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.window.is_some() {
            return;
        }
        if let Err(err) = self.start(event_loop) {
            self.fatal = Some(err);
            event_loop.exit();
        }
    }

    fn user_event(&mut self, _event_loop: &ActiveEventLoop, event: AppEvent) {
        let current = event.generation == self.generation;
        match event.event {
            // Always take: the mailbox contract needs one take per wake, even
            // if an old capture thread sent it.
            CaptureEvent::FrameReady => self.on_frame_ready(),
            CaptureEvent::Opened(info) if current => self.on_source_opened(info),
            CaptureEvent::Failed(err) if current => self.on_source_failed(err),
            CaptureEvent::Opened(_) | CaptureEvent::Failed(_) => {
                tracing::debug!("event from a replaced capture thread ignored");
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
                if let Some(window) = &self.window
                    && window.fullscreen().is_none()
                    && !window.is_maximized()
                    && size.width > 0
                    && size.height > 0
                    && let Some(g) = &mut self.windowed
                {
                    g.width = size.width;
                    g.height = size.height;
                }
                self.redraw();
            }
            WindowEvent::Moved(pos) => {
                if let Some(window) = &self.window
                    && window.fullscreen().is_none()
                    && !window.is_maximized()
                {
                    let size = window.inner_size();
                    self.windowed = Some(WindowGeometry {
                        x: pos.x,
                        y: pos.y,
                        width: size.width,
                        height: size.height,
                    });
                }
            }
            WindowEvent::CursorMoved { .. } => {
                self.last_mouse_move = Instant::now();
                if self.cursor_hidden {
                    self.cursor_hidden = false;
                    if let Some(window) = &self.window {
                        window.set_cursor_visible(true);
                    }
                }
            }
            WindowEvent::RedrawRequested => self.redraw(),
            WindowEvent::ModifiersChanged(modifiers) => self.alt_down = modifiers.state().alt_key(),
            WindowEvent::KeyboardInput { event, .. } if event.state == ElementState::Pressed => {
                self.on_key(&event.logical_key, event.repeat);
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
        if let Link::Retrying { at, .. } = self.link
            && now >= at
        {
            self.connect();
        }
        if now >= self.next_tick {
            self.tick(now);
            self.next_tick = now + STATS_INTERVAL;
        } else if self.toast.as_ref().is_some_and(|(_, until)| now >= *until) {
            self.toast = None;
            self.overlay_changed();
        }
        let wake = deadline.map_or(self.next_wake(), |d| d.min(self.next_wake()));
        event_loop.set_control_flow(ControlFlow::WaitUntil(wake));
    }

    fn exiting(&mut self, _event_loop: &ActiveEventLoop) {
        self.shutdown();
    }
}

/// Creates the target's source on the capture thread.
fn source_factory(target: &Target) -> SourceFactory {
    match target {
        Target::Synthetic(mode) => {
            let mode = *mode;
            Box::new(move || Ok(Box::new(SyntheticSource::new(mode)?) as Box<dyn VideoSource>))
        }
        #[cfg(windows)]
        Target::Device { selector, mode } => {
            let (selector, mode) = (selector.clone(), mode.clone());
            Box::new(move || {
                use crate::capture::media_foundation::{MediaFoundationSource, ReaderOptions};
                let source =
                    MediaFoundationSource::open(&selector, &mode, ReaderOptions::from_env())?;
                Ok(Box::new(source) as Box<dyn VideoSource>)
            })
        }
        #[cfg(not(windows))]
        Target::Device { .. } => Box::new(|| {
            Err(SourceError::Device(
                "capture devices need Media Foundation (Windows)".into(),
            ))
        }),
    }
}

fn target_label(target: &Target) -> String {
    match target {
        Target::Synthetic(_) => "TEST PATTERN".into(),
        Target::Device {
            selector: DeviceSelector::Name(name),
            ..
        } => name.clone(),
        Target::Device {
            selector: DeviceSelector::Index(i),
            ..
        } => format!("DEVICE #{i}"),
    }
}

/// The monitor that contains the point, if any.
fn monitor_at(event_loop: &ActiveEventLoop, x: i32, y: i32) -> Option<MonitorHandle> {
    // Test a point a little inside the window's top-left corner.
    let (px, py) = (i64::from(x) + 50, i64::from(y) + 20);
    event_loop.available_monitors().find(|m| {
        let pos = m.position();
        let size = m.size();
        let (mx, my) = (i64::from(pos.x), i64::from(pos.y));
        px >= mx && py >= my && px < mx + i64::from(size.width) && py < my + i64::from(size.height)
    })
}

/// Cuts `text` to at most `max` characters, marking the cut.
fn short(text: &str, max: usize) -> String {
    if text.chars().count() <= max {
        text.to_string()
    } else {
        let mut cut: String = text.chars().take(max.saturating_sub(3)).collect();
        cut.push_str("...");
        cut
    }
}

fn chooser_lines(names: &[String], can_cancel: bool) -> Vec<String> {
    let mut lines = vec![if names.is_empty() {
        "NO CAPTURE DEVICE FOUND - PLUG IN THE CARD AND PRESS D".to_string()
    } else {
        "CHOOSE THE CAPTURE DEVICE: PRESS ITS NUMBER".to_string()
    }];
    lines.extend(
        names
            .iter()
            .take(9)
            .enumerate()
            .map(|(i, name)| format!("  {}  {name}", i + 1)),
    );
    if can_cancel {
        lines.push("ESC: KEEP THE CURRENT DEVICE".into());
    }
    lines
}

fn help_lines() -> Vec<String> {
    vec![
        "F11 / ALT+ENTER  FULLSCREEN (ESC LEAVES)".into(),
        "M  MUTE     + / -  VOLUME".into(),
        "O  STATISTICS OVERLAY".into(),
        "D  CHOOSE DEVICE     R  RECONNECT NOW".into(),
    ]
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

fn stats_lines(
    source: Option<&SourceInfo>,
    snapshot: Option<&Snapshot>,
    renderer: Option<&Renderer>,
    audio: String,
) -> Vec<String> {
    let mut lines = vec![match source {
        Some(info) => format!("{}  {}", info.name, info.mode),
        None => "NO SOURCE".into(),
    }];
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
    lines.push(audio);
    if let Some(r) = renderer {
        let info = r.info();
        lines.push(format!(
            "{} {:?} LATENCY {} {:?}  {}",
            info.backend, info.present_mode, info.frame_latency, info.surface_format, info.adapter
        ));
    }
    lines.push("SOFTWARE TIMING ONLY, NOT HDMI-TO-PHOTON LATENCY".into());
    lines.push("F1 KEYS   F11 FULLSCREEN   M MUTE   +/- VOLUME   O OVERLAY".into());
    lines
}

fn audio_line(audio: Option<&AudioStatus>, settings: &Settings, device: bool) -> String {
    if !device {
        return "AUDIO: NONE FOR THE TEST PATTERN".into();
    }
    let volume = if settings.muted {
        "MUTED".to_string()
    } else {
        format!("VOL {} %", settings.volume)
    };
    let Some(status) = audio else {
        return if settings.audio {
            "AUDIO: STARTS WITH THE DEVICE".into()
        } else {
            "AUDIO: OFF (--audio TURNS IT ON)".into()
        };
    };
    let s = status.stats;
    match &status.state {
        AudioState::Starting => format!("AUDIO: STARTING  {volume}"),
        AudioState::NoInput { wanted } => format!("AUDIO: NO INPUT FOR {wanted}"),
        AudioState::Retrying(err) => format!("AUDIO: RETRYING - {err}"),
        AudioState::Playing {
            output,
            sample_rate,
            ..
        } => format!(
            "AUDIO > {output}  {sample_rate} HZ  BUF {:.0} MS  UNDERRUNS {}  DRIFT -{} +{}  {volume}",
            status.buffer_ms, s.underruns, s.dropped, s.inserted
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn long_texts_are_cut() {
        assert_eq!(short("abc", 5), "abc");
        assert_eq!(short("abcdefgh", 6), "abc...");
    }

    #[test]
    fn chooser_lists_up_to_nine_devices() {
        let names: Vec<String> = (1..=12).map(|i| format!("Cam {i}")).collect();
        let lines = chooser_lines(&names, true);
        assert!(lines[1].contains("1  Cam 1"));
        assert!(lines[9].contains("9  Cam 9"));
        assert!(lines.last().unwrap().contains("ESC"));
        assert_eq!(lines.len(), 11);
        assert!(chooser_lines(&[], false)[0].contains("NO CAPTURE DEVICE"));
    }
}
