# Handbetrieb, Beschaffung und Verkauf

[Planübersicht](../../UMSETZUNGSPLAN.md) · [Technische Zustände](../technical/STATE.md) · [Prüfmatrix](../qa/TESTS.md) · [Weiter zur Automatisierung](02-automatisierung.md)

## P04 · Bestand und frühe Persistenz

**Voraussetzungen** P00 und P01 sind abgenommen. Testumgebung und Schreibziele sind eindeutig. Die technische Grundlage steht in [STATE.md](../technical/STATE.md).

- [x] **P04-01** Eigentümer, Geld, Chargen, Warenorte und Kapazitäten als verbindlichen Serverzustand definieren. Jede Charge erhält eine stabile ID und genau einen logischen Ort.
- [x] **P04-02** Gemeinsame Berechtigungs- und Zustandsprüfung für Spieleraktionen festlegen. Ungültige Mengen, fremde Bestände, volle Ziele und veraltete Revisionen werden verständlich abgewiesen.
- [x] **P04-03** Reservierung und gemeinsame Umbuchung von Quelle und Ziel umsetzen. Wiederholte Vorgangs-IDs ergeben dasselbe Resultat. Reservierungen können kontrolliert ablaufen.
- [x] **P04-04** Ein versioniertes Profil für Geld, Bestand und laufenden Fortschritt laden. Startdaten entstehen erst nach bestätigtem Fehlen eines bestehenden Profils.
- [x] **P04-05** Schreibvorgänge an Sitzungsbesitz und Profilrevision binden. Eine verspätete oder abgelöste Sitzung kann den neueren Stand nicht überschreiben.
- [x] **P04-06** Bestätigten Speichervorgang und unklaren Schreibausgang getrennt behandeln. Bei Ladefehler bleiben wirtschaftliche Aktionen gesperrt. Nach einem Absturz gilt der letzte bestätigte Stand.
- [x] **P04-07** Wiederherstellung für reservierte und bereits umgebuchte Ware festlegen. Der bestätigte Ort wird rekonstruiert oder über einen ausgewiesenen physischen Abholpunkt wieder erreichbar gemacht.
- [x] **P04-08** P04-Prüfungen mit künstlichen Chargen aus der [Prüfmatrix](../qa/TESTS.md) ausführen und die Ergebnisse im Fortschritt festhalten.

**Abnahme** Dieselbe Charge kann bei konkurrierenden Übergaben genau einmal übernommen werden. Wiederbeitritt stellt den bestätigten Bestand wieder her. Ladefehler und alte Sitzungen überschreiben keine gültigen Daten. Diese Abnahme liegt vor wirtschaftlich relevanten Tests.

**Nachweis** Testlauf, verwendeter Profilstand und Ergebnis für Konkurrenz, Wiederbeitritt und erzwungenen Ladefehler vermerken.

[P04-01-Beleg](../evidence/P04-01.md): gemeinsames serverseitiges Datenmodell, ein logischer Ort pro Charge und Einzelplatzkapazität, 35 Prüfungen in Edit und Server-Play bestanden; Version 25. Reine künstliche Daten, keine aktiven Profile oder DataStore-Zugriffe. Aktionsprüfung und Persistenz bleiben offen.

[P04-02-Beleg](../evidence/P04-02.md): gemeinsame schreibfreie Aktionsprüfung für Eigentümer, Träger, Menge, Revision, Stufe und Zielbelegung; 35 Edit-/Server-Fälle bestanden, Version 26. Reservierung, Umbuchung, Weltanbindung und Persistenz bleiben die folgenden Schritte.

[P04-03-Beleg](../evidence/P04-03.md): Schema 2, gemeinsame Claim-/Zusageprüfung, atomare Umbuchung, idempotente Belege und kontrollierter Claim-Ablauf; 36 Fälle mit 211 Aufrufen je Edit/Server plus 70 Regressionsfälle je Modus bestanden. Unabhängiger Review abgeschlossen, Version 31 gespeichert. Nur künstlicher Serverzustand; Laden, Sitzungsbesitz, bestätigtes Speichern und Wiederherstellung bleiben offen.

