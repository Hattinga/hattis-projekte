# P03-02 · Hocker und Säge, technisches Modellmuster v0.1

16. November 2026. **Lokaler Codex-Prototyp zur technischen und gestalterischen Prüfung.** Keine finale Art-Freigabe, kein Roblox-Import und kein Abschluss von P03-02/P03-05. Fable bleibt für die wichtigen endgültigen Assets gemäß `docs/design/ART.md` bevorzugt.

[Gesamtansicht](renders/overview-final.png) · [Hockerverbindung](renders/stool-joint.png) · [Neun Teile im Träger](renders/kit-three-quarter.png) · [Säge vorn](renders/saw-front.png) · [Seite](renders/saw-side.png) · [Oben](renders/saw-top.png) · [Sägeblatt unter dem Tisch, Gehäuse ausgeblendet](renders/saw-blade-cutaway.png)

## Dateien und geprüfte Maße

Bearbeitbare Quelle: [p03-02-models-v01.blend](p03-02-models-v01.blend). Die Datei enthält ausschließlich die aktuelle P03-Modellszene mit gepackten Holztexturen; alte Versuche und die fremde Ausgangsszene gehören nicht zum Modellpaket. Der lokale Wiederherstellungsstand `before-p03-02.blend` bleibt außerhalb der Übergabe. Die originale Live-Szene `Scene` wurde nicht verändert.

Alle Maße der Tabelle sind **Roblox X × Y × Z = Breite × Höhe × Tiefe, in Metern**. Die Triangulation zählt ausgewertete Modifier und in Meshes umgewandelte Beschriftung mit. Unterschiedliche Schriftzüge erklären die abweichende Gesamtzahl der beiden sonst geometrisch identischen Hockerzustände.

| Export | Außenmaß m | Dreiecke | Meshes |
| --- | --- | ---: | ---: |
| [Hocker01_Raw.fbx](exports/Hocker01_Raw.fbx) | 0,40 × 0,45 × 0,40 | 4.656 | 27 |
| [Hocker01_Finish.fbx](exports/Hocker01_Finish.fbx) | 0,40 × 0,45 × 0,40 | 4.676 | 27 |
| [Hocker01_Kit.fbx](exports/Hocker01_Kit.fbx) | 0,60 × 0,18 × 0,50 | 2.337 | 22 |
| [Saege01.fbx](exports/Saege01.fbx) | 2,40 × 1,45 × 0,80 | 6.927 | 71 |
| [ControlCube_1m.fbx](exports/ControlCube_1m.fbx) | 1 × 1 × 1 | 12 | 1 |

Hocker und Träger enthalten jeweils exakt neun Holzobjekte: eine Sitzplatte, vier Beine und vier Zargen. Einzelteile, Gestellkontakt bei 0,425 m und Packlage folgen `docs/design/DIMENSIONS.md` und `assets/p03-reference/reference.md`. Kleine abtragende Fasen ändern die Nennhüllen nicht. Sitzschrauben und die seitlichen Zargenschrauben sitzen bündig in tatsächlichen Bohrungen. Holzmaserung folgt der jeweiligen Längsachse, auch bei den liegenden Bausatzteilen.

## Einheiten, Pivot und Marker

Die Blender-Quelldatei verwendet **Meter, +Z oben und +Y vorn**. Die projektgültige Abbildung ist `(Blender X,Y,Z) → (Roblox X,Z,-Y)`; dadurch wird Blender +Y zur vorgesehenen Roblox-Vorderseite −Z. Dies ersetzt für dieses Paket die allgemeine Stud-/Hitboxmittelpunkt-Konvention anderer Roblox-Projekte.

Jeder Export wird vorübergehend auf seinen Root bei `(0;0;0)` versetzt. Der Pivot liegt in der Mitte der unteren Aufstandsebene. Präsentationsabstände aus dem Blend werden nicht mitexportiert. Der FBX-Export nutzt `axis_forward=-Z`, `axis_up=Y`, `global_scale=1` und keine Anwendung des Studfaktors. Der Gesamtweg nach Roblox muss den 1-m-Körper einmalig auf **25/7 = 3,571429 Studs** bringen. Einheitenautomatik des Importers zunächst mit diesem Körper messen; keinen zweiten Skalierungsfaktor auf bereits korrekt skalierte Assets anwenden.

Säge-Marker, im Blender-Root gemessen: `Att_Input=(-0,80;0;0,90)`, `Att_Process=(0;0;0,90)`, `Att_Output=(+0,80;0;0,90)`. Blattpivot `(0;0;0,62)`, Haubenpivot `(0;-0,35;0,95)`. Hocker: `Att_Carry=(0;0;0,33)`. Blender-Marker sind Empties; die Studio-Rolle stellt ihre Attachments her. Mehrere isolierte Live-Versuche können Blender-Namenssuffixe wie `.004` erzeugen; für die Zuordnung gilt der kanonische Name vor dem ersten Punkt.

