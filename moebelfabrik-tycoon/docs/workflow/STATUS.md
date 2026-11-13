# Projektstatus

Stand 13. November 2026. **Auf dem Ladehof der Start-Tischlerei steht ein lenkbarer Quad-/Anhaenger-Stellvertreter mit Holzpaket und Hockerkarton; Masse und kurze Fahrprobe bestanden, Version 17 gespeichert. Die Stadt-Greybox (vier Tischlereien, 47 Gebaeude) ist unveraendert.**

| Feld | Aktuell |
|---|---|
| Letzter abgeschlossener Schritt | **P02-04** - lenkbarer Quad-/Anhaenger-Stellvertreter `Workspace.P02Vehicle`; Huellen, Deck, Slots, Kupplung und Last gemessen, Fahrprobe mit und ohne Fahrer bestanden |
| Naechster Umsetzungsschritt | **P02-05 abschliessen** - automatische Streckenfahrt zu allen vier Orten und Torprobe bestanden ([Zwischenbeleg](../evidence/P02-05.md)); es fehlen Avatarplatz mit Ware an jeder Uebergabe, eine handgefahrene Runde und der Wendekreis |
| Offene Entwurfsfrage | Hallentor 4 m / Halle 10 m tief: Kehre in der Halle passt nur mit schraegem Anlauf (0,31 m Reserve); gerader Anlauf streift den Torpfeiler um 0,32 m |
| Offener Test davor | **P02-02** - Stationsprobe vorhanden, vollstaendige Trageabnahme fehlt; getrennt vom Mapdesign |
| Noch offene Umgebungsvoraussetzung | **P00-03** - reales schwaecheres Testgeraet bestimmen |
| Planabschnitt | [Startplan](../plan/00-start.md) |
| Zustaendigkeit | Studio/QA fuer die Streckenfahrt; Blockaden behebt Studio |
| Aktueller Test-Place | Furniture Factory Tycoon, Place `79033653140107`, Universe `10776116608`, privat |
| Spielkarte | `Workspace.CityGreybox`, Revision 1; Ursprung (430;0;450) Studs, 19 Strassen/Zufahrten, 4 Tischlereien |
| Archivierte Vorprobe | `ServerStorage.MapPrototypes.MapGreybox`; Ringfassung ausserhalb des Workspace |
| Vergleichsobjekt | `Workspace.FableWorkshop`, Asset `106051543998570`; kein vorgesehenes Spielgebaeude |
| Technikproben | `Workspace.P02Greybox` und `Workspace.P02Line`; Prueftraeger in `ServerStorage.P02CarryProbe`, nicht im Spielstart |
| Arbeitsbranch | `work/p00-studio-import` |
| Speicherung | `save_place`: Saved zu TeamCreate, Version 17. Studio wieder Edit; nicht publiziert. Lokale `.rbxl` im Projektstamm bleibt der fruehere Ausgangsstand. |
| Fahrzeugprobe | `Workspace.P02Vehicle`, Revision 2; Quad mit `VehicleSeat` und Skript `Drive`, Testattribute `TestThrottle`/`TestSteer` am Quad |
| Stand vor P02-04 | Place-Version 14 in der Roblox-Versionshistorie; keine lokale `.rbxm` fuer diesen Schritt |
| Sicherung vor P02-01 | `.local/backups/2026-11-12-p02-01/before-p02-01.rbxm`, Rueckleseprobe bestanden; Details im Beleg |
| Sicherung vor Karte | `.local/backups/2026-11-12-p02-03/before-map.rbxm`, sechs Wurzeln, Rueckleseprobe bestanden |
| Sicherung vor Stadt | `.local/backups/2026-11-12-p02-03r/before-city.rbxm`, sieben Wurzeln und Rueckleseprobe bestanden |
| Pruefbeleg | [P02-04](../evidence/P02-04.md), [Messwerte](../evidence/P02-04.json); Stadt: [P02-03R](../evidence/P02-03R.md), Stadtentwurf [MAP](../design/MAP.md) |
| Studio-Wiederaufnahme | Studio-ID neu auflisten; zuletzt `fd3455fc-e99a-4501-b259-dae75005af5d`; Place/Universe oben erneut abgleichen. Der Studio-MCP ist seit 13.11. auch fuer Sitzungen in diesem Repo eingetragen. |

Bei Wiederaufnahme zuerst [MAP](../design/MAP.md) und den aktuellen Beleg lesen. Die kleine Werkstatt diente nur dem KI-/Importvergleich und darf nicht zum Spielgebaeude umgedeutet werden. Spielstart ist in der westlichen Tischlerei der Stadt. `CityGreybox` pruefen; den alten Ring-Builder nicht erneut ausfuehren. Vergleichs- und Technikproben bleiben fuer gezielte Tests erhalten.

Die Nutzerklaerung ist verbindlich: keine Ringkarte als Endlayout und keine kuenstliche Spiegelung; eine glaubwuerdig gewachsene Stadt mit mehreren Tischlereien. Die neue Stadtfassung setzt den Grundriss um; Gebaeude/Details sind noch Platzhalter und keine finale Artfreigabe.

P02-02, P02-05 und P02-06, finale Art und die Spielmechanik bleiben offen. Der Wendekreis des Gespanns ist noch nicht bestimmt; die Fahrerhoehe (1,88 m) gilt nur fuer einen Testavatar. Die neue Karte hat einen verkehrsfreien Spawn; der alte Spawnblocker ist durch dessen Versetzen aus dem Spielstart entfernt. Neue Fabrik-/Kartenmasse stammen aus MAP, nicht vom Vergleichshaus. P01-Mengen und Uebergaben bleiben die Grundlage der Produktionslogik. Vor weiteren Studio-Schreibzugriffen den aktuellen Stand sichern. Kein Commit, Push oder Publish ohne ausdruecklichen Auftrag.
