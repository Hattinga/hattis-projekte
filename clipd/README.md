# clipd

Schlanker Clipper fürs Zocken. clipd nimmt den Bildschirm dauerhaft in einen
Ringpuffer auf und speichert auf Tastendruck die letzte halbe Minute — das, was
gerade passiert ist, nicht das, was gleich passieren wird.

Nur Windows, und es braucht eine Grafikkarte von NVIDIA oder AMD: aufgenommen
wird mit der Desktop Duplication API, kodiert wird auf der Grafikkarte — mit
NVENC oder AMF. Welche Karte es wird, findet clipd beim Start selbst heraus.

## Wie es funktioniert

```
ddagrab ──┬───────────────► h264_nvenc ──┐
(Desktop  │                 (NVIDIA)     │   MPEG-TS über stdout
 Dupli-   └─► vpp_amf ────► h264_amf ────┼─► Ring im Arbeitsspeicher,
 cation)      (nach nv12)   (AMD)        │   an jedem Keyframe geteilt
                                         │          │
WASAPI-Loopback ──────────► aac ─────────┘          │
(was die Boxen spielen)                             ▼
                                   Hotkey ─► die neuesten Stücke am Stück
                                             ins MP4 (ohne neu zu
                                             kodieren) ─► clip-….mp4
```

Drei Dinge daran sind wichtiger, als sie aussehen:

- **Die Bilder bleiben auf der Grafikkarte.** `ddagrab` liefert D3D11-Bilder,
  und NVENC nimmt sie direkt entgegen. Es geht nichts über den PCIe-Bus zurück
  in den Hauptspeicher, und die CPU wandelt keine Farben um. NVENC macht aus dem
  BGRA des Desktops selbst yuv420p. AMF nimmt BGRA nicht an, deshalb wandelt
  bei AMD `vpp_amf` vorher um — ebenfalls auf dem Chip.
- **Ein Clip wird nicht neu kodiert und reicht bis zum Tastendruck.** Der
  Ring liegt im Arbeitsspeicher, ein Clip ist einfach ein zusammenhängendes
  Stück davon ab einem Keyframe, das ffmpeg ohne neues Kodieren in ein MP4
  packt. 30 Sekunden sind in Bruchteilen einer Sekunde geschrieben. Der Ring
  kostet so viel Arbeitsspeicher, wie er Sekunden hält: bei 60 s rund 12 bis
  25 MB.
- **Den Ton holt clipd selbst.** ffmpeg kann unter Windows nicht mitschneiden,
  was die Boxen spielen — DirectShow kennt nur Mikrofone. clipd zapft deshalb
  WASAPI im Loopback-Modus an und schiebt die Samples in ffmpegs Eingabe.

## Das Fenster

`clipd-app.exe` ist clipd mit Oberfläche. Es nimmt im Hintergrund auf, auch
wenn das Fenster zu ist — dann sitzt es im Infobereich neben der Uhr.

- **Bibliothek:** alle Clips mit Vorschaubild, links nach Spiel sortiert.
- **Schneiden:** Anfang und Ende am gelben Rahmen ziehen (oder `I` und `O`
  drücken), dann *Zuschneiden*. Das Stück wird auf der Grafikkarte neu
  kodiert und ist aufs Bild genau.
- **Für Discord:** macht aus der Auswahl eine H.264-Datei unter 10 MB mit
  einer Tonspur und legt sie in die Zwischenablage — in Discord mit Strg+V
  einfügen. Mit einem Webhook in den Einstellungen schickt *An Discord
  senden* sie gleich selbst in den Kanal.
- **Mehr:** als GIF (15 fps, 480 px breit) oder im Hochformat 9:16 für
  TikTok und Shorts.
- **Favoriten:** Ein Stern schützt einen Clip vor dem Aufräumen, das auf
  Wunsch alte Clips oder alles über einem Speicherlimit löscht.
