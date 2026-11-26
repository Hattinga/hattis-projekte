# FrameRush

Schlanker HDMI-Capture-Viewer für Windows mit möglichst wenig Latenz: zeigt
die PS5 über eine günstige USB-Capture-Karte in 1920×1080 bei 60 fps an,
spielt den Ton auf dem PC-Headset ab, und das Fenster lässt sich in Discord
teilen.

**Version 1.0.** Am 24.11.2026 mit der UGREEN-Karte („UGREEN 25854“) und
einer PS5 geprüft: Bild in 1920×1080 mit 60 fps, Ton im Headset, Vollbild,
USB oder HDMI abziehen und wieder anstecken (FrameRush verbindet sich von
selbst neu), Neustart mit gemerkter Karte, Fenster teilen in Discord.
**Nicht gemessen** ist die Ende-zu-Ende-Latenz (HDMI bis Bildschirm) und ein
Vergleich mit OBS. Null Latenz gibt es nicht: Die Karte puffert, USB
überträgt, Windows komponiert, und der Monitor baut das Bild auf.

## Benutzen

1. Zip entpacken, `FrameRush.exe` doppelklicken. Eine Installation ist nicht
   nötig.
2. Beim ersten Start listet FrameRush die Capture-Geräte auf: die Nummer der
   Karte drücken (bei der UGREEN-Karte „UGREEN 25854“). Ab dann öffnet
   FrameRush die Karte direkt.
3. **PS5:** HDCP ausschalten (Einstellungen → System → HDMI → HDCP
   aktivieren: aus), sonst bleibt das Bild schwarz. Geschützte Inhalte wie
   Streaming-Apps lassen sich nicht aufnehmen, daran ändert FrameRush nichts.
4. **Discord:** Bildschirm teilen → Anwendung → „FrameRush“.

Der Ton kommt aus dem Audio-Eingang der Karte („Digitale Audioschnittstelle
(UGREEN 25854)“) und geht auf die Windows-Standardausgabe. FrameRush nimmt
nur den Eingang, der nach der Karte benannt ist, und **nie** ein Mikrofon.

### Tasten

| Taste | Wirkung |
|---|---|
| F11 oder Alt+Enter | Vollbild an/aus (Esc verlässt es); im Vollbild verschwindet der Mauszeiger nach 2 s |
| M | Ton aus/an |
| + / − oder Pfeil hoch/runter | Lautstärke in 10-%-Schritten |
| O | Statistik-Overlay an/aus |
| D | anderes Capture-Gerät wählen |
| R | sofort neu verbinden (nach einem Fehler) |
| F1 | Tasten anzeigen |

Kurze Meldungen (Lautstärke, Ton aus, Gerät verbunden) erscheinen oben links
und verschwinden nach gut 2 s. Statusmeldungen, etwa „WAITING FOR … - NOT
CONNECTED“, bleiben stehen, solange das Problem besteht.

### Was FrameRush sich merkt

- **Einstellungen:** `%APPDATA%\FrameRush\settings.ini`: Gerät, Ton an/aus,
  Ausgabe, Lautstärke, stumm, Overlay, Vollbild, Fensterposition und
  -größe, maximiert. Datei löschen = alles zurücksetzen.
- **Log:** `%LOCALAPPDATA%\FrameRush\framerush.log`, der vorige Lauf steht in
  `framerush.old.log`. Bei Fehlern beim Start zeigt FrameRush ein
  Meldungsfenster mit dem Pfad.
- Solange FrameRush läuft, schaltet Windows den Bildschirm nicht ab. Am PC
  wird beim Spielen ja nichts bedient.

### Kommandozeile

Im Terminal funktionieren auch Optionen (`FrameRush.exe --help` zeigt alle):

```
FrameRush.exe --list-devices            # Video- und Audiogeräte mit Formaten
FrameRush.exe --device 25854            # dieses Gerät (Nummer oder Namensteil)
FrameRush.exe --audio-output "PRO X"    # andere Tonausgabe (Namensteil), "default" = Windows
FrameRush.exe --no-audio                # ohne Ton
FrameRush.exe --fullscreen --overlay
FrameRush.exe --synthetic               # Testbild ohne Gerät
FrameRush.exe --device 25854 --probe    # Video-Diagnose ohne Fenster (5 s)
FrameRush.exe --device 25854 --probe-audio   # Ton-Diagnose (5 s)
```

Ohne `--mode` nimmt FrameRush den besten NV12-Modus der Karte: die höchste
Bildrate bis 60 fps, dann das größte Bild. Bei der UGREEN-Karte ist das
1920×1080 @ 60.

