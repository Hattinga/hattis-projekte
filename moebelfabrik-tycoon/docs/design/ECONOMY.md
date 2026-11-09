# Wirtschaft

Der Betrieb verdient Spielgeld mit gelagerten Möbeln, die der Spieler an Käufer ausliefert. Der [Spielkern](CORE.md) beschreibt den Warenfluss und die Entwicklung von Handarbeit zu Personal und Förderbändern.

## Einkauf und Lagerproduktion

- Der Lieferant zeigt Materialtyp, Menge und Preis. Gekaufte Ware steht dort zum Verladen bereit. Das Fahrzeug bringt sie in das Rohstofflager der Fabrik.
- Der Spieler wählt das aktive Möbelrezept. Eingänge, Stationskapazität und Platz am Ausgang bestimmen, wann die Linie produziert. Fertige Möbel stehen bis zum Verkauf im Fertigwarenlager. Der Produktionsstart ist unabhängig von Käufern.
- Rohstoffe, Zwischenprodukte, Fertigwaren und Fahrzeugladung haben erkennbare Bestände. Ein voller Ausgang hält die Linie an. Entnahme oder Verkauf schafft Platz für den nächsten Durchlauf. Ein Modellwechsel erhält bereits begonnene Werkstücke und zeigt, welche Zutaten die neue Produktion benötigt.

## Verkauf nach der Fahrt

Die Verkaufsmenge wird beim Verladen sichtbar. Der Spieler fährt zum Verkaufsort und übergibt die Fracht dort. Die bestätigte physische Übergabe ist die Voraussetzung für Warenabgang und Gutschrift.

| Verkaufsweg | Entwurf für den Test |
| --- | --- |
| Möbelhändler | Bekannter Preis je Modell. Vor der Bestätigung zeigt die Übergabeansicht Menge und Gesamterlös. |
| Privatkäufer | Käufer vorläufig als NPC. Die Ansicht zeigt Händlervergleich und mögliche Auszahlungsspanne für die gewählte Menge. Der Spieler wählt den Privatverkauf vor der Preisenthüllung verbindlich. |

Bei bestätigter Übergabe an den Privatkäufer wird der Betrag einmal pro Verkaufs-ID ermittelt. Er kann über oder unter dem Händlererlös liegen. Warenabgang, festgelegter Betrag und Gutschrift gehören zur selben Abrechnung. Nach einer Wiederverbindung wird der bestätigte Verkauf mit demselben Betrag abgeschlossen. Ein Abbruch vor der Bestätigung lässt die Ware verfügbar und zeigt keinen ausgelosten Preis.

**Reines Testbeispiel.** Eine Materialcharge kostet 60 Spielgeld. Der Händler zahlt 100 für das fertige Möbel. Die Privatspanne beträgt im Test 80 bis 120. Für die Abnahme werden 80 und 120 gezielt ausgelöst. Diese Zahlen sind Prüfwerte. Preisspannen und Verteilung bleiben Balancing-Entscheidungen.

## Liquidität und Wiederanlauf

- Der Händlererlös des Einstiegsrezepts deckt in der Testwirtschaft die Rohstoffkosten. Verkaufsvorschau und Materialpreis helfen dem Spieler, Geld für den nächsten Einkauf einzuplanen.
- Für einen Stillstand durch Geldmangel ist ein zweckgebundener Materialvorschuss vorgesehen. Er ermöglicht einen Produktionszyklus, erzeugt keinen direkten Geldzufluss und kann während eines offenen Vorschusses nur einmal beansprucht werden. Ob er beim Verkauf verrechnet wird, wird im Solvenztest entschieden.

## Shop

Der erspielbare Ausrüstungskauf umfasst zuerst eine Verbesserung mit nachvollziehbarer Wirkung auf Kapazität oder Durchsatz. Der Lieferant verkauft Rohstoffe, Käufer nehmen fertige Möbel ab. Ein begehbarer Showroom und Angebote gegen Robux sind eigenständige, offene Entscheidungen.

Die Prüfungen für Bestände, Verkäufe, Wiederanlauf und Bedienbarkeit stehen in der [Testübersicht](../qa/TESTS.md).
