# Stand und nächste Schritte (clipd)

Stand 2026-09-29, Branch `feat/clipd`.

## Code-Review 2026-09-29
13 Befunde, 12 behoben (Commits 865dd6c, df9fe97): Kopieren in die Zwischenablage
ging nie und führte den Pfad als PowerShell aus; eine Aufnahme ging beim Neustart der
Aufnahme verloren (Spiel beendet, ffmpeg-Absturz, Einstellungen, Beenden) — wird jetzt
vorher gespeichert; Einfrieren beim Speichern der Einstellungen während eine Aufnahme
endet (Abbau jetzt nicht mehr im Hauptthread); ffprobe-Konsolenfenster nach jedem Clip;
Aufräumen löschte den gerade gespeicherten Clip und fremde Videos; favorites.json ohne
Sperre; Export konnte an vollem stderr hängen; Fensterbefehle nahmen beliebige Pfade;
Einstellungen während des Starts gingen verloren; Tastenfeld hielt die Tastatur fest;
halb entpacktes ffmpeg; COM5–9/LPT4–9, `;` in Discord-Dateinamen, Webhook-Host.
- **Offen:** „Beenden“ schließt auch einen über „Öffnen“ gestarteten Player (Job-Objekt
  erbt auf Kinder). Nach einem Absturz von clipd selbst wird eine halbe `aufnahme-*.ts`
  beim nächsten Start noch gelöscht statt gerettet.
- **Nicht zur Laufzeit geprüft:** die Rettung einer Aufnahme beim Neustart (braucht
  Spielfenster-Modus oder das Tray-Menü) — zuhause mit Spiel testen: Aufnahme starten,
  Spiel beenden, Clip muss im Ordner liegen. Rauchtest ohne Ton ok: Start 0,7 s,
  `clipd clip` und `clipd record` an/aus liefern korrekte MP4s.

## Offen / ungetestet
- **Fenster schließen gibt WebView frei**: am 2026-09-29 auf dem Laptop getestet
  (Release-Build, eigener `CLIPD_HOME`, ohne Ton/Mikro/Overlay). Ergebnis: Fenster zu →
  App und ffmpeg laufen weiter, alle 6 WebView2-Prozesse (~197 MB) sind weg, clipd
  bleibt bei ~14 MB privat (ffmpeg ~80 MB); zweiter Start (Single-Instance, wie der
  Tray-Klick) baut das Fenster wieder; `app.exit(0)` von „Beenden“ trägt `code: Some(0)`
  (Tauri-Quelltext geprüft), nur das Schließen des letzten Fensters hat `None`.
  Nicht per Klick geprüft: das Tray-Menü selbst.
- **Bild-Ton-Synchronität messen** (nur zuhause, macht Ton): Skript `sync.ps1`
  (weißer Blitz + Testton, misst Versatz). Vor der Korrektur: Ton 0,4 s zu spät.
- **NVIDIA** und **Spielfenster-Modus** (`capture = "game"`) mit echtem Spiel testen.
- Release: Tag `clipd-v0.1.0` pushen → `clipd-release.yml` baut den Installer
  (`--latest=false`, omnidl bleibt „latest“, Text aus CHANGELOG.md). Lokal gebaut am
  2026-09-29: `cargo tauri build --config tauri.release.conf.json` → 2 MB Setup.

## FiveM (2026-09-29, live gelesen)
- Spielprozess `FiveM_b3258_GTAProcess.exe`, Beschreibung „FiveM Game subprocess“ →
  Ordner heißt jetzt „FiveM“. Fenster randlos 0,0–1920×1080 auf DISPLAY1, zählt also
  als Vollbild. Aufnahme mit clipd im Spiel noch nicht probiert.