[P04-04-Beleg](../evidence/P04-04.md): versionierter Speicherumschlag mit Rezeptwahl und unverändertem State2; Initialisierung ausschließlich nach erfolgreichem Fehlen, Fehler bleiben gesperrt. 24 Ladefälle mit 64 Aufrufen plus 106 Regressionen je Edit/Server bestanden, Version 33. Künstliche Reader, kein echter Backend-Roundtrip oder aktive Wirtschaft; Sitzungsbesitz, echtes Speichern und Wiederherstellung bleiben offen.

[P04-05-Beleg](../evidence/P04-05.md): reine atomare Erwerb-/Schreib-/Freigabegrenze mit getrennter Speicherrevision und Lease; lokale Veröffentlichung an privaten Versuchsschlüssel gebunden. 41 Fälle lokal und je Edit/Server sowie je 130 Regressionen bestanden, unabhängiger Review abgeschlossen. Version 36 gespeichert. Kein echter Backend-Adapter oder `ready=true`; Bestätigung/Unklarheit folgt in P04-06 vor wirtschaftlichen Spieltests.

[P04-06-Beleg](../evidence/P04-06.md): 35 lokale Fälle sowie je 38 Adapterprüfungen und 171 Regressionen in Edit/Server bestanden. Auf Test-Place-Version 38 zusätzlich sieben echte DataStore-Prüfungen bestanden: bestätigter Save, frisches Rücklesen, Sperre und Abgleich nach künstlich verlorener Antwort, erneutes Laden und abgewiesener Versuch der alten Sitzung. Wirtschaftliche Aktionen bleiben gesperrt.

[P04-07-Beleg](../evidence/P04-07.md): bestätigte Quelle, Träger, Ziel und physische Ersatzauflage nach Neustart einer künstlichen Sitzung geprüft. Acht Serverfälle bestanden, Version 40 gespeichert. Bestands- und Zusagedaten bleiben beim reinen Wiederaufbau unverändert.

[P04-08-Beleg](../evidence/P04-08.md): QA-P04-01 bis -04 mit künstlichen Chargen, echtem DataStore und zwei Studio-Serverstarts geprüft. Reservierter Warenort, bestätigte Ablage und historischer Beleg bleiben nachvollziehbar. Maschinenjobs und Fahrzeuganbindung folgen in P05/P06.

## P05 · Einkauf und manuelle Dauerproduktion

**Voraussetzungen** P02 und P04 sind abgenommen. Werkstattplätze, Hocker und handliche Transportformate sind als Testaufbau festgelegt.

- [x] **P05-01** Ein Hockerrezept mit vier Stationen und erkennbaren Zwischenzuständen hinterlegen. Jede Station erhält feste Eingänge, Ausgänge und Puffergrenzen.
- [x] **P05-02** Einen Materialkauf mit Spielgeld abwickeln. Der Einkauf belastet das Profil und stellt die Charge am Lieferantenabholplatz bereit.
- [x] **P05-03** Aufnehmen und Ablegen eines Arbeitsloses an den richtigen Übergabepunkten ermöglichen. Trageanzeige und Rückmeldung erklären Inhalt, Ziel und Ablehnungsgrund.
- [x] **P05-04** Das Holzpaket an der Säge in einen sichtbaren Bausatz umwandeln.
- [x] **P05-05** Den Bausatz an der Montagebank zu einem erkennbaren Rohhocker verarbeiten.
- [x] **P05-06** Den Rohhocker am Finishplatz bearbeiten und die gewählte Oberfläche sichtbar anwenden.
- [x] **P05-07** Den fertigen Hocker am Packtisch in einen passenden Karton umwandeln und den Karton im Fertigwarenlager einlagern.
- [x] **P05-08** Die versorgten Stationen mit dem aktiven Rezept fortlaufend arbeiten lassen. Ein Maschinenlauf reserviert Platz für sein Ergebnis. Bei vollem Lager entsteht sichtbarer Rückstau, bevor weiterer Input verbraucht wird.
- [x] **P05-09** Einkauf und komplette Handkette mit der [Prüfmatrix](../qa/TESTS.md) prüfen. Für den isolierten Stationstest gekennzeichneten Testbestand verwenden. Die reguläre Beschaffungsfahrt folgt in P06.