- **Ton:** Spiel und Mikrofon lassen sich getrennt leiser, lauter oder stumm
  stellen, bevor man speichert.
- **Einstellungen** (Strg+,): Bildschirm, Qualität, Format, Clip-Länge,
  Geräte, Tastenkürzel, Start mit Windows.

Beide Programme teilen sich `config.toml`, `clips/` und `bin/`. Es sollte nur
eines von beiden aufnehmen.

## Benutzen im Terminal

```
clipd run                     # nimmt auf und wartet auf den Hotkey
clipd run --monitor 1         # anderer Bildschirm
clipd run --gpu amd           # Karte festlegen statt ausprobieren
clipd run --no-audio          # nur Bild
clipd run --mic               # Mikrofon als eigene Tonspur
clipd monitors                # zeigt, was aufgenommen werden kann
clipd audio                   # probiert jedes Wiedergabegerät auf Ton durch
clipd clip                    # speichert jetzt, aus einem anderen Fenster
clipd clip --secs 10          # kürzer als eingestellt
clipd record                  # Aufnahme beliebiger Länge starten/beenden
clipd export clip.mp4 --start 3 --end 12   # zuschneiden
clipd export clip.mp4 --discord --mic 0     # unter 10 MB, ohne Mikrofon
clipd config --init           # legt die config.toml an
```

`clipd run` läuft, bis man es mit Strg+C beendet. Die Hotkeys gelten
systemweit, das Spiel darf also im Vordergrund sein: `Strg+Alt+C` speichert
die letzten 30 Sekunden, `Strg+Alt+R` startet eine Aufnahme beliebiger Länge
und beendet sie wieder. Jeder Clip landet im Ordner des Spiels, das gerade
vorne war (`clips/Valorant/…`); ein Fenster, das nicht den ganzen Bildschirm
füllt, zählt als `Desktop`.

`clipd clip` und `clipd record` sprechen über eine Named Pipe mit dem
clipd, das gerade aufnimmt — egal ob Terminal oder Fenster — und eignen sich
für ein Stream Deck oder eine zweite Tastenbelegung. Sie benutzen die
Einstellungen, mit denen die Aufnahme gestartet wurde.

## Einstellungen

`config.toml` liegt neben der `clipd.exe` (oder unter `CLIPD_HOME`), die Clips
standardmäßig in `clips/`.

| Wert | Voreinstellung | Bedeutung |
|---|---|---|
| `monitor` | `0` | Bildschirm, wie ihn `clipd monitors` zählt |
| `fps` | `60` | Bildrate |
| `buffer_secs` | `60` | wie weit ein Clip zurückreichen kann |
| `segment_secs` | `1` | Abstand der Keyframes; so genau hält ein Clip seine Länge |
| `clip_secs` | `30` | was ein Tastendruck speichert |
| `capture` | `screen` | `game` nimmt, solange ein Spiel im Vollbild vorne ist, nur dessen Fenster auf — was darüber aufpoppt, landet in keinem Clip |
| `gpu` | `auto` | `auto`, `nvidia` oder `amd`; `auto` probiert NVIDIA, dann AMD |
| `codec` | `h264` | `h264` oder `hevc`; nur H.264 spielt das Fenster selbst ab |
| `quality` | `22` | 0 (riesig) bis 51 (schlecht); bei AMD ein fester QP |
| `preset` | `p5` | `p1` (schnell) bis `p7` (beste Qualität); AMD kennt nur drei Stufen: p1–p2, p3–p5, p6–p7 |
| `audio` | `true` | nimmt mit auf, was die Boxen spielen |
| `audio_kbit` | `160` | AAC-Bitrate des Tons |
| `audio_device` | leer | Teil des Gerätenamens; leer heißt Standardgerät |
| `mic` | `false` | nimmt das Mikrofon als zweite Tonspur auf |
| `mic_device` | leer | Teil des Mikrofonnamens; leer heißt Standardmikrofon |
| `hotkey` | `Ctrl+Alt+C` | auch deutsch: `Strg+Umschalt+F9` |
| `record_hotkey` | `Ctrl+Alt+R` | Aufnahme beliebiger Länge; leer schaltet sie ab |
| `long_hotkey` | leer | zweite Taste für einen längeren Clip |
| `long_clip_secs` | `120` | was die zweite Taste speichert |
| `keep_days` | `0` | Clips nach so vielen Tagen löschen; 0 heißt nie |
| `max_gb` | `0` | darüber gehen die ältesten Clips; 0 heißt kein Limit |
| `discord_webhook` | leer | Webhook eines Discord-Kanals für *An Discord senden* |
| `game_folders` | `true` | ein Ordner pro Spiel |
| `save_sound` | `true` | kurzer Ton, wenn ein Clip gespeichert ist |
| `overlay` | `true` | kurzer Hinweis oben rechts, der in keinem Clip auftaucht |
| `out_dir` | leer | leer heißt `clips/` |

