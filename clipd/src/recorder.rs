//! A running capture as one thing to hold on to: started once, asked for
//! clips and recordings, and stopped by dropping it.

use crate::buffer::{self, Buffer};
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
    shared: Arc<Shared>,
    tender: Option<std::thread::JoinHandle<()>>,
}

#[derive(Default)]
struct Shared {
    stop: AtomicBool,
    recording: Mutex<Option<Recording>>,
    /// One save at a time; two at once would fight over the list file.
    saving: Mutex<()>,
}

/// A recording started by hand: its first segment, which the ring spares
/// until the recording is saved, and the folder it goes to.
struct Recording {
    first: PathBuf,
    out_dir: PathBuf,
    since: Instant,
}

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

impl Recorder {
    /// Settles the card, starts the capture and waits for the first segment.
    /// `on_end` hears about it if ffmpeg stops on its own later.
    pub fn start(ffmpeg_bin: &Path, mut s: Settings, on_end: impl FnOnce(String) + Send + 'static) -> Result<Self> {
        s.check()?;
        s.gpu = ffmpeg::pick_gpu(ffmpeg_bin, &s)?;
        let mut buf = Buffer::start(ffmpeg_bin, &s)?;
        buf.wait_until_recording(&s, Duration::from_secs(10))?;
        // After the start, because starting empties the buffer folder.
        s.save_session()?;
        let shared = Arc::new(Shared::default());
        let (audio_device, mic_device) = (buf.audio_device.clone(), buf.mic_device.clone());
        let (tend_s, tend_shared) = (s.clone(), shared.clone());
        let tender =
            std::thread::Builder::new().name("clipd-ring".into()).spawn(move || tend(buf, tend_s, tend_shared, on_end))?;
        Ok(Self { settings: s, ffmpeg: ffmpeg_bin.to_path_buf(), audio_device, mic_device, shared, tender: Some(tender) })
    }

    /// Saves the last `clip_secs` under the game that is in front.
    pub fn save_clip(&self) -> Result<Saved> {
        let out_dir = self.out_dir();
        let _one = lock(&self.shared.saving);
        let done = clip::save(&self.ffmpeg, &self.settings, &crate::config::buffer_dir(), &out_dir)?;
        self.saved_sound();
        Ok(done)
    }

    /// Starts a recording of any length; it begins with the segment being
    /// written now, so at most one segment early.
    pub fn start_recording(&self) -> Result<()> {
        let mut rec = lock(&self.shared.recording);
        if rec.is_some() {
            bail!("Es läuft schon eine Aufnahme");
        }
        let all = buffer::segments(&crate::config::buffer_dir(), &self.settings);
        let Some(first) = all.last() else { bail!("Der Buffer ist noch leer") };
        *rec = Some(Recording { first: first.clone(), out_dir: self.out_dir(), since: Instant::now() });
        Ok(())
    }

    /// Ends the recording started by hand and saves it.
    pub fn stop_recording(&self) -> Result<Saved> {
        let Some(rec) = lock(&self.shared.recording).take() else { bail!("Es läuft keine Aufnahme") };
        let _one = lock(&self.shared.saving);
        let done = clip::save_since(&self.ffmpeg, &self.settings, &crate::config::buffer_dir(), &rec.first, &rec.out_dir)?;
        self.saved_sound();
        Ok(done)
    }

    /// How long the recording started by hand has been running.
    pub fn recording_for(&self) -> Option<Duration> {
        lock(&self.shared.recording).as_ref().map(|r| r.since.elapsed())
    }

    /// Whether ffmpeg is still capturing.
    pub fn is_running(&self) -> bool {
        self.tender.as_ref().is_some_and(|t| !t.is_finished())
    }

    fn out_dir(&self) -> PathBuf {
        clip_dir(&self.settings)
    }

    fn saved_sound(&self) {
        if self.settings.save_sound {
            crate::sys::chime();
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

/// Keeps the ring short and watches ffmpeg until told to stop. Owns the
/// buffer, so returning from here ends the capture.
fn tend(mut buf: Buffer, s: Settings, shared: Arc<Shared>, on_end: impl FnOnce(String)) {
    let keep = s.ring_len();
    let mut last_prune = Instant::now();
    while !shared.stop.load(Ordering::Relaxed) {
        if let Some(status) = buf.exited() {
            on_end(format!("Die Aufnahme ist beendet ({status})"));
            return;
        }
        if last_prune.elapsed() >= Duration::from_millis(500) {
            let spare = lock(&shared.recording).as_ref().map(|r| r.first.clone());
            buffer::prune(&buf.dir, &s, keep, spare.as_deref());
            last_prune = Instant::now();
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}
