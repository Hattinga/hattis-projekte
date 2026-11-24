# Hardware-Befund: UGREEN-Karte, Formatliste (2026-11-23)

> **Korrektur vom 2026-11-24:** Das hier beschriebene Gerät „UGREEN Camera
> 4K“ (`VID_EBA4&PID_6579`) ist eine **Webcam**, nicht die Capture-Karte.
> Die Karte ist „UGREEN 25854“ (`VID_2B89&PID_5854`), siehe
> [hardware-probe-2026-11-24.md](hardware-probe-2026-11-24.md). Der Text
> unten bleibt als Protokoll unverändert.

Ausgabe von `framerush --list-devices` auf dem Entwicklungs-PC (Windows 11,
i7-14700K, RTX 5060 Ti). Die Karte steckte am USB, ob ein HDMI-Signal anlag,
ist nicht festgehalten.

**Was das ist:** die nativen Medientypen, die der Treiber über Media
Foundation (`IMFSourceReader::GetNativeMediaType`) *meldet*.

**Was das nicht ist:** ein Nachweis, dass die Karte in diesen Formaten
tatsächlich stabil liefert. FrameRush kann noch nicht aufnehmen (Meilenstein
M2). Ob z. B. NV12 1920×1080 @ 60 wirklich mit 60 fps ankommt, über welchen
USB-Modus und mit welcher Latenz, ist offen.

Auffällig, aber ungeprüft:

- 1080p60 wird als **NV12** und als **MJPG** gemeldet. NV12 passt direkt zum
  vorhandenen NV12-Renderpfad, ohne JPEG-Dekodierung.
- **YUY2** gibt es bei 1920×1080 nur mit 5 fps.
- Formate über 1080p (3840×2160, 4000×3000, …) werden nur mit 30 fps
  gemeldet. Was davon echte HDMI-Eingangsauflösungen sind und was nur Skalierung
  durch den Chip, ist unbekannt.

```
[0] UGREEN Camera 4K
    id: \\?\usb#vid_eba4&pid_6579&mi_00#8&6705fe1&0&0000#{e5323777-f976-4f5b-9b55-b94699c46e44}\global
    native media types reported by the driver (44):
      #0   NV12       3840x2160    30.000 fps (30/1)
      #1   MJPG       3840x2160    30.000 fps (30/1)
      #2   NV12        1280x720    60.000 fps (60/1)
      #3   MJPG        1280x720    60.000 fps (60/1)
      #4   NV12        1280x720    30.000 fps (30/1)
      #5   MJPG        1280x720    30.000 fps (30/1)
      #6   NV12       1920x1080    60.000 fps (60/1)
      #7   MJPG       1920x1080    60.000 fps (60/1)
      #8   NV12       1920x1080    30.000 fps (30/1)
      #9   MJPG       1920x1080    30.000 fps (30/1)
      #10  NV12       4000x3000    30.000 fps (30/1)
      #11  MJPG       4000x3000    30.000 fps (30/1)
      #12  NV12         640x480    30.000 fps (30/1)
      #13  MJPG         640x480    30.000 fps (30/1)
      #14  NV12         640x360    60.000 fps (60/1)
      #15  MJPG         640x360    60.000 fps (60/1)
      #16  NV12         640x360    30.000 fps (30/1)
      #17  MJPG         640x360    30.000 fps (30/1)
      #18  NV12       2560x1440    30.000 fps (30/1)
      #19  MJPG       2560x1440    30.000 fps (30/1)
      #20  NV12       2592x1520    30.000 fps (30/1)
      #21  MJPG       2592x1520    30.000 fps (30/1)
      #22  NV12       2048x1536    30.000 fps (30/1)
      #23  MJPG       2048x1536    30.000 fps (30/1)
      #24  NV12        1280x960    30.000 fps (30/1)
      #25  MJPG        1280x960    30.000 fps (30/1)
      #26  NV12        1024x768    30.000 fps (30/1)
      #27  MJPG        1024x768    30.000 fps (30/1)
      #28  NV12         480x320    30.000 fps (30/1)
      #29  MJPG         480x320    30.000 fps (30/1)
      #30  NV12       1280x1024    30.000 fps (30/1)
      #31  MJPG       1280x1024    30.000 fps (30/1)
      #32  YUY2         640x480    30.000 fps (30/1)
      #33  YUY2       1920x1080     5.000 fps (5/1)
      #34  YUY2         640x360    30.000 fps (30/1)
      #35  YUY2       1280x1024     5.000 fps (5/1)
      #36  YUY2       2560x1440     3.000 fps (10000000/3333333)
      #37  YUY2       2592x1944     3.000 fps (10000000/3333333)
      #38  YUY2       1600x1200     5.000 fps (5/1)
      #39  YUY2         480x320    30.000 fps (30/1)
      #40  YUY2         320x240    30.000 fps (30/1)
      #41  YUY2         800x600    15.000 fps (15/1)
      #42  YUY2        1024x720    15.000 fps (15/1)
      #43  YUY2        1280x960    10.000 fps (10/1)

```
