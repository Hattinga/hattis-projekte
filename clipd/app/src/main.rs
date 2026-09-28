//! clipd with a window: the capture runs in the background, the window shows
//! the library, and the tray icon stays when the window is closed.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use clipd::config::Settings;
use clipd::library::{self, Edit, Entry, Meta, Target};
use clipd::recorder::Recorder;
use clipd::{ffmpeg, hotkey};
use serde::Serialize;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant};
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, WindowEvent, Wry};

#[derive(Default)]
struct App {
    recorder: Mutex<Option<Arc<Recorder>>>,
    keys: Mutex<Option<hotkey::Listener>>,
    /// Why there is no capture, or why it is incomplete.
    problem: Mutex<Option<String>>,
    starting: AtomicBool,
    /// The tray entry that starts or ends a recording, to rename it.
    record_item: Mutex<Option<MenuItem<Wry>>>,
    /// The volume warning, asked for at most every few seconds.
    warning: Mutex<Option<(Instant, Option<String>)>>,
    /// ffmpeg's first download: bytes so far and in total.
    download: Mutex<Option<(u64, Option<u64>)>>,
}

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct Status {
    /// "downloading", "starting", "running" or "stopped".
    state: &'static str,
    /// How far ffmpeg's first download is, 0 to 1, if it is going on.
    download: Option<f64>,
    problem: Option<String>,
    warning: Option<String>,
    recording_secs: Option<f64>,
    gpu: String,
    codec: String,
    fps: u32,
    audio: Option<String>,
    mic: Option<String>,
    hotkey: String,
    record_hotkey: String,
    clip_secs: u32,
}

fn recorder(app: &AppHandle) -> Option<Arc<Recorder>> {
    lock(&app.state::<App>().recorder).clone().filter(|r| r.is_running())
}

fn status_of(app: &AppHandle) -> Status {
    let st = app.state::<App>();
    let rec = lock(&st.recorder).clone();
    let running = rec.as_ref().is_some_and(|r| r.is_running());
    let download = *lock(&st.download);
    let state = if download.is_some() {
        "downloading"
    } else if st.starting.load(Ordering::Relaxed) {
        "starting"
    } else if running {
        "running"
    } else {
        "stopped"
    };
    let s = rec.as_ref().map(|r| r.settings.clone()).unwrap_or_else(Settings::load);
    let warning = if running && rec.as_ref().is_some_and(|r| r.audio_device.is_some()) {
        let mut w = lock(&st.warning);
        if w.as_ref().is_none_or(|(at, _)| at.elapsed() > Duration::from_secs(3)) {
            *w = Some((Instant::now(), clipd::audio::silence_warning()));
        }
        w.as_ref().and_then(|(_, text)| text.clone())
    } else {
        None
    };
    Status {
        state,
        download: download.map(|(got, total)| total.map_or(0.0, |t| got as f64 / t.max(1) as f64)),
        problem: lock(&st.problem).clone(),
        warning,
        recording_secs: rec.as_ref().filter(|_| running).and_then(|r| r.recording_for()).map(|d| d.as_secs_f64()),
        gpu: if running { s.gpu.label().into() } else { String::new() },
        codec: s.codec.label().into(),
        fps: s.fps,
        audio: rec.as_ref().and_then(|r| r.audio_device.clone()),
        mic: rec.as_ref().and_then(|r| r.mic_device.clone()),
        hotkey: s.hotkey.clone(),
        record_hotkey: s.record_hotkey.clone(),
        clip_secs: s.clip_secs,
    }
}

fn emit_status(app: &AppHandle) {
    let _ = app.emit("status", status_of(app));
}

/// (Re)starts the capture with what config.toml says, off the main thread:
/// settling the card and waiting for the first segment takes a second or two.
fn start_capture(app: &AppHandle) {
    let st = app.state::<App>();
    if st.starting.swap(true, Ordering::SeqCst) {
        return;
    }
    // The keys go first, since they hold a clone of the recorder.
    *lock(&st.keys) = None;
    *lock(&st.recorder) = None;
    *lock(&st.problem) = None;
    emit_status(app);
    let app = app.clone();
    std::thread::spawn(move || {
        let st = app.state::<App>();
        let fetched = ffmpeg::find().or_else(|_| {
            let progress_app = app.clone();
            let mut last = Instant::now();
            let got = ffmpeg::ensure(&mut |got, total| {
                *lock(&progress_app.state::<App>().download) = Some((got, total));
                if last.elapsed() > Duration::from_millis(400) {
                    last = Instant::now();
                    emit_status(&progress_app);
                }
            });
            *lock(&st.download) = None;
            got
        });
        let started = fetched.and_then(|bin| {
            let on_end = app.clone();
            Recorder::start(&bin, Settings::load(), move |why| {
                *lock(&on_end.state::<App>().problem) = Some(why);
                emit_status(&on_end);
            })
        });
        match started {
            Ok(rec) => {
                let rec = Arc::new(rec);
                allow_clips(&app, &rec.settings);
                match listen(&app, &rec) {
                    Ok(keys) => *lock(&st.keys) = Some(keys),
                    Err(e) => *lock(&st.problem) = Some(format!("{e:#}")),
                }
                *lock(&st.recorder) = Some(rec);
            }
            Err(e) => *lock(&st.problem) = Some(format!("{e:#}")),
        }
        st.starting.store(false, Ordering::SeqCst);
        update_tray(&app);
        emit_status(&app);
    });
}