## Voraussetzungen

- Windows 10/11 x64 mit einer DirectX-12-fähigen Grafikkarte
- Media Foundation. Fehlt bei Windows-„N“-Editionen ohne Media Feature Pack;
  ohne sie startet FrameRush nicht.
- Eine Capture-Karte, die Windows als Kamera erkennt (UVC) und NV12 anbietet

## Capture-Karte und Sicherheitssoftware

- **UGREEN 25854** (USB `VID_2B89&PID_5854`): NV12 und MJPG bis
  1920×1080 @ 60, YUY2 in 1080p nur mit 10 fps. Der NV12-Typ meldet BT.601
  Full Range, er entsteht also vermutlich in Windows aus MJPG. FrameRush
  liest Farbmatrix und Range aus dem Medientyp. Ohne HDMI-Signal liefert die
  Karte ein eigenes „No Signal“-Bild. Details:
  [docs/hardware-probe-2026-11-24.md](docs/hardware-probe-2026-11-24.md).
- **„UGREEN Camera 4K“** ist eine Webcam, nicht die Karte.
- **Kaspersky** sperrt auf dem Entwicklungs-PC den Kamera-Stream für das
  selbst gebaute Programm. Das Gerät öffnet sich, aber es kommen keine Bilder
  (Overlay „NO PICTURE FROM … FOR … S“). Mit ausgeschalteter
  „Programmüberwachung“ läuft alles. Eine Ausnahme nur für die Datei
  `framerush.exe` hat am 24.11. **nicht** gereicht.

## Was das Overlay zeigt (Taste O)

| Zeile | Bedeutung |
|---|---|
| `IN … FPS` | Frames pro Sekunde, die die Quelle liefert |
| `SHOWN … FPS` | neue Frames pro Sekunde, die tatsächlich präsentiert wurden |
| `DROPS MAILBOX` | Frames, die ein neuerer Frame ersetzt hat, bevor der Renderer sie abholte. Gewollt, so entsteht kein Rückstau |
| `DROPS SOURCE` | Lücken in den Zeitstempeln bzw. Sequenznummern der Quelle |
| `NOT SHOWN` | abgeholt, aber nicht präsentiert (Fenster minimiert, kein Swapchain-Bild) |
| `READY>TAKE` | Frame fertig → vom Renderer abgeholt, inklusive Warten auf das Swapchain-Bild |
| `READY>PRESENT` | Frame fertig → `present()` zurückgekehrt |
| `PRESENT INTERVAL` | Abstand zwischen zwei Presents, also die Gleichmäßigkeit der Bildfolge |
| `AUDIO > …` | Tonausgabe, Abtastrate, Puffer (Ziel ~30 ms), Aussetzer, Drift-Korrekturen (entfernte/doppelte Einzel-Frames) |

Alle Zeiten sind **Software-Zeitstempel** dieses Prozesses. Sie enthalten
weder Puffer und USB der Karte noch DWM, Scan-out oder Panel. Die echte
HDMI-zu-Photon-Latenz lässt sich nur mit Hochgeschwindigkeitskamera oder
Fotodiode messen.

## Messwerte

**Mit der Karte (24.11.2026):** UGREEN 25854, NV12 1920×1080 @ 60, PS5 mit
HDCP aus. Debug-Build, Fenster 1280×720, FIFO, Frame-Latenz 1. PS Remote Play
lief auf demselben PC, Kasperskys Programmüberwachung war aus. 10 s:

| Messgröße | Wert |
|---|---|
| rein / angezeigt | 590 / 587 Frames (60,0 / 60,0 fps) |
| Drops | Mailbox 2, Quelle 0 |
| Abstand der Gerätezeitstempel | 15,8–16,8 ms |
| Sample → dichter Frame (Kopie) | Mittel 0,47 ms, max 0,83 ms |
| ready → present | Mittel ~1,9 ms, max 2,5 ms |
| Present-Abstand | 16,0–17,6 ms |

Ton (`--probe-audio`, 6 s): Puffer 29–39 ms, keine Aussetzer, keine
Drift-Korrektur nötig.

„Ready“ ist der Zeitpunkt, an dem Media Foundation das Sample an FrameRush
übergibt. Puffer der Karte, USB, die vermutete MJPG-Dekodierung in Windows,
DWM, Scan-out und Panel fehlen darin. Das ist also **keine**
Ende-zu-Ende-Latenz.

**Prototyp mit Testbild (23.11.2026):** Debug-Build, Fenster 1280×720.
FIFO ~3 ms, Mailbox und Immediate ~2 ms ready→present bei 60/60 fps. Jeder
Lauf hatte beim Start einen Hänger von etwa 50 ms, und FIFO schwankt von Lauf
zu Lauf (der Takt der Quelle liegt zufällig zum VBlank).

