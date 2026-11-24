# Art Direction und Asset-Vertrag

Die Fabrik wirkt wie eine glaubwürdig gebaute, leicht stilisierte Tischlerei. Die Spielregeln stehen im [Spielkern](CORE.md). Der [Startplan](../plan/00-start.md) übersetzt diese Kriterien in die Musterprobe. Die erste Assetserie richtet sich nach dem Umfang der [Prototypabnahme](../plan/03-prototyp-abnahme.md).

## Stil, Maßstab und Referenzen

Helles Holz, gestrichene Wandflächen und dunkler Maschinenstahl bilden eine ruhige Umgebung für gut erkennbare Werkstücke. Die vorläufige Palette verwendet Wandweiß `#E8E0D1`, Holz `#C59664`, Stahl `#34383C`, Grün `#788678` und Sicherheitsorange `#D88B3D`. Farbmarkierungen unterstützen Formen, Symbole und Beschriftung.

Vor dem Modellieren werden Referenzansicht, wesentliche Abmessungen und entscheidende Verbindungen festgehalten. Das Maßblatt aus P01 bestimmt Raster, Einheiten, Bauteilstärken, Drehpunkte und Anschlüsse. Ein gemeinsamer Vergleich zeigt Avatar, Hocker, Maschine, Träger, Karton, Quad, Anhänger und Tor. Die Angaben werden nach dem Import nachgemessen.

Der [Waren- und Maßvertrag P01-03/P01-05](DIMENSIONS.md) enthält die ersten Sollmaße, Einzelteile und Packlagen sowie die gezielt abgeleiteten Tor- und Dachmaße der vorhandenen Werkstatt. Er ersetzt keine Modell- oder Art-Abnahme im Spiel.

## Sprache und Beschriftung

Verbindliche Nutzerentscheidung vom 16. November 2026: Das Spiel unterstützt **Englisch und Deutsch**. Neue Assets enthalten Formen, Symbole, Pfeile und leere Schildflächen; sprachabhängige Wörter werden als übersetzbare Roblox-Texte angebunden, nicht in Meshes oder Texturen eingebrannt. Stabile semantische Schlüssel verbinden Schild und Übersetzung. Englisch dient als Quell-/Fallbacksprache, Deutsch erhält eigene Übersetzungen; die Anzeige richtet sich nach der Spielersprache. Beide Sprachfassungen müssen auf den tatsächlichen Schildflächen lesbar bleiben.

Die deutschen Wörter in den bisherigen P03-02-Blender-Vorschauen sind historische Musterbeschriftungen. Die Importkopie entfernt diese Wort-Meshes und erhält eine getrennte EN-/DE-Textebene. Dieselbe Trennung gilt später für Spieleroberfläche, Rückmeldungen und Maschinenstatus. Serverseitige Aktionscodes bleiben sprachunabhängig; interne deutsche Fallbackmeldungen ersetzen keine übersetzte Spieleranzeige.

## Gebäude und Dach

Die Außenprobe umfasst eine kleine Gebäudeecke mit Wand, Fenster und Dach. Wand und Fensterrahmen besitzen erkennbare Tiefe. Dachneigung, Auflager, First und Überstand folgen dem Referenzblatt. Traufe und Ortgang bilden durchgehende Kanten. Die Dachfläche endet kontrolliert am Anschluss und schließt am First. Wandabschluss, Dachunterseite und Fensterlaibung werden auch seitlich geprüft.

Klaffende Dachnähte, schwebende Auflager, unplausible Wandstärken und sichtbare Durchdringungen sperren die Abnahme. Orthogonale Ansichten prüfen die Geometrie. Neutrale Beleuchtung und normale Spielkamera zeigen, ob die Ecke als zusammenhängendes Gebäude wirkt.

## Möbel und Maschinen

Die erste Holzserie teilt Materialien, geeignete Bauteile und eine abgestimmte Kantenbehandlung. Jedes Möbel erhält eine seiner Funktion entsprechende Silhouette und Konstruktion. Beim Hocker sitzen die Beine sichtbar unter der Sitzfläche. Bauteile und Montagezustand müssen geometrisch zusammenpassen. Weitere Serien beginnen erst nach bestandener Musterprobe.

Holzmaserung folgt dem Verlauf der einzelnen Bauteile. Ihre Größe bleibt über die Serie konsistent. Rohholz, Finish und Metall unterscheiden sich aus normaler Spielentfernung. Auflagen, Schutzabdeckungen und Durchlässe der Maschine erklären den Arbeitsbereich. Das Werkstück passt in die Maschine und behält beim Übergang seine Größe.

## Werkstücke und Fahrzeugladung

Holz wird als Bündel, zugeschnittene Teile werden in einem offenen Träger und fertige Möbel in einem passend dimensionierten Karton gezeigt. Die offenen Träger lassen Form und Menge erkennen. Kartonmarkierung und Mengenanzeige ergänzen die sichtbare Ladung. Der montierte Hocker bleibt vor dem Packen als solcher erkennbar.

Ladeflächen besitzen nachvollziehbare Grenzen und definierte Plätze. Ein Karton liegt sichtbar auf dem Anhänger auf und bleibt während der Fahrt befestigt. Beim Laden und Entladen ändert sich die sichtbare Ladung entsprechend der übertragenen Ware. Tore, Ladeflächen und Kurven werden mit dem beladenen Gespann geprüft. Spätere Fahrzeuggrößen erhalten vor der Modellserie eine eigene Probe für Ladevolumen, Ladehöhe, Durchfahrt und Wendefläche.

## Mindestset für P11

