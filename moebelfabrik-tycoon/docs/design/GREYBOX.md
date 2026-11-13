# Greybox-Stellplan

Stand 12. November 2026. P02-02, Revision 1. Konkrete Testgeometrie für den [Waren- und Maßvertrag](DIMENSIONS.md) und die [Stationsübergaben](PRODUCTION.md). Die Probe liegt neben Fables bestehender Werkstatt und ist ein Testaufbau vor der späteren Art-Integration.

**Klarstellung:** Weder die kleine Vergleichswerkstatt noch dieses technische Stationsfeld sind das vorgesehene Fabrikgebäude oder der Grundriss der Spielkarte. Die separate Kartenplanung steht in [MAP](MAP.md). Die P02-02-Trageabnahme ist noch offen; der Aufbau darf nicht als fertiger Spielbereich geführt werden.

## Zuständigkeit und Koordinaten

Führende Aufbauquelle ist `tools/studio/build-p02-02.luau`. Die neuen Teile liegen in `Workspace.P02Line`; der separate native Prüfträger liegt seit der Kartenkorrektur in `ServerStorage.P02CarryProbe` und wird ausschließlich für explizite Tests ausgerüstet. P02-eigene Referenzavatar-/Würfelpositionen und zwei Schilder in `Workspace.P02Greybox` werden versetzt. FableWorkshop, Baseplate und SpawnLocation waren nicht Teil dieser Stationsänderungen.

Alle folgenden X/Y-Koordinaten sind Meter im bestätigten **alten Werkstatt-Quellsystem**: horizontales X/Y, Höhe separat. Die Umrechnung benutzt den vorhandenen Pivot und `Vector3.new(-X, Höhe, Y) * 25/7`, wie beim Werkstattimport. Eine neue Blender-Exporttransformation wird nicht zusätzlich auf diese Quelle angewendet.

## Fläche und Wege

Das ursprüngliche 6×4-m-Maßfeld bleibt erhalten. Vier neue, seitlich anschließende Bodenstreifen bilden zusammen eine Fläche von **8×7 m**: X = -16 bis -8, Y = -1 bis 6. Alle Bodenoberkanten liegen bei Welt-Y = 0,5 Studs. Die Vergrößerung betrifft die Testfläche, keine Änderung der P01-Waren- oder Stationsmaße.

| Bereich | Grenzen / Breite |
| --- | --- |
| Mittelgang | Y = 2,5 bis 4,1; **1,60 m** |
| Linker Umgang | X = -16 bis -14,5; **1,50 m** |
| Rechter Umgang | X = -9,5 bis -8; **1,50 m** |
| Vorderer Gang | Zwischen Lagerkörpern bis Y = 0,4 und vorderer Stationskante Y = 1,7; **1,30 m** geometrisch, mindestens 1,20 m als Gehbereich vorgesehen |
| Torzugang | Zwischen Rohstoff- und Fertiglager X = -13,15 bis -10,85; **2,30 m** frei. Das vorhandene Referenztor mit 2,26 m äußerer Rahmenbreite bleibt darin stehen. |

Die bestehende Fußverbindung vom Spawn bleibt frei. Avatarreferenz und Meterwürfel rücken hinter die Stationen: (-14,8; 5,5) und (-9,0; 5,45). Diese Referenzkörper sind keine begehbare Stationsfläche. Wege dürfen nicht durch sie abgekürzt werden, auch wenn sie als Prüfhüllen keine Kollision besitzen.

## Stationen und Lager

| Station | Mittelpunkt X/Y | Ausrichtung / Warenfluss |
| --- | --- | --- |
| 1 Säge | -13,3 / 4,5 | Lokales +X; Eingang links, Ausgang rechts |
| 2 Montage | -10,7 / 4,5 | Lokales +X; Eingang links, Ausgang rechts |
| 3 Finish | -10,7 / 2,1 | Um 180° gedreht; Warenfluss nach -X |
| 4 Packen | -13,3 / 2,1 | Um 180° gedreht; Warenfluss nach -X |

Stationen behalten die 2,40×0,80-m-Grundfläche. Die feste Körperhöhe ist 0,88 m; 0,02-m-Auflagen enden auf der vereinbarten Höhe 0,90 m. Die Schilder stehen außerhalb der Werkstückgrundfläche. Die frei zu haltende Gesamt-Waren-/Stationshülle bleibt bis 1,45 m hoch.

Jede Station besitzt `Input`, `Process`, `Output`, jeweils 0,70×0,60 m. Die Auflagemittelpunkte liegen lokal bei X = -0,80 / 0 / +0,80. Je Auflage definiert genau ein `Transfer`-Attachment den gemeinsamen Punkt für Hand, Personal und Band. Standpunkte im Mittelgang ergänzen die Annäherung, ohne einen zweiten Warenplatz zu erzeugen. Farben und Aufschriften IN/ARBEIT/OUT unterstützen die Unterscheidung.

| Lager | Vier Slotmitten X, jeweils Y = 0,10 |
| --- | --- |
| Rohstofflager | -15,60 / -14,90 / -14,20 / -13,50 |
| Fertiglager | -10,50 / -9,80 / -9,10 / -8,40 |

Alle acht Slots liegen in einer einzigen vorderen Reihe, mit je 0,70×0,60 m Auflage und Höhe 0,90 m. Nummern unterscheiden die Plätze. Die Annäherung erfolgt vom vorderen Gang bei Y = 1,10; niemand muss über eine zweite Lagerreihe greifen. Lagerschild-Unterkanten liegen bei 1,475 m und damit über einem aufliegenden 0,51-m-Karton mit Oberkante 1,41 m.

Die erste gerade **Bandvorschau** verbindet Sägeausgang (-12,50; 4,50; H 0,90) mit Montageeingang (-11,50; 4,50; H 0,90). Die Entfernung beträgt 1,00 m, die nutzbare Breite 0,70 m. Die Vorschau markiert diese bestehenden Anschlüsse; sie bewegt keine Ware und erzeugt keinen zusätzlichen Puffer.

## Werkstückprobe und Abnahmegrenze

Ein nativer Roblox-Prüfträger enthält den offenen Träger und neun fest verbundene Holzteil-Stellvertreter. Seine Außenmaße sind 0,60×0,18×0,50 m. Er ist als reine Messhilfe gekennzeichnet und bleibt ohne Laufzeitskripte. Der Tester rüstet ihn aus dem Rucksack aus und läuft mit ihm vom Rohstofflager über die Eingangs-/Ausgangsstandpunkte aller vier Stationen zum Fertiglager. Die Vorlage ist kein zusätzlicher Warenbestand und keine gelieferte oder produzierte Charge.

Die Route führt vom vorderen Gang links um die erste Zeile in den Mittelgang, durchläuft die U-Folge und kehrt links zum vorderen Gang zurück. Zusätzlich werden alle acht Lagerplätze einzeln geprüft. Neben Avatarbewegung und Boden gehört die sichtbare Trägerhülle zur Prüfung: ihre nicht kollidierenden Teile dürfen nicht einfach durch die Stationskörper laufen. Die endgültige Tragepose und das beobachtete Ergebnis stehen im P02-02-Prüfbeleg.

P02-02 weist Stellplätze, gemeinsame Anschlüsse und den tatsächlichen Fuß-/Trageweg nach. Bearbeitung, Umbuchung, Rezeptfortschritt, automatische Bänder, Personal, Warenreservierungen und Persistenz werden erst in den vorgesehenen Folgephasen implementiert. Der reale Fahrzeugrundkurs und der Spawn in der Sollanfahrt bleiben P02-03/P02-05.
