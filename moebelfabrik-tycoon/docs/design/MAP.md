# Spielkarte · organisch gewachsene Stadt

Stand 12. November 2026. **P02-03R**, erste Stadt-Greybox. Verbindliche Nutzerklärung: eine gewachsene Stadt ohne Spiegelung, mit mehreren Tischlereien. Die kleine Werkstatt bleibt ausschließlich das KI-Vergleichsobjekt. Die alte Ringfassung ist archiviert und kein Endkonzept.

## Aktueller Grundriss

Eine geschwungene Hauptstraße verbindet ungleich große Stadtblöcke. Nord-/Südstraße, Marktgasse, Kirchgasse, Mühlgasse, Gartenweg und weitere Seitenstraßen bilden Kreuzungen, kleine Schleifen und Sackgassen. Es gibt keinen übergeordneten Umfahrungsring und keine vier gespiegelten Quadranten. Ortskern, Wohnviertel und Gewerberand besitzen unterschiedliche Bebauungsdichten und Fluchten.

Gebaut: **19 Straßen/Zufahrten, 87 geglättete Segmente, vier Tischlereien, 47 Gebäudeplatzhalter und 41 Bäume**. Darunter stehen 33 entlang ihrer Straßenfront ausgerichtete Häuser; die übrigen Gebäude stellen Betriebe, Läden und Wohnhäuser dar. Gehwege ergänzen die öffentlichen Straßen. Der Ortskern besitzt einen kleinen Platz mit Läden und Bänken.

Führende Quelle: [Stadt-Builder](../../tools/studio/build-p02-03r-city.luau). Live-Modell `Workspace.CityGreybox`, Revision 1. Unabhängiger Ursprung **(430;0;450) Studs**, Grundfläche **260×210 m**; Maßfaktor 25/7 Studs/m. Alle folgenden Angaben sind lokale X/Z-Koordinaten in Metern.

| Ort | Gebäudezentrum X/Z | Ladehof X/Z |
| --- | --- | --- |
| Start-Tischlerei West | -73 / -21 | -72 / -7 |
| Tischlerei Nord | -12 / -80,8 | -11 / -93 |
| Tischlerei Süd | -51 / 81 | -50 / 66 |
| Tischlerei Ost | 100,7 / 18 | 99 / 34 |
| Holzlieferant am Gewerberand | -112 / 83 | -112 / 66 |
| Möbelhandel | 75 / 89 | 73 / 73 |
| Privatkunden im Lindenviertel | mehrere Wohnhäuser | 8 / 78 |

Jeder Betrieb besitzt eine eigene erreichbare Zufahrt und Ladefläche. Die vier Werkstattgrundstücke sind unterschiedlich zugeschnitten und über die Stadt verteilt; sie sind keine vier identischen Tycoon-Platten. Die Höfe sind zunächst 12×12-m-Prüfflächen. Hauptstraße 7,50 m, Nebenstraßen 5,50–6,50 m; die tatsächliche Fahrzeug- und Schleppflächenprüfung folgt mit dem Gespann.

Die Start-Tischlerei ist als betretbare Hallenprobe gebaut. Andere Gebäude sind äußere Platzhalter. Der Spawn liegt auf dem Fußbereich der Start-Tischlerei, außerhalb des Straßenverkehrs. Der technische Prüfträger liegt in `ServerStorage.P02CarryProbe` und gehört nicht zum automatischen Spielstart.

## Prüfung und verbleibende Arbeit

[Lesender Check](../../tools/studio/check-p02-03r-city.luau) und [Prüfbeleg](../evidence/P02-03R.md) dokumentieren Straßenzusammenhang, sieben angeschlossene Ziele, Gehwegfreiheit und Einstieg. Drei Sockel-/Gehwegkonflikte wurden anhand einer unabhängigen Gegenprüfung korrigiert. Die 47 Gebäude wurden anschließend gegen alle Gehwegstreifen geprüft.

Der alte Ring bleibt unter `ServerStorage.MapPrototypes.MapGreybox` erhalten. Vergleichsmodell, Maßfeld und Stationsprobe werden nicht als Spielgebäude wiederverwendet. Gebäude, Materialien, Landschaft und Details sind noch nicht die finale Art; die Benutzerfreigabe der endgültigen Gestaltung bleibt offen. Es gibt hier noch keine Warenproduktion, wirtschaftlichen Buchungen, NPC-Arbeit oder Persistenz. P02-02-Trageabnahme und Fahrzeugtests bleiben getrennte offene Aufgaben.