Die Anzahl bezeichnet Vorlagen. Ein Modell kann an mehreren Orten stehen oder reine Materialzustände teilen. Greybox-Vorlagen sind für Straßen und Übergabeplätze zulässig, wenn die Maße und der Warenweg stimmen.

| Gruppe | Mindestumfang |
| --- | --- |
| Produkt | 1 Hocker-Bauteilsatz, als offener Bausatz und montiertes Möbel. 2 Oberflächenzustände für Rohholz und Finish. |
| Produktion | Je 1 Säge, Montagebank, Finishplatz und Packtisch. 1 gerades Band mit passenden Anschlussmarkern. |
| Waren und Träger | Je 1 Holzpaket, offener Teileträger und Hockerkarton mit erkennbarer Kennzeichnung. |
| Architekturprobe | Je 1 Wand-, Fenster- und Eckmodul sowie 1 Dachflächenmodul, Abschluss für Traufe und Ortgang und Firststück. Je 1 Boden-, Tor- und Leuchtenvorlage. |
| Fahrzeug | 1 Quad, 1 kleiner Anhänger und 1 Vorlage für sichtbare Ladeplätze. |
| Route | Je 1 Vorlage für gerade Straße, Kurve, Abzweig und Übergabefläche. Vier eindeutig erkennbare Zielorte. |

Die Vorlagen dienen einer geschlossenen Hockerlinie mit Fahrzeugroute. Ein zweites Möbel ist der erste Nachweis, dass sich die Serie sinnvoll erweitern lässt. Größere Möbel erhalten passende Träger oder Paletten und eine zugehörige Fahrzeugklasse.

## Abnahme im Spiel

Die [Blender-Rolle](../roles/BLENDER.md) liefert bemaßte Quelldateien, Exporte und Ansichten. Die Studio-Integration prüft importierte Maße, Drehpunkte, Materialzuordnung, Normalen, Kollision und bewegliche Teile. Die finale Evidenz enthält Spielkamera, Außenansicht, Detailaufnahme und eine kleine Bildschirmansicht nach [TESTS](../qa/TESTS.md).

Freigegeben wird die importierte Probe anhand der dokumentierten Passungen, Lesbarkeit und gemeinsamen Wirkung. Größensprünge, Texturverzerrungen, kollidierende Werkstücke und unlesbare Ladungszustände erfordern eine Korrektur am Muster. Leistungsgrenzen ergeben sich aus Messungen am festgelegten Testgerät.

## Vorläufiges Asset-Budget

Stand 20. November 2026, vorgeschlagen mit der [HQ-Serie 1](../../assets/hq/README.md). Es gilt bis zur Messung am Zielgerät (P11-05) und wird danach bestätigt oder angepasst.

| Gruppe | Dreiecke | MeshParts |
|---|---:|---:|
| Ware | ≤ 2.500 | ≤ 4 |
| Station | ≤ 8.000 | ≤ 10 |
| Bandmodul | ≤ 2.500 | ≤ 6 |
| Halle mit 4 Stationen, 2 Bändern und 12 Waren | ≤ 60.000 | ≤ 90 |

- **Texturen:** Holz, Karton und Bandgummi teilen fünf kachelbare Sätze mit 512 px je 0,5 m. Lackierte, metallische und Kunststoffflächen bleiben ohne Textur und verwenden MeshPart-Farbe und -Material.
- **Geometrie:** Sie wird je Material zu einem MeshPart zusammengefasst. Bewegliche oder umfärbbare Teile wie Sägeblatt, Drehteller, Lüfter und Statuslampe bleiben eigene MeshParts.


## Modellierungsvergleich

Die kleine importierte Werkstatt ist ausschließlich ein KI-Vergleichs- und Importtestobjekt. Jonas hat am 12. November 2026 ausdrücklich klargestellt, dass sie nicht als Gebäude der Spielkarte vorgesehen ist. Eine Bevorzugung des Testentwurfs gibt weder dieses Gebäude für das Spiel frei noch bindet sie das Mapdesign an seine Größe. Die eigentliche Fabrik und weitere Kartenassets erhalten eigene Entwürfe.

Jonas hat in beiden Werkstattproben Fables Entwurf bevorzugt, zuletzt am 11. November 2026 mit dem Urteil "A eindeutig besser". Diese Auswahl bleibt eine gestalterische Referenz und ist keine allgemeine Modellrangliste.

Nutzerkorrektur vom 17. November 2026: **Fable 5.2 steht nicht mehr kostenlos zur Verfügung.** Die weitere Umsetzung setzt deshalb keinen kostenlosen Fable-Zugang voraus. Vorhandene Blender-Quellen, Exporte und Referenzen werden weiterverwendet. Die Qualitäts- und Abnahmekriterien dieses Vertrags bleiben verbindlich.

Anschließender ausdrücklicher Nutzerauftrag: **Opus 5.5 übernimmt die weitere Modellarbeit.** Der Lead hat `claude-opus-5-5` über Claude Code gestartet und die Modellkennung sowie erfolgreiche Blender-MCP-Aufrufe geprüft. Opus prüft den tatsächlichen offenen Blender-Stand vor Änderungen; Quellen und Ausgangsszenen bleiben erhalten. Codex übernimmt Briefings, technische Gegenprüfung, Spielcode und Studio-Integration. Zusätzliche kostenpflichtige 3D-Generierungsdienste sind nicht beauftragt.

Die gewaehlte Werkstatt hat 13.080 Dreiecke. Quellen, Zuordnung, Messungen und der noch offene Studio-Import sind im [Setup-Beleg](../evidence/P00-STUDIO-SETUP.md) auffindbar. Die Gestaltungsauswahl ersetzt die Abnahme im Spiel nicht.