## Fehlerbehebung

| Symptom | Ursache und Lösung |
|---|---|
| „NO PICTURE FROM … FOR … S“, die Windows-Kamera-App zeigt aber ein Bild; FrameRush lässt sich danach eventuell nicht beenden | Sicherheitssoftware sperrt den Kamera-Stream (siehe oben, Kaspersky). Für FrameRush freigeben bzw. die Programmüberwachung ausschalten. Hängende Reste verschwinden erst nach einem Neustart von Windows. |
| „WAITING FOR … - NOT CONNECTED“ | Die Karte ist nicht eingesteckt oder hat einen anderen Namen. Einstecken; FrameRush verbindet sich dann von selbst. Mit D ein anderes Gerät wählen. |
| „… BUSY“, `0xC00D3704` | Eine andere App hält die Karte (Kamera-App, OBS, Discord-Kamera). Die App schließen, dann R. Hilft das nicht, Windows neu starten. |
| Schwarzes Bild, PS5 läuft | HDCP an der PS5 ausschalten (siehe oben). |
| Kein Ton, Toast „NO AUDIO INPUT FOUND FOR …“ | Die Karte hat keinen Audio-Eingang mit ihrem Namen. `--list-devices` zeigt die Eingänge. |
| Ton auf dem falschen Gerät | Windows-Standardausgabe ändern, oder `--audio-output "<Namensteil>"` (wird gemerkt). |
| FrameRush startet nicht, fehlende `MFPlat.dll` | Windows-N-Edition: „Media Feature Pack“ installieren. |
| `no DX12 GPU adapter can present to this window` | Grafiktreiber aktualisieren, DX12-fähige GPU nötig. |

## Bauen

- [Rust](https://rustup.rs/) stable ≥ 1.88, Ziel `x86_64-pc-windows-msvc`
- Visual Studio 2022 Build Tools mit „Desktopentwicklung mit C++“:
  ```
  winget install Microsoft.VisualStudio.2022.BuildTools --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
  ```

```
cargo run                                  # Debug-Build mit Konsole
cargo run -- --synthetic --overlay         # Testbild mit Statistik
powershell -ExecutionPolicy Bypass -File scripts\package.ps1
                                           # Release: dist\FrameRush-<Version>\ und .zip
```

Der Release-Build ist eine Fensteranwendung ohne Konsolenfenster. Aus einem
Terminal gestartet, schreibt er `--help`, `--list-devices` und die Probes
trotzdem dorthin. `scripts\package.ps1` baut mit `cargo build --release`.
Scheitert das, weil Sicherheitssoftware die neuen Build-Skripte unter
`target\release` sperrt (so auf dem Entwicklungs-PC), baut das Skript
dasselbe optimierte Programm im Dev-Profil und verwendet dabei die
vorhandenen Build-Skripte weiter. Die Begründung steht im Skript.

Prüfungen wie in CLAUDE.md:

```
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
cargo test -- --ignored   # Media-Foundation-Test, öffnet kurz alle Kameras
```

Mehr Log: `$env:RUST_LOG="debug"`. `$env:FRAMERUSH_MF_LOW_LATENCY="1"` setzt
`MF_LOW_LATENCY` am Source Reader (standardmäßig aus, Wirkung nicht
gemessen).

| Fehler beim Bauen | Lösung |
|---|---|
| `os error 4551` (Anwendungssteuerungsrichtlinie) | Windows Smart App Control blockiert lokal gebaute .exe-Dateien: Windows-Sicherheit → App- & Browsersteuerung → Smart App Control → Aus. |
| `Zugriff verweigert (os error 5)` / `os error 32` bei `build_script_build` | Virenscanner (hier Kaspersky) sperrt frisch gebaute Build-Skripte. Ausnahme für `FrameRush\target\` anlegen; für das Paket greift sonst der Umweg in `scripts\package.ps1`. |

## Doku

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): Aufbau, Threads,
  Latest-Frame-Mailbox, Present-Pfad, Media Foundation, Ton, Wiederverbinden
- [docs/hardware-probe-2026-11-24.md](docs/hardware-probe-2026-11-24.md):
  Karte, Formate, Messläufe, Kaspersky
- [CLAUDE.md](CLAUDE.md): Projektziele, Regeln und Meilensteine

## Lizenz

MIT, siehe `LICENSE` (im Download-Ordner bzw. im Wurzelverzeichnis des
Repositorys).
