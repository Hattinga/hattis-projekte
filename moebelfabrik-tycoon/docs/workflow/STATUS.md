# Projektstatus

Stand 13. November 2026. **Das beladene Quad-/Anhaenger-Gespann faehrt automatisch zu allen vier Orten der Stadt-Greybox und zurueck; Avatarplatz an den Uebergaben, Wendekreis und Tordurchfahrt sind gemessen. P02-04 und P02-05 sind abgenommen, Place-Version 19 gespeichert (mit P02Overview), nicht publiziert.**

| Feld | Aktuell |
|---|---|
| Letzter abgeschlossener Schritt | **P02-05** - beladene Streckenfahrt, Uebergabeplatz, Wendekreis, Torprobe ([Beleg](../evidence/P02-05.md)) |
| Davor | **P02-04** - lenkbarer Quad-/Anhaenger-Stellvertreter `Workspace.P02Vehicle` ([Beleg](../evidence/P02-04.md)) |
| Naechster Umsetzungsschritt | **P02-06** - beschrifteten Uebersichtsstand (Stationsfolge, Lagerslots, Strassenroute) und Aufnahme der Fahrt mit sichtbarer Last sichern |
| Offener Test daneben | **P02-02** - Stationsprobe vorhanden, vollstaendige Trageabnahme fehlt ([Beleg](../evidence/P02-02.md)) |
| Noch offene Umgebungsvoraussetzung | **P00-03** - reales schwaecheres Testgeraet bestimmen (braucht den Nutzer) |
| Offene Entwurfsfrage (Nutzer) | Hallentor 4 m / Halle 10 m tief: Kehre in der Halle passt nur mit schraegem Anlauf (0,31 m Reserve); gerader Anlauf streift den Torpfeiler um 0,32 m. Tor breiter, Halle tiefer oder rueckwaerts ausfahren? Nichts geaendert. |
| Planabschnitt | [Startplan](../plan/00-start.md) |
| Zustaendigkeit | Studio fuer P02-06; QA fuer P02-02 |
| Aktueller Test-Place | Furniture Factory Tycoon, Place `79033653140107`, Universe `10776116608`, privat |
| Spielkarte | `Workspace.CityGreybox`, Revision 1; Ursprung (430;0;450) Studs, 19 Strassen/Zufahrten, 4 Tischlereien |
| Fahrzeugprobe | `Workspace.P02Vehicle`, Revision 2, steht auf dem Ladehof der Start-Tischlerei; Quad mit `VehicleSeat`, Prompt "Fahren" und Serverskript `Drive`; ohne Fahrer steuern die Attribute `TestThrottle`/`TestSteer` am Quad |
| Archivierte Vorprobe | `ServerStorage.MapPrototypes.MapGreybox`; Ringfassung ausserhalb des Workspace |
| Vergleichsobjekt | `Workspace.FableWorkshop`, Asset `106051543998570`; kein vorgesehenes Spielgebaeude |
| Technikproben | `Workspace.P02Greybox` und `Workspace.P02Line`; Prueftraeger in `ServerStorage.P02CarryProbe`, nicht im Spielstart |
| Arbeitsbranch | `work/p00-studio-import`, auf `origin` gepusht |
| Speicherung | `save_place`: Saved zu TeamCreate, **Version 19**. Studio in Edit; nicht publiziert. Lokale `.rbxl` im Projektstamm ist der fruehere Ausgangsstand, nicht der aktuelle Place. |
| Wiederherstellbare Staende | Version 14 = vor P02-04 (ohne Fahrzeug); Version 17 = mit Fahrzeug; Version 19 = zusaetzlich mit P02Overview. Aeltere lokale Sicherungen unter `.local/backups/` (nicht im Repo). |
| Pruefbelege | [P02-05](../evidence/P02-05.md), [P02-04](../evidence/P02-04.md), [P02-03R](../evidence/P02-03R.md); Stadtentwurf [MAP](../design/MAP.md), Masse [DIMENSIONS](../design/DIMENSIONS.md) |

