# Prototyp und Abnahme

## P10 · Zweites Rezept und Management

**Abhängigkeit** P09 ist abgenommen.

- [x] **P10-01** Lege den Beistelltisch als zweites Rezept mit eigener Materialmenge, erkennbarem Werkstück und abweichendem Montagebedarf fest. Nutze vorhandene Stationen und prüfe die passende Transportgröße. ([Vertrag](../design/TABLE.md), [Beleg](../evidence/P10.md#p10-01--beistelltisch-als-zweites-rezept))
- [x] **P10-02** Gib der Linie eine Rezeptwahl und mache ihre Wirkung auf den nächsten Produktionszyklus sichtbar. Prüfe einen Wechsel bei begonnener Bearbeitung und behalte die Werkstücke des alten Rezepts eindeutig zugeordnet. ([Regeln](../design/PRODUCTION.md#rezeptwechsel-ohne-umdeuten-alter-ware), [Beleg](../evidence/P10.md#p10-02--rezeptwahl-der-linie))
- [x] **P10-03** Zeige Rohstoff- und Fertigwarenbestand, Fahrzeugladung, freie Plätze und aktuelle Engpässe. Ergänze für Kauf, Rezeptwahl und Verkauf klare Bestätigungen sowie bedienbare Touch-Aktionen. ([Regeln](../design/PRODUCTION.md#betriebsübersicht-bestätigungen-und-touch-bedienung-p10-03), [Beleg](../evidence/P10.md#p10-03--betriebsübersicht-bestätigungen-und-touch-tasten))
- [x] **P10-04** Ergänze eine mit Spielgeld erwerbbare Ausrüstung mit sichtbarer Wirkung, etwa eine größere Montagekapazität. Zeige Preis und Nutzen vor dem Kauf und prüfe den Materialnachschub nach einer zu hohen Ausgabe. ([Regeln](../design/PRODUCTION.md#ausrüstung-p10-04), [Beleg](../evidence/P10.md#p10-04--erwerbbare-ausrüstung-montagevorrichtung))
- [ ] **P10-05** Mache die Entscheidung zwischen Hocker und Tisch überprüfbar. Vergleiche Materialbedarf, Belegung der Montage, Platz im Lager oder Fahrzeug und den Händlererlös. Spiele beide Rezepte über die bestehende Fahrzeugroute bis zur Abrechnung.
- [ ] **P10-06** Gib fünf neuen Testpersonen nach dem Band-Upgrade fünf Minuten zur freien Nutzung. Mindestens drei setzen selbst eine sinnvolle Entscheidung zu Rezept, Nachschub, Lager, Kapazität oder Verkaufszeitpunkt um. Halte fest, welche Informationen sie genutzt haben und welche Hürden auftraten.

**Abnahme und Nachweis** Beide Rezepte liefern die festgelegten Bestände und belegen die Montage unterschiedlich lange. Ein Kauf verändert die gewählte Kapazität. Sichere zwei Ablaufprotokolle, den Soll-Ist-Abgleich der Bestände und die Beobachtungen aus der freien Testphase. Die Schwelle von drei aus fünf ist ein internes Kriterium zur Prüfung des Entwurfs. Details stehen in der [Wirtschaft](../design/ECONOMY.md) und in der [Testübersicht](../qa/TESTS.md).

[P10-Prüfbelege](../evidence/P10.md)

## P11 · Art-Integration und Prototypabnahme

**Abhängigkeiten** P03 und P10 sind abgenommen. Der in P03 bewertete Musterausschnitt ist das Qualitätsgate für den Ausbau der Assetserie.

- [ ] **P11-01** Integriere die freigegebene Werkstattecke und passende Hocker-, Material-, Stations- und Fahrzeugmodelle. Vergleiche Maßstab und Anschlüsse mit der frühen Art-Probe. Hole bei Abweichungen eine erneute Beurteilung des Ausschnitts ein.
- [ ] **P11-02** Prüfe im Spiel Wand, Fenster, Dachanschluss, Möbelverbindungen, Ladefläche und Tore. Dokumentiere sichtbare Übergänge und kritische Abmessungen aus Spielkamera sowie einer Nahansicht. Die Kriterien stehen in [Art Direction](../design/ART.md).
- [ ] **P11-03** Spiele die komplette Route mit dem integrierten Set. Kaufe Rohstoffe beim Lieferanten, lade sie auf das Quad, entlade an der Fabrik, produziere auf Lager und fahre die Ware zur physischen Übergabe. Prüfe Händler und Privatkäufer sowie Hand-, NPC- und Bandübergaben.
- [ ] **P11-04** Wiederhole die Fehlerfälle für volles Lager, Überladung, doppelte Aktion und Verbindungsabbruch. Prüfe die Abrechnungen mit erzwungenen höheren und niedrigeren Privaterlösen. Erfasse Bestand und Guthaben vor und nach jedem Fall.
- [ ] **P11-05** Prüfe Lesbarkeit, Interaktionsflächen, Fahrzeugsteuerung und Ladepunkte auf den vereinbarten Zielprofilen. Notiere Gerät und Einstellungen. PC und Touch sind vorläufige Prüfprofile, bis die Zielgeräte feststehen.
- [ ] **P11-06** Lass fünf neue Testpersonen die erste Runde einschließlich Nachschub spielen. Mindestens vier erreichen Produktion, Verkauf und erneuten Materialkauf ohne mündliche Anleitung. Erfasse auch die freie Produktionsentscheidung aus P10 am integrierten Stand.
- [ ] **P11-07** Protokolliere das Ergebnis jedes Abnahmekriteriums und die Entscheidung zum Ausbau. Behebe Fehler mit Materialverlust, Doppelbestand oder doppelter Gutschrift und wiederhole die zugehörigen Fälle vor Freigabe.

**Abnahme und Nachweis** Der Musterausschnitt ist gestalterisch akzeptiert, der Produktions- und Verkaufsweg besteht die [Tests](../qa/TESTS.md) und die protokollierten Geräteprüfungen erlauben eine Entscheidung zum Ausbau. Halte Spielansichten, Buildstand, Gerät, Testfall, Beobachtung und Ergebnis fest. Die Fünfergruppe liefert frühe interne Hinweise zur Bedienung und zum Spielablauf.
