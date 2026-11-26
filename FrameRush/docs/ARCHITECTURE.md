# FrameRush: Architektur

Stand: Version 1.0 (2026-11-24).
- Live-Vorschau von der UGREEN-Karte (NV12 1080p60) über Media Foundation
- Ton über WASAPI
- Geräteauswahl, Wiederverbinden und gemerkte Einstellungen
- Release-Paket

Die synthetische Quelle bleibt für Tests ohne Karte. Ende-zu-Ende-Latenz
(M3) ist bewusst nicht gemessen.

## Überblick

```
 Capture-Thread                         Haupt-Thread (winit-Eventloop)
 ──────────────                         ──────────────────────────────
 VideoSource::next_frame()
   │  (Synthetic: Testbild rendern,
   │   bis zur Deadline warten)
   ▼
 Mailbox::publish(frame) ──────────┐
   │ Stored? (leer → voll)         │ Slot (Kapazität 1)
   ▼                               │
 proxy.send_event(FrameReady) ───► on_frame_ready()
                                     1. renderer.acquire()     ← hier wartet FIFO/VSync
                                     2. mailbox.take()         ← immer der neueste Frame
                                     3. upload_frame()         ← write_texture je Plane
                                     4. draw_and_present()     ← NV12→RGB, Letterbox, Overlay
                                     5. metrics.record_shown()
```

Für das Video gibt es zwei Threads und eine Übergabestelle. Der
Capture-Thread wartet nie auf den Renderer. Der Renderer bekommt immer den
neuesten Frame, ältere werden verworfen statt gepuffert. Der Ton läuft auf
einem dritten, eigenen Thread (siehe „Ton“).

## Module

| Datei | Aufgabe |
|---|---|
| `src/main.rs` | Logging (Konsole und Datei), Panic-Hook, CLI-Auswertung, `--list-devices` |
| `src/probe.rs` | `--probe` und `--probe-audio`: Gerät ohne Fenster öffnen und Diagnose ausgeben |
| `src/cli.rs` | Optionen (handgeschrieben, wenige Flags), mit Tests |
| `src/app.rs` | winit-`ApplicationHandler`: Fenster, Tasten, Verbindungszustand, Geräteauswahl, Toasts, Ton-Anbindung |
| `src/settings.rs` | gemerkte Einstellungen (`settings.ini`), mit Tests |
| `src/platform.rs` | Bildschirm wachhalten, Konsole des Release-Builds, Fehlerdialog, Fenster-Icon |
| `src/audio/mod.rs` | `AudioHandle`, `PlayoutBuffer` mit Drift-Ausgleich, mit Tests |
| `src/audio/wasapi.rs` | WASAPI: Endpunkte finden, Aufnahme → Wiedergabe, Neuverbinden |
| `src/capture/mod.rs` | `Frame`, `PixelFormat`, `VideoMode`, `VideoSource`-Trait, Capture-Thread |
| `src/capture/mailbox.rs` | Latest-Frame-Mailbox mit Weck-Vertrag, mit Tests |
| `src/capture/synthetic.rs` | synthetische Quelle mit Testbild und Takt, mit Tests |
| `src/capture/media_foundation.rs` | MF-Geräte, gemeldete Medientypen und alle Attribute auflisten, COM/MF-Sitzung |
| `src/capture/media_foundation/source.rs` | `MediaFoundationSource`: asynchroner Source Reader, NV12-Kopie, Farbraum, mit Tests |
| `src/render/mod.rs` | wgpu/DX12: Surface, Pipelines, Upload, Present, Letterbox |
| `src/render/*.wgsl` | Fullscreen-Dreieck, BGRA- und NV12-Shader, Overlay |
| `src/metrics.rs` | FPS, Drops, Software-Zeiten |
| `src/font.rs` | 5×7-Bitmap-Font für Testbild und Overlay |
| `src/error.rs` | `AppError` mit Meldungen für Nutzer |

## Latest-Frame-Mailbox

`Mailbox<T>` hält höchstens **ein** Element (`Mutex<Option<T>>` plus Zähler).

- `publish` ersetzt ein noch nicht abgeholtes Element und zählt es als
  `replaced`. Der alte Frame wird erst nach dem Lock freigegeben.
