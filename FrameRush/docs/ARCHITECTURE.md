# FrameRush: Architektur

Stand: Meilenstein M0, Prototyp mit synthetischer Quelle (2026-11-23).

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
| `src/cli.rs` | Optionen (handgeschrieben, wenige Flags), mit Tests |
| `src/app.rs` | winit-`ApplicationHandler`: Fenster, Tasten, Weckrufe, Statistik-Takt |
| `src/capture/mod.rs` | `Frame`, `PixelFormat`, `VideoMode`, `VideoSource`-Trait, Capture-Thread |
| `src/capture/mailbox.rs` | Latest-Frame-Mailbox mit Weck-Vertrag, mit Tests |
| `src/capture/synthetic.rs` | synthetische Quelle mit Testbild und Takt, mit Tests |
| `src/capture/media_foundation.rs` | MF-Geräte und gemeldete Medientypen auflisten, nur lesend |
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

## Media Foundation: was da ist und was fehlt

**Vorhanden** (`--list-devices`, nur lesend):

- `MFEnumDeviceSources` mit Video-Capture-Filter: Name und symbolischer Link.
- Für jedes Gerät `ActivateObject` → `IMFSourceReader` →
  `GetNativeMediaType` bis `MF_E_NO_MORE_TYPES`: Subtype, Größe, Framerate.
- Läuft auf einem eigenen Thread mit COM im MTA. Der winit-Thread
  initialisiert OLE als STA und darf nicht umgeschaltet werden.
- Erster Befund mit der echten Karte:
  [hardware-probe-2026-11-23.md](hardware-probe-2026-11-23.md).

**Bewusst noch nicht implementiert** (M2, braucht die echte Karte zum
Prüfen):

- `MediaFoundationSource: VideoSource`. Sie wird in der `SourceFactory` auf
  dem Capture-Thread erzeugt, das ist schon so verdrahtet, weil die
  windows-rs-COM-Typen nicht `Send` sind.
- Medientyp wählen: einen der *gemeldeten* nativen Typen mit
  `SetCurrentMediaType`, bevorzugt NV12, damit der vorhandene Renderpfad
  passt. Nichts davon wird vorab angenommen.
- `ReadSample` lesen, Puffer mit `IMF2DBuffer::Lock2D` (Stride oder Padding)
  in das dichte `Frame`-Layout kopieren oder Stride im Renderer unterstützen.
- Matrix und Range aus `MF_MT_YUV_MATRIX` und `MF_MT_VIDEO_NOMINAL_RANGE`
  lesen. Der Shader nimmt im Moment fest BT.709 Limited an.
- Stoppen: `ReadSample` blockiert. Beenden über `IMFMediaSource::Shutdown`
  oder den asynchronen Callback-Modus.
- Abziehen und Wiederanstecken, Gerät belegt, Standby: Fehler aus
  `ReadSample` → `CaptureEvent::Failed` (gibt es schon) → neu öffnen.

## Fehler und Beenden

- Fehler beim Start (Fenster, GPU, Thread) beenden das Programm mit einer
  Meldung und Exit-Code 1.
- Fehler der Quelle zur Laufzeit kommen als `CaptureEvent::Failed` an. Das
  Fenster bleibt offen und zeigt den Fehler im Overlay.
- Beim Schließen stoppt `exiting()` den Capture-Thread und wartet auf ihn
  (`join`), danach steht die Endstatistik im Log.
- Device-Lost der GPU wird nur geloggt. Ein Neuaufbau ist offen (M5).

## Ohne Hardware nicht prüfbar

- Ob die UGREEN-Karte die gemeldeten Formate (z. B. NV12 1080p60) wirklich
  liefert, und mit welcher Bildrate, welchem USB-Modus und welcher Latenz
- echte HDMI-zu-Photon-Latenz; dafür braucht es Kamera oder Fotodiode
- Vergleich mit OBS/PotPlayer unter gleichen Bedingungen
- Farbmatrix und Range des echten Signals
- Abziehen und Wiederanstecken, Gerät von einer anderen App belegt, Standby
  mit laufender Karte
- Teilen in Discord (Fenster teilen); geht ohne Discord-Sitzung nicht
- Ton (M4)
