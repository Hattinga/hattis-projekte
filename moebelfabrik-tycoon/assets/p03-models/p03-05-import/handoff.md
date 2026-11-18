# P03-05 · Importvorbereitung v0.1

16.11.2026. Technische Importkopie; keine Roblox-Aufrufe, Uploads oder Artfreigabe.
Originalpaket `assets/p03-models/p03-02/` und ursprüngliche Live-Szene unverändert.
Lokales Backup: `before-p03-05.blend` (nicht in die Modellübergabe übernehmen).

## Bereit zur Übernahme

- `p03-05-import-v01.blend`: isolierte Szene mit gepackten Holz-PNGs.
- `exports/`: genau fünf FBX mit eingebetteten Texturen; benötigte `.fbm`-Texturordner mitnehmen.
- `textures/`, `tools/prepare.py`, `tools/roundtrip.py`, `tools/render.py`.
- `checks.json`: 297 bestandene Prüfungen und vollständiger Manifest je Asset/Mesh einschließlich Material, linearer Farbe, Texturen, Vertex-Bounds, Root-Matrix und Markern.
- `roundtrip.json`: fünf isolierte Blender-Rückimporte bestanden, einschließlich aller 140 verbleibenden Meshes und vorhandener Texturen.
- `labels.json`: acht semantische Label-Anker für echtes Roblox-Text/UI in Englisch und Deutsch.
- `renders/overview-import.png`: nach der Sprachumstellung mit `look` visuell geprüft.

| FBX | Meshes | Dreiecke | Sollmaße Roblox X/Y/Z in m |
| --- | ---: | ---: | --- |
| Hocker01_Raw | 26 | 4456 | 0,40 / 0,45 / 0,40 |
| Hocker01_Finish | 26 | 4456 | 0,40 / 0,45 / 0,40 |
| Hocker01_Kit | 21 | 2172 | 0,60 / 0,18 / 0,50 |
| Saege01 | 66 | 5756 | 2,40 / 1,45 / 0,80 |
| ControlCube_1m | 1 | 12 | 1 / 1 / 1 |

## Geänderte Importkopie

Alle acht Wort-Meshes sind vom Export ausgeschlossen. Ihre Schildplatten bleiben bestehen;
sie werden in Roblox mit lokalisierbarem Text belegt. Originale Wort-Meshes bleiben ausschließlich
als ausgeblendete `helper=true`-Quellhilfen in der privaten Blend; keine davon ist im FBX.
Die drei sprachneutralen Pfeile besitzen jetzt 0,1 mm nach innen gerichtete Dicke.
Alle tatsächlich exportierten Meshes sind geschlossen und besitzen positives Volumen, auch die Pfeile.
Hüllen, Gelenkkontakte, Pivots, Materialtexturen und freie Warenprismen bleiben erhalten.

Die acht Schlüssel sind `stool.raw`, `stool.finished`, `kit.parts`, `saw.name`, `saw.status`,
`saw.input`, `saw.process`, `saw.output`. Jeder Eintrag in `labels.json` enthält den alten Wortlaut
nur als Referenz sowie den exakten Root-Frame, Rechts-/Oben-/Normalenvektor,
Mittelpunkt der Schriftzeile (`anchor_root_blender_m`), Glyphmittelpunkt, physische Schriftgröße und verfügbare Fläche.
Die Fläche wird um diesen Anker zentriert; der Glyphmittelpunkt dient nur zum Vergleich der alten Meshschrift.
Ein SurfaceGui soll keine gebackene Übersetzung übernehmen, sondern die gewünschten EN/DE-Texte lokal anzeigen.

## Maßstab und Orientierung

Blender Meter, +Z oben und +Y vorn. Abbildung `(X,Y,Z) -> (X,Z,-Y)`.
FBX verwendet `axis_forward=-Z`, `axis_up=Y`, `global_scale=1`, unskalierte Meter.
Jeder Export wird allein mit Bodenmittelpunkt im Ursprung geschrieben; Präsentationsabstände fehlen.
Der 1-m-Körper muss nach Roblox-Import 25/7 = 3,571429 Studs messen; Faktor genau einmal anwenden.

Die Säge hat den Eingang bei -X und Ausgang bei +X. Statusschild liegt bei +X und hinten (-Y in Blender),
Bedienknopf vorn (+Y). Diese zwei Merkmale prüfen Drehung/Spiegelung. Die Bausatzbeine liegen auf +X,
die Sitzplatte ist nach -X versetzt. Hocker-Schilder zeigen nach +Y, ihre X-/Y-Schraubenhöhen unterscheiden sich.
Der Kontrollkörper ist rotationssymmetrisch und prüft ausschließlich Größe und Bodenbezug.

## Wiederholung und Grenzen

In Blender `tools/prepare.py`, danach `tools/roundtrip.py`, danach `tools/render.py` ausführen.
`prepare.py` sucht das unveränderte P03-02-Quellpaket im Projekt; alternativ `P03_SOURCE_PATH` angeben.
Alle Ausgaben verwenden das Paketverzeichnis relativ zu `tools`; alternativ `P03_PACKAGE_DIR` setzen.
Jeder Neuaufbau lädt eine neue eigene Szene; vorhandene Nutzerszenen werden nicht gelöscht.

Roblox-Import, Text/UI, Kollision, Materialkorrektur und Spielkameraprüfung führt die Studio-Rolle aus.
Aktiver Sägeschnitt/Schutzanimation und finale Art bleiben offen. Noch keine permanenten Assets angelegt.