/// Lets the window load clips and thumbnails through the asset protocol —
/// only these two folders, nothing else on the disk.
fn allow_clips(app: &AppHandle, s: &Settings) {
    let scope = app.asset_protocol_scope();
    let _ = scope.allow_directory(s.clips_dir(), true);
    let _ = scope.allow_directory(clipd::config::base_dir().join("cache"), true);
}

fn listen(app: &AppHandle, rec: &Arc<Recorder>) -> anyhow::Result<hotkey::Listener> {
    use clipd::control::Request;
    let s = &rec.settings;
    let mut keys = vec![(hotkey::parse(&s.hotkey)?, s.hotkey.clone())];
    let mut requests = vec![Request::Clip(None)];
    if !s.record_hotkey.trim().is_empty() {
        keys.push((hotkey::parse(&s.record_hotkey)?, s.record_hotkey.clone()));
        requests.push(Request::Record);
    }
    if !s.long_hotkey.trim().is_empty() {
        keys.push((hotkey::parse(&s.long_hotkey)?, s.long_hotkey.clone()));
        requests.push(Request::Clip(Some(s.long_clip_secs)));
    }
    let (app, rec) = (app.clone(), rec.clone());
    hotkey::Listener::start(keys, move |key| {
        let _ = match requests[key] {
            Request::Clip(secs) => save_last(&app, &rec, secs).map(|_| ()),
            Request::Record => toggle(&app, &rec).map(|_| ()),
        };
    })
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct Saved {
    path: PathBuf,
    secs: Option<f64>,
    /// "clip" or "recording".
    kind: &'static str,
}

fn save(app: &AppHandle, rec: &Recorder) -> Result<(), String> {
    save_last(app, rec, None).map(|_| ())
}

fn save_last(app: &AppHandle, rec: &Recorder, secs: Option<u32>) -> Result<PathBuf, String> {
    match secs.map_or_else(|| rec.save_clip(), |s| rec.save_last(s)) {
        Ok(done) => {
            let _ = app.emit("saved", Saved { path: done.path.clone(), secs: done.secs, kind: "clip" });
            Ok(done.path)
        }
        Err(e) => {
            let msg = format!("{e:#}");
            let _ = app.emit("failed", &msg);
            Err(msg)
        }
    }
}

/// Starts a recording, or ends and saves the one running.
fn toggle(app: &AppHandle, rec: &Recorder) -> Result<Option<PathBuf>, String> {
    let result = rec.toggle_recording().map(|done| {
        done.map(|done| {
            let _ = app.emit("saved", Saved { path: done.path.clone(), secs: done.secs, kind: "recording" });
            done.path
        })
    });
    update_tray(app);
    emit_status(app);
    result.map_err(|e| {
        let msg = format!("{e:#}");
        let _ = app.emit("failed", &msg);
        msg
    })
}

fn update_tray(app: &AppHandle) {
    let recording = recorder(app).is_some_and(|r| r.recording_for().is_some());
    if let Some(item) = lock(&app.state::<App>().record_item).as_ref() {
        let _ = item.set_text(if recording { "Aufnahme beenden" } else { "Aufnahme starten" });
    }
}

fn show_main(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.unminimize();
        let _ = w.show();
        let _ = w.set_focus();
    }
}

/// Runs blocking work off the main thread, so the window keeps drawing.
async fn blocking<T: Send + 'static>(f: impl FnOnce() -> Result<T, String> + Send + 'static) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(f).await.map_err(err)?
}

