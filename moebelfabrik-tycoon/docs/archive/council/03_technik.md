# Council 03 - Technik und Machbarkeit

**Rolle:** Roblox-Technikreview. **Stand:** 06.11.2026. **Urteil:** Bedingtes Go für einen begrenzten Prototyp. Dieser Text ist ein technischer Entwurf. Es wurden weder Code noch Performance, Speicherstände oder Studio-Importe getestet. In der Sitzung sind keine Roblox-Studio-MCP-Tools verfügbar.

## 1. Machbarer Kern und klare Grenze

Die gewünschte Entwicklung - selbst tragen, Mitarbeiter einsetzen, Förderbänder bauen - lässt sich als drei Arten desselben Materialtransports entwerfen. Das vermeidet drei getrennte Wirtschaftssysteme. Entscheidend ist ein eindeutiger serverseitiger Bestand: Jedes Material befindet sich genau an einem logischen Ort. Ein sichtbares Brett, ein NPC und ein Förderband dürfen diesen Bestand darstellen und bewegen, aber niemals unabhängig vervielfachen. Physikalische Kollisionen bleiben für Glaubwürdigkeit und Bewegung; die Wirtschaft wird durch explizite Übergaben geführt.

Diese Trennung ist auch eine Sicherheitsentscheidung: Roblox beschreibt, dass Clients mit Netzwerkbesitz die Physik ihrer Teile beeinflussen und Berührungsereignisse manipulieren können. Ein Kontakt mit dem Verkaufspunkt wäre deshalb keine ausreichende Auszahlungserlaubnis. [Roblox: Network ownership](https://create.roblox.com/docs/scripting/security/network-ownership)

## 2. Minimales Zustandsmodell

**Entwurf:** Ein Spielerprofil enthält Währung, freigeschaltete Rezepte, Maschinen und deren Layout, Mitarbeiter mit Aufgaben sowie eine Rebirth-Generation. Eine Charge hat eine ID, einen Eigentümer, einen Produkttyp, eine ganzzahlige Menge, die Verarbeitungsstufe und genau einen Ort: Lager, Träger, Stationspuffer oder Transportsegment. Transportreservierungen sind vorübergehend und besitzen einen Ablaufzeitpunkt.

Eine Station benötigt Rezept, Zustand, Eingangs- und Ausgangskapazität und gegebenenfalls einen Produktionsauftrag. Zustände reichen zunächst als frei, bereit, arbeitet oder Ausgang voll. Aufträge verbrauchen Inputs und erzeugen Outputs nach einer definierten Rezeptmenge. Kleine Zwischenprodukte werden in sichtbaren Kisten oder Trays gebündelt; es entsteht kein eigener Datenbankeintrag für jede Schraube. Bezahlen, Materialkauf, Verkauf und Transport verwenden dieselben geprüften Bestandsregeln.

## 3. Übergaben, Konkurrenz und Duplikate

Roblox verlangt serverseitige Prüfung von Berechtigungen, Kontext, Datentypen und Werten für Aktionen an der Client-Server-Grenze. [Roblox: Client-server boundary](https://create.roblox.com/docs/scripting/security/client-server-boundary)

**Konsequenz für unseren Entwurf:** Der Client fordert eine Aktion an; der Server bestimmt Preis, Rezept und Ergebnis. Er prüft unter anderem Plot-Eigentum, Nähe, tatsächlichen Ausgangsbestand, freien Zielplatz und erlaubte Produktionsstufe. Fremde Plots und unerwartete IDs werden abgewiesen; numerische Mengen müssen endlich, positiv, ganzzahlig und begrenzt sein. Aktionsfrequenzen werden serverseitig beschränkt.

Zwei Arbeiter können denselben Auftrag sehen. Daher reserviert genau einer die Quelle und den vorgesehenen Zielplatz. Die eigentliche Übergabe prüft Reservierung und Zustandsrevision erneut und bucht Quelle und Ziel gemeinsam in einer kurzen, nicht wartenden Serveroperation. Vorherige Animationen oder Wegsuche zählen nicht als Buchung. Wiederholte Anfragen mit derselben Vorgangs-ID liefern das vorherige Ergebnis, ohne erneut zu bezahlen. Bei Abbruch wird die Reservierung freigegeben; verschwindet ein Träger, kehrt seine Charge an einen festgelegten gültigen Lagerort zurück. Veraltete Reservierungen einer früheren Rebirth-Generation sind ungültig.

## 4. Förderbänder und Mitarbeiter

**Förderband-Entwurf:** Stationen haben sichtbar markierte Ein- und Ausgänge. Ein Band verbindet zunächst eine Quelle mit einem Ziel; Verzweigungen, frei platzierbare Höhenwechsel und automatische globale Routenplanung entfallen im Prototyp. Der Server führt Transportfortschritt und Zielreservierung. Clients stellen das Produkt entlang des Bandes dar. Ein volles Ziel stoppt die Zufuhr an einem sichtbaren Puffer. Nichts fällt aus der Welt und verschwindet aus dem Bestand. Große Möbel werden später als passende flache Teile, Transportpaletten oder Kartons befördert; ein fertiges Sofa muss nicht auf ein schmales Brettförderband passen.

**NPC-Entwurf:** Mitarbeiter erhalten feste Stationsaufgaben oder Transportstrecken. Sie benutzen dieselben reservierten Übergaben wie der Spieler. Maschinen besitzen Bedienplätze außerhalb des Laufwegs. Roblox bietet Wegsuche um Hindernisse; Wege können blockieren und müssen bei Bedarf neu berechnet werden. [Roblox: Pathfinding](https://create.roblox.com/docs/characters/pathfinding)

Unser Konzept braucht zusätzlich einen Timeout mit sichtbarem Status und sicherer Rückgabe reservierter Ware. Maschinenverschiebungen sind während laufender Arbeit zunächst gesperrt. Für den ersten Test reichen festgelegte Stellplätze und freie Gänge. Damit prüfen wir das gewünschte Spielgefühl, ohne vorher ein beliebig umbaubares Navigationssystem zu entwickeln.

## 5. Speichern, Rebirth und Fehlerverhalten

Roblox-DataStores werden serverseitig verwendet. Netzwerkaufrufe können scheitern; `UpdateAsync` verarbeitet konkurrierende Änderungen an einem Schlüssel, und dessen Callback darf nicht warten. Studio-Tests sollen getrennte Testdaten verwenden. [Roblox: Data stores](https://create.roblox.com/docs/cloud-services/data-stores)

**Vorgeschlagenes Speicherschema:** Schema-Version, Profilrevision, aktive Sitzung, Währung, Rebirth-Anzahl, Rezepte, dauerhafte Designs und Baupläne, Maschinen/Layout, Mitarbeiter sowie Materialmengen je Speicherort. Temporäre Pfade, sichtbare Bandpositionen und NPC-Animationen werden nicht gespeichert. Beim Laden werden laufende Transporte und Produktionen nach einer festgelegten, bestandsneutralen Regel in sichere Puffer überführt. Ein Versionswechsel benötigt eine explizite Migration.

`UpdateAsync` allein ist kein vollständiges Sitzungsmanagement. Eine Sitzungsreservierung samt Ablauf und Revisionsprüfung verhindert, dass ein alter Server einen neueren Profilstand überschreibt. Autosaves werden zusammengefasst; kein DataStore-Aufruf pro getragenem Brett. Bei fehlgeschlagenem Laden bleibt wirtschaftliches Spielen gesperrt, statt einen leeren Standardstand zurückzuschreiben. Bei Speicherproblemen wird der Zustand sichtbar als ungesichert markiert; Rebirth und weitere irreversible Käufe bleiben gesperrt.

Ein Rebirth ist eine Profiltransaktion: Voraussetzungen prüfen, neue Generation bilden, behaltene Inhalte und zurückgesetzte Inhalte gemeinsam schreiben, anschließend den neuen Weltzustand aktivieren. Bei unklarem Schreibausgang prüft eine Vorgangs-ID das Ergebnis, bevor erneut gebucht wird. Ein Prozessabsturz kann Fortschritt seit dem letzten bestätigten Save verlieren; vollständige Verlustfreiheit wird nicht versprochen. Robux-Käufe gehören erst nach geklärtem Shopumfang und gesondertem, idempotentem Kaufbelegsystem in die Produktion.

## 6. Mobile und messbare Freigaben

Roblox empfiehlt Tests auf einem tatsächlichen schwächeren Referenzgerät; der Studio-Geräteemulator ersetzt keine Speichermessung. Streaming kann Weltinhalte laden und entladen, weshalb lokale Modellreferenzen nicht dauerhaft vorausgesetzt werden dürfen. [Roblox: Performance](https://create.roblox.com/docs/performance-optimization/design), [Roblox: Streaming](https://create.roblox.com/docs/workspace/streaming)

**Kleinste technische Probe:** ein Plot, ein Hockerrezept, vollständige manuelle Kette, ein NPC-Transportauftrag, eine Bandverbindung, Kauf/Verkauf und Speichern. Keine Online-Wirtschaft, kein Handel und keine Offline-Produktion. Weltdekoration und sichtbare Produkte bleiben begrenzt und werden wiederverwendet.

**Geplante Gates, noch ohne Ergebnis:** (1) Doppelklicks und zwei gleichzeitige Träger erzeugen in reproduzierbaren Wiederholungstests weder Zusatzware noch doppelte Zahlungen. (2) Blockierter NPC, voller Ausgang und Verlassen während einer Übergabe erhalten den Bestand. (3) Getrennt getestete Ladefehler, Savefehler, Wiederbeitritt und Rebirth ergeben einen konsistenten Profilstand. (4) Auf dem erst festzulegenden echten Referenzgerät funktionieren Tragen, Ablage und Statusanzeigen ohne Maus. (5) Das Team legt aus Messungen eine zulässige Plot-, NPC- und Produktmenge fest. Bis dahin gibt es keine belastbare Kapazitäts- oder Performancezusage.

## 7. Gegenrede und finales Technikvotum

Ich unterstütze die gestufte Synthese nach Lektüre des Skeptikers einschließlich Gegenrede, des Spielerlebnisreviews und der Art Direction. Ein Hocker mit vollständiger Handkette, anschließend ein NPC-Träger und eine feste Bandverbindung prüfen die drei gewünschten Entwicklungsstufen ausreichend für eine erste technische Entscheidung. Ein zweites Rezept folgt erst nach diesem Basistest. Der wirtschaftliche Ablauf benötigt trotzdem von Beginn an Rohstoffkauf, Verkauf, sichere Wiederanlaufhilfe und einen konsistenten Speicherstand. Sonst prüfen wir eine Materialanimation statt eines Betriebs.

**Kleinster sicherer Umfang:** Ein Plot besitzt feste Stations- und Upgrade-Stellplätze sowie eindeutig definierte Transportanschlüsse. Hier wird der Besitz einer Maschine gespeichert; beliebiges Verschieben, Überlappungsprüfungen und nach jedem Umbau neu geplante Wege gehören später dazu. Ein leerer Upgrade-Stellplatz bietet bereits eine nachvollziehbare Kapazitätsentscheidung nach der Automatisierung. Die gleiche räumliche Vereinfachung hält mobile Bedienung, NPC-Wege und Art-Anschlüsse überschaubar. Die Außenprobe mit Wand, Fenster und Dachkante ist sinnvoll: Sie prüft das ursprüngliche Qualitätsproblem innerhalb derselben Muster-Szene und rechtfertigt keine zusätzliche Map.

Der Skeptiker fordert zu Recht nachvollziehbare Bestandsübergänge. Für Abbrüche schlage ich eine feste Regel vor: Eine noch nicht verbuchte Übergabe bleibt an der Quelle; eine bereits verbuchte Trägercharge landet im profilgebundenen Rückgabelager. Reservierungen werden gelöst, ohne neue Ware zu erzeugen. Ein voller Stationspuffer ändert diese Regel nicht. Beim Wiederbeitritt wird ein gespeicherter Transport nach derselben Regel aufgelöst; Eingabe und Ergebnis eines Produktionsauftrags dürfen dabei niemals gleichzeitig gutgeschrieben werden.

Das schützt die Regeln, bietet aber keine absolute Verlustfreiheit bei einem Serverabsturz. Der letzte bestätigte Save ist die Wiederherstellungsgrenze. Bei unbestätigten Schreibvorgängen muss der nächste Server den Profilstand und die Vorgangs-ID prüfen; bloßes Wiederholen einer Auszahlung ist unzulässig. Auch eine Wiederanlaufhilfe benötigt serverseitige Berechtigungsprüfung, damit aus wiederholtem Abholen und Verkaufen kein Geldgenerator entsteht.

Rebirth bleibt eine spätere Funktion. Anfangs genügen versioniertes Profil, getrennte dauerhafte und laufende Fortschrittsdaten sowie eine Generationskennung; ein ungenutztes vollständiges Reset-System wird nicht gebaut. Robux-Käufe bleiben außerhalb des Prototyps.

**Finales Votum:** Go für diesen gestuften Kernnachweis. **Technisches Veto:** Keine zusätzliche Produktfamilie oder Echtgeldwirtschaft, solange reproduzierbare Doppelübergaben, gleichzeitige Sessions oder Ladefehler Material beziehungsweise Währung duplizieren oder einen vorhandenen Speicherstand mit Standardwerten überschreiben können. Das sind geplante Tests und keine bereits erzielten Ergebnisse.
