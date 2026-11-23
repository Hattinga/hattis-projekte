# FrameRush

Schlanker HDMI-Capture-Viewer für Windows mit möglichst wenig Latenz. Ziel:
die PS5 über eine günstige UGREEN-USB-Capture-Karte in 1920×1080 bei 60 fps
anzeigen, den Ton auf dem PC-Headset hören und das Fenster in Discord teilen.

**Stand: Prototyp (Meilenstein M0).** FrameRush zeigt eine *synthetische*
Videoquelle an, ein animiertes Testbild in 1920×1080 @ 60. Damit läuft die
ganze Kette von Quelle über Mailbox und GPU bis zum Bildschirm bereits ohne
Capture-Karte. Die Karte selbst wird erst erkannt (`--list-devices`) und noch
nicht aufgenommen. Ton gibt es noch nicht.

Null Latenz gibt es nicht. Die Karte puffert, USB überträgt, Windows
komponiert, und der Monitor baut das Bild auf. FrameRush misst nur seinen
eigenen Software-Anteil und zeigt ihn als solchen an.

## Voraussetzungen

- Windows 10/11 x64 mit einer DirectX-12-fähigen Grafikkarte
- Media Foundation. Fehlt bei Windows-„N“-Editionen ohne Media Feature Pack;
  ohne sie startet FrameRush nicht.