/// The running capture's settings, or config.toml's with the card settled —
/// exporting needs to know which encoder there is.
fn settled_settings(app: &AppHandle) -> Result<(PathBuf, Settings), String> {
    if let Some(rec) = recorder(app) {
        return Ok((rec.ffmpeg.clone(), rec.settings.clone()));
    }
    let bin = ffmpeg::find().map_err(err)?;
    let mut s = Settings::load();
    s.gpu = ffmpeg::pick_gpu(&bin, &s).map_err(|e| format!("{e:#}"))?;
    Ok((bin, s))
}

#[tauri::command]
fn status(app: AppHandle) -> Status {
    status_of(&app)
}

#[tauri::command]
async fn save_clip(app: AppHandle) -> Result<(), String> {
    blocking(move || {
        let rec = recorder(&app).ok_or("Es läuft keine Aufnahme")?;
        save(&app, &rec)
    })
    .await
}

#[tauri::command]
async fn toggle_recording(app: AppHandle) -> Result<Option<PathBuf>, String> {
    blocking(move || {
        let rec = recorder(&app).ok_or("Es läuft keine Aufnahme")?;
        toggle(&app, &rec)
    })
    .await
}

#[tauri::command]
fn clips() -> Vec<Entry> {
    library::list(&Settings::load().clips_dir())
}

#[tauri::command]
async fn meta(path: PathBuf) -> Result<Meta, String> {
    blocking(move || {
        let bin = ffmpeg::find().map_err(err)?;
        library::meta(&bin, &path).map_err(|e| format!("{e:#}"))
    })
    .await
}

#[tauri::command]
async fn export(app: AppHandle, path: PathBuf, edit: Edit, target: Target) -> Result<PathBuf, String> {
    blocking(move || {
        let (bin, s) = settled_settings(&app)?;
        let progress_app = app.clone();
        library::export(&bin, &s, &path, &edit, target, &mut |f| {
            let _ = progress_app.emit("export-progress", f);
        })
        .map_err(|e| format!("{e:#}"))
    })
    .await
}

#[tauri::command]
async fn strip(path: PathBuf) -> Result<Vec<PathBuf>, String> {
    blocking(move || {
        let bin = ffmpeg::find().map_err(err)?;
        library::strip(&bin, &path, 10).map_err(|e| format!("{e:#}"))
    })
    .await
}

/// Puts the file itself on the clipboard, the way Explorer's copy does, so it
/// can be pasted into Discord with Ctrl+V.
#[tauri::command]
async fn copy_file(path: PathBuf) -> Result<(), String> {
    blocking(move || {
        use std::os::windows::process::CommandExt;
        let out = std::process::Command::new("powershell")
            .args(["-NoProfile", "-NonInteractive", "-Command", "Set-Clipboard -LiteralPath $args[0]"])
            .arg(&path)
            .creation_flags(0x0800_0000)
            .output()
            .map_err(err)?;
        if out.status.success() {
            Ok(())
        } else {
            Err(format!("Kopieren ging nicht: {}", String::from_utf8_lossy(&out.stderr).trim()))
        }
    })
    .await
}

#[tauri::command]
fn open_external(path: PathBuf) -> Result<(), String> {
    tauri_plugin_opener::open_path(path, None::<&str>).map_err(err)
}

/// Makes the Discord version of the selection and posts it into the channel
/// set in the settings.
#[tauri::command]
async fn send_discord(app: AppHandle, path: PathBuf, edit: Edit) -> Result<PathBuf, String> {
    blocking(move || {
        let webhook = Settings::load().discord_webhook;
        if !library::webhook_ok(&webhook) {
            return Err("In den Einstellungen fehlt der Webhook des Discord-Kanals".into());
        }
        let (bin, s) = settled_settings(&app)?;
        let progress_app = app.clone();
        let out = library::export(&bin, &s, &path, &edit, Target::Discord, &mut |f| {
            let _ = progress_app.emit("export-progress", f * 0.9);
        })
        .map_err(|e| format!("{e:#}"))?;
        library::send_to_discord(&webhook, &out).map_err(|e| format!("{e:#}"))?;
        let _ = app.emit("export-progress", 1.0);
        Ok(out)
    })
    .await
}

#[tauri::command]
fn rename(path: PathBuf, name: String) -> Result<PathBuf, String> {
    library::rename(&path, &name).map_err(|e| format!("{e:#}"))
}

#[tauri::command]
fn delete(path: PathBuf) -> Result<(), String> {
    trash::delete(&path).map_err(|e| format!("Der Clip lässt sich nicht löschen: {e}"))?;
    library::favorite_moved(&path, None);
    Ok(())
}

#[tauri::command]
fn set_favorite(path: PathBuf, on: bool) -> Result<(), String> {
    library::set_favorite(&path, on).map_err(|e| format!("{e:#}"))
}