- `publish` meldet `Stored` genau dann, wenn der Slot von leer auf voll
  wechselt. Nur dann weckt der Capture-Thread den Renderer.
- Vertrag: Der Renderer ruft `take` nur als Antwort auf einen Weckruf auf,
  genau einmal pro Weckruf. Dann ist höchstens ein Weckruf unterwegs, und
  jeder Weckruf findet einen Frame.

Warum der Vertrag wichtig ist: winits `EventLoopProxy` nutzt intern einen
unbeschränkten Kanal. Ein Weckruf pro Frame würde bei hängendem Eventloop
eine Warteschlange aufbauen, die Mailbox selbst bliebe zwar klein. Der Test
`concurrent_handoff_keeps_order_and_bounds_wakes` prüft das mit einem
Weckkanal der Kapazität 1: 50 000 Frames, Reihenfolge streng steigend, und
`published == taken + replaced`.

Resize, Expose und Overlay-Umschalten präsentieren deshalb die **vorhandene**
Textur neu und nehmen nichts aus der Mailbox.

## Present-Pfad

1. **Erst `acquire`, dann `take`.** `Surface::get_current_texture` blockiert
   je nach Present-Modus und `desired_maximum_frame_latency`, bei FIFO bis
   zum nächsten VBlank. Wer vorher den Frame nimmt, zeigt einen Frame, der
   während des Wartens veraltet ist.
2. **Frame-Latenz 1** (Standard, `--frame-latency 1..3`): DX12
   `SetMaximumFrameLatency(1)`, also höchstens ein Bild in der Warteschlange.
   Die GPU-Last ist winzig, deshalb kostet das keinen Durchsatz.
3. **Present-Modi** (`--present-mode`): `fifo` (VSync, kein Tearing),
   `mailbox` (neuestes Bild ersetzt ein wartendes, kein Tearing), `immediate`
   (sofort, kann reißen). wgpu meldet auf diesem PC für DX12 alle drei. Ein
   nicht angebotener Modus fällt mit Warnung auf FIFO zurück. Welcher Modus
   mit der echten Karte am besten ist, wird in M3 gemessen, nicht vorab
   festgelegt.
4. **Upload:** `Queue::write_texture`, eine Textur pro Plane: NV12 als
   `R8Unorm` (Y) plus `Rg8Unorm` (CbCr in halber Auflösung), BGRA als
   `Bgra8Unorm`. Die Farbumrechnung passiert im Fragment-Shader. Pro Frame
   gehen 3,1 MB (NV12) über PCIe. Zero-Copy, D3D11-Interop und
   Puffer-Recycling kommen erst nach dem Profiling mit echter Hardware (M3).
5. **Farbe:** NV12 wird als BT.709, Limited Range interpretiert. Die
   Swapchain ist bevorzugt `Bgra8Unorm` ohne sRGB, sodass die gamma-kodierten
   Videowerte unverändert durchgehen. Bei einer sRGB-Swapchain linearisiert
   der Shader vorher.
6. **Letterbox** über den Viewport, auf ganze Pixel gerundet. 1080p auf einem
   1080p-Vollbild wird also 1:1 abgebildet.

### Backend: nur DX12

wgpu ist ohne Vulkan, GL und Metal gebaut. Die Gründe:

- DX12 ist unter Windows das native Backend, mit DXGI-Flip-Model-Swapchain.
  wgpu-hal schaltet DXGIs eigenes Alt+Enter dabei ab.
- Auf dem Entwicklungs-PC hat der Virenscanner das Build-Skript von `ash`
  (Vulkan-Bindings) direkt nach dem Linken gelöscht.
- Weniger Abhängigkeiten heißt kürzere Build-Zeit.

## Synthetische Quelle

- Takt nach absoluten Deadlines: `start + n · Periode`, mit Bruch-Frameraten
  wie 60000/1001 ohne Drift. Die Quelle rendert den Frame, wartet bis zu
  seinem Slot und gibt ihn frei. Dieses Warten simuliert den Takt der
  Hardware; einen festen Sleep im Videopfad gibt es nicht. Liegt der Thread
  zurück, überspringt er verpasste Slots, statt sie in einem Schwall
  nachzuliefern. Die übersprungenen Slots zählen als `DROPS SOURCE`.
