//! Top-level errors with messages meant for the user.

use std::fmt;

use crate::capture::SourceError;
use crate::render::RenderError;

#[derive(Debug)]
pub enum AppError {
    /// Invalid command line.
    Usage(String),
    /// The video source could not be opened (`--probe`; the viewer shows
    /// source errors in its overlay instead).
    Source(SourceError),
    EventLoop(winit::error::EventLoopError),
    Window(winit::error::OsError),
    Render(RenderError),
    /// Device enumeration failed.
    DeviceProbe(String),
}

impl fmt::Display for AppError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Usage(msg) => write!(f, "{msg}"),
            Self::Source(err) => write!(f, "{err}"),
            Self::EventLoop(err) => write!(f, "window system error: {err}"),
            Self::Window(err) => write!(f, "cannot create the window: {err}"),
            Self::Render(err) => write!(f, "GPU initialisation failed: {err}"),
            Self::DeviceProbe(msg) => write!(f, "device enumeration failed: {msg}"),
        }
    }
}

impl std::error::Error for AppError {}

impl From<winit::error::EventLoopError> for AppError {
    fn from(err: winit::error::EventLoopError) -> Self {
        Self::EventLoop(err)
    }
}

impl From<winit::error::OsError> for AppError {
    fn from(err: winit::error::OsError) -> Self {
        Self::Window(err)
    }
}

impl From<RenderError> for AppError {
    fn from(err: RenderError) -> Self {
        Self::Render(err)
    }
}