## P02-06 angefangen, nicht abgenommen (Stand bei Sitzungsende 13.11.)

- Gebaut und im Place gespeichert (Version 19): `Workspace.P02Overview`, Revision 1, nur nicht kollidierende Markierungen: fuenf farbige Routenstreifen der P02-05-Fahrt, Kehrkreise auf den vier Hoefen, von oben lesbare Schilder fuer die vier Orte, Legende mit Etappenlaengen, Tor- und Gespannhinweis sowie Stationsfolge 1-4, beide Lager und Band ueber `Workspace.P02Line`. Quelle: [build-p02-06-overview.luau](../../tools/studio/build-p02-06-overview.luau); die Datei entspricht dem Place, wurde in ihrer Endfassung aber nicht komplett neu ausgefuehrt (Schilder wurden im Place nachgedreht).
- Aufnahmen liegen lokal (nicht im Repo) unter `.local/evidence/`: `P02-06-city-route.jpg` (Stadt von oben mit Route und Schildern), `P02-06-stations.jpg` (Stationsfeld von oben), `P02-06-drive.jpg` (Gespann faehrt mit sichtbarer Last, 4,4 m/s, automatische Fahrt, Kamera per Client-Skript nachgefuehrt).
- **Fehlt noch:** Beleg `docs/evidence/P02-06.md` mit den raeumlichen Vorgaben fuer P03 und Integration (Werte stehen in den Belegen P02-04 und P02-05 sowie in DIMENSIONS/MAP), Checkbox P02-06 im Startplan, Pruefung, dass `P02Overview` im Spiel nicht stoert (Neon-Streifen leuchten im Play-Modus stark; ggf. Material aendern oder das Modell nach `ServerStorage` legen).
- Eine handgesteuerte Tastaturfahrt in dieser Sitzung ist von der Strasse abgekommen und auf dem Rasen haengen geblieben; sie zaehlt nicht als Nachweis.

## Uebergabe an den naechsten Bearbeiter

**Studio-Zugang.** Alle Studio-Schritte laufen ueber den Roblox-Studio-MCP-Server (`%LOCALAPPDATA%\Roblox\mcp.bat`, Werkzeuge `list_roblox_studios`, `execute_luau`, `start_stop_play`, `save_place`, `screen_capture`). Der Agent braucht diesen Server in seiner eigenen Konfiguration; fuer Claude Code ist er seit 13.11. fuer dieses Repo eingetragen. Studio-ID vor jedem Schreibschritt neu auflisten (zuletzt `fd3455fc-e99a-4501-b259-dae75005af5d`) und Place/Universe abgleichen. Ohne Studio-Zugang sind nur Papier- und Skriptarbeiten moeglich.

**Arbeitsweise, die sich bewaehrt hat.**

- Builder und Checks liegen als Quelltext unter [tools/studio](../../tools/studio); `execute_luau` kann keine Dateien lesen, der Inhalt wird als Code uebergeben. Builder laufen im Edit-Datamodel, Proben im Server-Datamodel waehrend Play.
- Proben mit laengerer Laufzeit starten per `task.spawn`, schreiben ihr Ergebnis als JSON in einen `StringValue` in `ServerStorage` und werden mit kurzen Folgeaufrufen abgefragt. Play-Aenderungen bleiben nicht im Place.
- Vor einem Schreibschritt im Edit-Modus `save_place` als Wiederherstellungspunkt; nach Abnahme erneut speichern. Nie publizieren.
- Alle Masse in Metern, Faktor 25/7 Studs je Meter; lokale Kartenkoordinaten X/Z relativ zum Stadtursprung.

**Skripte dieses Abschnitts.**

