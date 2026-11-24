# FrameRush: Architektur

Stand: Meilenstein M2 (2026-11-24). Live-Vorschau von der UGREEN-Karte
(NV12 1080p60) über Media Foundation läuft; die synthetische Quelle bleibt
für Tests ohne Karte.

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

Zwei Threads, eine Übergabestelle. Der Capture-Thread wartet nie auf den
Renderer. Der Renderer bekommt immer den neuesten Frame, ältere werden
verworfen statt gepuffert.

## Module

| Datei | Aufgabe |
|---|---|
| `src/main.rs` | Logging, CLI-Auswertung, `--list-devices` |
| `src/probe.rs` | `--probe`: Gerät ohne Fenster öffnen, Medientyp, Puffer, Zeiten, Wertebereiche |
| `src/cli.rs` | Optionen (handgeschrieben, wenige Flags), mit Tests |
| `src/app.rs` | winit-`ApplicationHandler`: Fenster, Tasten, Weckrufe, Statistik-Takt |
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

## Fehler und Beenden

- Fehler beim Start (Fenster, GPU, Thread) beenden das Programm mit einer
  Meldung und Exit-Code 1.
- Fehler der Quelle zur Laufzeit kommen als `CaptureEvent::Failed` an. Das
  Fenster bleibt offen und zeigt den Fehler im Overlay.
- Beim Schließen stoppt `exiting()` den Capture-Thread und wartet höchstens
  2 s auf ihn (`CaptureHandle::stop`), danach steht die Endstatistik im Log.
  Hängt das Gerät beim Schließen, bleibt der Thread zurück, und im Log steht
  ein Fehler. Getestet mit einer Quelle, deren Abbau absichtlich hängt.
- Device-Lost der GPU wird nur geloggt. Ein Neuaufbau ist offen (M5).

## Mit Hardware geprüft (2026-11-24)

- NV12 1920×1080 @ 60 von der UGREEN 25854: 60 fps, keine Lücken laut
  Zeitstempel, Puffer ohne Padding, Farbraum BT.601 Full aus dem Medientyp.
  Das PS5-Bild sah im Screenshot natürlich aus. Gemessen ist der Farbraum
  damit nicht.
- Ohne HDMI-Signal liefert die Karte ihr eigenes „No Signal“-Bild.

## Noch nicht geprüft

- USB-Modus der Karte und ob NV12 wirklich aus MJPG dekodiert wird
- echte HDMI-zu-Photon-Latenz; dafür braucht es Kamera oder Fotodiode
- Vergleich mit OBS/PotPlayer unter gleichen Bedingungen
- Abziehen und Wiederanstecken während der Aufnahme, Standby mit laufender
  Karte
- Betrieb mit eingeschaltetem Kaspersky und einer Ausnahme für FrameRush
- Teilen in Discord (Fenster teilen)
- Ton (M4)