**Abnahme** Ein Spieler kann Holz kaufen, Zwischenprodukte tragen und ohne vorherigen Kundenauftrag mehrere Hocker herstellen und lagern. Falsche Ablagen erhalten die Ware. Ein volles Lager stoppt die Linie verständlich. Der Kauf allein liefert kein Holz in die Fabrik.

**Nachweis** Einen vollständigen Hocker-Durchlauf mit Eingangs- und Endbestand sowie Status bei vollem Ausgang dokumentieren.

[P05-01-Beleg](../evidence/P05-01.md): Rezept Hocker01 v1 und zwölf Plätze aus der Greybox gebunden. Je neun Prüfgruppen in Edit und Server bestanden, private Version 41.

[P05-02-Beleg](../evidence/P05-02.md): Ein Kauf bucht Preis, Holzpaket, Delivery-Zusage und Beleg gemeinsam. Fünf Prüfgruppen mit echten und künstlichen Speichervorgängen bestanden, private Version 42.

[P05-03-Beleg](../evidence/P05-03.md): Fünf Serverprüfgruppen zu Aufnahme, Rückgabe, physischer Nähe, falscher Stufe und vollem Eingang bestanden. Der Nutzer hat den Tastaturdurchlauf auf privater Version 44 bestätigt.

[P05-04-Beleg](../evidence/P05-04.md): Der Sägelauf speichert den Arbeitsbereich und die Ausgangsreservierung gemeinsam. Nach 6 s entsteht ein Bausatz mit neun Teilen, Hülle 0,60 × 0,18 × 0,50 m. Vier Serverprüfgruppen mit echtem Test-Save und die Regressionen bestanden, private Version 46. Ein Spielerauslöser fehlt noch und folgt mit P05-08.

[P05-05-Beleg](../evidence/P05-05.md): `Stations` führt Start und Ende für alle vier Stationsregeln aus `State.STATIONS` aus. Der Montagelauf macht nach 8 s aus dem Bausatz einen vermessenen Rohhocker (0,40 × 0,45 × 0,40 m). Die Stationssuite (12 Fälle) und vier Serverprüfgruppen mit echtem Test-Save bestanden, private Version 47.

[P05-06-Beleg](../evidence/P05-06.md) · [P05-07-Beleg](../evidence/P05-07.md): Der Finishlauf (6 s) wendet die eine Finish-Oberfläche von Hocker01 v1 sichtbar an. Der Packlauf (4 s) erzeugt einen beschrifteten Karton von 0,46 × 0,51 × 0,46 m. Nur dieser wird im Fertiglager eingelagert, ein volles Lager hält ihn getragen und staut die Linie zurück. Die Schilder sind zweisprachig über `FactoryLabels`. Stationssuite 14/14 und vier Serverprüfgruppen bestanden, private Version 48.

[P05-08-Beleg](../evidence/P05-08.md): `Line.tick` beendet fällige Läufe und startet bereite Stationen ohne automatische Weitergabe. `LineView` zeigt jede Charge an ihrem bestätigten Ort sowie zweisprachige Stations- und Lagerschilder. Bei vollen Ausgängen und vollem Lager wird kein Input verbraucht und nichts gespeichert, ein freigegebener Platz setzt die Linie fort. Stationssuite 18/18 und vier Serverprüfgruppen nach QA-P05-03 bestanden, private Version 49.

[P05-09-Beleg](../evidence/P05-09.md): Spielbare Linien-Demo mit 16 Prompts, Echtzeittakt, Warenansichten und HUD. Automatische Kette (34 s) und Tastaturdurchlauf mit echten E-Prompts bestanden, jeweils zwei Kartons ohne Auftrag eingelagert. Befund: Gegenüberliegende Stationen teilen den Bedienplatz, deshalb werden Prompts nur in Blickrichtung angeboten. **P05 ist abgenommen.** Die Kaufbedienung für Spieler folgt mit dem Beladen am Lieferanten (P06-04).

## P06 · Quad, Ladung und echte Fahrten

**Voraussetzungen** P02, P04 und P05 sind abgenommen. Maße für Ladeplätze, Hockerkarton, Anhänger und Ladezonen sind abgestimmt.