| Datei | Zweck | Stand |
|---|---|---|
| [build-p02-04-vehicle.luau](../../tools/studio/build-p02-04-vehicle.luau) | baut `Workspace.P02Vehicle` (bricht ab, wenn es schon existiert) | entspricht Revision 2 im Place; die Datei selbst wurde nach der Sitzabsenkung nicht komplett neu ausgefuehrt, die Aenderung wurde im Place nachgezogen |
| [check-p02-04-vehicle.luau](../../tools/studio/check-p02-04-vehicle.luau) | lesende Massabnahme im Edit-Modus | ausgefuehrt, bestanden |
| [drive-p02-05-route.luau](../../tools/studio/drive-p02-05-route.luau) | automatische Streckenfahrt, Ergebnis in `ServerStorage.P0205Result` | ausgefuehrt, bestanden |
| [drive-p02-05-gate.luau](../../tools/studio/drive-p02-05-gate.luau) | Torprobe, zwei Varianten | beide Varianten einzeln gefahren; die zusammengefasste Datei nicht erneut ausgefuehrt |
| [probe-p02-05-handover.luau](../../tools/studio/probe-p02-05-handover.luau) | Avatar mit Ware um den Anhaenger, Wendekreis; Ergebnis in `ServerStorage.P0205Handover` | ausgefuehrt, bestanden |

**Naechste Schritte in Reihenfolge.**

1. **P02-06**: beschrifteter Uebersichtsstand und Fahrtaufnahme mit sichtbarer Last. Aufnahmen nach `.local/evidence/` (nicht im Repo), Beleg nach `docs/evidence/P02-06.md`.
2. **P02-02**: vollstaendige Trageabnahme der Stationsfolge in `Workspace.P02Line` mit `ServerStorage.P02CarryProbe` (alle 20 Auflagen, Lagerplaetze, Gaenge). Die Technik aus `probe-p02-05-handover.luau` (Avatar per `MoveTo`, Ueberlappung der getragenen Ware messen) laesst sich uebernehmen.
3. **P03** (Art-Muster) braucht Blender; der Nutzer stellt Blender auf Zuruf bereit. P03 ist von P02-06 unabhaengig.
4. Nutzerentscheidungen einholen: Hallentor (oben), schwaecheres Testgeraet (P00-03), handgefahrene Runde mit dem Gespann als Gegenprobe zur automatischen Fahrt.

**Bekannte Grenzen.** Gefahren hat bisher nur ein Serverskript plus zwei kurze Tastaturlaeufe; Fahrgefuehl, Federung und Kamera sind nicht abgestimmt. Fahrerhoehe 1,88 m gilt fuer einen R15-Testavatar. Auf zwei Etappen lag kurz ein Rad ueber einem Gehwegstreifen; die Stelle ist nicht lokalisiert. An den Zielen gibt es noch keine festen Uebergabepunkte. Gebaeude und Fahrzeug sind Platzhalter, keine Art-Freigabe.

## Dauerhafte Vorgaben

Bei Wiederaufnahme zuerst [MAP](../design/MAP.md) und den aktuellen Beleg lesen. Die kleine Werkstatt diente nur dem KI-/Importvergleich und darf nicht zum Spielgebaeude umgedeutet werden. Spielstart ist in der westlichen Tischlerei der Stadt. `CityGreybox` pruefen; den alten Ring-Builder nicht erneut ausfuehren. Vergleichs- und Technikproben bleiben fuer gezielte Tests erhalten.

Die Nutzerklaerung ist verbindlich: keine Ringkarte als Endlayout und keine kuenstliche Spiegelung; eine glaubwuerdig gewachsene Stadt mit mehreren Tischlereien. Gebaeude/Details sind Platzhalter und keine finale Artfreigabe.

P02-02, P02-06, finale Art und die Spielmechanik bleiben offen. Neue Fabrik-/Kartenmasse stammen aus MAP, nicht vom Vergleichshaus. P01-Mengen und Uebergaben bleiben die Grundlage der Produktionslogik. Commit und Push auf den Arbeitsbranch sind vom Nutzer am 13.11. beauftragt; Merge nach `main` und Publish des Place nur auf ausdruecklichen Auftrag.
