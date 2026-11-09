# Mitarbeiter und Förderband

[Planübersicht](../../UMSETZUNGSPLAN.md) · [Handbetrieb](01-handbetrieb.md) · [Technische Zustände](../technical/STATE.md) · [Prüfmatrix](../qa/TESTS.md)

## P08 · Erster Mitarbeiter

**Voraussetzungen** P07 ist abgenommen. Der gespeicherte Kreislauf aus Einkauf, manueller Herstellung und physischer Auslieferung ist vollständig spielbar.

- [ ] **P08-01** Einen ersten Mitarbeiter mit Spielgeld anstellbar machen und seine Freischaltung im Werkstattprofil speichern.
- [ ] **P08-02** Eine feste Transportstrecke zwischen zwei vorhandenen Stationen mit klarer Quelle, Ziel und freien Laufwegen zuweisen.
- [ ] **P08-03** Die Charge und den Zielplatz bei Auftragsannahme über die gemeinsamen Bestandsregeln reservieren. Der Mitarbeiter übergibt Ware erst am vorgesehenen Ziel.
- [ ] **P08-04** Zustände für unterwegs, Material fehlt, Ziel voll und Weg blockiert sichtbar machen.
- [ ] **P08-05** Unterbrechungen mit begrenzten Wiederholungen und kontrollierter Freigabe behandeln. Unübernommene Ware bleibt an der Quelle. Übernommene Ware bleibt an einem eindeutig bestimmten physischen Abholort verfügbar.
- [ ] **P08-06** Manuelle Übernahme und Mitarbeitertransport gegeneinander prüfen. Eigentümer und andere Träger sehen dieselbe Reservierung und erhalten bei Konflikten eine klare Rückmeldung.
- [ ] **P08-07** Die Tests der [Prüfmatrix](../qa/TESTS.md) für Konkurrenz, blockierten Weg, volles Ziel und Wiederbeitritt ausführen. Beobachten, welche nächste Betriebsentscheidung Spieler nach der Entlastung treffen.

**Abnahme** Der Mitarbeiter übernimmt genau eine bekannte Arbeit zuverlässig. Die manuelle Kette bleibt bedienbar. Zielblockade und Abbruch erhalten die Charge. Der Besitzer erkennt Status und nächste Handlung.

**Nachweis** Einen vollständigen Transport zu Fuß und einen gezielt blockierten Transport mit den betroffenen Chargenorten dokumentieren. Die beobachtete Entscheidung nach der Einstellung ergänzen.

## P09 · Erstes festes Förderband

**Voraussetzungen** P08 ist abgenommen. Der Mitarbeitertransport nutzt die gemeinsame Reservierung und Umbuchung. Die vorgesehene Bandstrecke besitzt passende Stationsanschlüsse.

- [ ] **P09-01** Ein gerades Band mit einem festen Eingabe- und Ausgabeanschluss freischaltbar machen. Die Verbindung bleibt im Werkstattprofil gespeichert.
- [ ] **P09-02** Ein definiertes Transportformat und einen sichtbaren Zwischenpuffer festlegen. Quellstation, Band und Zielstation akzeptieren dieselbe Größe und Verarbeitungsstufe.
- [ ] **P09-03** Eine Charge über die gemeinsame Reservierung vom Quellausgang auf den Bandabschnitt und anschließend zum Zieleingang umbuchen.
- [ ] **P09-04** Die sichtbare Bewegung der Charge am verbindlichen Transportzustand ausrichten. Beim Wiederbeitritt den bestätigten Band- oder Pufferzustand wiederherstellen.
- [ ] **P09-05** Das Band bei vollem Ziel anhalten und nach freiem Platz fortsetzen. Der Stillstand wird bis zur Quelle als kontrollierter Rückstau sichtbar.
- [ ] **P09-06** Den bisherigen Träger nach Übernahme seines Wegs einem anderen vorgesehenen Werkstattweg zuweisen.
- [ ] **P09-07** Konkurrierende Abholungen durch Spieler, Mitarbeiter und Band mit den zutreffenden Fällen der [Prüfmatrix](../qa/TESTS.md) prüfen.
- [ ] **P09-08** Nach Bandfreischaltung eine konkrete Betriebsentscheidung wie Lagerausbau, Nachschub oder Verkauf anbieten und beobachten.
- [ ] **P09-09** Die vereinbarte Geräteprüfung mit sichtbarer Bewegung, Rückstau und mehreren aktiven Werkstätten durchführen. Messergebnisse und beobachtete Grenzen dokumentieren.

**Abnahme** Das Band übernimmt eine bisher manuelle oder personelle Strecke. Puffer und Lage der Ware bleiben bei vollem Ziel und Wiederbeitritt nachvollziehbar. In Konkurrenzfällen erfolgt jede Umbuchung einmal. Weitere Rezepte und freie Bandnetze erhalten ihre eigene spätere Abnahme.

**Nachweis** Aufnahme eines laufenden und gestauten Bands, Bestandsprotokoll bei Konkurrenz und Wiederbeitritt sowie das Ergebnis der Geräteprüfung festhalten.
