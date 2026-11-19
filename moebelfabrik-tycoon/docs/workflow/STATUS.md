# Projektstatus

Stand 19. November 2026. **P02, P04, P05 und P06-01 bis P06-06 sind abgenommen.** Die P06-Studio-Demo verbindet Holzkauf, physische Übergaben und serverseitige Fahrtnachweise mit demselben Bestand. **Als Nächstes folgt P06-07 (Fahrzeugladung nach Wiederbeitritt und physische Bergung).**

| Feld | Aktuell |
|---|---|
| Letzter abgeschlossener Schritt | **P06-06** – Server bestätigt die Fahrt mit zwei Kartons zum Händler und Privatkunden ([Beleg](../evidence/P06-06.md)) |
| Davor | **P06-04/05** – Kauf mit R, Verladen und Entladen mit E, Holz auf den reservierten Rohstoffplatz ([Beleg](../evidence/P06-04-05.md)) |
| Naechster Umsetzungsschritt | **P06-07** – bestätigte Ladung beim Wiederbeitritt an den Anhängerplätzen oder an einer physischen Bergungsstelle darstellen |
| Entscheidungen 18.11. (delegiert) | Hallentor: Laden nur auf dem Hof, Halle wird nicht befahren, Tor bleibt 4 m ([MAP](../design/MAP.md)). Oberfläche: eine Finish-Oberfläche in Hocker01 v1 ([PRODUCTION](../design/PRODUCTION.md)). P00-03: Zielprofil schwächeres Android-Phone 1600×720, Touch, Grafikstufe 1; bis zum echten Gerät Studio-Emulator als Stellvertreter, Checkbox bleibt offen ([P00](../plan/00-start.md)) |
| Paralleles Paket | **P03-03** – Gebäude-Außenprobe lokal übernommen ([Beleg](../evidence/P03-03.md)), Abnahme und Roblox-Import stehen aus. **P03-05-Upload blockiert:** Der Nutzer muss unter `Assistant Settings > MCP Permissions` den Ordner `assets\p03-models\p03-05-import\exports` freigeben, das kann Claude nicht selbst tun. |
| Planabschnitt | [Handbetrieb, P06](../plan/01-handbetrieb.md#p06--quad-ladung-und-echte-fahrten) |
| Handlinie | `Workspace.P02Line` steht seit P06-01 in der Halle `CityGreybox.Buildings.Tischlerei_West` (Pivot 169,29/3,85/376,50 Studs). Die alten Bodenstreifen liegen in `ServerStorage.P02LineArchive`. Proben und Demo binden über Namen. |
| Zustaendigkeit | Lead integriert gemeinsame Dateien/Studio; Blender-Agent lieferte getrenntes P03-02-Paket, Lead hat Quelle/Exporte/Ansichten uebernommen. Kein paralleler Studio-Schreiber |
| Aktueller Test-Place | Furniture Factory Tycoon, Place `79033653140107`, Universe `10776116608`, privat |
| Spielkarte | `Workspace.CityGreybox`, Revision 1; Ursprung (430;0;450) Studs, 19 Strassen/Zufahrten, 4 Tischlereien |
| Fahrzeugprobe | `Workspace.P02Vehicle`, Revision 2, steht auf dem Ladehof der Start-Tischlerei; Quad mit `VehicleSeat`, Prompt "Fahren" und Serverskript `Drive`; ohne Fahrer steuern die Attribute `TestThrottle`/`TestSteer` am Quad |
| Archivierte Vorprobe | `ServerStorage.MapPrototypes.MapGreybox`; Ringfassung ausserhalb des Workspace |
| Archivierte Uebersicht | `ServerStorage.P02Overview`, Revision 2; nur fuer Edit-Aufnahmen voruebergehend nach Workspace verschieben, vor Play und Speicherung zuruecklegen |
| Vergleichsobjekt | `Workspace.FableWorkshop`, Asset `106051543998570`; kein vorgesehenes Spielgebaeude |
| Technikproben | `Workspace.P02Greybox` und `Workspace.P02Line`; Prueftraeger in `ServerStorage.P02CarryProbe`, nicht im Spielstart |
| Arbeitsbranch | `work/p00-studio-import`; jeder Abschluss wird gepusht (Nutzerauftrag vom 18.11.: fortlaufend committen und pushen) |
| Speicherung | TeamCreate **Version 60**, privater Stand, Studio im Edit-Modus. |
| Wiederherstellbare Staende | Version 53 = Fahrzeug-Slot-Punkte, Version 57 = getestete Lademodule, Version 60 = Fahrtnachweis und Serverphysik. |
| Pruefbelege | [P02-06](../evidence/P02-06.md), [P02-05](../evidence/P02-05.md), [P02-04](../evidence/P02-04.md), [P02-03R](../evidence/P02-03R.md); Stadtentwurf [MAP](../design/MAP.md), Masse [DIMENSIONS](../design/DIMENSIONS.md) |

## P06-06 abgenommen (19.11.)

- [Trips](../../src/server/Trips.luau) beobachtet die Fahrt im Server. Der Nachweis gilt je Ladung und Käuferzone. Beide Ziele wurden mit durchgehender Fahrt und zwei befestigten Kartons erreicht. Ein Positionssprung und eine Fahrtunterbrechung durch geänderte Ladung oder Eigentümerschaft entwerten den betroffenen Nachweis. [Beleg](../evidence/P06-06.md)

## P06-04/05 abgenommen (19.11.)

- [Loading](../../src/server/Loading.luau) prüft Fahrzeug, Eigentümer, Stillstand und beide Ladepunkte. Bei einer Entnahme bleibt das geprüfte Ziel für diese Charge gültig, während der Spieler sie trägt.
- [Studio-Demo und Prüfbeleg](../evidence/P06-04-05.md) dokumentieren den Tastaturdurchlauf, vier Gruppen von Serverprüfungen und die P05-Regression.

## P06-03 abgenommen (18.11.)

- [Vehicles.luau](../../src/server/Vehicles.luau) bindet `Vehicle.Quad1.SlotA/B` (Kapazität 1, Holzpaket oder Karton), `LineView` kennt Mounts für fahrende Plätze. Die P02-04-Stellvertreterladung liegt in `ServerStorage.P02VehicleArchive`, das Fahrzeug trägt `VehicleId=Quad1` und `Revision=3`.
- Die [Serverprobe](../../tools/studio/test-p06-03-vehicle-slots.luau) bestand vier Gruppen: Bindung, Grenzen über die gemeinsamen Regeln, befestigte Ladung (0,005 Studs Drift nach 9,4 m), Wiederherstellung auf die Slot-Punkte. [Beleg](../evidence/P06-03.md)

## P06-02 abgenommen (18.11.)

- [drive-p06-02-route.luau](../../tools/studio/drive-p06-02-route.luau): P02-05-Fahrmodell plus Hüllenprüfung gegen alle P06-01-Teile und Zonenprüfung je Halt. Fünf Etappen, 730 m Straße: 0 Hindernisse, 0 Kontakte, 0 Räder neben dem Belag, Slots A/B und 12/12 Hüllenecken in jeder Zone. Das Gespann parkt mittiger als im Freiraummodell angenommen.
- Echte Fahrereingabe per simulierter Tastatur: E steigt auf, W/A ergeben 18,7 m Fahrt und 96° Linksdrehung, danach steht das Gespann aufrecht. [Beleg](../evidence/P06-02.md)

## P06-01 abgenommen (18.11.)

- Die Handlinie wurde starr in die Halle der Start-Tischlerei verschoben, die Lagerseite liegt am Tor. [build-p06-01-zones.luau](../../tools/studio/build-p06-01-zones.luau) legt `LoadZone`, Annahmen und Lieferanten-Bedienmarken an. [check-p06-01-zones.luau](../../tools/studio/check-p06-01-zones.luau) bestand fünf Gruppen: Zonen, Überschneidungsfreiheit, Abstand zum Fahrmodell, Wegfindung durch das Tor, Übersetzung.
- Lieferantenplätze wurden 0,4 m nach außen verschoben (vorher 3 cm im Einfahrweg), Annahmen liegen in der hinteren linken Hofecke. [Beleg](../evidence/P06-01.md)

## P05-09 und Phase P05 abgenommen (18.11.)

- Die [Linien-Demo](../../tools/studio/start-p05-09-line-demo.luau) wird im Server eines frischen Play-Starts per `execute_luau` gestartet. Sie bietet 16 E-Prompts, Echtzeittakt, Warenansichten, HUD und zwei markierte Testpakete und läuft ohne DataStore. Die [automatische Kette](../../tools/studio/test-p05-09-chain.luau) läuft auf der gestarteten Demo.
- Der Tastaturdurchlauf erfolgte per `character_navigation` und `user_keyboard_input` (Taste E). Er brachte zwei Kartons ins Fertiglager, falsche Ablagen blieben in der Hand, Rückstau an der Säge war sichtbar.
- Befund: Gegenüberliegende Stationen teilen den Bedienplatz im Gang, E traf deshalb die falsche Auflage. Korrektur: Prompts werden nur in Blickrichtung angeboten (Regel in [PRODUCTION](../design/PRODUCTION.md)). Eine kürzere Reichweite half nicht, weil der Stationskörper den Avatar auf etwa 4 Studs hält. [Beleg](../evidence/P05-09.md)

## P05-08 abgenommen (18.11.)

- [Line.luau](../../src/server/Line.luau) (Takt, Status, Lagerbelegung), [WareView.luau](../../src/server/WareView.luau) (alle fünf Stufen inkl. Holzpaket) und [LineView.luau](../../src/server/LineView.luau) (Ansichten aus dem bestätigten Bestand, Stations- und Lagerschilder). `FactoryLabels` hat jetzt 25 Einträge.
- Die Stationssuite bestand 18/18 Fälle, die [Serverprobe](../../tools/studio/test-p05-08-line.luau) nach QA-P05-03 vier Gruppen. Bei Rückstau gab es keinen Verbrauch und keinen Save, nach Platzfreigabe lief die Linie weiter, fehlendes Holz wurde angezeigt. [Beleg](../evidence/P05-08.md)

## P05-06 und P05-07 abgenommen (18.11.)

- Der Finishlauf (6 s) zeigt die eine Finish-Oberfläche von Hocker01 v1 (ART: roh/Finish). Wählbare Varianten sind nicht Teil von v1. Der Packlauf (4 s) liefert [CartonView](../../src/server/CartonView.luau). `Recipe.bindStore` bindet `Fertiglager` als `FinishedStore.Slot1–4`.
- [Labels.luau](../../src/server/Labels.luau) und die gespeicherte `LocalizationService.FactoryLabels` machen die Warenschilder zweisprachig (EN-Quelle, DE-Übersetzung, Client `de-de` geprüft).
- Die gemeinsame [Serverprobe](../../tools/studio/test-p05-06-07-finish-pack.luau) bestand vier Gruppen, die Stationssuite 14/14 einschließlich der vollständigen Kette bis ins Fertiglager. Belege: [P05-06](../evidence/P05-06.md), [P05-07](../evidence/P05-07.md)

## P05-05 abgenommen (18.11.)

- `State.STATIONS` ist die einzige Quelle für die vier Stationsregeln. [Stations.luau](../../src/server/Stations.luau) führt Start und Ende jeder Station aus, Sawmill ruft es nur noch für die Säge auf. [StoolView.luau](../../src/server/StoolView.luau) stellt den Hocker als vermessene Greybox dar ("Rohhocker"/"Fertig").
- Die lokale [Stationssuite](../../tools/tests/p05-05-stations.luau) bestand 12/12 Fälle (`node tools/tests/run-p05-05.mjs`). Die [Serverprobe](../../tools/studio/test-p05-05-assembly.luau) bestand vier Gruppen, die P05-04-Probe lief unverändert, ebenso die Edit-Regressionen. [Beleg](../evidence/P05-05.md)
- Kein Bild: Der Viewport lieferte nach dem Play-Stopp schwarze Aufnahmen. Maße und Standfläche wurden per Skript geprüft.

## P05-04 abgenommen (18.11.)

- [Sawmill.luau](../../src/server/Sawmill.luau) und [KitView.luau](../../src/server/KitView.luau) sind eingebaut, State/Actions/Recipe ersetzt. Alle zwölf Factory-Module stimmen per Prüfsumme mit `src/server` überein. Die strikte Luau-Analyse und die lokalen Suiten P04-05 (41) und P04-06 (35) bestanden.
- Die [Serverprobe](../../tools/studio/test-p05-04-sawmill.luau) bestand vier Gruppen mit echtem Save in `FactoryP0504_Test`. Regressionen P04-01, P04-02, P04-07, P05-01 und P05-02 bestanden in Edit bzw. Server. [Beleg](../evidence/P05-04.md)
- Korrektur: Roblox vergrößert Teile unter 0,05 Studs. Die dünnen Bausatzwände sind deshalb 14 mm stark, die Hülle bleibt exakt 0,60 × 0,18 × 0,50 m.
- Hinweis für Edit-Tests: `require` im Edit-Datamodel liefert nach Quellenänderung noch gecachte Module. Daher auf einer frischen Kopie des Factory-Ordners prüfen (wie P04-01/P04-02).
- Offen: Ein Spieler- oder Stationsauslöser, die Statusanzeigen der Säge und das sichtbare Paket im Arbeitsbereich folgen mit P05-08. Die 6 s zählen ab der Serverzeit vor dem Start-Save.

## P05-02 abgenommen (18.11.)

- `Factory.Purchases` bestätigt Spielgeld, Charge am Lieferanten, Delivery-Zusage und Kaufbeleg gemeinsam. Fünf Prüfgruppen einschließlich echter Speicherung und Abgleich bestanden. [Beleg](../evidence/P05-02.md)

## P05-01 abgenommen (18.11.)

- `Factory.Recipe` bindet vier Stationen mit jeweils Eingang, Arbeitsbereich und Ausgang an zwölf physische Auflagen. Je neun Prüfgruppen in Edit und Server bestanden. [Beleg](../evidence/P05-01.md)

## P04-08 und P04 abgenommen (18.11.)

- Acht integrierte Prüfungen in zwei Studio-Serverstarts, künstlicher Record im isolierten DataStore. Unbestätigte Aufnahme verschwand beim Neustart, die bestätigte Ablage und ihr Beleg blieben erhalten. [Beleg](../evidence/P04-08.md)

## P04-07 abgenommen (18.11.)

- `Factory.Recovery` ordnet bestätigte Chargen einem eindeutigen normalen oder alternativen physischen Punkt zu. Acht Studio-Server-Prüfungen mit künstlichen Chargen bestanden. [Beleg](../evidence/P04-07.md)

## P04-06 abgenommen (18.11.)

- [Persistence.luau](../../src/server/Persistence.luau): frischer Reader, atomare Sessions-Callbacks, Metadaten-Erhalt, privater bestaetigter Stand und Single-flight. Unklarer Ausgang sperrt weitere Schreibvorgaenge; nur exaktes frisches Ruecklesen bestaetigt den Vorschlag. Stets `ready=false`.
- 35 unabhaengige lokale Faelle und Typpruefung bestanden; je 38 Adapterchecks plus 171 Regressionen in Studio Edit/Server. Unabhaengiger Quellreview ohne offene Integritaetsfehler. [Beleg](../evidence/P04-06.md), [Messwerte](../evidence/P04-06.json). Version38 gespeichert; Testkopien entfernt, kein Clientzugriff.
- Nach Aktivierung des Studio-API-Zugriffs bestanden sieben echte Backend-Prüfungen in `FactoryP0406_Test` mit zufälligem Scope und künstlichem Profil. Der neue Controller las den bestätigten Wert 789 wieder ein. Die alte Sitzung konnte ihn nicht überschreiben. Der künstliche Record ist auf Revision 6 freigegeben, Studio wieder in Edit.

## P04-05 Sitzungsgrenze abgenommen (17.11.)

- [Sessions.luau](../../src/server/Sessions.luau): getrennte Speicherrevision, Besitz mit Ablaufzeit und atomare Erwerb-/Schreib-/Freigabepruefung. Aktuelle atomare Daten gewinnen gegen alte Ladekopien; private Versuchsschluessel sperren verspaetete lokale Antworten. Alle Resultate weiter `ready=false`.
- 41 Faelle lokal und je Studio Edit/Server plus je 130 Regressionen bestanden, unabhaengiger Quellreview und getrennte Testsuite. [Beleg](../evidence/P04-05.md), [Messwerte](../evidence/P04-05.json). Servermodule auf Client unsichtbar, Testkopien entfernt. Vorzustand Version34, Abschluss Version36.
- Kein echter Backend-Adapter oder aktives Profil. P04-06 muss jede Transformation am aktuellen Backend-Wert ausfuehren, Zeit in jedem Callback/Retry frisch bestimmen und nur bestaetigte Resultate lokal uebernehmen. Gesamte P04-Persistenzabnahme bleibt offen.
- Art-Vertrag korrigiert: kein kostenloser Fable-5.2-Zugang vorausgesetzt; vorhandene Blender-Quellen weiterverwenden. Lokaler Roblox-Skill auf 2.15.0 aktualisiert und gesichert (17 Dateien, zehn Audits; eingeschraenkter Live-API-Nachweis).

## P04-04 Ladegrenze abgenommen (16.11.)

- [Profiles.luau](../../src/server/Profiles.luau) laedt den geschlossenen Umschlag Version1 mit State2/Rezeptwahl. Nur erfolgreiches Fehlen erlaubt einen Initializer. Fehler/fremde/beschaedigte Daten bleiben ohne Ersatzprofil. Erfolg bleibt `ready=false`.
- 24 Faelle mit 64 Aufrufen und 106 Regressionen je Edit/Server bestanden, unabhaengiger Review abgeschlossen. [Beleg](../evidence/P04-04.md), [Messwerte](../evidence/P04-04.json). Version33 gespeichert; keine Servermodule auf dem Client.
- Kuenstliche Reader, kein echter Backend-Roundtrip, keine dauerhafte Ersterstellung oder Freigabe. P04-05 bindet aktive Veroeffentlichung/Schreiben an Sitzungsbesitz und Revision.

## P04-03 abgenommen (16.11.)

- [Transfers.luau](../../src/server/Transfers.luau) reserviert Quelle/Ziel, bucht genau einmal um und behandelt Replay, Abbruch und Ablauf. Return-/Delivery-Zusagen bleiben unabhaengig vom Claim-Ablauf bestehen. Schema 2 und gemeinsame Pruefung in State/Actions integriert.
- 36 Faelle mit 211 API-Aufrufen je Edit/Server, zusaetzlich State/Actions je 35 bestanden; unabhaengiger Lesereview und Quellenvergleich abgeschlossen. [Beleg](../evidence/P04-03.md), [Messwerte](../evidence/P04-03.json). Version 31 gespeichert, Client ohne Servermodule; Testkopien entfernt.
- Nur kuenstlicher Serverzustand, kein dauerhaft bestaetigter Save eines Spielerprofils. Remotes, Weltaktionen, Laden und Sitzungsbesitz fehlen weiterhin. P04-04 folgt; parallele Modellarbeit hat getrennte Zustaendigkeit.

## P03-01 Arbeitsreferenz abgenommen (16.11.)

- [Referenzblatt](../../assets/p03-reference/reference.svg) und [Mass-/Anschlussbrief](../../assets/p03-reference/reference.md) technisch uebernommen; SVG/XML, Dateiidentitaet und komplette Vorschau geprueft. Hauptformen/Anschluesse sind auf Vertragswerte oder gekennzeichnete neue Entscheidungen zurueckgefuehrt. [Beleg](../evidence/P03-01.md).
- P03-02 wurde parallel als technisches Modellpaket ausgearbeitet; siehe naechsten Abschnitt. Aktiver Saegeschnitt/Schutzbewegung bleiben offen.

## P03-02 Modellpaket bereit, Abnahme offen (16.11.)

- [Quelle und Uebergabe](../../assets/p03-models/p03-02/handoff.md): Roh-/Finishhocker, neun Holzteile im offenen Traeger, Saege und 1-m-Koerper. Blend, fuenf FBX, gepackte Texturen, reproduzierbare Skripte und sieben aktuelle Ansichten. [Gesamtbild](../../assets/p03-models/p03-02/renders/overview-final.png).
- 179 Geometriepruefungen und fuenf FBX-Rueckimporte in Blender bestanden. Unabhaengiger Quellreview, Lead-Bildpruefung und SHA-256-Vergleich aller 25 uebernommenen Dateien abgeschlossen. [Beleg](../evidence/P03-02.md).
- Originalszene erhalten; Backup nur `.local/p03-02-models/before-p03-02.blend`. Kein Roblox-Import/Upload. Normale und kleine Spielkamera, Kollision, aktiver Saegeschnitt und finale Art fehlen. P03-02/P03-05 bleiben offen; vorhandene Blender-Pakete weiterverwenden, Fable 5.2 ist keine kostenlose Umsetzungsvoraussetzung mehr.

## P03-05 neutraler Import und EN/DE vorbereitet (16.11.)

- Nutzer verlangt Englisch und Deutsch; [Art-Vertrag](../design/ART.md#sprache-und-beschriftung) und [Sprachvertrag](../technical/LOCALIZATION.md) halten die Entscheidung fest. Acht Wort-Meshes aus Importkopie entfernt, Schildflaechen erhalten; drei Pfeile mit Volumen. Historische P03-02-Quellen/Vorschauen unveraendert.
- [Importpaket](../../assets/p03-models/p03-05-import/handoff.md): 297 Pruefungen, 140 geschlossene Exportmeshes und fuenf FBX-Rueckimporte bestanden. Native `LocalizationTable` mit acht Schluesseln, EN-/DE-Translator und `AutoLocalize`-Bindungen an temporaeren Modellwurzeln getestet; Layout auf importierten Assets noch offen.
- Nutzer hat fuenf permanente Assets auf Account3493645144 freigegeben. Scopes `asset:read/write` liefern200. Erster Upload des Kontrollkoerpers durch MCP-Ordnerschutz abgewiesen, **kein Asset/keine Operation angelegt**. Exakter Exportordner wurde erneut zur Freigabe angefragt. Kein Umgehungsversuch oder erneuter Upload. [Beleg](../evidence/P03-05.md).
- Nach Bestaetigung unter `Assistant Settings > MCP Permissions` genau den Ordner `C:\Claudeprojecte\repo\hattis-projekte\moebelfabrik-tycoon\assets\p03-models\p03-05-import\exports` erneut verwenden; jeden Upload samt Operation/Asset-ID protokollieren und nicht duplizieren. Ausgang fuer Place-Import Version33.

## P04-02 abgenommen (13.11.)

- [Actions.luau](../../src/server/Actions.luau) prueft eigenen Bestand, Menge1, Revision, Quelle, Träger, Stufe und Zielkapazitaet mit deutschen Rueckmeldungen. Direkte Lager-zu-Station-/Fahrzeug-Wege werden verworfen. Kein Schreibzugriff durch die Pruefung.
- 35 synthetische Faelle je Edit und Server bestanden, unabhaengiger Lesereview abgeschlossen; [Beleg](../evidence/P04-02.md), [Messwerte](../evidence/P04-02.json). Version 26 gespeichert, Client ohne Servermodule.
- Die damaligen lokalen P04-03-Pakete wurden inzwischen integriert und unter P04-03 abgenommen; aktuelle Quelle ist `src/server/`, nicht die alten `.local`-Kopien. Keine parallelen Studio-Schreiber.

## P04-01 abgenommen (13.11.)

- Quelle [State.luau](../../src/server/State.luau), Live-Modul `ServerScriptService.Factory.State`. Eigentümer, Geld, Revision, Einzelplaetze und Chargen; ein einziger logischer Ort pro Charge. Geschlossene JSON-taugliche Records mit Rezeptversion1 und Menge1.
- [35 Pruefungen](../../tools/studio/test-p04-01-state.luau) je Edit und Server bestanden, Client ohne Modulzugriff; unabhaengiger Review abgeschlossen. [Beleg](../evidence/P04-01.md), [Messwerte](../evidence/P04-01.json).
- Nur ModuleScript, keine Startskripte, Remotes, aktiven Profile oder DataStore-Zugriffe. Leere Konstruktor-Profile sind Schema-Muster und duerfen fehlgeschlagenes Laden nicht ersetzen. Gesamte P04-Persistenzabnahme steht aus.

## P02-02 nachgeholt und abgenommen (13.11.)

- [Trageprobe](../../tools/studio/probe-p02-02-carry.luau) mit sichtbarem 20-Teil-Traeger: 20/20 Auflagen und Ablagen, 25/25 Laufziele, 1.530 Messungen ohne Hüllenüberschneidung oder fehlenden Boden. Unabhaengige QA bestaetigt Ergebnis und geschlossene Pruefluecken.
- Sichere Abstaende in [GREYBOX](../design/GREYBOX.md): Lager 0,20 m und Stationen 0,15 m hinter den urspruenglichen Fussmarken; westliche Drehpunkte weiter aussen. Die alten Lagerfussmarken allein sind keine freien Trageposen.
- Nur Laufzeit-Probe, keine gespeicherten Szenenaenderungen. Studio wieder Edit, Teststand weiter Version 22. Rohbilder `.local/evidence/P02-02-carry-stations.jpg` und `P02-02-carry-finished-store.jpg`.
- Geprueft: ein R15-Avatar, skriptgesteuerte Bewegung und Handhabung, sechs feste Koerper, orientierte Huelle mit 1 mm Randeinzug. Finale Animation, manuelle Bedienung und Fabrikintegration bleiben spaeteren Aufgaben vorbehalten.

## P02-06 abgenommen (13.11.)

- `ServerStorage.P02Overview`, Revision 2: fuenf Routenfarben, vier Orte, Stationsfolge, beide Lager, Band und einzeln lesbare R1-R4/F1-F4. Builder komplett ausgefuehrt und 193 Part-/Text-Eintraege mit dem Place abgeglichen. [Check](../../tools/studio/check-p02-06-overview.luau) in Edit und Play bestanden; keine Uebersicht auf dem Spielclient.
- Aufnahmen unter `.local/evidence/`: `P02-06-city-route.jpg`, `P02-06-stations-final.jpg`, `P02-06-store-slots.jpg`, `P02-06-drive-clean.jpg` sowie `P02-06-drive-sequence/index.html` mit acht unveraenderten Fahrbildern ueber 15,002 s. QA hat Slotlesbarkeit, Ortswechsel und sichtbare Last bestaetigt.
- [Abnahme und raeumliche Vorgaben fuer P03](../evidence/P02-06.md), [Messwerte](../evidence/P02-06.json). Vorzustand Version 20, Abschluss Version 22. Keine Aenderungen an Stadt, Fahrzeug oder Stationen; kein Commit/Push in dieser Fortsetzung.
- Vollstaendige manuelle Runde bleibt offen. Fruehere von der Strasse abgekommene Tastaturfahrten zaehlen nicht als Nachweis.

## Uebergabe an den naechsten Bearbeiter

**Studio-Zugang.** Alle Studio-Schritte laufen ueber den Roblox-Studio-MCP-Server (`%LOCALAPPDATA%\Roblox\mcp.bat`, Werkzeuge `list_roblox_studios`, `execute_luau`, `start_stop_play`, `save_place`, `screen_capture`). Der Agent braucht diesen Server in seiner eigenen Konfiguration; fuer Claude Code ist er seit 13.11. fuer dieses Repo eingetragen. Studio-ID vor jedem Schreibschritt neu auflisten (zuletzt `9738348c-a74c-444f-9a58-eab8182a87ec`) und Place/Universe abgleichen; bei Verbindungswechsel die neu gelieferte ID verwenden. Ohne Studio-Zugang sind nur Papier- und Skriptarbeiten moeglich.

**Arbeitsweise, die sich bewaehrt hat.**

- Builder und Checks liegen als Quelltext unter [tools/studio](../../tools/studio); `execute_luau` kann keine Dateien lesen, der Inhalt wird als Code uebergeben. Builder laufen im Edit-Datamodel, Proben im Server-Datamodel waehrend Play.
- Proben mit laengerer Laufzeit starten per `task.spawn`, schreiben ihr Ergebnis als JSON in einen `StringValue` in `ServerStorage` und werden mit kurzen Folgeaufrufen abgefragt. Play-Aenderungen bleiben nicht im Place.
- Vor einem Schreibschritt im Edit-Modus `save_place` als Wiederherstellungspunkt; nach Abnahme erneut speichern. Nie publizieren.
- Alle Masse in Metern, Faktor 25/7 Studs je Meter; lokale Kartenkoordinaten X/Z relativ zum Stadtursprung.

**Skripte dieses Abschnitts.**

| Datei | Zweck | Stand |
|---|---|---|
| [src/server/Stations.luau](../../src/server/Stations.luau) | Stationslauf für alle vier Stationen: Start mit Ausgangsreservierung, einmaliger Abschluss | 12 lokale Fälle, 4 Servergruppen (Montage), Version 47 |
| [src/server/StoolView.luau](../../src/server/StoolView.luau) | Greybox-Hocker, roh oder fertig | Hülle 0,40 × 0,45 × 0,40 m auf der Montageauflage gemessen, Version 47 |
| [src/server/Sawmill.luau](../../src/server/Sawmill.luau) | Säge als dünner Wrapper um Stations | P05-04-Probe erneut bestanden, Version 47 |
| [src/server/KitView.luau](../../src/server/KitView.luau) | Greybox-Bausatz mit neun Holzteilen | Hülle 0,60 × 0,18 × 0,50 m in Edit/Server gemessen, Version 46 |
| [src/server/Persistence.luau](../../src/server/Persistence.luau) | Backend-Adapter, bestätigter Stand und unklarer Ausgang | 35 lokal, je 38 + 171 Edit/Server, 7 echte DataStore-Prüfungen auf Version 38 |
| [src/server/Sessions.luau](../../src/server/Sessions.luau) | Sitzungsbesitz, Speicherrevision und lokale Versuchssperre | 41 Fälle lokal sowie je in Edit und Server, Version 36; Backend-Nachweis P04-06 bestanden |
| [src/server/Profiles.luau](../../src/server/Profiles.luau) | versionierte schreibfreie Ladeentscheidung | 24 Edit-/Server-Faelle bestanden, Version33; echte Speicheranbindung offen |
| [src/server/Transfers.luau](../../src/server/Transfers.luau) | Reservierung, atomare Umbuchung und idempotente Belege | 36 Edit-/Server-Faelle bestanden, Regression Version33 |
| [src/server/Actions.luau](../../src/server/Actions.luau) | gemeinsame schreibfreie Aktions-/Reservierungspruefung | 35 Regressionsfaelle sowie P04-03 bestanden, Version31 |
| [src/server/State.luau](../../src/server/State.luau) | Datenvertrag Schema2, Claims/Zusagen/Belegbeziehungen | 35 Regressionsfaelle sowie P04-03 bestanden, Version31 |
| [probe-p02-02-carry.luau](../../tools/studio/probe-p02-02-carry.luau) | durchgehende Tragefolge mit allen 20 Auflagen | Endfassung in Play bestanden, danach Edit-Check erneut bestanden |
| [build-p02-06-overview.luau](../../tools/studio/build-p02-06-overview.luau) | baut `ServerStorage.P02Overview`, bricht bei vorhandenem Modell ab | Endfassung komplett ausgefuehrt und mit dem Place abgeglichen |
| [check-p02-06-overview.luau](../../tools/studio/check-p02-06-overview.luau) | lesende Inhalts-, Archivierungs- und Slotpruefung | Edit/Server-Play bestanden; Client ohne Uebersicht |
| [build-p02-04-vehicle.luau](../../tools/studio/build-p02-04-vehicle.luau) | baut `Workspace.P02Vehicle` (bricht ab, wenn es schon existiert) | entspricht Revision 2 im Place; die Datei selbst wurde nach der Sitzabsenkung nicht komplett neu ausgefuehrt, die Aenderung wurde im Place nachgezogen |
| [check-p02-04-vehicle.luau](../../tools/studio/check-p02-04-vehicle.luau) | lesende Massabnahme im Edit-Modus | ausgefuehrt, bestanden |
| [drive-p02-05-route.luau](../../tools/studio/drive-p02-05-route.luau) | automatische Streckenfahrt, Ergebnis in `ServerStorage.P0205Result` | ausgefuehrt, bestanden |
| [drive-p02-05-gate.luau](../../tools/studio/drive-p02-05-gate.luau) | Torprobe, zwei Varianten | beide Varianten einzeln gefahren; die zusammengefasste Datei nicht erneut ausgefuehrt |
| [probe-p02-05-handover.luau](../../tools/studio/probe-p02-05-handover.luau) | Avatar mit Ware um den Anhaenger, Wendekreis; Ergebnis in `ServerStorage.P0205Handover` | ausgefuehrt, bestanden |

**Naechste Schritte in Reihenfolge.**

1. **P06**: Beladen und Entladen über die gemeinsamen Umbuchungen (P06-04/05), danach Fahrtnachweis und Wiederbeitritt. Spieler-Kaufbedienung am Lieferantenhof gehört zu P06-04.
2. **P03-02/P03-05**: Nach ausstehender Exportordnerfreigabe die neutrale Kopie unter `assets/p03-models/p03-05-import/` einmalig hochladen/importieren; `label-p03-05-probe.luau` mit deren `labels.json` ausfuehren. 1-m-Koerper, Material/Normalen/Marker/Kollision und beide Sprachen pruefen. Aktive Saegeprozessdarstellung/Art bleiben offen, kein paralleler Studio-Schreiber. Fable 5.2 nicht als kostenlosen Dienst einplanen; Art-Vertrag beachten.
3. Handgefahrene Runde mit dem Gespann als Gegenprobe zur automatischen Fahrt (in P06-08 per simulierter Eingabe möglich). P00-03 auf einem echten Gerät, sobald verfügbar.

**Bekannte Grenzen.** Gefahren hat bisher nur ein Serverskript plus zwei kurze Tastaturlaeufe; Fahrgefuehl, Federung und Kamera sind nicht abgestimmt. Fahrerhoehe 1,88 m gilt fuer einen R15-Testavatar. Auf zwei Etappen lag kurz ein Rad ueber einem Gehwegstreifen; die Stelle ist nicht lokalisiert. An den Zielen gibt es noch keine festen Uebergabepunkte. Gebaeude und Fahrzeug sind Platzhalter, keine Art-Freigabe.

## Dauerhafte Vorgaben

Bei Wiederaufnahme zuerst [MAP](../design/MAP.md) und den aktuellen Beleg lesen. Die kleine Werkstatt diente nur dem KI-/Importvergleich und darf nicht zum Spielgebaeude umgedeutet werden. Spielstart ist in der westlichen Tischlerei der Stadt. `CityGreybox` pruefen; den alten Ring-Builder nicht erneut ausfuehren. Vergleichs- und Technikproben bleiben fuer gezielte Tests erhalten.

Die Nutzerklaerung ist verbindlich: keine Ringkarte als Endlayout und keine kuenstliche Spiegelung; eine glaubwuerdig gewachsene Stadt mit mehreren Tischlereien. Gebaeude/Details sind Platzhalter und keine finale Artfreigabe.

Finale Art und die Spielmechanik bleiben offen. Neue Fabrik-/Kartenmasse stammen aus MAP, nicht vom Vergleichshaus. P01-Mengen und Uebergaben bleiben die Grundlage der Produktionslogik. Commit und Push auf den Arbeitsbranch sind vom Nutzer am 13.11. beauftragt; die jetzigen Abschluesse sind bislang uncommitted. Merge nach `main` und Publish des Place nur auf ausdruecklichen Auftrag.
