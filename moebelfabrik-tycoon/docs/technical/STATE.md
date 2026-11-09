# Materialbestand, Verkäufe und Speicherung

[Kernkonzept](../design/CORE.md) · [Handbetrieb](../plan/01-handbetrieb.md) · [Automatisierung](../plan/02-automatisierung.md) · [Prüfmatrix](../qa/TESTS.md)

## Zuständigkeit und Daten

Der Server führt den verbindlichen Bestand einer Werkstatt. Spieler, Mitarbeiter und Förderband bewegen dieselben Chargen über gemeinsame Umbuchungen. Der Client fordert Handlungen an und zeigt den bestätigten Zustand an. Modelle, Animationen und Berührungen dienen der Darstellung und Eingabe.

| Zustand | Benötigte Angaben |
| --- | --- |
| Profil | Eigentümer, Schemaversion, Revision, aktive Sitzung und bestätigter Geldstand |
| Fortschritt | Laufende Werkstatt mit Ausrüstung und Rezeptwahl. Dauerhafte Freischaltungen separat erfassen, sobald sie benötigt werden. |
| Charge | Stabile ID, Eigentümer, Material oder Möbelmodell, Menge, Verarbeitungsstufe und genau ein logischer Ort |
| Station | Fester Stellplatz, Rezept, Eingangs- und Ausgangspuffer, laufender Maschinenlauf und reservierter Ausgang |
| Transport | Träger oder Verbindung, Quell- und Zielplatz, betroffene Charge, Reservierungsstatus und Ablaufzeit |
| Fahrzeugladung | Fahrzeug-ID, Ladeplatz, zulässige Größe und Kapazität. Die Ladung wird befestigt dargestellt. |
| Wirtschaftsvorgang | ID, betroffene Chargen und Mengen, Kauf- oder Verkaufskanal, Betrag und verbindlicher Abschlussstatus |

Mögliche Warenorte sind Lieferantenabholplatz, Werkstattlager, Träger, Stationspuffer, laufender Maschinenlauf, Fertigwarenlager, Fahrzeugladeplatz und Bandabschnitt. Wiederherstellbare Ware kann an einem eindeutig ausgewiesenen physischen Abholpunkt liegen. Beim Aufteilen einer Charge bleibt die Gesamtmenge erhalten. Maschinenläufe ändern Materialart und Menge ausschließlich gemäß Rezept.

## Gemeinsame Übergaben

Der Server prüft Akteur, Berechtigung, erwarteten Ausgangszustand, gültige Menge, passenden Ort und Zielkapazität. Der Vorgang reserviert die Quelle und bei Bedarf den Zielplatz. Die Umbuchung entfernt Ware von der Quelle und weist sie im selben Änderungsschritt dem Ziel zu. Animation und Wegsuche laufen außerhalb dieses Schritts. Wiederholungen mit derselben Vorgangs-ID und denselben Eingaben geben das vorhandene Ergebnis zurück. Reservierungen laufen kontrolliert ab oder werden bei Abbruch freigegeben.

Beim Einkauf werden Spielgeld und neu bereitgestellte Ware gemeinsam verbucht. Die Charge entsteht am Lieferantenabholplatz. Eine Station reserviert vor dem Materialverbrauch Platz für ihr Ergebnis. Ein volles Fertigwarenlager erzeugt sichtbaren Rückstau bis zu den Stationen. Ein interner Fertigungsjob steht für einen Maschinenlauf, während der Spieler auf Bestand produziert und erst danach einen Abnehmer wählt.

## Fahrzeuge und Verkäufe

Ein- und Ausladen prüfen Eigentümer, Ladezone, Kapazität des Zielorts und die physisch erreichbare Übergabestelle. Für Lieferungen prüft der Server, ob der beobachtete Fahrtverlauf plausibel ist und die Ware am passenden Ziel entladen wird. Ein behaupteter Standort, eine Berührung oder eine Clientmeldung allein ist für die Auszahlung unzureichend. Normale Beschaffungs- und Verkaufswege erfolgen als Fahrten.

| Kanal | Preisbildung und Abschluss |
| --- | --- |
| Möbelhändler | Der Server berechnet den bekannten Modellpreis für die bestätigte Stückzahl. |
| Privatkunde | Die mögliche Erlösspanne und der Händlervergleich sind vor der bindenden Wahl sichtbar. Der Server legt das Zufallsergebnis nach Bestätigung einmal für die Verkaufs-ID fest. |

Eine verbindliche Verkaufs-ID referenziert die reservierte Ware und den festgelegten Preis. Schreibwiederholungen und Wiederbeitritt verwenden denselben gespeicherten Betrag. Das endgültige Ergebnis wird erst nach bestätigter Speicherung gezeigt. Warenabgang, Geldgutschrift und Abschlussstatus gehören in dieselbe geprüfte Änderung desselben Spielerprofils. Bei unklarem Schreibausgang wird der gespeicherte Vorgang vor einem erneuten Versuch geprüft. Ein bereits abgeschlossener Verkauf liefert den vorhandenen Beleg. Die Transaktion ist auf ein Spielerprofil begrenzt.

## Speichern und Wiederherstellen

Persistenz gehört zum ersten Bestandsnachweis. Das Profil trennt bestätigte Speicherdaten von laufender Darstellung. Revision und Sitzungszuordnung schützen vor verspäteten Schreibvorgängen älterer Sitzungen. Startdaten entstehen ausschließlich nach einer erfolgreichen Prüfung, dass für den Spieler noch kein Profil existiert. Kann das Profil nicht geladen werden, bleiben wirtschaftliche Aktionen gesperrt. Bei unklarem Ergebnis bleibt der betroffene Verkauf bis zur Prüfung offen.

Unverbuchte Übergaben bleiben an ihrer Quelle. Bereits verbuchte Ware bleibt am bestätigten Ort. Nach Wiederbeitritt werden Fahrzeugladung und Lager gemeinsam aus dem Profil rekonstruiert. Kann ein bestätigter Ort technisch nicht wiederhergestellt werden, wird die Ware an einem dokumentierten physischen Abholpunkt bereitgestellt. Abholung und anschließende Fahrt sind weiterhin nötig. Beim Wiederherstellen eines Maschinenlaufs darf dieselbe Charge nur als laufender Input oder als fertiger Output vorliegen.

Der letzte bestätigte Save bestimmt den Wiederherstellungsstand nach einem Absturz. Verlust von Änderungen seit dieser Bestätigung ist möglich. Ein späterer Rebirth darf erst nach Klärung offener Verkäufe, Reservierungen und Ladungen stattfinden. Zurückgesetzte und dauerhafte Inhalte werden gemeinsam in einer neuen Profilrevision gespeichert. Konkrete Reset-Regeln gehören in die spätere Rebirth-Phase.