- [x] **P06-01** Eine kurze befahrbare Strecke mit Lieferant, Werkstatt, Händler und Privatkundenplatz als Testumgebung abstecken.
- [x] **P06-02** Ein steuerbares Quad und einen kleinen Anhänger zunächst mit maßhaltiger Stellvertretergeometrie bereitstellen. Wendeflächen und Anfahrt auf der tatsächlichen Strecke prüfen.
- [x] **P06-03** Dem eigenen Fahrzeug feste Ladeplätze und nachvollziehbare Kapazitätsgrenzen zuweisen.
- [x] **P06-04** Physisches Beladen am Lieferanten und an der Werkstatt mit den Bestandsumbuchungen verbinden. Ware erscheint befestigt am bestätigten Ladeplatz.
- [x] **P06-05** Entladen am passenden physischen Ziel mit Prüfung von Fracht, Fahrzeug, Eigentümer und Ladezone umsetzen. Ein volles Ziel lässt die Ware auf dem Fahrzeug.
- [x] **P06-06** Für die spätere Verkaufsfreigabe serverseitig beobachtbare Fahrtmerkmale und bestätigte Ankunft erfassen. Eine bloße Berührung oder behauptete Zielposition genügt nicht.
- [x] **P06-07** Fahrzeugladung beim Wiederbeitritt gemeinsam mit dem übrigen Bestand wiederherstellen. Einen physischen Bergungs- und Abholweg für technisch nicht wiederherstellbare Positionen vorsehen.
- [x] **P06-08** Die gesamte Fahrt mit Holz zur Werkstatt und einem Hockerkarton bis zur Käuferzone prüfen. Die eigentliche Verkaufsabrechnung folgt in P07.

**Abnahme** Rohstoffe und Fertigware erreichen ihr Ziel über echte Fahrten. Sichtbare Ladung und bestätigte Ladeplätze stimmen überein. Doppeltes Entladen, falsche Zone, zu große Ladung und Wiederbeitritt führen zu eindeutigen, bestandsneutralen Ergebnissen.

**Nachweis** Fahrt und Übergabepunkte mit Video oder Screenshots festhalten. Bestände vor dem Beladen, nach dem Entladen und nach Wiederbeitritt protokollieren.

[P06-01-Beleg](../evidence/P06-01.md): Die Handlinie steht in der Halle der Start-Tischlerei, der Lagerzugang liegt im Tor. Vier Ladezonen über die vollen Höfe, Annahmeplätze bei Händler und Privatkunde in der hinteren linken Hofecke, Lieferantenplätze 0,4 m nach außen verschoben. Freiraum zum Fahrmodell, Wegfindung durch das Tor und zweisprachige Schilder geprüft, private Version 52.

[P06-02-Beleg](../evidence/P06-02.md): Das Gespann fuhr alle fünf Etappen ohne Kontakt zu Hindernissen oder P06-01-Teilen und ohne Rad neben dem Belag. Jede Haltestellung liegt vollständig in der Ladezone. Echte Fahrereingabe (E, W/A) steuert das Gespann.

[P06-03-Beleg](../evidence/P06-03.md): `Vehicles` bindet die Anhängerplätze A/B als `VehicleSlot` (je 1 Holzpaket oder Karton). Ware wird aus dem Bestand dargestellt und am Slot befestigt (0,005 Studs Drift nach 9,4 m Fahrt). Volle Plätze, falsche Stufe und der Weg ohne Hand werden über die gemeinsamen Regeln abgewiesen, private Version 53.

[P06-04/05-Beleg](../evidence/P06-04-05.md): Kauf am Lieferanten und physische Übergaben mit R/E sowie die Prüfung auf Besitzer, Stillstand, Ladezone und freien Zielplatz bestanden. Holz belegt den reservierten Rohstoffplatz genau einmal. Ein Karton bleibt bei vollem Fertiglager am Anhänger. Private Version 57.

[P06-06-Beleg](../evidence/P06-06.md): Zwei Kartons erreichten Händler und Privatkunden über 335,57 m durchgehende Fahrt. Der Server bestätigte die jeweils aktuelle Käuferzone je Ladeplatz und Charge. Ein Positionssprung blieb ohne Nachweis. Private Version 60.

