# P14 und P15 – Mehrspielerprüfung und Veröffentlichung

Für diese Phase genügen die relevanten Fälle der [Testmatrix](../qa/TESTS.md), der letzte Prototypbeleg und die [Zustandsregeln](../technical/STATE.md). Setze die vorherigen Meilensteine für den vorgesehenen Umfang voraus.

## P14 – Mehrspielerstand prüfen

**Voraussetzungen.** P11, P12 und P13. Lege den geplanten Umfang des ersten externen Tests fest und verwende einen getrennten Teststand.

- [ ] **P14-01** Zwei Spieler mit getrennten Betrieben gleichzeitig testen. Prüfe Laden, Tragen, Kauf und Verkauf an fremden Plots und Fahrzeugen.
- [ ] **P14-02** Einen vollen Fertigwarenpuffer, mehrere NPCs, Bänder und beladene Fahrzeuge gemeinsam laufen lassen. Protokolliere die Last, bei der Eingaben und Anzeige zuverlässig bleiben.
- [ ] **P14-03** Auf dem vereinbarten echten Touch-Gerät den vollständigen Spielweg fahren. Prüfe Bedienflächen, Kamerasicht, Lesbarkeit, Laden und Entladen.
- [ ] **P14-04** Verbindungsabbruch während Fahrt, Bandtransport und Privatverkauf auslösen. Prüfe den zuletzt bestätigten Zustand, Wiederherstellung und einmalige Gutschrift.
- [ ] **P14-05** Den Spielstandwechsel mit einem älteren Testprofil erproben. Prüfe fehlende Felder, fehlgeschlagenes Laden und Konkurrenz zwischen alter und neuer Sitzung.
- [ ] **P14-06** Leistungsgrenzen aus den Messungen ableiten. Dokumentiere tatsächlich getestete Plot-, Fahrzeug-, Mitarbeiter- und Warenmengen.
- [ ] **P14-07** Kritische Fehler nach Korrektur erneut reproduzieren. Führe anschließend je eine vollständige Hand- und Automationsrunde durch.

**Abnahme.** Besitzgrenzen und Bestand bleiben bei paralleler Nutzung konsistent. Der Ablauf ist auf dem vereinbarten Gerät spielbar. Für Last, Datenwiederherstellung und offene Fehler gibt es konkrete Belege.

## P15 – Veröffentlichung vorbereiten

**Voraussetzung.** P14 ist abgenommen. Der Lead benennt den geprüften Stand, der für die Veröffentlichung vorgesehen ist.

- [ ] **P15-01** Den ersten öffentlichen Spielumfang festhalten. Beschreibe enthaltene Rezepte, Fahrzeuge, Automationsstufen und Rebirths anhand des geprüften Stands.
- [ ] **P15-02** Einführungsablauf, Statusanzeigen und Fehlermeldungen aus Sicht eines neuen Spielers prüfen. Übernimm Korrekturen in die zuständige Phase.
- [ ] **P15-03** Titel, Beschreibung und Vorschaubilder aus dem tatsächlichen Spielstand vorbereiten. Referenziere die geprüften Assetquellen und den dokumentierten Nutzungsumfang.
- [ ] **P15-04** Speicherstand und Projektdateien sichern. Halte getestete Version, Wiederanlauf und die Möglichkeit zur Rückkehr auf einen vorherigen Stand fest.
- [ ] **P15-05** Einen kleinen eingeladenen Spieltest auswerten. Ordne Rückmeldungen nach Einstieg, Fahrten, Produktion, Verkauf, Automation und Art.
- [ ] **P15-06** Den Release-Kandidaten mit Nachweisen und offenen Einschränkungen bereitstellen. Veröffentlichung erfolgt auf ausdrücklichen Auftrag für diesen konkreten Stand.

**Abnahme.** Der Release-Kandidat ist reproduzierbar und einem gesicherten Teststand zugeordnet. Beobachtungen und offene Entscheidungen stehen im Prüfbeleg.

## Erweiterungen nach dem Kern

Freie Maschinenplatzierung, komplexe Bandnetze, automatisierte Fahrten, Möbelshowroom, Handel zwischen Spielern und weitere Shopformen erhalten jeweils eigene Pakete, wenn sie für die nächste Ausbaustufe gewählt werden.
