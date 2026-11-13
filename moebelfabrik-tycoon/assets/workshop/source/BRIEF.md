# Runde 2 · Begehbare Tischlerwerkstatt

Baue eine detailreiche, leicht stilisierte Tischlerwerkstatt als komplett inspizierbares Spielmodell. Die Konstruktion muss außen, von unten am Dachüberstand und durch das offene Tor nachvollziehbar sein. Verwende echte räumliche Geometrie für die entscheidenden Anschlüsse. Definiere Innenausbau und Dach als getrennte Bauteile. Die Einreichung wird im 3D-Viewport verglichen.

## Gleiche Vorgaben

Meter, Z nach oben, vorne Y = 0. Wandkörper X = −3,20 bis +3,20, Y = 0 bis 5,00. Boden Z = 0, Wandstärke 0,20 m. Satteldachfirst entlang Y bei X = 0, Dachunterseite am First Z = 4,65 und auf beiden Außenwänden Z = 3,20. Seitlicher Überstand 0,36 m, stirnseitiger 0,30 m. Metallhaut auf sichtbarer Holzschalung, saubere Abschlüsse am First, Ortgang und Traufe. Außenmaße mit Trim möglichst unter 7,20 × 5,70 × 4,90 m.

- An der Vorderseite eine offene zweiflügelige Werkstatttür. Lichte Öffnung X = −1,05 bis +1,05, Z = 0 bis 2,35. Beide Blätter etwa 100° nach außen aufgeklappt. Rahmen, Schwelle, Scharniere und Griffe sind räumlich sichtbar.
- Rechte Wand mit zwei tatsächlich ausgesparten Fenstern. Mittelpunkte Y = 1,40 und 3,65, jeweils 1,10 m breit, Brüstung Z = 1,20, Oberkante Z = 2,20. Laibungen, Rahmen, Sprossen und Fensterbank mit erkennbarer Tiefe.
- Plinth, Schalung, Eckleisten und ein glaubwürdiger Wandschnitt am Eingang. Eine Traufseite zeigt Auflager und mehrere passende Sparrenenden. Im Innenraum mindestens zwei sichtbare Träger oder Binder und ein Boden mit sinnvoller Materialaufteilung.
- Innen an der linken Wand eine Tischlerwerkbank mit Schraubstock. Hinten ein offenes Regal und geordnetes Rohholz. Details wie Holzfugen, Griffe, Verbindungen und Schraubstockbacken sollen aus der Nähe überzeugen. Wenige passende Gebrauchsobjekte sind erlaubt. Kein Text, keine Marken, keine gesamte Umgebung.
- Palette aus hellem Wandweiß `#E8E0D1`, Holz `#C59664`, Dachstahl `#34383C` und gedämpftem Grün `#788678`. Matte, glaubwürdige Materialien und leichte Variation. Eigenständige Geometrie und Blender-Materialien ohne heruntergeladene Meshes, Texturen oder externe Assetdienste.

Für den Dachanschluss dient dasselbe Foto als allgemeine Inspiration wie in Runde 1. Die Maße und der Innenraum stammen aus diesem Brief. [Referenzfoto von Royolflush, CC BY-SA 4.0](https://commons.wikimedia.org/wiki/File:EZ_fit_Riverside_10x12_wood-storage-shed.jpg)

## Abgabe

Ein eigenständiges `build.py` für Blender 5.1, das `workshop.blend` und `workshop.fbx` im übergebenen Ausgabeordner erstellt. Alle Gebäudeobjekte und Einrichtungsgegenstände liegen unter der Collection `ASSET`. Lege alle Bauteile, die bei der Innenraumansicht ausgeblendet werden sollen, in eine Untercollection `ROOF`. Wände und Innenausbau bleiben bei ausgeschaltetem Dach sichtbar. Keine Lichter, Hintergründe oder Kameras im Export.

```powershell
blender.exe --background --factory-startup --python build.py -- <Ausgabeordner>
```

Maximal 40.000 evaluierte Dreiecke für das gesamte Asset. Benenne logische Bauteile. Erhalte Maßstab, editierbare Geometrie, verlässliche Normalen und glaubwürdige Fugen. Das Mesh soll auch bei flachem Licht lesbar sein. Der Vergleich prüft aus derselben 3D-Ansicht Dachanschluss, Fenster und Tor, Innenraum, Maßstab und Geometrieaufwand.
