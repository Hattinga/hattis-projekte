# Hardware-Befund: UGREEN 25854, Formate, Live-Vorschau und Kaspersky (2026-11-24)

Entwicklungs-PC (Windows 11, i7-14700K, RTX 5060 Ti). Debug-Build von
FrameRush. Alle Zeiten sind Ortszeit.

## Welches Gerät die Capture-Karte ist

- **Karte: „UGREEN 25854“**, USB `VID_2B89&PID_5854&REV_2100`, am
  24.11. um 13:43 zum ersten Mal installiert. Der Nutzer hat bestätigt, dass
  das die HDMI-Karte ist. Es ist ein Verbundgerät mit drei Schnittstellen:
  Video (`MI_00`, Klasse Camera), Audio (`MI_02`, „UGREEN 25854“) und HID
  (`MI_04`).
- **„UGREEN Camera 4K“** (`VID_EBA4&PID_6579`) ist eine **Webcam** mit
  eigenem Mikrofon („UGREEN Camera Audio“). Sie meldet
  Sensorauflösungen wie 4000×3000 und 2592×1944. Der Befund vom 23.11.
  ([hardware-probe-2026-11-23.md](hardware-probe-2026-11-23.md))
  beschreibt dieses Gerät, **nicht** die Capture-Karte.
- Die Karte hängt an Port 1 eines xHCI-Root-Hubs („USB-Root-Hub (USB
  3.0)“). Ob die Verbindung SuperSpeed oder nur High-Speed (USB 2.0) ist,
  ist **nicht geprüft**. Der Root-Hub bedient beides.

## Gemeldete Modi

`framerush --list-devices` meldet für die Karte 139 native Medientypen
(Auszug unten, vollständig in der Ausgabe des Befehls):

- **NV12 und MJPG kommen immer paarweise vor**, mit gleicher Größe und
  Bildrate: 1920×1080, 1600×1200, 1360×768, 1280×1024, 1280×960, 1280×720,
  1024×768, 800×600, 720×576, 720×480, 640×480. Jede Größe gibt es mit 60,
  50, 30, 20 und 10 fps.
- **YUY2** gibt es nur bis etwa 40–46 MB/s: 1920×1080 höchstens mit 10 fps,
  1280×720 mit 25 fps, 720×480 und 640×480 mit 60 fps.

**Schluss, nicht geprüft:** Rohes NV12 in 1080p60 bräuchte etwa 187 MB/s.
Die YUY2-Grenze passt zur Bandbreite von USB 2.0. Dann kann NV12 in 1080p60
nicht unkomprimiert über das Kabel kommen. Am wahrscheinlichsten überträgt
die Karte MJPG, und Windows dekodiert es zu NV12. Dazu passt das
Farbformat des NV12-Typs (nächster Abschnitt). Die Webcam und die Logitech
C505 zeigen dasselbe NV12/MJPG-Paarmuster.

```
[2] UGREEN 25854
    id: \\?\usb#vid_2b89&pid_5854&mi_00#7&297d0366&0&0000#{e5323777-f976-4f5b-9b55-b94699c46e44}\global
    native media types reported by the driver (139):
      #0   NV12       1920x1080    60.000 fps (60/1)
      #1   MJPG       1920x1080    60.000 fps (60/1)
      #2   NV12       1920x1080    50.000 fps (50/1)
      #3   MJPG       1920x1080    50.000 fps (50/1)
      #4   NV12       1920x1080    30.000 fps (30/1)
      #5   MJPG       1920x1080    30.000 fps (30/1)
      ...
      #50  NV12        1280x720    60.000 fps (60/1)
      #51  MJPG        1280x720    60.000 fps (60/1)
      ...
      #110 YUY2       1920x1080    10.000 fps (10/1)
      #111 YUY2       1920x1080     5.000 fps (5/1)
      ...
      #120 YUY2        1280x720    25.000 fps (25/1)
      ...
      #131 YUY2         720x480    60.000 fps (60/1)
      ...
      #135 YUY2         640x480    60.000 fps (60/1)
```

## Ausgehandelter Typ NV12 1920×1080 @ 60 (#0)

Aus `framerush --device 25854 --probe`, nach `SetCurrentMediaType` mit
dem nativen Typ #0:

