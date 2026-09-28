use anyhow::{Context, Result};
use clap::{Args, Parser, Subcommand, ValueEnum};
use clipd::config::{Codec, Gpu, Settings};
use clipd::recorder::Recorder;
use clipd::{buffer, clip, config, ffmpeg, hotkey, sys};
use std::sync::Arc;

#[derive(Parser)]
#[command(name = "clipd", version, about = "Schlanker Clipper fürs Zocken: Replay-Buffer, Hotkey, schneiden, teilen")]
struct Cli {
    #[command(subcommand)]
    cmd: Option<Cmd>,
}

#[derive(Subcommand)]
enum Cmd {
    /// Nimmt laufend auf und speichert auf Tastendruck (Standard).
    Run(RunArgs),
    /// Speichert jetzt einen Clip aus dem Buffer einer laufenden Aufnahme.
    Clip {
        /// Wie viele Sekunden, statt der Länge der laufenden Aufnahme.
        #[arg(long)]
        secs: Option<u32>,
    },
    /// Zeigt, welche Bildschirme aufgenommen werden können.
    Monitors,
    /// Probiert jedes Wiedergabegerät durch und zeigt, welches Ton liefert.
    Audio,
    /// Zeigt die Einstellungen und wo sie liegen.
    Config {
        /// Schreibt die aktuellen Werte in die config.toml.
        #[arg(long)]
        init: bool,
    },
}

#[derive(Args, Default)]
struct RunArgs {
    /// Bildschirm, wie ihn `clipd monitors` zählt.
    #[arg(long)]
    monitor: Option<u32>,
    #[arg(long)]
    fps: Option<u32>,
    /// Wie weit ein Clip zurückreichen darf, in Sekunden.
    #[arg(long)]
    buffer_secs: Option<u32>,
    /// Wie viele Sekunden ein Tastendruck speichert.
    #[arg(long)]
    clip_secs: Option<u32>,
    /// Wessen Kodierer aufnimmt; automatisch probiert NVIDIA, dann AMD.
    #[arg(long)]
    gpu: Option<GpuArg>,
    #[arg(long)]
    codec: Option<CodecArg>,
    /// Qualität, 0 (riesig) bis 51 (schlecht).
    #[arg(long)]
    quality: Option<u8>,
    /// Tastenkombination, etwa "Strg+Alt+C".
    #[arg(long)]
    hotkey: Option<String>,
    /// Ordner für die fertigen Clips.
    #[arg(long)]
    out: Option<std::path::PathBuf>,
    /// Zeichnet den Mauszeiger mit auf.
    #[arg(long)]
    draw_mouse: bool,
    /// Nimmt nur das Bild auf, ohne Ton.
    #[arg(long)]
    no_audio: bool,
    /// Nimmt das Mikrofon als eigene Tonspur mit auf.
    #[arg(long)]
    mic: bool,
}

#[derive(Clone, Copy, ValueEnum)]
enum GpuArg {
    Auto,
    Nvidia,
    Amd,
}

impl From<GpuArg> for Gpu {
    fn from(g: GpuArg) -> Self {
        match g {
            GpuArg::Auto => Gpu::Auto,
            GpuArg::Nvidia => Gpu::Nvidia,
            GpuArg::Amd => Gpu::Amd,
        }
    }
}

#[derive(Clone, Copy, ValueEnum)]
enum CodecArg {
    H264,
    Hevc,
    Av1,
}

impl From<CodecArg> for Codec {
    fn from(c: CodecArg) -> Self {
        match c {
            CodecArg::H264 => Codec::H264,
            CodecArg::Hevc => Codec::Hevc,
            CodecArg::Av1 => Codec::Av1,
        }
    }
}

impl RunArgs {
    /// Command line beats config.toml, which beats the defaults.
    fn apply(self, s: &mut Settings) {
        let set = |dst: &mut u32, v: Option<u32>| {
            if let Some(v) = v {
                *dst = v;
            }
        };
        set(&mut s.monitor, self.monitor);
        set(&mut s.fps, self.fps);
        set(&mut s.buffer_secs, self.buffer_secs);
        set(&mut s.clip_secs, self.clip_secs);
        if let Some(g) = self.gpu {
            s.gpu = g.into();
        }
        if let Some(c) = self.codec {
            s.codec = c.into();
        }
        if let Some(q) = self.quality {
            s.quality = q;
        }
        if let Some(h) = self.hotkey {
            s.hotkey = h;
        }
        if let Some(o) = self.out {
            s.out_dir = o;
        }
        if self.draw_mouse {
            s.draw_mouse = true;
        }
        if self.no_audio {
            s.audio = false;
        }
        if self.mic {
            s.mic = true;
        }
    }
}