Die Säge führt Ware von **−X nach +X**. In der gezeigten Kameraansicht steht EIN daher rechts im Bild und AUS links; dies ist eine Kameraprojektion, keine umgekehrte Warenrichtung. Pfeile weisen nach +X und haben nach oben gerichtete Flächennormalen.

## Materialien und Export

Materialslots: `WoodRaw`, `WoodFinish`, `MachineSteel`, `BrushedSteel`, `MutedGreen`, `SafetyOrange`, `Black`, `Label`, `Red` und `Carrier` mit Projektpräfix `P03_` und möglichen Blender-Versuchssuffixen. Rohholz und Finish verwenden getrennte echte PNG-Texturen statt Blender-exklusiver prozeduraler Holzshader. Holz-UVs teilen einen festen physischen Maßstab. Die PNGs liegen unter [textures](textures); sie sind im Blend gepackt und in den Holz-FBX eingebettet. Farb-/Metall-/Rauheitszuordnung nach Roblox separat prüfen; FBX ist keine Materialfreigabe.

Unsichtbare Boolean-Schneidkörper sind mit `helper=true` markiert und nicht exportiert. Boden, Kamera, Licht und die anderen Modellgruppen gehören nicht zum jeweiligen Einzel-FBX. Der Kontrollkörper ist ein eigener Export und in der neutralen Präsentation ausgeblendet. Die Texturkopien und eventuell vom FBX-Reimport erzeugten `.fbm`-Ordner unter `exports` dürfen neben den FBX verbleiben.

## Ausgeführte Prüfungen

[checks.json](checks.json) enthält **179 bestandene Prüfungen**: ausgewertete Bounds und Bodenpivot, neun Holzobjekte, Sitz-/Beinkontakt und Zargenlänge, geschlossene Meshkanten mit positivem signiertem Volumen, bündige Schraubenkappen, aufwärts gerichtete Pfeile sowie alle drei freien Warenprismen.

Die Auflagen liegen bei 0,90 m. Jeder freie Prismenkörper misst 0,70 × 0,55 × 0,60 m (Roblox Breite × Höhe × Tiefe) bis 1,45 m; keine feste Maschinengeometrie schneidet sein Inneres. Das Blatt endet geparkt bei 0,77 m unter der Tischunterkante 0,80 m. Haube und Stützen stehen vollständig im hinteren 0,31…0,39-m-Streifen. Die Welle und zwei Lageraufhängungen machen den Blattanschluss in der Gehäuse-Ausblendansicht nachvollziehbar.

[fbx-roundtrip.json](fbx-roundtrip.json): fünf Exporte in jeweils neue isolierte Blender-Szenen reimportiert. Metermaße, Root bei Null, Unterseite Null und vorhandene Texturen bestätigt. Dies ist eine **Blender-FBX-Prüfung**, kein Roblox-Nachweis. Neutrale Bilder wurden mit `look` geprüft; die finale Seitenansicht umfasst auch die Fußenden. Der frühe `overview-v01.png` ist überholt, gültig ist `overview-final.png`.

## Wiederholen und offene Punkte

Alle vier Skripte nutzen ihren Paketpfad relativ zu `tools`, alternativ eine explizite Variable `P03_PACKAGE_DIR`. In Blender nacheinander ausführen:

```python
from pathlib import Path
package = Path(r"C:\Pfad\zum\p03-02-Paket")
for name in ["build.py", "finish.py", "roundtrip.py", "render.py"]:
    script = package / "tools" / name
    exec(compile(script.read_text(encoding="utf-8"), str(script), "exec"), {"__file__": str(script)})
```

`build.py` erstellt eine neue eigene Szene und löscht keine vorhandene Szene. `finish.py` verifiziert, exportiert und schreibt nur die aktuelle Modellszene in die Blend-Datei. `roundtrip.py` erzeugt getrennte Prüfszenen und stellt die aktive Modellszene wieder her. `render.py` stellt Kamera und eigene Sichtbarkeitsänderungen nach den Ansichten zurück.

Offen: tatsächlicher Roblox-Import mit 1-m-Messung, Kollisionskörper, Oberfläche/Textur, Normalen und Marker im Spiel, normale/kleine Spielkamera und finale Artentscheidung. Kein volles kollidierendes Stationsquader bis 1,45 m verwenden: es würde die nachgewiesenen Warenfreiräume schließen. Physische Kollisionskörper erst anhand Unterbau/Tisch und geparkter Rückenteile festlegen.

Die Säge zeigt ausdrücklich den **geparkten Übergabemodus**. Aktiver Schnitt, Blattzähne/Schutzverriegelung, Haubenfahrt und Prozessanimation sind noch nicht entworfen oder geprüft. Das Blender-Blatt ist eine maßhaltige Scheibe mit eigener Achse, keine fertige Schnittsimulation. Es wird keine beladene Trägerwanne durch ein angehobenes Blatt geführt. Gebäude-/Torentscheidung und Fahrzeugmaße wurden nicht bearbeitet. Performancebudget und Zusammenfassen der vielen Material-Meshes bleiben vor der Assetserie abzustimmen.
