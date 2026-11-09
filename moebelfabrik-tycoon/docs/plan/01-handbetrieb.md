# Handbetrieb, Beschaffung und Verkauf

[Planübersicht](../../UMSETZUNGSPLAN.md) · [Technische Zustände](../technical/STATE.md) · [Prüfmatrix](../qa/TESTS.md) · [Weiter zur Automatisierung](02-automatisierung.md)

## P04 · Bestand und frühe Persistenz

**Voraussetzungen** P00 und P01 sind abgenommen. Testumgebung und Schreibziele sind eindeutig. Die technische Grundlage steht in [STATE.md](../technical/STATE.md).

- [ ] **P04-01** Eigentümer, Geld, Chargen, Warenorte und Kapazitäten als verbindlichen Serverzustand definieren. Jede Charge erhält eine stabile ID und genau einen logischen Ort.
- [ ] **P04-02** Gemeinsame Berechtigungs- und Zustandsprüfung für Spieleraktionen festlegen. Ungültige Mengen, fremde Bestände, volle Ziele und veraltete Revisionen werden verständlich abgewiesen.
- [ ] **P04-03** Reservierung und gemeinsame Umbuchung von Quelle und Ziel umsetzen. Wiederholte Vorgangs-IDs ergeben dasselbe Resultat. Reservierungen können kontrolliert ablaufen.
- [ ] **P04-04** Ein versioniertes Profil für Geld, Bestand und laufenden Fortschritt laden. Startdaten entstehen erst nach bestätigtem Fehlen eines bestehenden Profils.
- [ ] **P04-05** Schreibvorgänge an Sitzungsbesitz und Profilrevision binden. Eine verspätete oder abgelöste Sitzung kann den neueren Stand nicht überschreiben.
- [ ] **P04-06** Bestätigten Speichervorgang und unklaren Schreibausgang getrennt behandeln. Bei Ladefehler bleiben wirtschaftliche Aktionen gesperrt. Nach einem Absturz gilt der letzte bestätigte Stand.
- [ ] **P04-07** Wiederherstellung für reservierte und bereits umgebuchte Ware festlegen. Der bestätigte Ort wird rekonstruiert oder über einen ausgewiesenen physischen Abholpunkt wieder erreichbar gemacht.
- [ ] **P04-08** P04-Prüfungen mit künstlichen Chargen aus der [Prüfmatrix](../qa/TESTS.md) ausführen und die Ergebnisse im Fortschritt festhalten.

**Abnahme** Dieselbe Charge kann bei konkurrierenden Übergaben genau einmal übernommen werden. Wiederbeitritt stellt den bestätigten Bestand wieder her. Ladefehler und alte Sitzungen überschreiben keine gültigen Daten. Diese Abnahme liegt vor wirtschaftlich relevanten Tests.

**Nachweis** Testlauf, verwendeter Profilstand und Ergebnis für Konkurrenz, Wiederbeitritt und erzwungenen Ladefehler vermerken.

## P05 · Einkauf und manuelle Dauerproduktion

**Voraussetzungen** P02 und P04 sind abgenommen. Werkstattplätze, Hocker und handliche Transportformate sind als Testaufbau festgelegt.

- [ ] **P05-01** Ein Hockerrezept mit vier Stationen und erkennbaren Zwischenzuständen hinterlegen. Jede Station erhält feste Eingänge, Ausgänge und Puffergrenzen.
- [ ] **P05-02** Einen Materialkauf mit Spielgeld abwickeln. Der Einkauf belastet das Profil und stellt die Charge am Lieferantenabholplatz bereit.
- [ ] **P05-03** Aufnehmen und Ablegen eines Arbeitsloses an den richtigen Übergabepunkten ermöglichen. Trageanzeige und Rückmeldung erklären Inhalt, Ziel und Ablehnungsgrund.
- [ ] **P05-04** Das Holzpaket an der Säge in einen sichtbaren Bausatz umwandeln.
- [ ] **P05-05** Den Bausatz an der Montagebank zu einem erkennbaren Rohhocker verarbeiten.
- [ ] **P05-06** Den Rohhocker am Finishplatz bearbeiten und die gewählte Oberfläche sichtbar anwenden.
- [ ] **P05-07** Den fertigen Hocker am Packtisch in einen passenden Karton umwandeln und den Karton im Fertigwarenlager einlagern.
- [ ] **P05-08** Die versorgten Stationen mit dem aktiven Rezept fortlaufend arbeiten lassen. Ein Maschinenlauf reserviert Platz für sein Ergebnis. Bei vollem Lager entsteht sichtbarer Rückstau, bevor weiterer Input verbraucht wird.
- [ ] **P05-09** Einkauf und komplette Handkette mit der [Prüfmatrix](../qa/TESTS.md) prüfen. Für den isolierten Stationstest gekennzeichneten Testbestand verwenden. Die reguläre Beschaffungsfahrt folgt in P06.

**Abnahme** Ein Spieler kann Holz kaufen, Zwischenprodukte tragen und ohne vorherigen Kundenauftrag mehrere Hocker herstellen und lagern. Falsche Ablagen erhalten die Ware. Ein volles Lager stoppt die Linie verständlich. Der Kauf allein liefert kein Holz in die Fabrik.