```
MF_MT_FRAME_SIZE                   1920 x 1080
MF_MT_YUV_MATRIX                   2 (BT.601)
MF_MT_MAJOR_TYPE                   Video
53A0529C-890B-4216-8BF9-599367AD6D20 3
MF_MT_VIDEO_CHROMA_SITING          1
73D1072D-1870-4174-A063-29FF4FF6C11E F72A76A0-EB0A-11D0-ACE4-0000C0CC16BA
MF_MT_FIXED_SIZE_SAMPLES           1
MF_MT_VIDEO_NOMINAL_RANGE          1 (0-255 (full))
MF_MT_FRAME_RATE                   60/1
MF_MT_PIXEL_ASPECT_RATIO           1/1
MF_MT_ALL_SAMPLES_INDEPENDENT      1
MF_MT_FRAME_RATE_RANGE_MIN         60/1
MF_MT_VIDEO_PRIMARIES              2 (BT.709)
MF_MT_INTERLACE_MODE               2 (progressive)
MF_MT_FRAME_RATE_RANGE_MAX         60/1
EA031A62-8BBB-43C5-B5C4-572D2D231C18 1
MF_MT_SUBTYPE                      NV12
```

- **BT.601, Full Range (0–255).** So kodiert JPEG. Der Renderer hatte bis
  M0 fest BT.709 Limited angenommen; damit wären Schwarz und Weiß verfälscht
  und die Farben leicht verschoben gewesen. Seit M2 liest FrameRush Matrix
  und Range aus dem Typ.
- Kein `MF_MT_DEFAULT_STRIDE`. Den Pitch liefert erst der gesperrte Puffer.
- Der NV12-Typ 1920×1080 @ 30 der Webcam meldet dieselben Werte.

## Live-Vorschau funktioniert (nach Neustart, ab 15:00)

**Bedingungen:**
- Debug-Build, Fenster 1280×720 (nicht Vollbild, also von DWM komponiert),
  FIFO, Frame-Latenz 1, Modus NV12 #0 1920×1080 @ 60.
- Kaspersky-„Programmüberwachung“ (Wortlaut des Nutzers) **aus**, siehe
  nächster Abschnitt.
- **PS Remote Play lief auf demselben PC**, damit die PS5 wach bleibt. Das
  kann die Ausgabe der PS5 und die Last des PCs beeinflussen.
- In welchem HDMI-Modus die PS5 tatsächlich ausgibt, ist nicht festgestellt.
- Alle Zeiten sind Software-Zeiten dieses Prozesses, keine
  HDMI-zu-Photon-Latenz.

| Zeit | Lauf | HDMI-Eingang | Ergebnis |
|---|---|---|---|
| 15:07 | `--probe --mode 110` (YUY2, nur zählen), Kaspersky an | ab | 1 Stream-Tick, 0 Samples; Schließen hängt (über 2 s), der Prozess beendet sich danach aber vollständig |
| ~15:09 | wie oben, Kaspersky-Modul aus | ab | 28 Samples in 3 s (10 fps), erstes nach 304 ms, Abstand 99,95–100,00 ms, 4 147 200 Bytes je Sample (1920 × 1080 × 2); geschlossen in 17 ms |
| 15:10 | `--probe` NV12 #0, 5 s | ab | 297 Frames, laut Zeitstempel keiner verloren; erstes nach 80 ms; Abstand am Gerät 16,58–16,77 ms (Mittel 16,66); Kopieren 0,34–1,73 ms (Mittel 0,51); Puffer ohne Padding (Pitch 1920, CbCr ab Byte 2 073 600); geschlossen in 44 ms |
| ~15:11 | Viewer, 8 s | ab | zeigt das „No Signal“-Bild der Karte; 475 rein, 468 angezeigt, Mailbox-Drops 6, Quellen-Drops 0; Farbraum BT.601 Full |
| ~15:12 | Viewer, 10 s | PS5, HDCP laut Nutzer aus | **zeigt das PS5-Bild**; 590 rein, 587 angezeigt, Mailbox-Drops 2, Quellen-Drops 0; Abstand am Gerät 15,82–16,81 ms; Kopieren Mittel 0,47 ms, max 0,83 ms; ready→present im Log-Fenster Mittel 1,9 ms, max 2,5 ms; Present-Abstand 16,0–17,6 ms |

Ein Screenshot des Viewers mit PS5-Bild wurde geprüft, ist aber nicht im
Repository abgelegt, weil er persönliche Kontodaten zeigt.

## Ursache der fehlenden Frames: Kaspersky

- Kaspersky (Dienst `AVP21.27`) hängt mit dem Filter
  `\FileSystem\KLIF.K4W-21-27` im Treiber-Stack der Karte **und** der
  Webcam (`DEVPKEY_Device_Stack`: `KLIF.K4W-21-27` → `ksthunk` →
  `usbvideo` → `usbccgp`).
- Der Nutzer hat heute eine Kaspersky-Meldung gesehen. Ihren Wortlaut weiß er
  nicht mehr.
- **Gegenprobe auf frisch gestartetem System:** YUY2 mit Kaspersky an:
  1 Stream-Tick, 0 Samples, Schließen hängt. Direkt nachdem die
  „Programmüberwachung“ aus war: Samples kommen, das Gerät schließt in
  17–44 ms. Die Windows-Kamera-App, ein vertrauenswürdiges Microsoft-Programm,
  bekam die ganze Zeit Bilder.