Der Puffer kostet Arbeitsspeicher: 1080p60 mit `quality = 22` sind je nach Bild und
Format rund 200 bis 400 KB pro Sekunde, also 12 bis 25 MB für die
voreingestellten 60 Sekunden.

## Was noch fehlt

- **Ein Installer.** Tauri kann einen bauen (`cargo tauri build` in `app/`),
  eingerichtet ist das noch nicht.
- **Linux und macOS.** Aufnahme, Ton und Hotkeys sind heute Windows-APIs.

## Bekannte Eigenheiten

- **Ein Clip ist bis zu einer Sekunde länger als eingestellt.** Er beginnt
  auf einem Keyframe, und davon gibt es einen pro `segment_secs`.
- **Kein AV1.** ffmpeg schreibt AV1 zwar in MPEG-TS, kann es daraus aber nicht
  wieder lesen — und der Ring ist MPEG-TS.
- **Ton und Bild starten nicht gleichzeitig.** ffmpeg beginnt beide bei 0,
  der Ton fließt aber sofort, das erste Bild erst nach ein paar hundert
  Millisekunden. clipd legt deshalb den Anfang des Tons auf das erste Bild und
  wirft den Ton davor weg; ohne das lief der Ton rund 0,4 s hinterher.
- **Bei NVIDIA ist der Farbraum als BT.601 ausgezeichnet.** NVENC rechnet das
  BGRA des Desktops selbst nach yuv420p um und schreibt dazu `bt470bg` in die Datei.
  Das ist in sich stimmig — ein Testbild kommt Pixel für Pixel wieder heraus —
  aber für HD-Material ungewöhnlich. Wer eine Datei weiterverarbeitet, sollte
  die Auszeichnung nicht einfach auf BT.709 umschreiben. Bei AMD rechnet
  `vpp_amf` ausdrücklich nach BT.709 um, und so steht es auch in der Datei.
- **Im Spielfenster-Modus fängt der Puffer beim Wechsel neu an.** Kommt ein
  Spiel nach vorne oder geht es, startet clipd die Aufnahme mit dem neuen
  Ziel neu; was davor im Puffer lag, gehört nicht zum Spiel. Während einer
  laufenden Aufnahme wird nicht gewechselt.
- **Nicht jede Karte kann jeden Codec.** clipd probiert beim Start ein einzelnes Bild durch und nennt, woran es
  scheitert, statt mit leerem Buffer weiterzulaufen.
- **Der Ton ist, was man hört.** Der Loopback greift hinter dem
  Lautstärkeregler ab: Steht Windows auf 0 % oder ist stumm geschaltet, wird
  auch der Clip stumm.
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

`cargo run -p clipd-app` startet das Fenster, `cargo run -- run` die
Terminal-Fassung. Die Oberfläche ist schlichtes HTML, CSS und JavaScript in
`app/ui/` — ohne npm und ohne Build-Schritt.

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
