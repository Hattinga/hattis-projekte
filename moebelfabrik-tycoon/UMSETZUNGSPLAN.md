# Umsetzungsplan für Möbelfabrik Tycoon

Planstand 9. November 2026. Grundlage ist [Konzept v1.1](docs/archive/Moebelfabrik_Konzept_v1.1.md). Die Checklisten in den Phasendateien sind der verbindliche Aufgabenstand. [STATUS.md](docs/workflow/STATUS.md) nennt genau den nächsten bearbeitbaren Schritt.

## Reihenfolge

| Meilenstein | Phasen | Sichtbares Ergebnis |
|---|---|---|
| M0 Arbeitsgrundlage | [P00–P02](docs/plan/00-start.md) | Testumgebung, gemeinsamer Maßstab und kompakte, befahrbare Testwelt. |
| M-Art Muster | [P03](docs/plan/00-start.md) | Hocker, Maschine und Gebäudekante überzeugen aus der tatsächlichen Spielkamera. Maßstab für Quad, Anhänger und Ladung passt. |
| M1 Handbetrieb | [P04–P07](docs/plan/01-handbetrieb.md) | Holz abholen, Hocker auf Lager herstellen, am Ziel abladen und über beide Wege verkaufen. Bestand und Spielstand bleiben bei Fehlern konsistent. |
| M2 Automation | [P08–P09](docs/plan/02-automatisierung.md) | Ein Mitarbeiter und später ein festes Band übernehmen bekannte Wege. |
| M3 Abgenommener Kern | [P10–P11](docs/plan/03-prototyp-abnahme.md) | Zweites Möbel mit eigener Betriebsentscheidung, stimmige Art, Bedienbarkeit und reproduzierbare Tests. |
| M4 Erweiterungen | [P12–P13](docs/plan/04-fahrzeuge-rebirth.md) | Nutzbarer Lkw und zusätzlicher Fertigungszweig mit freiwilligem Rebirth. |
| M5 Spieltest und Veröffentlichung | [P14–P15](docs/plan/05-release.md) | Geprüfter Mehrspielerstand und eine vorbereitete Veröffentlichung. |

**Kritischer Pfad.** P00 → P01. Danach können P02, P03 und P04 parallel beginnen, sobald ihre jeweiligen Voraussetzungen erfüllt sind. P05 benötigt P02 und P04. P06 → P07 → P08 → P09 → P10 folgen aufeinander. P11 setzt auch die Art-Abnahme aus P03 voraus. P12 und P13 erweitern erst den abgenommenen Kern.

## Umfang der ersten spielbaren Probe

Eine Werkstatt, ein Holzhocker, vier Stationen, Roh- und Fertiglager, ein Lieferant, ein Händler, ein Privatkunde sowie ein Quad mit kleinem Anhänger. Die Route verbindet alle vier Orte. Der Fertigungsablauf ist zuerst von Hand spielbar. Mitarbeiter, Band und zweites Möbel kommen in getrennten Arbeitspaketen hinzu.

## Entscheidungen und Nachweise

- [Kernkonzept](docs/design/CORE.md) hält Nutzerentscheidungen und vorläufige Prototypwerte auseinander.
- [Testmatrix](docs/qa/TESTS.md) beschreibt die Prüfungen für Warenfluss, Fahrten, Verkäufe, Art, Wiederbeitritt und Spielerlebnis.
- [Workflow](docs/workflow/WORKFLOW.md) regelt Zuständigkeit, Bearbeitung, Abnahme und Übergabe.
- [Council-Archiv](docs/archive/README.md) enthält Konzept und Hintergründe für gezielte Rückfragen.

## Start

Beginne bei **P00-01** im [Startplan](docs/plan/00-start.md). Beende den Schritt mit einer benannten Testumgebung und einer nachvollziehbaren Wahl des Bearbeitungswegs. Danach bestimmt die Checkliste den nächsten Schritt.