- Zum Bauen:
  - [Rust](https://rustup.rs/) stable ≥ 1.88, Ziel `x86_64-pc-windows-msvc`
  - Visual Studio 2022 Build Tools mit „Desktopentwicklung mit C++“ (MSVC
    und Windows SDK), z. B.:
    ```
    winget install Microsoft.VisualStudio.2022.BuildTools --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    ```

## Bauen und starten

```
cargo run                         # Testbild 1920x1080 NV12 @ 60, VSync
cargo run -- --help               # alle Optionen
cargo run -- --list-devices       # Capture-Geräte und ihre gemeldeten Formate
cargo run -- --present-mode mailbox
cargo run -- --format bgra --fps 60000/1001
cargo run -- --fullscreen --no-overlay
cargo run -- --exit-after 10      # nach 10 s beenden, Statistik ins Log
```

Mehr Log: `$env:RUST_LOG="debug"; cargo run` (PowerShell).

Prüfungen wie in CLAUDE.md:

```
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
cargo test -- --ignored   # Media-Foundation-Test, öffnet kurz alle Kameras
```

### Tasten

| Taste | Wirkung |
|---|---|
| F11 oder Alt+Enter | Vollbild ohne Rahmen an/aus |
| Esc | Vollbild verlassen |
| O | Statistik-Overlay an/aus (z. B. für einen sauberen Discord-Stream) |

## Was das Overlay zeigt

| Zeile | Bedeutung |
|---|---|
| `IN … FPS` | Frames pro Sekunde, die die Quelle liefert |
| `SHOWN … FPS` | neue Frames pro Sekunde, die tatsächlich präsentiert wurden |
| `DROPS MAILBOX` | Frames, die ein neuerer Frame ersetzt hat, bevor der Renderer sie abholte. Gewollt, so entsteht kein Rückstau |
| `DROPS SOURCE` | Lücken in den Sequenznummern der Quelle |
| `NOT SHOWN` | abgeholt, aber nicht präsentiert (Fenster minimiert, kein Swapchain-Bild) |
| `READY>TAKE` | Frame fertig → vom Renderer abgeholt, inklusive Warten auf das Swapchain-Bild |
| `READY>PRESENT` | Frame fertig → `present()` zurückgekehrt |
| `PRESENT INTERVAL` | Abstand zwischen zwei Presents, also die Gleichmäßigkeit der Bildfolge |

Alle Zeiten sind **Software-Zeitstempel** dieses Prozesses. Sie enthalten
weder Puffer und USB der Karte noch DWM, Scan-out oder Panel. Die echte
HDMI-zu-Photon-Latenz lässt sich nur mit Hochgeschwindigkeitskamera oder
Fotodiode messen. Dafür hat das Testbild einen großen Frame-Zähler und eine
Frame-Uhr.

## Messwerte des Prototyps (2026-11-23)

Debug-Build, RTX 5060 Ti, DX12, Frame-Latenz 1, synthetische Quelle
1920×1080 @ 60. Fenster 1280×720, nicht im Vollbild, also von DWM
komponiert, auf dem Hauptmonitor (1920×1080 @ 60 Hz an der RTX). Je Lauf
10,5 s. Die Zeiten stammen aus den Sekunden ohne Hänger:

| Present-Modus | Läufe | rein / angezeigt | Mailbox-Drops je Lauf | ready→present (Mittel) | Present-Abstand |
|---|---|---|---|---|---|
| FIFO (VSync), NV12 | 1 | 60 / 60 fps | 7 | ~3,0 ms | 15,2–17,8 ms |
| FIFO (VSync), BGRA | 1 | 60 / 60 fps | 8 | ~2,9 ms | 15,4–17,8 ms |
| Mailbox, NV12 | 1 | 60 / 60 fps | 7 | ~2,1 ms | 15,8–17,8 ms |
| Immediate, NV12 | 3 | 60 / 60 fps | 70 / 6 / 5 | ~2,1 ms | 15,2–18,1 ms |

So sind die Zahlen zu lesen:

- **Start:** Jeder Lauf hat in der ersten Sekunde einen Hänger von etwa
  50 ms, solange Fenster und Swapchain entstehen. Daher kommen die meisten
  Drops.
- **Hänger im Betrieb:** Vereinzelt gibt es Hänger von etwa 50 ms. Ein
  Immediate-Lauf stand einmal gut eine Sekunde lang (70 Drops); zwei
  Wiederholungen zeigten das nicht. Die Ursache ist offen, der PC war
  nebenher in Benutzung, und gemessen wurde ein Debug-Build. Das wird in M3
  mit Release-Build nachgemessen.
- **FIFO schwankt von Lauf zu Lauf:** Die Wartezeit hängt davon ab, wie der
  Takt der Quelle zufällig zum VBlank liegt. Ein früherer FIFO-Lauf mit
  gleichem Timing-Code ergab ~5,3 ms. Ein einzelner Lauf ist also nicht
  repräsentativ.
- **Was die Zahlen nicht sind:** Das sind Software-Zeiten mit einer
  synthetischen Quelle, kein Vergleich mit OBS/PotPlayer und keine
  End-to-End-Latenz. Vollbild, wo Windows eventuell ohne DWM-Komposition
  direkt flippt, ist nicht gemessen. Welcher Modus mit der echten Karte am
  besten ist, bleibt offen (Meilenstein M3).

## Capture-Karte, PS5 und Discord

- **Formate der Karte:** `--list-devices` zeigt, was der Treiber meldet. Der
  erste Befund für die UGREEN-Karte steht in
  [docs/hardware-probe-2026-11-23.md](docs/hardware-probe-2026-11-23.md):
  NV12 und MJPG in 1920×1080 @ 60, YUY2 in 1080p nur mit 5 fps. Gemeldet
  heißt nicht geprüft.
- **PS5:** Für Gameplay muss HDCP aus sein (Einstellungen → System → HDMI →
  HDCP aktivieren: aus). Geschützte Inhalte, etwa Streaming-Apps, lassen sich
  nicht aufnehmen, und daran ändert FrameRush nichts.
- **Discord:** Das Fenster ist ein normales DX12-Fenster und sollte sich über
  „Bildschirm teilen → Anwendung/Fenster“ teilen lassen. **Noch nicht
  getestet.**

## Fehlerbehebung

| Symptom | Ursache und Lösung |
|---|---|
| `Eine Anwendungssteuerungsrichtlinie hat diese Datei blockiert (os error 4551)` beim Bauen | Windows Smart App Control blockiert lokal gebaute .exe-Dateien, auch Cargos Build-Skripte. Für Entwicklung abschalten: Windows-Sicherheit → App- & Browsersteuerung → Smart App Control → Aus. |
| `Zugriff verweigert (os error 5)` beim Ausführen von `build_script_build` | Der Virenscanner (hier Kaspersky) hält frisch gebaute .exe-Dateien für verdächtig, ein Fehlalarm. Ausnahme für den Ordner `FrameRush\target\` anlegen und neu bauen. |
| `no DX12 GPU adapter can present to this window` | Grafiktreiber aktualisieren, DX12-fähige GPU nötig |
| Warnung `present mode not supported, using Fifo` | Der gewünschte Modus wird von GPU oder Treiber nicht angeboten; FrameRush nimmt VSync |
| `could not read media types … device in use` | Eine andere App (OBS, Kamera-App, Discord) hält die Karte; die App schließen |
| FrameRush startet nicht, fehlende `MFPlat.dll` | Windows-N-Edition: „Media Feature Pack“ installieren |

## Doku

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): Aufbau, Threads,
  Latest-Frame-Mailbox, Present-Pfad und wo die Media-Foundation-Quelle
  andockt
- [CLAUDE.md](CLAUDE.md): Projektziele, Regeln und Meilensteine

## Lizenz

[MIT](../LICENSE)