- Das Testbild wird zum größten Teil einmal vorberechnet. Pro Frame kommen
  eine Kopie (3,1 MB bei NV12) und ein paar Rechtecke dazu.
- Inhalt: Frame-Zähler und Zeitstempel oben rechts (das Overlay sitzt oben
  links), ein Balken, der 16 px pro Frame wandert und Judder oder Tearing
  sichtbar macht, eine Frame-Uhr aus 60 Zellen (`frame % 60`), 75-%-Farbbalken
  und ein Graukeil für die YUV-Prüfung.

## Media Foundation

Stand 2026-11-24: Live-Vorschau mit der UGREEN 25854 in NV12 1080p60 geprüft
(siehe
[hardware-probe-2026-11-24.md](hardware-probe-2026-11-24.md)).

**Geräte auflisten** (`--list-devices`, `media_foundation.rs`):

- `MFEnumDeviceSources` mit Video-Capture-Filter: Name und symbolischer Link.
- Für jedes Gerät `ActivateObject` → `IMFSourceReader` →
  `GetNativeMediaType` bis `MF_E_NO_MORE_TYPES`: Subtype, Größe, Framerate.
- `dump_attributes` gibt alle Attribute eines Medientyps aus, unbekannte als
  GUID.
- Jeder Thread mit MF-Objekten initialisiert COM im MTA (`MfSession`). Der
  winit-Thread initialisiert OLE als STA und darf nicht umgeschaltet werden.

**Aufnehmen** (`media_foundation/source.rs`, `MediaFoundationSource`):

- Wird in der `SourceFactory` auf dem Capture-Thread erzeugt, weil die
  windows-rs-COM-Typen nicht `Send` sind.
- Gerät per Nummer oder Namensteil (`DeviceSelector`), Modus per Nummer oder
  passend zu Größe, Format und Bildrate (`ModeSelector`). Nur gemeldete
  native Typen, `MF_READWRITE_DISABLE_CONVERTERS`; der Viewer nimmt nur NV12.
- `IMFSourceReader` im asynchronen Modus. Es ist immer genau ein
  `ReadSample` unterwegs. `next_frame` wartet höchstens 200 ms und gibt
  sonst `Ok(None)` zurück, damit ein Stopp auch ohne Signal ankommt.
- Puffer: `IMF2DBuffer2::Lock2DSize` → Pitch und Länge; die CbCr-Ebene liegt
  hinter den *allokierten* Y-Zeilen (z. B. 1088 statt 1080), zeilenweise in
  das dichte `Frame`-Layout kopiert. Ohne 2D-Schnittstelle:
  `MF_MT_DEFAULT_STRIDE`.
- Farbe: `MF_MT_YUV_MATRIX` und `MF_MT_VIDEO_NOMINAL_RANGE` →
  `Frame::color` → Uniform im NV12-Shader (BT.601/BT.709, Limited/Full).
  Fehlen die Angaben: BT.601 bis 576 Zeilen, sonst BT.709, Limited Range.
- Sequenznummern aus den Zeitstempeln der Samples, damit Lücken als
  `DROPS SOURCE` sichtbar werden.
- Abbau: `Flush` → auf `OnFlush` warten → Reader freigeben → Quelle
  `Shutdown` → `MFShutdown`. Das Freigeben des Readers hing, solange
  Kaspersky den Stream sperrte (siehe Befund). Deshalb wartet
  `CaptureHandle::stop` höchstens 2 s und lässt den Thread dann zurück,
  statt das Fenster einzufrieren.
- `--probe` öffnet das Gerät genauso, aber ohne Fenster, auf einem eigenen
  Thread mit begrenztem Warten. Es zählt auch YUY2 und MJPG.

**Offen:** Neu-Öffnen nach Abziehen, Belegung oder Standby (heute: Fehler
im Overlay); Latenzvergleich NV12 (vermutlich von Windows aus MJPG
dekodiert) gegen MJPG mit eigener Dekodierung (M3).

## Verbindung, Geräteauswahl und Einstellungen (`app.rs`, `settings.rs`)