- Damit passen alle Läufe ohne Samples vor dem Neustart, auch der erste um
  14:18 und der mit der Webcam, am besten zu einer Sperre durch Kaspersky.
  HDCP, NV12-Dekodierung und MF-Einstellungen erklären sie nicht. Die
  frühere Deutung, der Lauf um 14:18 passe zu HDCP, ist überholt.
- Wahrscheinlich hat der KLIF-Filter auch die I/O-Anfragen festgehalten,
  sodass die Prozesse sich nicht beenden ließen. Belegt ist dieser Mechanismus
  nicht.
- **Nicht geprüft:** ob statt des ganzen Moduls eine Ausnahme nur für
  `framerush.exe` reicht und ob sie einen Neubau übersteht (jeder Build
  erzeugt eine neue `.exe`). Stand 24.11.: das Modul ist aus.

## Vor dem Neustart (14:18–14:57, Kaspersky an)

Zeiten in Ortszeit (MEZ), die Logzeilen stehen in UTC.

| Zeit | Gerät | Modus | HDMI-Eingang | Ergebnis |
|---|---|---|---|---|
| 14:18 | 25854 | #0 NV12 1080p60 | PS5 an, HDCP unklar | 0 Frames in 5 s, 1 Stream-Tick; Prozess hängt beim Beenden |
| 14:21 | 25854 | #0 NV12 1080p60 | wie oben | alte Binärdatei, hängt ebenfalls |
| 14:34 | UGREEN Camera 4K (Webcam) | #8 NV12 1080p30 | – (die Kamera-App hielt seit 14:32 die Karte) | 0 Frames in 3 s, 1 Stream-Tick; hängt beim Freigeben des Source Readers |
| 14:47 | 25854 | #0 NV12 1080p60 | ab | `MF_E_HW_MFT_FAILED_START_STREAMING` (0xC00D3704), weil die Kamera-App die Karte hielt; sauber beendet |
| 14:48 | 25854 | #0 NV12 1080p60 | ab, Kamera-App zu | ohne `MF_LOW_LATENCY` und ohne Stream-Abwahl: 1 Stream-Tick, 0 Samples, hängt beim Freigeben |
| 14:50 | 25854 | #0 NV12 1080p60 | wie oben | synchrones `ReadSample`: 1 Stream-Tick, dann blockiert der nächste Aufruf |
| 14:50 | 25854 | #110 YUY2, nur zählen | wie oben | sofort 0xC00D3704, Gerät von hängendem Prozess belegt |
| 14:57 | 25854 | #0 NV12 1080p60 | PS5 an, HDCP laut Nutzer aus | sofort 0xC00D3704, von 5 hängenden Prozessen belegt |

- Das Schließen hing jedes Mal beim Freigeben des Source Readers, nachdem
  der Flush bestätigt war. Nach `Stop-Process` blieb je ein Thread im
  Kernel-Wartezustand („Executive“). Abziehen der Karte half nicht, erst ein
  Neustart.
- Der Kamera-Datenschutz von Windows erlaubt Desktop-Apps den Zugriff
  (`ConsentStore\webcam` und `NonPackaged`: `Allow`). Daran lag es nicht.
- Testweise eingebaute Schalter (Stream-Abwahl, synchrones Lesen,
  Hardware-Transforms) haben nichts geändert und sind wieder entfernt.
  Geblieben ist `FRAMERUSH_MF_LOW_LATENCY` als Messpunkt für M3.
- Geblieben ist auch das begrenzte Stoppen: Viewer und `--probe` warten
  höchstens 2 s auf das Schließen des Geräts und melden ein Hängen, statt das
  Fenster einzufrieren.

## Referenz: Windows-Kamera-App

Vom Nutzer nach dem ersten Neu-Anstecken beobachtet: ohne Eingangssignal das
„No Signal“-Bild der Karte, mit eingeschalteter PS5 ein schwarzes Bild. Ob das
Schwarz an HDCP lag, ist offen. Mit HDCP aus (laut Nutzer) zeigt FrameRush das
PS5-Bild.

## Offen

- Kaspersky wieder einschalten und eine Ausnahme nur für FrameRush testen,
  auch nach einem Neubau.
- M3: Latenz gegen OBS/PotPlayer unter gleichen Bedingungen, Release-Build,
  Vollbild, `MF_LOW_LATENCY`, Present-Modi, und die Kosten der vermuteten
  MJPG→NV12-Dekodierung (MJPG nativ zum Vergleich).
- Abziehen von HDMI oder USB während der Viewer läuft (CLAUDE.md Punkt 8),
  Standby, Teilen in Discord: nicht getestet.
- USB-Modus der Karte (High-Speed oder SuperSpeed): nicht geprüft.