**Nachweis** Einen vollständigen Hocker-Durchlauf mit Eingangs- und Endbestand sowie Status bei vollem Ausgang dokumentieren.

## P06 · Quad, Ladung und echte Fahrten

**Voraussetzungen** P02, P04 und P05 sind abgenommen. Maße für Ladeplätze, Hockerkarton, Anhänger und Ladezonen sind abgestimmt.

- [ ] **P06-01** Eine kurze befahrbare Strecke mit Lieferant, Werkstatt, Händler und Privatkundenplatz als Testumgebung abstecken.
- [ ] **P06-02** Ein steuerbares Quad und einen kleinen Anhänger zunächst mit maßhaltiger Stellvertretergeometrie bereitstellen. Wendeflächen und Anfahrt auf der tatsächlichen Strecke prüfen.
- [ ] **P06-03** Dem eigenen Fahrzeug feste Ladeplätze und nachvollziehbare Kapazitätsgrenzen zuweisen.
- [ ] **P06-04** Physisches Beladen am Lieferanten und an der Werkstatt mit den Bestandsumbuchungen verbinden. Ware erscheint befestigt am bestätigten Ladeplatz.
- [ ] **P06-05** Entladen am passenden physischen Ziel mit Prüfung von Fracht, Fahrzeug, Eigentümer und Ladezone umsetzen. Ein volles Ziel lässt die Ware auf dem Fahrzeug.
- [ ] **P06-06** Für die spätere Verkaufsfreigabe serverseitig beobachtbare Fahrtmerkmale und bestätigte Ankunft erfassen. Eine bloße Berührung oder behauptete Zielposition genügt nicht.
- [ ] **P06-07** Fahrzeugladung beim Wiederbeitritt gemeinsam mit dem übrigen Bestand wiederherstellen. Einen physischen Bergungs- und Abholweg für technisch nicht wiederherstellbare Positionen vorsehen.
- [ ] **P06-08** Die gesamte Fahrt mit Holz zur Werkstatt und einem Hockerkarton bis zur Käuferzone prüfen. Die eigentliche Verkaufsabrechnung folgt in P07.

**Abnahme** Rohstoffe und Fertigware erreichen ihr Ziel über echte Fahrten. Sichtbare Ladung und bestätigte Ladeplätze stimmen überein. Doppeltes Entladen, falsche Zone, zu große Ladung und Wiederbeitritt führen zu eindeutigen, bestandsneutralen Ergebnissen.

**Nachweis** Fahrt und Übergabepunkte mit Video oder Screenshots festhalten. Bestände vor dem Beladen, nach dem Entladen und nach Wiederbeitritt protokollieren.

## P07 · Händler, Privatverkauf und kompletter Kreislauf

**Voraussetzungen** P06 ist abgenommen. Beide Käuferzonen sind erreichbar. Verwendete Testpreise und Privatspanne sind als vorläufig gekennzeichnet.

- [ ] **P07-01** Für eine gültige Übergabe nur die bestätigte Menge aus den passenden Fahrzeugladeplätzen reservieren. Käufer, Ladezone und Fahrtzustand serverseitig prüfen.
- [ ] **P07-02** Beim Möbelhändler den bekannten Modellpreis und Gesamterlös für die reservierte Menge anzeigen und verwenden.
- [ ] **P07-03** Beim Privatkunden Menge, Händlervergleich und möglichen Erlösbereich vor der bindenden Bestätigung anzeigen. Abbruch vor Bestätigung gibt die Reservierung frei.
- [ ] **P07-04** Den Privaterlös nach Bestätigung einmal serverseitig festlegen und mit der Verkaufs-ID wiederherstellbar speichern. Wiederholte Schreibversuche verwenden das festgelegte Ergebnis.
- [ ] **P07-05** Warenabgang, Geldgutschrift und Verkaufsabschluss in derselben geprüften Profiländerung speichern. Den Beleg erst nach bestätigtem Abschluss anzeigen.
- [ ] **P07-06** Bei unterbrochenem Verkauf den vorhandenen Status wieder aufnehmen. Ein bereits bezahlter Vorgang liefert denselben Beleg. Ein unklarer Schreibausgang wird vor einem neuen Versuch geprüft.
- [ ] **P07-07** Eine begrenzte, zweckgebundene Wiederanlaufhilfe für fehlendes Betriebskapital einbauen und ihren wiederholten Missbrauch prüfen.
- [ ] **P07-08** Beide Verkaufskanäle als kompletten Kreislauf aus Einkauf, Fahrt, Handproduktion, Lager, Auslieferung und bestätigter Zahlung mit der [Prüfmatrix](../qa/TESTS.md) abnehmen.

**Abnahme** Verkaufserlös wird erst nach gültiger physischer Übergabe bestätigt. Ein guter und ein schlechter Privatpreis lassen sich unter kontrollierten Testbedingungen nachvollziehen. Doppelklick, erzwungener Schreibfehler und Wiederbeitritt erzeugen keine zweite Auszahlung und keinen neuen Privatpreis. Der Kreislauf kann mit neu gekauftem Rohstoff weiterlaufen.

**Nachweis** Je Kanal einen Fahrt- und Verkaufsbeleg mit Verkaufs-ID, Mengen und Geldänderung sichern. Den beobachteten Wiederanlauf nach Fehler und nach fehlendem Kapital vermerken.