## Performance-Review (Laptop, Ryzen 7730U, AMD, 1920×1200@60, Desktop-Inhalt)
- Aufnahme: ffmpeg 14–17 % eines Kerns, clipd 1 %, GPU 3D ~16 %.
- RAM clipd: Ring ~30 MB bei 120 s Desktop, steigt mit Bildinhalt (Spiele eher
  100–300 MB). Kein Leck (6-Minuten-Test).
- Clip speichern: ~0,7 s (0,3 s bewusste Wartezeit auf den Ton, Rest ffmpeg + ffprobe).
- App im Tray: WebView2 6 Prozesse, ~193 MB privat solange das Fenster offen ist;
  seit dem letzten Commit beim geschlossenen Fenster 0 (nachgemessen 2026-09-29).
- Umgesetzt: kein Doppel-Kopieren beim Speichern, Ring-Lock nur kurz (Arc-Segmente),
  `shrink_to_fit` (−20 % RAM), Spielfenster-Check ohne EXE-Versionsinfo, Lautstärke-Check alle 10 s.
- Default `buffer_secs` ist jetzt 60 (halber RAM); bestehende config.toml behalten ihren Wert.
- ffprobe nach dem Speichern entfällt: die Länge für Overlay und Toast kommt aus
  `ffmpeg -progress pipe:1` (`out_time_us`, auf die Mikrosekunde wie ffprobe),
  ffprobe nur noch als Rückfall. Spart einen Prozessstart (~95 ms gemessen).
- Zweite Runde (2026-09-29, Branch `perf/clipd`, gemessen mit Testbild-Clips, ohne
  Aufnahme): ein ffmpeg-Start kostet hier ~165 ms, mehr als ein Bild zu dekodieren.
  - Schnittleiste: ein ffmpeg mit zehn Eingängen statt zehn ffmpegs, Länge aus dem
    Cache statt ffprobe: ~2,2 s → ~0,65 s (30 s, 1080p60).
  - Vorschaubild entsteht parallel zu ffprobe: ~0,3 s → ~0,2 s je neuem Clip
    (Clips unter 3 s brauchen einen zweiten Versuch, ~0,43 s).
  - `-encoders`/`-filters` je ffmpeg-Build in `cache/ffmpeg-lists.json`: spart bei
    jedem Aufnahmestart zwei ffmpeg-Starts (~120 ms kalt, danach < 1 ms).
  - Bildschirmliste: ein ffmpeg je Monitor statt zwei (Einstellungen öffnen schneller).
  - Ton-Interleave mit Slices statt Byte für Byte: 1,8 → 0,03 ms je Sekunde Ton
    (mit Mikro 3,4 → 0,7 ms), bei 200 Aufrufen/s.
  - Speichern schreibt die Ring-Segmente einzeln an ffmpeg: kein 64-MB-Zwischenpuffer
    (30 s bei 16 Mbit/s), ~18 ms weniger.
  - Fenster: Playhead-Schleife nur beim Abspielen (vorher 60 Hz dauerhaft), Status-Poll
    pausiert minimiert und fasst das DOM nur bei Änderung an, Fokus baut das Raster
    nur bei geänderter Liste neu.
  - Verworfen: `Ring::push` ohne Zwischen-Vec (gemessen ~0,7 ms je Stream-Sekunde,
    vorher wie nachher), `opt-level = "s"` (CLI 1,28 → 1,00 MB, neben ~90 MB ffmpeg
    unerheblich), Probe-Encode in `pick_gpu` cachen (bei „auto“ bliebe clipd nach
    einem NVIDIA-Aussetzer bei AMD hängen), Takt 5 ms des Ton-Schreibers und 100 ms
    der Überwachung (ohne Ton-Test nicht prüfbar bzw. vernachlässigbar).

## Regeln
- Nutzer ist oft in der Schule: keine Töne, keine Lautstärkeänderung, keine
  Vollbild-Testfenster (`save_sound = false`, `overlay = false` in Test-config.toml).
- Linux: bewusst nicht machen (Nutzerwunsch).
