# Stand und nächste Schritte (clipd)

Stand 2026-09-28, Branch `feat/clipd`.

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
  (`--latest=false`, omnidl bleibt „latest“).

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
- ffprobe nach dem Speichern kostet nur ~95 ms und liefert die Länge für Overlay und
  Toast; bewusst behalten.

## Regeln
- Nutzer ist oft in der Schule: keine Töne, keine Lautstärkeänderung, keine
  Vollbild-Testfenster (`save_sound = false`, `overlay = false` in Test-config.toml).
- Linux: bewusst nicht machen (Nutzerwunsch).