#[tauri::command]
fn reveal(path: PathBuf) -> Result<(), String> {
    tauri_plugin_opener::reveal_item_in_dir(path).map_err(err)
}

#[tauri::command]
fn open_clips_folder() -> Result<(), String> {
    let dir = Settings::load().clips_dir();
    std::fs::create_dir_all(&dir).map_err(err)?;
    tauri_plugin_opener::open_path(dir, None::<&str>).map_err(err)
}

#[tauri::command]
fn settings() -> Settings {
    Settings::load()
}

#[tauri::command]
fn save_settings(app: AppHandle, settings: Settings) -> Result<(), String> {
    settings.check().map_err(|e| format!("{e:#}"))?;
    settings.save().map_err(|e| format!("{e:#}"))?;
    start_capture(&app);
    Ok(())
}

#[tauri::command]
fn restart_capture(app: AppHandle) {
    start_capture(&app);
}

#[derive(Serialize)]
struct Devices {
    speakers: Vec<String>,
    microphones: Vec<String>,
    monitors: Vec<(u32, String)>,
}

#[tauri::command]
async fn devices() -> Result<Devices, String> {
    blocking(|| {
        let monitors = ffmpeg::find().map(|bin| ffmpeg::monitors(&bin)).unwrap_or_default();
        Ok(Devices {
            speakers: clipd::audio::devices().unwrap_or_default(),
            microphones: clipd::audio::microphones().unwrap_or_default(),
            monitors,
        })
    })
    .await
}

fn tray(app: &AppHandle) -> tauri::Result<()> {
    let save_item = MenuItem::with_id(app, "save", "Clip speichern", true, None::<&str>)?;
    let record = MenuItem::with_id(app, "record", "Aufnahme starten", true, None::<&str>)?;
    let show = MenuItem::with_id(app, "show", "clipd öffnen", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Beenden", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&save_item, &record, &PredefinedMenuItem::separator(app)?, &show, &quit])?;
    *lock(&app.state::<App>().record_item) = Some(record);
    let mut builder = TrayIconBuilder::with_id("clipd").tooltip("clipd").menu(&menu).show_menu_on_left_click(false);
    if let Some(icon) = app.default_window_icon() {
        builder = builder.icon(icon.clone());
    }
    builder
        .on_menu_event(|app, event| {
            let app = app.clone();
            match event.id.as_ref() {
                "save" => {
                    std::thread::spawn(move || {
                        if let Some(rec) = recorder(&app) {
                            let _ = save(&app, &rec);
                        }
                    });
                }
                "record" => {
                    std::thread::spawn(move || {
                        if let Some(rec) = recorder(&app) {
                            let _ = toggle(&app, &rec);
                        }
                    });
                }
                "show" => show_main(&app),
                "quit" => app.exit(0),
                _ => {}
            }
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                show_main(tray.app_handle());
            }
        })
        .build(app)?;
    Ok(())
}

fn main() {
    // Before any capture starts, so not even a crash leaves an ffmpeg behind.
    clipd::sys::kill_children_on_exit();
    let hidden = std::env::args().any(|a| a == "--hidden");
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| show_main(app)))
        .plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, Some(vec!["--hidden"])))
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .manage(App::default())
        .setup(move |app| {
            let handle = app.handle().clone();
            tray(&handle)?;
            allow_clips(&handle, &Settings::load());
            start_capture(&handle);
            // `clipd clip` and `clipd record` from a terminal or a Stream Deck.
            let control = handle.clone();
            clipd::control::serve(move |request| {
                let rec = recorder(&control).ok_or("Es läuft keine Aufnahme")?;
                match request {
                    clipd::control::Request::Clip(secs) => save_last(&control, &rec, secs).map(|p| p.display().to_string()),
                    clipd::control::Request::Record => {
                        toggle(&control, &rec).map(|p| p.map_or("Aufnahme läuft …".into(), |p| p.display().to_string()))
                    }
                }
            });
            if !hidden {
                show_main(&handle);
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            // Closing the window keeps clipd recording in the tray.
            if let WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .invoke_handler(tauri::generate_handler![
            status,
            save_clip,
            toggle_recording,
            clips,
            meta,
            strip,
            copy_file,
            open_external,
            export,
            send_discord,
            rename,
            delete,
            set_favorite,
            reveal,
            open_clips_folder,
            settings,
            save_settings,
            restart_capture,
            devices
        ])
        .run(tauri::generate_context!())
        .expect("clipd lässt sich nicht starten");
}
