//! A running capture as one thing to hold on to: started once, asked for
//! clips and recordings, and stopped by dropping it.

use crate::buffer::{Buffer, Ring};
use crate::clip::{self, Saved};
use crate::config::Settings;
use crate::{ffmpeg, game};
use anyhow::{Result, bail};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant};

pub struct Recorder {
    /// What the capture runs with; `gpu` is always settled here.
    pub settings: Settings,
    pub ffmpeg: PathBuf,
    /// The playback device on the sound track, if there is sound.
    pub audio_device: Option<String>,
    /// The microphone on the second track, if there is one.
    pub mic_device: Option<String>,
    ring: Arc<Ring>,
    shared: Arc<Shared>,
    tender: Option<std::thread::JoinHandle<()>>,
}

#[derive(Default)]
struct Shared {
    stop: AtomicBool,
    /// Where a recording started by hand goes, and since when it runs.
    recording: Mutex<Option<(PathBuf, Instant)>>,
}

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

impl Recorder {
    /// Settles the card, starts the capture and waits for the first keyframe.
    /// `on_end` hears about it if ffmpeg stops on its own later.
    pub fn start(ffmpeg_bin: &Path, mut s: Settings, on_end: impl FnOnce(String) + Send + 'static) -> Result<Self> {
        s.check()?;
        s.gpu = ffmpeg::pick_gpu(ffmpeg_bin, &s)?;
        let mut buf = Buffer::start(ffmpeg_bin, &s)?;
        buf.wait_until_recording(Duration::from_secs(10))?;
        let shared = Arc::new(Shared::default());
        let (audio_device, mic_device, ring) = (buf.audio_device.clone(), buf.mic_device.clone(), buf.ring.clone());
        let tend_shared = shared.clone();
        let tender = std::thread::Builder::new().name("clipd-watch".into()).spawn(move || {
            while !tend_shared.stop.load(Ordering::Relaxed) {
                if let Some(status) = buf.exited() {
                    std::thread::sleep(Duration::from_millis(100));
                    on_end(format!("Die Aufnahme ist beendet ({status}){}", buf.last_words()));
                    return;
                }
                std::thread::sleep(Duration::from_millis(100));
            }
            // Dropping the buffer here ends ffmpeg.
        })?;
        Ok(Self {
            settings: s,
            ffmpeg: ffmpeg_bin.to_path_buf(),
            audio_device,
            mic_device,
            ring,
            shared,
            tender: Some(tender),
        })
    }

    /// Saves the last `clip_secs` under the game that is in front.
    pub fn save_clip(&self) -> Result<Saved> {
        self.save_last(self.settings.clip_secs)
    }

    /// Saves the last `secs` under the game that is in front.
    pub fn save_last(&self, secs: u32) -> Result<Saved> {
        let out_dir = clip_dir(&self.settings);
        // The sound of the last moment is still on its way through the pipe
        // and the AAC encoder when the key is pressed; a short wait lets it
        // arrive, at the price of a little picture after the press.
        std::thread::sleep(Duration::from_millis(300));
        let ts = self.ring.last(self.settings.clip_len(secs));
        let done = clip::save(&self.ffmpeg, &ts, &out_dir)?;
        self.saved("Clip gespeichert", &done);
        Ok(done)
    }

    /// Starts a recording of any length. It begins with the keyframe interval
    /// being written now, so at most `segment_secs` early, and it keeps going
    /// into a file for as long as it runs.
    pub fn start_recording(&self) -> Result<()> {
        let mut rec = lock(&self.shared.recording);
        if rec.is_some() {
            bail!("Es läuft schon eine Aufnahme");
        }
        let file = crate::config::buffer_dir().join(format!("aufnahme-{}.ts", std::process::id()));
        self.ring.start_recording(&file)?;
        *rec = Some((clip_dir(&self.settings), Instant::now()));
        if self.settings.overlay {
            let how = crate::hotkey::display(&self.settings.record_hotkey);
            crate::overlay::flash(
                "Aufnahme läuft",
                &if how.is_empty() { String::new() } else { format!("{how} beendet sie") },
            );
        }
        Ok(())
    }

    /// Ends the recording started by hand and saves it.
    pub fn stop_recording(&self) -> Result<Saved> {
        let Some((out_dir, _)) = lock(&self.shared.recording).take() else { bail!("Es läuft keine Aufnahme") };
        let file = self.ring.stop_recording()?;
        let done = clip::save_file(&self.ffmpeg, &file, &out_dir)?;
        self.saved("Aufnahme gespeichert", &done);
        Ok(done)
    }

    /// Starts a recording, or ends and saves the one running; `None` means
    /// one has just started.
    pub fn toggle_recording(&self) -> Result<Option<Saved>> {
        if self.recording_for().is_none() { self.start_recording().map(|_| None) } else { self.stop_recording().map(Some) }
    }

    /// How long the recording started by hand has been running.
    pub fn recording_for(&self) -> Option<Duration> {
        lock(&self.shared.recording).as_ref().map(|(_, since)| since.elapsed())
    }

    /// Memory the ring takes up right now.
    pub fn buffered_bytes(&self) -> usize {
        self.ring.bytes()
    }

    /// Whether ffmpeg is still capturing.
    pub fn is_running(&self) -> bool {
        self.tender.as_ref().is_some_and(|t| !t.is_finished())
    }

    /// The signs that a save worked, since a game in front hides every other.
    fn saved(&self, what: &str, done: &Saved) {
        if self.settings.save_sound {
            crate::sys::chime();
        }
        if self.settings.overlay {
            let game = done.path.parent().filter(|_| self.settings.game_folders).and_then(|p| p.file_name());
            let length = done.secs.map(|s| format!("{}:{:02}", s as u64 / 60, s as u64 % 60));
            let detail: Vec<String> =
                [game.map(|g| g.to_string_lossy().into_owned()), length].into_iter().flatten().collect();
            crate::overlay::flash(what, &detail.join(" · "));
        }
    }
}

impl Drop for Recorder {
    fn drop(&mut self) {
        self.shared.stop.store(true, Ordering::Relaxed);
        if let Some(t) = self.tender.take() {
            let _ = t.join();
        }
    }
}

/// `clips/<Spiel>` for the window in front, or plain `clips`.
pub fn clip_dir(s: &Settings) -> PathBuf {
    let clips = s.clips_dir();
    if s.game_folders { clips.join(game::folder_name(&game::game_name(&game::foreground()))) } else { clips }
}
