# clipd

Schlanker Clipper fürs Zocken. clipd nimmt den Bildschirm dauerhaft in einen
Ringpuffer auf und speichert auf Tastendruck die letzte halbe Minute — das, was
gerade passiert ist, nicht das, was gleich passieren wird.

Nur Windows, und es braucht eine Grafikkarte von NVIDIA oder AMD: aufgenommen
wird mit der Desktop Duplication API, kodiert wird auf der Grafikkarte — mit
NVENC oder AMF. Welche Karte es wird, findet clipd beim Start selbst heraus.

## Wie es funktioniert

```
ddagrab ──┬───────────────► hevc_nvenc ──┐
(Desktop  │                 (NVIDIA)     │
 Dupli-   └─► vpp_amf ────► hevc_amf ────┼─► seg00000001.ts, seg00000002.ts, …
 cation)      (nach nv12)   (AMD)        │   1 Sekunde pro Datei (Ring auf Platte)
                                         │          │
WASAPI-Loopback ──────────► aac ─────────┘          │
(was die Boxen spielen)                             ▼
                                   Hotkey ─► die neuesten Segmente
                                             aneinanderhängen (ohne neu zu
                                             kodieren) ─► clip-….mp4
```

Drei Dinge daran sind wichtiger, als sie aussehen:

- **Die Bilder bleiben auf der Grafikkarte.** `ddagrab` liefert D3D11-Bilder,
  und NVENC nimmt sie direkt entgegen. Es geht nichts über den PCIe-Bus zurück
  in den Hauptspeicher, und die CPU wandelt keine Farben um. NVENC macht aus dem
  BGRA des Desktops selbst yuv420p. AMF nimmt BGRA nicht an, deshalb wandelt
  bei AMD `vpp_amf` vorher um — ebenfalls auf dem Chip.
- **Ein Clip wird nicht neu kodiert.** Er hängt fertige Segmente aneinander und
  kopiert die Streams. Ein 30-Sekunden-Clip ist deshalb in Bruchteilen einer
  Sekunde geschrieben, egal wie lang er ist.
- **Den Ton holt clipd selbst.** ffmpeg kann unter Windows nicht mitschneiden,
  was die Boxen spielen — DirectShow kennt nur Mikrofone. clipd zapft deshalb
  WASAPI im Loopback-Modus an und schiebt die Samples in ffmpegs Eingabe.

## Benutzen

```
clipd run                     # nimmt auf und wartet auf den Hotkey
clipd run --monitor 1         # anderer Bildschirm
clipd run --gpu amd           # Karte festlegen statt ausprobieren
clipd run --no-audio          # nur Bild
clipd monitors                # zeigt, was aufgenommen werden kann
clipd audio                   # probiert jedes Wiedergabegerät auf Ton durch
clipd clip                    # speichert jetzt, aus einem anderen Fenster
clipd clip --secs 10          # kürzer als eingestellt
clipd config --init           # legt die config.toml an
```

`clipd run` läuft, bis man es mit Strg+C beendet. Der Hotkey (voreingestellt
`Strg+Alt+C`) gilt systemweit, das Spiel darf also im Vordergrund sein.

`clipd clip` speichert aus dem Puffer der laufenden Aufnahme und eignet sich
für ein Stream Deck oder eine zweite Tastenbelegung. Es benutzt die
Einstellungen, mit denen die Aufnahme gestartet wurde.

## Einstellungen

`config.toml` liegt neben der `clipd.exe` (oder unter `CLIPD_HOME`), die Clips
standardmäßig in `clips/`.

| Wert | Voreinstellung | Bedeutung |
|---|---|---|
| `monitor` | `0` | Bildschirm, wie ihn `clipd monitors` zählt |
| `fps` | `60` | Bildrate |
| `buffer_secs` | `120` | wie weit ein Clip zurückreichen kann |
| `segment_secs` | `1` | Länge einer Pufferdatei |
| `clip_secs` | `30` | was ein Tastendruck speichert |
| `gpu` | `auto` | `auto`, `nvidia` oder `amd`; `auto` probiert NVIDIA, dann AMD |
| `codec` | `hevc` | `h264`, `hevc` oder `av1` |
| `quality` | `22` | 0 (riesig) bis 51 (schlecht); bei AMD ein fester QP |
| `preset` | `p5` | `p1` (schnell) bis `p7` (beste Qualität); AMD kennt nur drei Stufen: p1–p2, p3–p5, p6–p7 |
| `audio` | `true` | nimmt mit auf, was die Boxen spielen |
| `audio_kbit` | `160` | AAC-Bitrate des Tons |
| `audio_device` | leer | Teil des Gerätenamens; leer heißt Standardgerät |
| `hotkey` | `Ctrl+Alt+C` | auch deutsch: `Strg+Umschalt+F9` |
| `out_dir` | leer | leer heißt `clips/` |

