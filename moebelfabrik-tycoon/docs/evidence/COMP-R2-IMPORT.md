# COMP-R2-IMPORT – Fables Werkstatt in Studio

Stand 12. November 2026. Technische Importprobe und Begehung bestanden. Keine vollstaendige P03-Artfreigabe und noch kein Produktionsablauf.

## Teststand

- Ziel ist die vom Nutzer geoeffnete private Experience **Furniture Factory Tycoon**, Place `79033653140107`, Universe `10776116608`, Besitzer `3493645144`.
- Der Nutzer hat die zuvor lokale Testwelt zwischenzeitlich selbst als private Experience gespeichert. Gepruefter Cloud-Ausgangsstand war Place-Version 2. Studio-ID waehrend der Arbeit: `991e71ed-7e08-4f5f-ad91-7e909df8fdf6`; bei Wiederaufnahme neu auflisten.
- Der lokale leere Ausgangs-Place ist weiterhin unter `.local/backups/2026-11-12-initial/` gesichert. Git-Arbeitsbranch `work/p00-studio-import`, Ausgangscommit `3e9b1b78c6f671692c420a2931b80904f81b56ff`.
- Die aktuelle bearbeitete Welt liegt im offenen Studio-Editor. Sie muss vor dem Schliessen dort gespeichert werden. Die lokale Datei im Projektstamm ist noch der fruehere Ausgangsstand. Der Agent hat die Experience nicht veroeffentlicht.

## Upload und unveraenderte Quellen

Der Nutzer bestaetigte die dauerhafte Assetanlage auf dem Studio-Konto, die beiden Scopes `asset:read`/`asset:write` und den Upload-Ordner. Danach waren die Scope-Tests erfolgreich. Es wurde genau **ein Modell-Upload** ausgefuehrt.

- Modell-Asset `106051543998570`, Revision 1, Moderation Approved.
- Operation `8ac1f81b-0ed1-4582-92e2-1dfeda2b8788`.
- GLB 690.728 Bytes, 45 Quellmeshes, 153 Material-Primitives, 13.080 Dreiecke. Groesstes Quellmesh 1.300 Dreiecke, unter dem am 12.11. nachgesehenen Limit 20.000.
- Original `.blend`, `.fbx`, `build.py`, Brief und GLB sind unter `assets/workshop/` archiviert. Keine zusaetzlichen Bild-Uploads oder importierten Bildtexturen.
- Automatisch entstandene Mesh-IDs und die letzten Testwerte stehen in [COMP-R2-IMPORT.json](COMP-R2-IMPORT.json).

## Importbefund und Korrekturen

Alle 153 erwarteten Material-Primitives kamen als MeshParts an, verteilt auf 45 Quellknoten. Der Import hatte alle Teile auf Grau gesetzt, sie unanchored gelassen und Meter als Studs behandelt. Die originale Quelle hatte keine verlorenen Bildtexturen.

Alle 153 Farben wurden aus den GLB-Materialwerten nach sRGB zurueckgefuehrt. Glas uebernimmt die Original-Alpha-Werte. Der Skalar-Metallic/Roughness-Shader ist in Standard-Roblox-Materialien nur angenaehert. Das dunkle Dach verwendet Plastic fuer eine matte Wirkung, Umgebungsglanz wurde von 1 auf 0,15 reduziert. Sonstige Lichtwerte blieben auf dem vorhandenen Teststand.

Die verifizierte Quellachsen-Zuordnung wurde korrigiert. Fenster liegen rechts an +X, das offene Tor zeigt zum Spawn an +Z. Der Massfaktor ist etwa 3,571429 Studs/m. Sichtbare Aussenmasse inklusive offener Tueren etwa **25,536 x 17,482 x 22,991 Studs** (X/Y/Z). Die lichte Torhoehe betraegt etwa 8,393 Studs.

Die Werkstatt steht direkt hinter dem Spawn, sichtbare Bounding-Box-Mitte bei X=0, Z=-26, Fundamentunterkante am Boden Y=0, Fussboden etwa Y=0,5. Der Spawn bleibt frei. Alle 153 MeshParts sind anchored.

21 einfache unsichtbare Kollisionskoerper bilden Boden, Waende, Fenster, offene Tuerblaetter, Dach und groessere Einrichtung ab. Dekorative Teilmeshes sind selbst nicht kollidierend. Dadurch fuellen gemeinsame konvexe Huellen der verstreuten Meshinseln weder Tor noch Innenraum. Diese Kollision ist fuer die Begehungsprobe vereinfacht, keine Simulation jeder Schraube.

Die Studio-Kopie ist als Package mit dem rohen Upload verknuepft. Diese lokalen Reparaturen wurden nicht in die Asset-Revision zurueckveroeffentlicht. Bei erneutem Einfuegen oder Package-Update ist der Reparaturhelfer erneut auf eine frische Kopie anzuwenden. Rueckgaengig ueber die benannten ChangeHistory-Aufzeichnungen oder den gesicherten Ausgangsstand.

## Ausgefuehrte Tests

- Aussenansicht nach Korrektur und normale Spielkamera im Innenraum visuell angesehen. Werkbank, Regal, Werkzeugwand, Rohholz, Fenster, Binder und Dach sind sichtbar.
- Avatar mit etwa 5,57 Studs gemessener Gesamthoehe lief im Playtest vom Spawn durch das Tor in den Innenraum und wieder zum Spawn. Zielabweichungen innen 0,853 Studs, aussen 0,879 Studs, Lebenspunkte 100.
- Nach dem letzten Kollisionsaufbau erneut getestet. Abwaertsstrahl trifft `Collision.Floor`, beide Seiten treffen Wandkoerper, Aufwaertsstrahl trifft `Collision.Roof1`, der mittige Strahl durch das Tor bleibt frei. Der hintere Strahl trifft wie erwartet zuerst das Rohholzregal.
- Ein zu frueher Navigationsversuch scheiterte waehrend des Avatar-Ladens. Mit begrenztem Warten auf die geladene Figur wiederholt; danach bestanden. Kein Laufzeitfehler der Werkstatt selbst ermittelt.
- Abschliessender Zustand wieder **Edit**, 153 MeshParts, keine unanchored Teile, 21 Colliders, keine TextureID-/ColorMap-Bildassets. Die Editor-Kamera zeigt die Werkstatt.

## Offen und naechster Schritt

Aktuellen Editorstand in Studio speichern. Danach Hockerrezept und Uebergaben P01-01/P01-02 festlegen, anschliessend die erste Handarbeitslinie bauen. Der reale schwaechere Testrechner P00-03 ist noch offen. Leistung, mobiles Geraet, Fahrzeugdurchfahrt, komplette P03-Artabnahme und Produktion wurden noch nicht geprueft. Kein Commit oder Push ausgefuehrt.