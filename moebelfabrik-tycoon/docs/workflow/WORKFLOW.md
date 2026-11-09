# Projektablauf

## Aufgabe übernehmen

1. Prüfe den aktuellen Status und die Voraussetzungen der Aufgabe. Lies nur den aktuellen Phasenabschnitt und die dafür benötigte Fachreferenz.
2. Prüfe Arbeitsordner, Branch und vorhandene Änderungen. Benenne bei einem Studio-Schritt zusätzlich den Ziel-Place und den wiederherstellbaren Stand.
3. Lege Schreibpfade, Zuständigkeit, Ergebnis und Abnahme im [Aufgabenbrief](HANDOFF.md) fest. Eine einfache Aufgabe kann direkt im Chat oder in der Agentenbeauftragung denselben Inhalt verwenden.
4. Setze die Aufgabe in einem kleinen prüfbaren Schritt um. Verwende vorhandene Module und Werkzeuge, sobald sie den Schritt abdecken.

## Zusammenarbeit

- Eine Datei oder ein Live-Place hat für jede Änderung genau einen Schreiber. Der Lead führt Ergebnisse zusammen und entscheidet bei Konflikten über die Reihenfolge.
- Unabhängige Arbeitspakete laufen parallel. Separate schreibende Git-Arbeitsaufträge erhalten eigene Branches und bei gleichzeitigem Checkout eigene Worktrees. Branch-Namen enthalten die Aufgaben-ID, etwa `work/p04-02-bestand`.
- Lege den Ausgangsbranch anhand des tatsächlichen Repos fest. Prüfe fremde Änderungen vor Integration und übernimm sie unverändert, sofern die Aufgabe keine konkrete Anpassung verlangt.
- Übergib an einen Subagenten nur Aufgabenbrief, seine Rollenkarte und die relevanten Abschnitte. Der Subagent meldet Änderungen, Prüfergebnis und verbleibende Abhängigkeiten.
- Der Studio-Integrator koordiniert Schreibzugriffe auf den Test-Place. Blender-Exporte werden als Dateien übergeben. QA nimmt einen eindeutigen Stand als Testziel.

## Abnahme und Wiederaufnahme

1. Führe den im Paket beschriebenen Normalfall und die betroffenen Fehlerfälle aus. Vergleiche die Wirkung im Spiel mit dem tatsächlich gespeicherten Bestand.
2. Vermerke Datum, Aufgaben-ID, Teststand, Prüfmethode und Ergebnis. Lege kleine relevante Belege in `docs/evidence/` ab. Lokale Rohaufnahmen und Zugangsdaten bleiben außerhalb der nachverfolgten Projektunterlagen.
3. Markiere die Aufgabe im Phasenplan als erledigt, sobald ihr Ergebnis geprüft ist. Bei fehlendem Nachweis bleibt die Checkbox offen und der Status benennt den konkreten fehlenden Test.
4. Aktualisiere die Statusdatei mit nächster Aufgabe, Link, Zuständigkeit und Beleg. Ändert sich eine Nutzerentscheidung, aktualisiere zuerst die zuständige Fachdatei und danach die betroffenen Aufgaben.
5. Der Lead prüft das Gesamtergebnis am Ende eines Meilensteins. Fehler gehen als kleine Reparaturaufgabe mit Reproduktion und Wiederholungsprüfung in dieselbe Phase.

## Fachregeln bei Bedarf

| Aufgabe | Nur relevante Fachdatei öffnen |
|---|---|
| Spielablauf oder Scope | [Kernkonzept](../design/CORE.md) |
| Preise, Lager und Verkauf | [Wirtschaft](../design/ECONOMY.md) |
| Modelle, Material und Maßstab | [Art Direction](../design/ART.md) |
| Bestand, Verkäufe und Speichern | [Zustandsregeln](../technical/STATE.md) |
| Reproduktion und Abnahme | [Testmatrix](../qa/TESTS.md) |