Der Puffer kostet Platz: 1080p60 mit HEVC und `quality = 22` sind rund
270 KB pro Sekunde, also etwa 32 MB für die voreingestellten 120 Sekunden.

## Was noch fehlt

- **Schneiden und Teilen.** Bisher speichert clipd nur ganze Clips.
- **Fenster.** clipd ist heute ein Programm fürs Terminal.

## Bekannte Eigenheiten

- **Ein Clip endet bis zu einer Sekunde vor dem Tastendruck.** ffmpeg gibt
  seine Ausgabe in Blöcken von 256 KiB an das Dateisystem weiter; weder
  `-flush_packets` noch `-avioflags direct` ändern daran etwas. Eine Sekunde
  Aufnahme ist etwa 270 KB groß, eine gerade offene Segmentdatei ist also
  entweder noch ganz leer oder schon 256 KiB lang. clipd nimmt mit, was da ist —
  deshalb ist ein Clip mal 5,00 und mal 5,62 Sekunden lang. Wer das nicht will,
  muss den Ring in den Arbeitsspeicher holen, statt ihn über Dateien zu führen.
- **Bei NVIDIA ist der Farbraum als BT.601 ausgezeichnet.** NVENC rechnet das
  BGRA des Desktops selbst nach yuv420p um und schreibt dazu `bt470bg` in die Datei.
  Das ist in sich stimmig — ein Testbild kommt Pixel für Pixel wieder heraus —
  aber für HD-Material ungewöhnlich. Wer eine Datei weiterverarbeitet, sollte
  die Auszeichnung nicht einfach auf BT.709 umschreiben. Bei AMD rechnet
  `vpp_amf` ausdrücklich nach BT.709 um, und so steht es auch in der Datei.
- **Nicht jede Karte kann jeden Codec.** AV1 etwa braucht eine neuere Karte.
  clipd probiert beim Start ein einzelnes Bild durch und nennt, woran es
  scheitert, statt mit leerem Buffer weiterzulaufen.
- **Der Ton ist, was man hört.** Der Loopback greift hinter dem
  Lautstärkeregler ab: Steht Windows auf 0 % oder ist stumm geschaltet, wird
  auch der Clip stumm.
- **AV1 landet in Matroska.** MPEG-TS trägt kein AV1. Dann ist auch das gerade
  offene Segment tabu, weil Matroska einen fehlenden Schluss nicht verzeiht.
- **Nicht jedes Wiedergabegerät kann Loopback.** Manche virtuellen Geräte —
  SteelSeries Sonar zum Beispiel — kehren aus
  `IAudioClient::Initialize` nie zurück, wenn man sie zum Mitschneiden öffnet.
  Deshalb wartet clipd nur begrenzt auf ein Gerät und nimmt danach ohne Ton
  auf, statt gar nicht. `clipd audio` probiert alle Geräte durch und nennt das,
  das in die `audio_device` gehört.
- **Ein Virenscanner sieht genauso aus.** Kaspersky hält `Initialize` an, bis
  jemand seine Rückfrage beantwortet — und jeder neue Build ist für ihn ein
  neues Programm, das er fragt. Eine Ausnahme für `target\` hilft beim
  Entwickeln.
- **Ein hängengebliebenes `Initialize` kann die Tonaufnahme lahmlegen** — und
  zwar für den ganzen Rechner, nicht nur für clipd. Danach scheitert jede
  Aufnahme mit `0x800706CC`, auch in anderen Programmen, während die Wiedergabe
  weiter läuft. Kurieren lässt sich das nur mit einem Neustart des Dienstes
  (als Administrator: `net stop audiosrv && net start audiosrv`) oder des
  Rechners.

## Entwicklung

`cargo run --example loopback_probe` prüft, ob WASAPI auf diesem Rechner
überhaupt einen Mitschnitt zulässt — Mikrofon und Loopback, in beiden
COM-Apartments. Das trennt einen Fehler in clipd von einem Rechner, auf dem
die Tonaufnahme gerade klemmt.

## Bauen

```
cargo build --release
cargo test
```

`ffmpeg.exe` und `ffprobe.exe` gehören nach `bin/` neben die `clipd.exe` (oder
in den PATH). Der Build muss `ddagrab` und NVENC oder AMF samt `vpp_amf`
können — die üblichen Windows-Builds von gyan.dev und BtbN können das.