[P06-07-Beleg](../evidence/P06-07.md): Drei frische Studio-Server mit demselben isolierten Testprofil stellten Ladeplätze, Ware am Lieferanten und reservierten Rückgabeplatz wieder her. Eine fehlende Anhängerauflage führte zum physischen Bergungsplatz. Private Version 61.

[P06-08-Beleg](../evidence/P06-08.md): Eine Charge fuhr als Holz auf A vom Lieferanten zur Werkstatt, durchlief alle vier Stationen und erreichte als Karton auf B den Händler. Die Strecke betrug 434 m, ohne Kontakt und mit bestätigter Käuferankunft. Revision und Guthaben blieben bei jeder Fahrt unverändert. Fehlerfälle über P06-03 bis P06-07. **P06 ist abgenommen.** Private Version 67.

## P07 · Händler, Privatverkauf und kompletter Kreislauf

**Voraussetzungen** P06 ist abgenommen. Beide Käuferzonen sind erreichbar. Verwendete Testpreise und Privatspanne sind als vorläufig gekennzeichnet.

- [x] **P07-01** Für eine gültige Übergabe nur die bestätigte Menge aus den passenden Fahrzeugladeplätzen reservieren. Käufer, Ladezone und Fahrtzustand serverseitig prüfen.
- [x] **P07-02** Beim Möbelhändler den bekannten Modellpreis und Gesamterlös für die reservierte Menge anzeigen und verwenden.
- [x] **P07-03** Beim Privatkunden Menge, Händlervergleich und möglichen Erlösbereich vor der bindenden Bestätigung anzeigen. Abbruch vor Bestätigung gibt die Reservierung frei.
- [x] **P07-04** Den Privaterlös nach Bestätigung einmal serverseitig festlegen und mit der Verkaufs-ID wiederherstellbar speichern. Wiederholte Schreibversuche verwenden das festgelegte Ergebnis.
- [x] **P07-05** Warenabgang, Geldgutschrift und Verkaufsabschluss in derselben geprüften Profiländerung speichern. Den Beleg erst nach bestätigtem Abschluss anzeigen.
- [x] **P07-06** Bei unterbrochenem Verkauf den vorhandenen Status wieder aufnehmen. Ein bereits bezahlter Vorgang liefert denselben Beleg. Ein unklarer Schreibausgang wird vor einem neuen Versuch geprüft.
- [ ] **P07-07** Eine begrenzte, zweckgebundene Wiederanlaufhilfe für fehlendes Betriebskapital einbauen und ihren wiederholten Missbrauch prüfen.
- [ ] **P07-08** Beide Verkaufskanäle als kompletten Kreislauf aus Einkauf, Fahrt, Handproduktion, Lager, Auslieferung und bestätigter Zahlung mit der [Prüfmatrix](../qa/TESTS.md) abnehmen.

**Abnahme** Verkaufserlös wird erst nach gültiger physischer Übergabe bestätigt. Ein guter und ein schlechter Privatpreis lassen sich unter kontrollierten Testbedingungen nachvollziehen. Doppelklick, erzwungener Schreibfehler und Wiederbeitritt erzeugen keine zweite Auszahlung und keinen neuen Privatpreis. Der Kreislauf kann mit neu gekauftem Rohstoff weiterlaufen.

**Nachweis** Je Kanal einen Fahrt- und Verkaufsbeleg mit Verkaufs-ID, Mengen und Geldänderung sichern. Den beobachteten Wiederanlauf nach Fehler und nach fehlendem Kapital vermerken.

[P07-Beleg](../evidence/P07.md): Ein Karton wird im Käuferhof nach bestätigter Ankunft in die Hand genommen und an der Annahme bindend übergeben. Der Händler zahlte 100, der Privatkunde mit erzwungenem Testwert 120. Abbruch, Doppelbestätigung, fremde Annahme und Reichweite wurden geprüft, Bestand und Guthaben blieben dabei korrekt. Lokal bestanden 12 von 12 Fällen, darunter die Testwerte 80 und 120, unklarer Schreibausgang und neue Sitzung ohne neuen Wurf. Über einen echten Serverwechsel mit DataStore blieben der offene Verkauf, der bezahlte Beleg und das Guthaben erhalten.
