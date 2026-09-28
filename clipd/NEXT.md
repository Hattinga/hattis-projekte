# Stand und nächste Schritte (clipd)

Stand 2026-09-28, Branch `feat/clipd`.

## Offen / ungetestet
- **Fenster schließen gibt WebView frei** (letzter Commit): `create: false` in
  tauri.conf.json, `show_main` baut das Fenster bei Bedarf, `RunEvent::ExitRequested`
  mit `code: None` verhindert das Beenden. Baut und Clippy ist sauber, **zur Laufzeit
  noch nicht ausprobiert**: Fenster öffnen/schließen/wieder öffnen über das Tray-Symbol
  prüfen, und dass „Beenden“ wirklich beendet.
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
- App im Tray vorher: WebView2 6 Prozesse, ~193 MB privat → mit letztem Commit sollte
  das beim geschlossenen Fenster wegfallen (nachmessen: `perf.ps1 -Mode app`).
- Umgesetzt: kein Doppel-Kopieren beim Speichern, Ring-Lock nur kurz (Arc-Segmente),
  `shrink_to_fit` (−20 % RAM), Spielfenster-Check ohne EXE-Versionsinfo, Lautstärke-Check alle 10 s.
- Ideen: ffprobe nach dem Speichern sparen; Default `buffer_secs` 120 → 60 halbiert RAM.

## Regeln
- Nutzer ist oft in der Schule: keine Töne, keine Lautstärkeänderung, keine
  Vollbild-Testfenster (`save_sound = false`, `overlay = false` in Test-config.toml).
- Linux: bewusst nicht machen (Nutzerwunsch).
