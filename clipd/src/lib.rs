//! clipd records the desktop into a rolling buffer on the graphics card, so a
//! hotkey can still save the half minute that has just gone by.
//!
//! The chain is `ddagrab` (Desktop Duplication, frames stay in graphics memory)
//! into `nvenc`, or through `vpp_amf` into AMF on an AMD card, written as
//! short segments. A clip stitches the newest segments
//! together by copying the streams, which needs no second encode.

pub mod audio;
pub mod buffer;
pub mod clip;
pub mod config;
pub mod control;
pub mod ffmpeg;
pub mod game;
pub mod hotkey;
pub mod library;
pub mod overlay;
pub mod recorder;
pub mod sys;