fn main() {
    clipd::sys::use_utf8_console();
    if let Err(e) = run() {
        eprintln!("clipd: {e:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    match Cli::parse().cmd.unwrap_or_else(|| Cmd::Run(RunArgs::default())) {
        Cmd::Run(args) => record(args),
        Cmd::Clip { secs } => clip_now(secs),
        Cmd::Monitors => monitors(),
        Cmd::Audio => audio_devices(),
        Cmd::Config { init } => show_config(init),
    }
}

fn settings(args: RunArgs) -> Result<Settings> {
    let mut s = Settings::load();
    args.apply(&mut s);
    s.check()?;
    Ok(s)
}

fn record(args: RunArgs) -> Result<()> {
    let s = settings(args)?;
    let bin = ffmpeg::find()?;
    // Before the capture starts, so a crash cannot leave an ffmpeg behind.
    sys::kill_children_on_exit();

    let rec = Arc::new(Recorder::start(&bin, s, |why| {
        eprintln!("clipd: {why}");
        std::process::exit(1);
    })?);
    let s = &rec.settings;
    println!(
        "clipd nimmt Bildschirm {} auf: {} fps {} mit {}, Qualität {}, Buffer {} s",
        s.monitor,
        s.fps,
        s.codec.label(),
        s.gpu.label(),
        s.quality,
        s.buffer_secs
    );
    match &rec.audio_device {
        Some(device) => println!("Ton: {device} ({} kbit/s AAC)", s.audio_kbit),
        None => println!("Ton: keiner"),
    }
    if let Some(mic) = &rec.mic_device {
        println!("Mikrofon: {mic} (eigene Tonspur)");
    }
    if rec.audio_device.is_some()
        && let Some(warning) = clipd::audio::silence_warning()
    {
        eprintln!("clipd: Achtung: {warning}");
    }
    println!("{} speichert die letzten {} s nach {}", s.hotkey, s.clip_secs, s.clips_dir().display());
    let mut keys = vec![(hotkey::parse(&s.hotkey)?, s.hotkey.clone())];
    if !s.record_hotkey.trim().is_empty() {
        println!("{} startet und beendet eine Aufnahme beliebiger Länge", s.record_hotkey);
        keys.push((hotkey::parse(&s.record_hotkey)?, s.record_hotkey.clone()));
    }
    println!("Beenden mit Strg+C.");

    let on_key = rec.clone();
    let _keys = hotkey::Listener::start(keys, move |key| {
        let done = match key {
            0 => on_key.save_clip(),
            _ if on_key.recording_for().is_none() => match on_key.start_recording() {
                Ok(()) => {
                    println!("Aufnahme läuft …");
                    return;
                }
                Err(e) => Err(e),
            },
            _ => on_key.stop_recording(),
        };
        match done {
            Ok(done) => println!("{}", clip::describe(&done)),
            Err(e) => eprintln!("clipd: {e:#}"),
        }
    })?;
    loop {
        std::thread::park();
    }
}

/// Saves from the buffer of an already running clipd, so a second terminal or a
/// stream deck can trigger a clip too. Uses the settings that capture was
/// started with, not what config.toml happens to say now.
fn clip_now(secs: Option<u32>) -> Result<()> {
    let mut s = match Settings::load_session() {
        Some(s) => s,
        None => settings(RunArgs::default())?,
    };
    if let Some(secs) = secs {
        s.clip_secs = secs;
        s.check()?;
    }
    let bin = ffmpeg::find()?;
    let dir = config::buffer_dir();
    anyhow::ensure!(
        !buffer::segments(&dir, &s).is_empty(),
        "Im Buffer liegt nichts. Läuft `clipd run` in einem anderen Fenster?"
    );
    let done = clip::save(&bin, &s, &dir, &s.clips_dir())?;
    println!("{}", clip::describe(&done));
    Ok(())
}

fn monitors() -> Result<()> {
    let bin = ffmpeg::find()?;
    let found = ffmpeg::monitors(&bin);
    anyhow::ensure!(!found.is_empty(), "Es liess sich kein Bildschirm aufnehmen.");
    println!("Bildschirme, die aufgenommen werden können:");
    for (idx, size) in found {
        println!("  {idx}  {size}");
    }
    println!("Mit `clipd run --monitor <Nummer>` wählen.");
    Ok(())
}

/// Tries every playback device in turn. Windows lets a device be the default
/// one and still never answer a loopback request — some virtual sound cards
/// do exactly that — so the only honest answer comes from trying.
fn audio_devices() -> Result<()> {
    let found = clipd::audio::devices()?;
    anyhow::ensure!(!found.is_empty(), "Windows meldet kein Wiedergabegerät.");
    println!("Wiedergabegeräte (das erste ist das Standardgerät):");
    let mut works: Option<String> = None;
    for name in &found {
        print!("  {name}\n    ");
        match clipd::audio::open_within(name, None, std::time::Duration::from_secs(3)) {
            Ok(audio) => {
                println!("Ton: ja, {} Hz, {} Kanäle", audio.format.rate, audio.format.channels);
                works.get_or_insert_with(|| name.clone());
            }
            Err(e) => println!("Ton: nein — {e:#}"),
        }
    }
    match works {
        Some(name) if name == found[0] => println!("\nDas Standardgerät liefert Ton, es ist nichts einzustellen."),
        Some(name) => println!("\nIn die config.toml: audio_device = \"{}\"", short(&name)),
        None => println!("\nKein Gerät liefert Ton. Mit `clipd run --no-audio` nimmt clipd nur das Bild auf."),
    }
    Ok(())
}

/// A short, still unique-enough piece of a device name for the config file.
fn short(name: &str) -> String {
    name.split(['(', '-']).next().unwrap_or(name).trim().to_string()
}

fn show_config(init: bool) -> Result<()> {
    let s = Settings::load();
    let path = config::config_path();
    if init {
        s.save()?;
        println!("Geschrieben: {}", path.display());
    } else if path.is_file() {
        println!("Einstellungen: {}", path.display());
    } else {
        println!("Noch keine {} — es gelten die Standardwerte (`clipd config --init` legt sie an).", path.display());
    }
    println!("Buffer: {}", config::buffer_dir().display());
    println!("Clips:  {}", s.clips_dir().display());
    println!();
    print!("{}", toml::to_string_pretty(&s).context("Einstellungen lassen sich nicht anzeigen")?);
    s.check()
}