- **Ziel:** `--synthetic`, `--device` oder, ohne beides, das in
  `%APPDATA%\FrameRush\settings.ini` gemerkte Gerät. Gibt es keins, zeigt
  das Fenster eine Auswahl. Sie listet nur Namen
  (`list_device_names`, kein `ActivateObject`), damit keine Webcam-LED
  angeht. Gemerkt wird der Name, den das Gerät beim Öffnen meldet, nie die
  Nummer.
- **Zustände:** `Idle` → `Connecting` → `Live`, bei Fehlern `Retrying` oder
  `Stuck`. Jeder Verbindungsversuch startet einen neuen Capture-Thread mit
  einer Generationsnummer. `Opened`/`Failed` eines ersetzten Threads werden
  ignoriert, `FrameReady` dagegen immer verarbeitet, denn der Weck-Vertrag
  der Mailbox verlangt ein `take` pro Weckruf.
- **Neu verbinden** nur nach `CaptureEvent::Failed`, nie wegen ausbleibender
  Bilder. Eine Quelle, die nichts liefert (gesperrter Stream), würde sonst
  Thread um Thread im Treiber festsetzen.
  - nicht gefunden (`NotFound`): alle 2 s; dabei wird nichts geöffnet
  - belegt (`Busy`, 0xC00D3704): Backoff, nach 3 Fehlschlägen `Stuck`, bis R
    gedrückt wird
  - nicht unterstützter Modus: `Stuck`
  - sonst: Backoff 2, 4, 8, 10 s; nach 10 s stabilem Betrieb wieder ab 2 s
- Alte Capture-Threads werden ohne Warten zurückgelassen
  (`request_stop`, `try_join` im Sekundentakt). Der UI-Thread blockiert nie
  auf das Schließen eines Geräts.
- **UI:** Statuszeilen (Verbinden, Warten, Fehler, „keine Bilder“) sind
  immer sichtbar, Toasts 2,5 s, die Statistik nur mit O. Im Vollbild
  verschwindet der Mauszeiger nach 2 s Ruhe. Solange FrameRush läuft, sorgt
  `SetThreadExecutionState(ES_DISPLAY_REQUIRED)` dafür, dass der Bildschirm
  an bleibt.
- **Einstellungen:** `key = value`, von Hand geparst. Unbekannte Schlüssel
  und kaputte Werte ergeben Warnungen und Standardwerte. Geschrieben wird
  über eine temporäre Datei und `rename`, beim Öffnen eines Geräts und beim
  Beenden (Fenster, Vollbild, maximiert, Lautstärke, stumm, Overlay).

## Ton (`audio/`)

```
 Audio-Thread (COM MTA, ein Thread für beide Streams)
   WaitForMultipleObjects([Capture-Event, Render-Event], 200 ms)
     Capture: alle Pakete → PlayoutBuffer (f32 Stereo)
     Render:  freier Platz ← PlayoutBuffer.pull(gain)
```

- **Eingang:** der Aufnahme-Endpunkt, dessen Name den Videogerätenamen
  enthält, z. B. „Digitale Audioschnittstelle (UGREEN 25854)“. Es gibt
  **keinen** Rückfall auf das Standard-Aufnahmegerät, auf dem
  Entwicklungs-PC wäre das eins von fünf Mikrofonen.
- **Ausgang:** die Windows-Standardausgabe oder `--audio-output`
  (Namensteil, wird gemerkt).
- **Format:** Beide Streams laufen in 32-bit float Stereo mit der Mix-Rate
  der Ausgabe (auf dem Entwicklungs-PC 96 kHz), mit `AUTOCONVERTPCM`. Windows
  rechnet also um, FrameRush braucht keinen eigenen Resampler.
- **`PlayoutBuffer`:**
  - Ziel 30 ms
  - Wiedergabe beginnt erst, wenn das Ziel erreicht ist; Unterlauf ergibt
    Stille und ein neues Vorpuffern
  - geglätteter Füllstand über Ziel + 10 ms: ein Frame von 500 fällt weg;
    unter Ziel − 10 ms: einer wird wiederholt (maximal 0,2 %, Taktdrift
    üblicher Geräte liegt weit darunter)
  - mehr als das Fünffache des Ziels (nach einem Hänger): sofort aufs Ziel
    gekürzt
  - Getestet mit simulierter Drift von ±0,1 %.
