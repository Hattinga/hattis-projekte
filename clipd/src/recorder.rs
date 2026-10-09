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
    shared: Arc<Shared>,
    tender: Option<std::thread::JoinHandle<()>>,
}

struct Shared {
    stop: AtomicBool,
    /// The ring of the capture running now; following a game starts a new one.
    ring: Mutex<Arc<Ring>>,
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
        let buf = start_buffer(ffmpeg_bin, &s)?;
        let shared = Arc::new(Shared {
            stop: AtomicBool::new(false),
            ring: Mutex::new(buf.ring.clone()),
            recording: Mutex::new(None),
        });
        let (audio_device, mic_device) = (buf.audio_device.clone(), buf.mic_device.clone());
        let (tend_shared, tend_s, tend_bin) = (shared.clone(), s.clone(), ffmpeg_bin.to_path_buf());
        let tender = std::thread::Builder::new()
            .name("clipd-watch".into())
            .spawn(move || tend(buf, tend_s, &tend_bin, &tend_shared, on_end))?;
        Ok(Self { settings: s, ffmpeg: ffmpeg_bin.to_path_buf(), audio_device, mic_device, shared, tender: Some(tender) })
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
        let ts = self.ring().last(self.settings.clip_len(secs));
        let done = clip::save(&self.ffmpeg, ts, &out_dir)?;
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
        self.ring().start_recording(&file)?;
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
        let file = self.ring().stop_recording()?;
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
        self.ring().bytes()
    }

    fn ring(&self) -> Arc<Ring> {
        lock(&self.shared.ring).clone()
    }

    /// Whether ffmpeg is still capturing.
    pub fn is_running(&self) -> bool {
        self.tender.as_ref().is_some_and(|t| !t.is_finished())
    }

    fn saved(&self, what: &str, done: &Saved) {
        announce(&self.settings, what, done);
    }
}

/// The signs that a save worked, since a game in front hides every other.
/// Also the moment to tidy up, now that there is one clip more.
fn announce(s: &Settings, what: &str, done: &Saved) {
    crate::library::tidy(&s.clips_dir(), s.keep_days, s.max_gb);
    if s.save_sound {
        crate::sys::chime();
    }
    if s.overlay {
        let game = done.path.parent().filter(|_| s.game_folders).and_then(|p| p.file_name());
        let length = done.secs.map(|s| format!("{}:{:02}", s as u64 / 60, s as u64 % 60));
        let detail: Vec<String> = [game.map(|g| g.to_string_lossy().into_owned()), length].into_iter().flatten().collect();
        crate::overlay::flash(what, &detail.join(" · "));
    }
}

/// Ends and saves a recording that `ring` is writing, because the capture
/// behind it is about to go away: a new ring, a new ffmpeg or none at all.
/// The next capture cannot carry it on — its stream starts over and may
/// even have another size.
/// `recording` is what was taken out of the shared state, so no lock is held
/// while ffmpeg writes the file.
fn rescue(ffmpeg_bin: &Path, s: &Settings, ring: &Ring, recording: Option<(PathBuf, Instant)>) {
    let Some((out_dir, _)) = recording else { return };
    match ring.stop_recording().and_then(|file| clip::save_file(ffmpeg_bin, &file, &out_dir)) {
        Ok(done) => announce(s, "Aufnahme gespeichert", &done),
        Err(e) => eprintln!("clipd: die Aufnahme ließ sich nicht retten — {e:#}"),
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

/// [`tend_capture`], and whatever recording is still running saved at the
/// end, however the capture ended.
fn tend(buf: Buffer, s: Settings, ffmpeg_bin: &Path, shared: &Shared, on_end: impl FnOnce(String)) {
    tend_capture(buf, s.clone(), ffmpeg_bin, shared, on_end);
    let ring = lock(&shared.ring).clone();
    let recording = lock(&shared.recording).take();
    rescue(ffmpeg_bin, &s, &ring, recording);
}

/// Watches ffmpeg until told to stop, and in game mode follows the game in
/// front: a fullscreen game gets a capture of its own window, everything
/// else the screen. Owns the buffer, so returning from here ends the capture.
fn tend_capture(mut buf: Buffer, mut s: Settings, ffmpeg_bin: &Path, shared: &Shared, on_end: impl FnOnce(String)) {
    let mut last_look = Instant::now();
    let mut refused = None;
    while !shared.stop.load(Ordering::Relaxed) {
        if let Some(status) = buf.exited() {
            // A game window that closes ends its capture; that is the cue to
            // go back to the screen, not a failure.
            if s.window.is_none() {
                std::thread::sleep(Duration::from_millis(100));
                on_end(format!("Die Aufnahme ist beendet ({status}){}", buf.last_words()));
                return;
            }
            s.window = None;
            match restart(ffmpeg_bin, &s, shared) {
                Some(b) => buf = b,
                None => return on_end("Die Aufnahme ließ sich nicht wieder starten".into()),
            }
        }
        let recording = lock(&shared.recording).is_some();
        if s.capture == crate::config::Capture::Game && !recording && last_look.elapsed() >= Duration::from_secs(1) {
            last_look = Instant::now();
            // Once a second: only the window and whether it covers the
            // screen, not the name from the program's version resource.
            let wanted = game::game_window(&game::foreground_window());
            if wanted != s.window && wanted != refused {
                let next = Settings { window: wanted, ..s.clone() };
                match restart(ffmpeg_bin, &next, shared) {
                    Some(b) => {
                        buf = b;
                        s = next;
                    }
                    // This window will not be captured on its own; what runs
                    // now carries on, and it is not asked again every second.
                    None => refused = wanted,
                }
            }
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    // Dropping the buffer here ends ffmpeg.
}

/// A fresh capture with `s`, its ring put in place of the old one. A
/// recording on the old ring is saved rather than lost; the recording lock
/// is held over the swap, so none can start on the old ring meanwhile.
fn restart(ffmpeg_bin: &Path, s: &Settings, shared: &Shared) -> Option<Buffer> {
    let buf = start_buffer(ffmpeg_bin, s).ok()?;
    let (old, recording) = {
        let mut recording = lock(&shared.recording);
        (std::mem::replace(&mut *lock(&shared.ring), buf.ring.clone()), recording.take())
    };
    rescue(ffmpeg_bin, s, &old, recording);
    Some(buf)
}

/// Starts a capture and waits for its first keyframe. If ffmpeg gives up
/// with sound — the device opened fine, but its format cannot be encoded —
/// it tries once more without: a clip without sound still beats none.
fn start_buffer(ffmpeg_bin: &Path, s: &Settings) -> Result<Buffer> {
    let mut buf = Buffer::start(ffmpeg_bin, s)?;
    match buf.wait_until_recording(Duration::from_secs(10)) {
        Ok(()) => Ok(buf),
        Err(e) if buf.audio_device.is_some() => {
            eprintln!("clipd: Aufnahme ohne Ton — mit Ton scheitert sie: {e:#}");
            drop(buf);
            let mut quiet = Buffer::start(ffmpeg_bin, &Settings { audio: false, ..s.clone() })?;
            quiet.wait_until_recording(Duration::from_secs(10))?;
            Ok(quiet)
        }
        Err(e) => Err(e),
    }
}

/// `clips/<Spiel>` for the window in front, or plain `clips`.
pub fn clip_dir(s: &Settings) -> PathBuf {
    let clips = s.clips_dir();
    if s.game_folders { clips.join(game::folder_name(&game::game_name(&game::foreground()))) } else { clips }
}
