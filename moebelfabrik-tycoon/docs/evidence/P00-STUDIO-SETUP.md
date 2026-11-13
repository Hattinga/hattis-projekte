# P00 – Studio-Einrichtung und Wiederaufnahme

Stand 12. November 2026. Lead und Studio-Integration liegen beim Hauptagenten. Auftrag COMP-R2-IMPORT ist die technische Importprobe von Fables ausgewaehlter Werkstatt. Dies nimmt die spaetere P03-Abnahme nicht vorweg.

## Testziel und Bearbeitungsweg

- Lokaler Test-Place: `Furniture-Factory-Tycoon.rbxl` im Projektstamm. Nicht in der Cloud veroeffentlicht, PlaceId und GameId beide 0.
- Studio-MCP-Verbindung verifiziert: `list_roblox_studios`, Edit-Zustand, Workspace-Baum, lesende Luau-Abfrage und Viewport-Aufnahme erfolgreich.
- Die Instanz-ID vom 12.11. war `0215638d-f1ea-4fa7-a6ec-518212b6f218`. Bei jeder neuen Sitzung erneut auflisten, nicht die alte ID voraussetzen.
- Vorhandene Welt: Baseplate und SpawnLocation, keine ServerScriptService-Skripte. Bearbeitung ueber die offiziellen Studio-MCP-Werkzeuge.

## Git, Sicherung und fuehrende Quellen

- Ausgangsbranch `main`, Ausgangscommit `3e9b1b78c6f671692c420a2931b80904f81b56ff`.
- Arbeitsbranch `work/p00-studio-import`. Vor Arbeitsbeginn war ausschliesslich die lokale Place-Datei untracked. Kein Commit oder Push ausgefuehrt.
- Separater Snapshot: `.local/backups/2026-11-12-initial/Furniture-Factory-Tycoon.rbxl`, 88.707 Bytes. SHA-256 identisch zur gesicherten Datei: `19126AB8B1B0DF4A299ABA0A5640CB80BF3EB20C94519AC4C3AD9D88F12FF9AB`.
- Wiederherstellung: Snapshot in Studio ueber Datei > Oeffnen laden. Vor einem Ersetzen des Arbeits-Place den aktuellen Stand separat sichern. Snapshot nicht ueberschreiben.
- Fuehrende Place-Quelle ist `Furniture-Factory-Tycoon.rbxl` im Projektstamm. Studio-Aenderungen muessen dorthin gespeichert werden. Ein nur im offenen Editor vorhandener Stand gilt noch nicht als gesicherte Datei.
- Neue Spielskripte sollen kuenftig als lesbare Dateien im Projekt versioniert und gezielt nach Studio uebertragen werden. Noch existieren keine Spielskripte.
- Gepruefte Modellquelle: `C:/Users/hatti/Documents/ChatGPT/Random ass Side Projects/furniture-tycoon/competition/runde2/fable/workshop.blend`.
- Erzeugungsskript und Original-FBX liegen daneben als `build.py` und `workshop.fbx`. `.blend`-SHA-256: `BE3B99FECF7CE81273D8C1671D867281E9F3CBA4D34EFA787833A73B26E08EEA`, FBX-SHA-256: `E35407077FBA2B859AABAE2512B49CBF6302193568BF01DCA08CF02A8F701D4D`.
- Neue Exporte werden aus der gespeicherten Quelle in einem getrennten Blender-Prozess erzeugt. Das Original und die Live-Blender-Szene bleiben Referenz.

## Modell und Importziel

- Nutzerwahl vom 11. November: A eindeutig besser. A ist Fable 5.2, B Codex. Auswahlbeleg: `competition/runde2/ABNAHME.md` im obigen Vergleichsordner.
- Quelle erneut geprueft: 45 Meshes, 13.080 Dreiecke insgesamt, groesstes Mesh 1.300 Dreiecke. Kein Mesh liegt ueber dem am 12.11. in den offiziellen Modell-Spezifikationen genannten Limit von 20.000.
- Weltachsen der Quelle: Z nach oben, Tor bei Y=0, Fenster an +X. Gesamtmasse einschliesslich offener Tueren und Fundament: 7,15 x 6,43747 x 4,895 m.
- Technische Importprobe verwendet vorlaeufig 1 m = 1/0,28 Studs. Erwartete Gesamthoehe 17,48214 Studs, lichte Tuerhoehe 8,39286 Studs. Dies ersetzt noch nicht den gemeinsamen Massvertrag P01-05.
- Fables Materialien verwenden ueberwiegend reine Farbwerte und keine heruntergeladenen Texturen. Import auf Farbe, Transparenz, Ausrichtung, Massstab und Vollstaendigkeit pruefen.

## Freigaben und offene Arbeit

Der lesende Scope-Test ergab, dass `asset:read` und `asset:write` noch nicht gewaehrt sind. Der Nutzer wurde gebeten, sie unter Assistant > Settings > MCP Permissions > Publish & manage assets zu aktivieren und den Quellordner `.../competition/runde2/fable` als Upload-Ordner freizugeben. Die Einwilligung zur dauerhaften Werkstatt-Assetanlage auf dem in Studio angemeldeten Roblox-Konto wurde gemeinsam angefragt. Noch kein Upload und keine Studio-Mutation erfolgt.

Nach Bestaetigung erneut pruefen, GLB direkt im freigegebenen Ordner exportieren, genau ein Modell hochladen, Asset-ID protokollieren und diese wiederverwenden. Bei verweigerten Rechten anhalten, keinen alternativen Umgehungsweg verwenden. Noch keine Zustimmung zur Veroeffentlichung der gesamten Experience.

P00-03 bleibt offen: Schwaecheres reales Testgeraet, Eingabe, Aufloesung und Grafikstufe sind noch nicht festgelegt. Bisherige Desktoppruefungen sind kein Leistungsnachweis fuer Mobilgeraete.

## Evidenzorte

- Kurze versionierte Testprotokolle: `docs/evidence/<Aufgaben-ID>.md` oder `.json`.
- Lokale Art-Aufnahmen: `.local/evidence/<Aufgaben-ID>/art/`.
- Lokale Fahrvideos: `.local/evidence/<Aufgaben-ID>/video/`.
- Lokale Rohprotokolle: `.local/evidence/<Aufgaben-ID>/logs/`.
- Jeder Beleg nennt Aufgabe, Place/Asset-ID oder Dateihash, Methode, Ergebnis und offene Pruefung. Aufnahme und Protokoll teilen dieselbe Aufgaben-ID.

## Fortsetzung 12. November

Die anfaenglich fehlenden Freigaben wurden erteilt. Der Nutzer speicherte die Testwelt als private Experience. Import und Begehung sind inzwischen abgeschlossen; aktueller Stand und fuehrende Quellen stehen in [COMP-R2-IMPORT](COMP-R2-IMPORT.md). Die frueheren Angaben zu fehlender Freigabe und externem Quellordner sind der Einrichtungsverlauf, nicht der aktuelle Arbeitsstand.