- **Fehler** (Abziehen, Ausgabe weg): neuer Versuch mit Backoff, fehlender
  Eingang alle 3 s. Lautstärke (quadratische Kurve) und Stumm über Atomics,
  ohne Neustart. Stoppen höchstens 2 s, wie beim Video.

## Release-Hülle (`main.rs`, `platform.rs`)

- Release-Builds sind eine Fensteranwendung
  (`windows_subsystem = "windows"`). Aus einem Terminal gestartet, hängen sie
  sich mit `AttachConsole(ATTACH_PARENT_PROCESS)` an dessen Konsole.
- Log in `%LOCALAPPDATA%\FrameRush\framerush.log`, der vorige Lauf in
  `framerush.old.log`. Startfehler und Panics zeigen ohne Konsole ein
  Meldungsfenster mit dem Log-Pfad.
- `scripts\package.ps1` baut `dist\FrameRush-<Version>\` und die Zip-Datei.
  Scheitert `--release` an gesperrten Build-Skripten, nimmt es den
  optimierten Dev-Profil-Build (Begründung im Skript).
- **Icon:** `assets\framerush.ico` (gezeichnet von `scripts\make-icon.ps1`)
  wird über `assets\framerush.rc` mit `rc.exe` zur `.res` kompiliert und per
  `cargo rustc -- -C link-arg=…` nur in FrameRush.exe gelinkt. Bewusst ohne
  `build.rs`, denn ein weiteres neues Build-Skript würde Kaspersky sperren.
  Der Dateiname der `.res` enthält ihren Hash, damit Cargo nach einer
  Icon-Änderung neu linkt. Windows nimmt das EXE-Icon nicht von selbst fürs
  Fenster, daher lädt `platform::set_window_icon` es (16/32 px × Skalierung)
  für Titelleiste und Taskleiste. Builds ohne Ressource (`cargo run`)
  behalten das Standardsymbol.
- `scripts\install.ps1` installiert pro Benutzer nach
  `%LOCALAPPDATA%\Programs\FrameRush\` und legt Verknüpfungen im Startmenü
  (Windows-Suche) und auf dem Desktop an; `-Uninstall` entfernt beides.

## Fehler und Beenden

- Fehler beim Start (Fenster, GPU) beenden das Programm mit einer Meldung
  (Release: Meldungsfenster) und Exit-Code 1.
- Fehler der Quelle zur Laufzeit kommen als `CaptureEvent::Failed` an und
  führen zum Neuverbinden (siehe oben). Das Fenster bleibt offen.
- Beim Schließen: Einstellungen speichern, Ton und Capture höchstens je 2 s
  stoppen, alte Threads nur anstoßen, `ES_CONTINUOUS` zurücksetzen,
  Endstatistik ins Log. Das zeitbegrenzte Stoppen ist mit einer Quelle
  getestet, deren Abbau absichtlich hängt.
- Device-Lost der GPU wird nur geloggt. Ein Neuaufbau ist offen.

## Mit Hardware geprüft (2026-11-24, UGREEN 25854 + PS5)

- NV12 1920×1080 @ 60: 60 fps, keine Lücken laut Zeitstempel, Puffer ohne
  Padding, Farbraum BT.601 Full aus dem Medientyp. Das PS5-Bild sah im
  Screenshot natürlich aus. Gemessen ist der Farbraum damit nicht.
- Ohne HDMI-Signal liefert die Karte ihr eigenes „No Signal“-Bild.
- Ton im Headset klar (Nutzer), Puffer 29–39 ms, keine Aussetzer.
- Vom Nutzer mit dem Paket (`dist\FrameRush-1.0.0\FrameRush.exe`) geprüft:
  - Vollbild und Ausblenden des Mauszeigers
  - USB und HDMI ab und wieder an: verbindet sich von selbst neu
  - Neustart mit gemerktem Gerät
  - Teilen des Fensters in Discord

## Noch nicht geprüft

- echte HDMI-zu-Photon-Latenz und ein Vergleich mit OBS/PotPlayer (bewusst
  zurückgestellt)
- Standby/Ruhezustand des PCs mit laufender Karte
- Betrieb mit eingeschalteter Kaspersky-Programmüberwachung und einer
  wirksamen Freigabe; eine Datei-Ausnahme reichte nicht
- USB-Modus der Karte und ob NV12 wirklich aus MJPG dekodiert wird
