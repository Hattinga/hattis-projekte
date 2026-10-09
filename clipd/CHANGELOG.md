# Änderungen

## 0.1.0

Die erste Fassung.

- **Clips auf Tastendruck.** clipd nimmt laufend in einen Ring im Arbeitsspeicher
  auf (60 s voreingestellt) und speichert mit Strg+Alt+C die letzten 30 Sekunden —
  ohne neu zu kodieren, in Bruchteilen einer Sekunde. Eine zweite Taste kann einen
  längeren Clip speichern.
- **Aufnahmen beliebiger Länge** mit Strg+Alt+R starten und beenden.
- **Aufnahme auf der Grafikkarte** mit NVIDIA (NVENC) oder AMD (AMF); welche Karte,
  findet clipd selbst heraus. Wahlweise der ganze Bildschirm oder nur das Fenster
  des Spiels.
- **Ton** von den Boxen und auf Wunsch das Mikrofon als eigene Spur. Surround-Geräte
  wie SteelSeries Sonar (8 Kanäle) mischt clipd auf Stereo.
- **Ordner pro Spiel:** Clips landen unter dem Spiel, das gerade vorne war.
- **Fenster** mit Bibliothek, Vorschaubildern, Player mit Schnittrahmen, Favoriten
  und Aufräumen nach Alter oder Speicherplatz.
- **Teilen:** Discord-Datei unter 10 MB in die Zwischenablage oder direkt per
  Webhook in einen Kanal, außerdem GIF und Hochformat 9:16.
- **Im Hintergrund:** Symbol im Infobereich, Start mit Windows, kurze Einblendung
  über dem Spiel beim Speichern. Ein geschlossenes Fenster gibt seinen Speicher frei.
- **Terminal:** `clipd run`, `clipd clip`, `clipd record` (auch für Stream Deck),
  `clipd export`, `clipd monitors`, `clipd audio`.
- **Installer** für Windows; ffmpeg lädt clipd beim ersten Start selbst.
