# Beistelltisch01 als zweites Rezept

Stand 25. November 2026. Entwurfsvertrag für **P10-01**, Rezept `Beistelltisch01`, Version 1. Mengen, Zeiten und Preise sind vorläufige Prüfwerte wie beim [Hockerrezept](PRODUCTION.md). Die Maße und der Wirtschaftsvergleich sind per [Skript](../../tools/tests/p10-01-sidetable-fit.mjs) nachgerechnet (39 von 39 Prüfungen). Es gibt noch kein Modell und keine Umsetzung im Spiel. [Beleg](../evidence/P10.md#p10-01--beistelltisch-als-zweites-rezept)

[Spielkern](CORE.md) · [Wirtschaft](ECONOMY.md) · [Maßblatt](DIMENSIONS.md) · [Verladekette](LOGISTICS.md) · [Zustandsregeln](../technical/STATE.md)

## Entscheidungen

1. **Gleiche Stationen, gleiche Plätze.** Der Tisch läuft über Säge, Montagebank, Finishplatz und Packtisch. Jede Station bearbeitet eine Charge und jede Stufe belegt genau einen Platz. Eingangs-, Ausgangs-, Lager- und Anhängerplätze bleiben unverändert.
2. **Kein Gut, das mehrere Plätze belegt.** Reservierung, Umbuchung, Fahrzeugplätze und Bandpuffer rechnen mit einer Charge je Platz. Ein Tisch, der zwei Anhängerplätze braucht, würde diese Regeln in allen Modulen ändern. Der Unterschied beim Platz entsteht stattdessen über den Wert je Platz (siehe Vergleich).
3. **Gleicher Träger, gleiches Band.** Der Tisch-Bausatz liegt im selben offenen Träger (0,60 × 0,18 × 0,50 m). Der Puffer `Band.First` und die Auflagen bleiben unverändert.
4. **Stufen.** Eine Stufe ist ein Bearbeitungsstand, `recipeId` an der Charge nennt das Produkt. `Holzpaket`, `Bausatz`, `Fertig` und `Karton` gelten für beide Rezepte, neu ist nur `Rohtisch`. Der Mitarbeiter- und Bandweg und die Fahrzeug-, Lager- und Verkaufsprüfungen arbeiten mit Stufennamen und bleiben dadurch unverändert. Bestehende Spielstände bleiben ohne Migration gültig. Eine Charge behält ihre Rezeptzuordnung bis zum Verkauf.
5. **Zwei Holzangebote.** Der Lieferant bietet ein Holzpaket für den Hocker (60) und ein Tischholzpaket (80) an. Der einmalige Materialvorschuss bei Stillstand bleibt auf das Hocker-Holzpaket (60) begrenzt.

## Rezept

| Schritt / Station | Eingang pro Lauf | Ausgang pro Lauf | Bearbeitung |
| --- | --- | --- | --- |
| Zuschnitt / Säge | 1 Tischholzpaket mit 10 Teilen | 1 offener Träger mit 10 Teilen | 8 s |
| Montage / Montagebank | 1 vollständiger Tisch-Bausatz | 1 montierter Rohtisch | **14 s** |
| Finish / Finishplatz | 1 Rohtisch | 1 fertiger Tisch | 8 s |
| Verpackung / Packtisch | 1 fertiger Tisch | 1 geschlossener Tischkarton | 5 s |

Bilanz einer Charge: 1 Tischholzpaket → 1 Bausatz → 1 Rohtisch → 1 fertiger Tisch → 1 Karton mit 1 Tisch. Die reine Stationszeit beträgt 35 s. Die Montage ist die längste Station und bestimmt den Takt der Linie. Beim Hocker bestimmt sie mit 8 s ebenfalls den Takt.

## Vergleich mit dem Hocker

| Kennzahl | Hocker01 | Beistelltisch01 |
| --- | --- | --- |
| Teile im Bausatz | 9 | 10 |
| Holzvolumen der Teile | 7,5 dm³ | 9,7 dm³ (+29 %) |
| Einkauf je Charge | 60 | 80 |
| Händlererlös | 100 | 140 |
| Privatspanne (±20 %) | 80 bis 120 | 112 bis 168 |
| Gewinn je Charge am Händler | 40 | 60 |
| Montagezeit | 8 s | 14 s |
| Stationszeit gesamt | 24 s | 35 s |
| Gewinn je Montage-Sekunde | **5,00** | 4,29 |
| Gewinn je Anhänger- oder Lagerplatz | 40 | **60** |
| Gewinn je eingesetztem Spielgeld | 0,67 | **0,75** |

Es gibt einen echten Zielkonflikt. Wer die Montage auslastet, verdient mit dem Hocker mehr je Sekunde. Wer durch Fahrten und Lagerplätze begrenzt ist, verdient mit dem Tisch mehr je Platz. Der Tisch verlangt außerdem 20 Spielgeld mehr Einsatz je Charge. Die Ausrüstung aus P10-04 (größere Montagekapazität) verschiebt diese Abwägung. Die Werte sind Prüfwerte. Beim Balancing bleibt die Bedingung, dass kein Rezept in allen Kennzahlen vorn liegt.

## Werkstück

Der Tisch ist ein quadratischer Beistelltisch mit überstehender Platte, schlanken Beinen, Zargen und einem Ablageboden. Der Ablageboden und die schlankeren Beine unterscheiden die Silhouette vom Hocker. Das Stufenschild nennt „Rohtisch“ beziehungsweise „Fertig“, der Karton trägt ein Tischsymbol und „1 Tisch“.

Hülle des montierten Tischs: **0,42 × 0,48 × 0,42 m** (X × Y × Z), Pivot wie bei allen Waren in der Mitte der Grundfläche.

| Teil | Anzahl | Maß m | Lage im montierten Tisch |
| --- | --- | --- | --- |
| Platte | 1 | 0,42 × 0,025 × 0,42 | Y = 0,455 bis 0,48; Überstand 0,045 m rundum |
| Bein | 4 | 0,03 × 0,455 × 0,03 | Mittelpunkte X/Z = jeweils ±0,15; Fuß Y = 0; Kopf endet bündig unter der Platte |
| Zarge | 4 | 0,27 × 0,07 × 0,02 | Y = 0,385 bis 0,455; bündig mit der Beinaußenseite, Enden stoßen an die Beininnenseiten |
| Ablageboden | 1 | 0,33 × 0,02 × 0,33 mit vier Eckausschnitten 0,03 × 0,03 | Y = 0,17 bis 0,19; die Beine stehen in den Ausschnitten |

Das Gestell misst außen 0,33 × 0,33 m, zwischen gegenüberliegenden Beininnenseiten liegen 0,27 m, passend zur Zargenlänge und zum Boden.

## Packlage im Holzpaket und im Träger

Dieselbe Anordnung liegt im Tischholzpaket (außen 0,60 × 0,15 × 0,50 m, innen 0,58 × 0,13 × 0,48 m) und im offenen Träger (nutzbar 0,58 × 0,48 m). Koordinaten in Metern relativ zum Warenpivot, Boden oben bei Y = 0,01.

- Platte: X = -0,2825 bis +0,1375, Z = ±0,21, Y = 0,01 bis 0,035.
- Vier liegende Beine: Z = ±0,2275, Y = 0,01 bis 0,04. Die X-Unterkanten sind 0,1425 / 0,1775 / 0,2125 / 0,2475, Breite je 0,03.
- Ablageboden auf der Platte, um X = -0,0725 zentriert, Y = 0,035 bis 0,055.
- Vier flach liegende Zargen in zwei Lagen auf dem Boden, Y = 0,055 bis 0,095, je zwei nebeneinander bei Z = -0,0725 bis -0,0025 und +0,0025 bis +0,0725.

Die kleinste Luft beträgt 0,0075 m in X, 0,0125 m in Z und 0,045 m in der Höhe. Zwischen Platte und erstem Bein bleiben 0,005 m Fuge. Alle zehn Teile liegen auf dem Boden oder auf einem tiefer liegenden Teil.

## Transportgrößen

| Ware | Hülle m (X × Y × Z) | Auflage 0,70 × 0,60 m mit 0,05 m Rand (nutzbar 0,60 × 0,50) | Anhängerplatz 0,65 × 0,55 m | Tragen (Unterseite 0,70 m) |
| --- | --- | --- | --- | --- |
| Tischholzpaket | 0,60 × 0,15 × 0,50 | passt exakt, Oberkante 1,05 m | passt, Luft 0,05 / 0,05 m, Oberkante 0,70 m | Abschluss 0,85 m |
| Offener Bausatz | 0,60 × 0,18 × 0,50 (derselbe Träger) | passt exakt, Oberkante 1,08 m | nur intern | Abschluss 0,88 m |
| Rohtisch / fertiger Tisch | 0,42 × 0,48 × 0,42 | passt, Oberkante 1,38 m | nur intern | Abschluss 1,18 m |
| Tischkarton | 0,48 × 0,54 × 0,48 (innen 0,46 × 0,52 × 0,46, 0,02 m Luft) | passt, Oberkante 1,44 m | passt, Luft 0,17 / 0,07 m, Oberkante 1,09 m | Abschluss 1,24 m |

Der Tischkarton bleibt unter dem freien Warenraum bis 1,45 m (Reserve 0,01 m) und unter der Lagerschild-Unterkante bei 1,475 m (Reserve 0,035 m). Das begrenzt die Tischhöhe. Ein höheres Produkt bräuchte höhere Schilder oder niedrigere Auflagen. Auf dem Anhängerdeck bleibt der Karton mit 1,09 m unter der Prüfhülle von 1,15 m. Das Tischholzpaket nutzt die Längsachse quer zur Fahrt wie das Hocker-Holzpaket.

## Auswirkungen auf die Umsetzung

Das gilt für P10-02 und später. P10-01 ändert weder Code noch Studio.

- Umgesetzt in P10-02: [Recipes](../../src/server/Recipes.luau) hält Stufen, Zeiten und Preise beider Rezepte. `State` prüft Rezept und Stufe je Charge, `State.STATIONS` bleibt die Quelle der Stationsplätze, die Zeiten kommen über `State.ruleFor` aus dem Rezept der Charge.
- Stationsplätze nehmen die Stufen beider Rezepte an (`Recipes.acceptedStages`). Die Säge startet nur Pakete des gewählten Rezepts, spätere Stationen folgen dem Rezept der Charge.
- Der Verkauf nimmt den Preis aus dem Rezept der Charge. Händlererlös und Privatspanne stehen oben.
- Der Einkauf liefert das Holzpaket des gewählten Rezepts zu dessen Preis, der Materialvorschuss bleibt beim Hocker.
- Darstellung: eine `TableView` analog zu `StoolView` und `KitView` mit den Maßen oben, dazu Labels in Englisch und Deutsch.
- Unverändert bleiben Band, Bandpuffer, Fahrzeugplätze, Lagerplätze und die Reservierungsregeln.

## Offen

- Es gibt kein Blender-Modell und keine Art-Freigabe. Greybox-Teile genügen für P10-02 bis P10-05.
- Die Spielprüfung der Maße (Auflage, Lager, Anhänger, Tragen) steht aus und gehört in P10-05.
- Preise, Zeiten und Privatspanne sind Balancing-Prüfwerte.
