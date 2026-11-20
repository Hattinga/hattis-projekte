# Materialbestand, Verkäufe und Speicherung

[Kernkonzept](../design/CORE.md) · [Handbetrieb](../plan/01-handbetrieb.md) · [Automatisierung](../plan/02-automatisierung.md) · [Prüfmatrix](../qa/TESTS.md)

## Zuständigkeit und Daten

Der Server führt den verbindlichen Bestand einer Werkstatt. Spieler, Mitarbeiter und Förderband bewegen dieselben Chargen über gemeinsame Umbuchungen. Der Client fordert Handlungen an und zeigt den bestätigten Zustand an. Modelle, Animationen und Berührungen dienen der Darstellung und Eingabe.

### Implementierter Datenvertrag P04-01 / P04-03

Quelle: [src/server/State.luau](../../src/server/State.luau), im Test-Place `ServerScriptService.Factory.State`. [35 Prüfungen](../../tools/studio/test-p04-01-state.luau) sind in Edit und Server-Play bestanden, siehe [Beleg](../evidence/P04-01.md). Das Modul startet nichts selbst, erzeugt keine Spielerprofile und liest oder schreibt keine DataStores. Ein aktives wirtschaftliches Profil darf erst über P04-04 bis P04-06 entstehen; das echte schwächere Testgerät P00-03 bleibt offen.

Seit [P04-03](../evidence/P04-03.md) gilt **Schema 2**, ohne produktive Migration: Es gibt weiterhin keine freigegebenen Spielerprofile. Die ursprünglichen 35 State-Prüfungen und die 36 Übergabeprüfungen bestehen in Edit und Server-Play, gespeichert als Place-Version 31.

| Record | Verbindliche Felder im aktuellen Schema 2 |
| --- | --- |
| Profil | `schemaVersion`, `ownerUserId`, `revision`, `money`, `locations`, `batches`, `claims`, `reservations`, `receipts`; optional `pendingSale` ([P07](#verkauf-p07)) |
| Warenort | `id`, `kind`, `capacity=1`, `acceptedStages` |
| Charge | `id`, `ownerUserId`, `recipeId=Hocker01`, `recipeVersion=1`, `stage`, `quantity=1`, `locationId` |

`batches[batchId].locationId` ist die **einzige Ortszuordnung**. Warenorte enthalten keine zweite Chargenliste; `countAt` zählt dieselben Chargen für alle Akteure. Alle Platz-IDs gelten innerhalb des Eigentümerprofils. Jede Charge wiederholt den Eigentümer und muss mit dem Profil übereinstimmen; Dictionary-Schlüssel und `id` müssen gleich sein. IDs werden vom späteren Serverablauf vergeben und bei Stufenwechseln erhalten. Der Konstruktor nimmt bereits vergebene IDs entgegen und erzeugt beim Prüfen oder JSON-Rücklesen keine neuen.

Ein Warenort ist ein **physischer Einzelplatz**, keine ganze Lagerzone: vier Rohstoffplätze werden als vier IDs mit Kapazität 1 geführt, zwei Anhängerplätze als zwei IDs. Gleiches gilt für jeden Stations-Eingang, Arbeitsbereich und Ausgang. Ortsarten: `Supplier`, `RawStore`, `FinishedStore`, `Carrier`, `StationInput`, `StationProcess`, `StationOutput`, `Machine`, `VehicleSlot`, `Band`, `Recovery`. Konkrete Platzregistrierung und Stufenzuordnung richten sich nach [PRODUCTION](../design/PRODUCTION.md) und [LOGISTICS](../design/LOGISTICS.md); sie dürfen keine zusätzlichen unsichtbaren Lagerplätze schaffen.

Geld und Revision sind endliche, nichtnegative Ganzzahlen bis `2^53−1`, Eigentümer-IDs positive Ganzzahlen. Die fünf Stufen heißen `Holzpaket`, `Bausatz`, `Rohhocker`, `Fertig`, `Karton`. Die neun Holzteile sind Inhalt einer Charge mit Menge 1. Recordfelder sind geschlossen; Metatables, Zusatzfelder, zyklische Erweiterungen, ungültige UTF-8-IDs und unzulässige Stufenlisten werden abgewiesen. Daten bleiben ohne Instances, Funktionen oder Vektortypen JSON-tauglich.

Reservierungen und Belege sind in P04-03 ergänzt; die Rezeptwahl lebt seit P04-04 im getrennt versionierten Profilumschlag. Sitzungsbesitz und weitere Werkstattfortschritte folgen in ihren Schritten. Der aktuelle Konstruktor ist ein **leeres Schema-Muster mit Geld 0**, kein freigegebener Profilstart und kein Ersatz für bestätigtes Laden. `validate` prüft Dateninvarianten einschließlich historischer Belegbeziehungen; Actions prüft Berechtigungen, Transfers veröffentlicht atomare Änderungen.

| Zustand | Benötigte Angaben |
| --- | --- |
| Profil | Eigentümer, Schemaversion, Revision, aktive Sitzung und bestätigter Geldstand |
| Fortschritt | Laufende Werkstatt mit Ausrüstung und Rezeptwahl. Dauerhafte Freischaltungen separat erfassen, sobald sie benötigt werden. |
| Charge | Stabile ID, Eigentümer, Material oder Möbelmodell, Menge, Verarbeitungsstufe und genau ein logischer Ort |
| Station | Fester Stellplatz, Rezept, Eingangs- und Ausgangspuffer, laufender Maschinenlauf und reservierter Ausgang |
| Transport | Träger oder Verbindung, Quell- und Zielplatz, betroffene Charge, Reservierungsstatus und Ablaufzeit |
| Fahrzeugladung | Fahrzeug-ID, Ladeplatz, zulässige Größe und Kapazität. Die Ladung wird befestigt dargestellt. |
| Wirtschaftsvorgang | ID, betroffene Chargen und Mengen, Kauf- oder Verkaufskanal, Betrag und verbindlicher Abschlussstatus |

Mögliche Warenorte sind Lieferantenabholplatz, Werkstattlager, Träger, Stationspuffer, laufender Maschinenlauf, Fertigwarenlager, Fahrzeugladeplatz und Bandabschnitt. Wiederherstellbare Ware kann an einem eindeutig ausgewiesenen physischen Abholpunkt liegen. Beim Aufteilen einer Charge bleibt die Gesamtmenge erhalten. Maschinenläufe ändern Materialart und Menge ausschließlich gemäß Rezept.

## Gemeinsame Übergaben

### Implementiertes Profil-Laden P04-04

[Profiles.luau](../../src/server/Profiles.luau), serverseitig unter `ServerScriptService.Factory.Profiles`, trennt Leseerfolg, bestätigtes Fehlen und ungültige Daten. [24 Ladefälle](../../tools/studio/test-p04-04-profiles.luau) je Edit/Server bestanden; [Beleg und Grenzen](../evidence/P04-04.md). Der Loader startet nichts, verwendet keinen DataStore selbst und verändert keinen aktiven Store.

Der geschlossene Speicherumschlag besitzt **`profileVersion=1`**, `state` im unveränderten Schema 2 und `progress={version=1, selectedRecipeId=Hocker01, selectedRecipeVersion=1}`. Dies ist von der State-Schemaversion getrennt. Laufende Übergaben einschließlich aller Belege bleiben in State erhalten. Künftige Ausrüstung, Maschinenläufe oder weitere Rezepte benötigen eine explizite Erweiterung/Migration.

`load(ownerUserId, readProfile, initialize?)` prüft den Eigentümer vor dem stabilen Dezimalkey `Player_<ID>` und ruft den vertrauenswürdigen Reader genau einmal auf. Der Reader liefert einen Rohwert, bei bestätigtem Fehlen `nil`, bei Fehler eine Exception. Nur erfolgreiches `nil` erlaubt den optionalen Initializer einmalig; ohne ihn entsteht das leere nichtwirtschaftliche Schema mit Geld 0. Vorhandene falsche/beschädigte/fremde/unbekannte Daten erhalten niemals Ersatzstartdaten. Rückgabecodes `LOADED`/`INITIALIZED` bestätigen nur diese lokale Entscheidung, keinen Save.

Jedes Resultat hat **`ready=false`**. Ein Erfolg liefert eine abgetrennte `data`-Kopie mit `origin=Existing` oder `Absent`. Reader/Initializer dürfen yielden; das Modul besitzt keine globale Profilregistry und veröffentlicht keine Daten in einer aktiven Sitzung. P04-05 muss den Besitzer vor einer solchen Veröffentlichung erneut prüfen. Ein echter Adapter muss Frische/Cacheverhalten und Fehler-als-Exception zusichern; atomare erstmalige Erzeugung, reales Laden und Speichern sind noch nicht geprüft.

### Implementierter Sitzungsbesitz P04-05

[Sessions.luau](../../src/server/Sessions.luau), im Test-Place `ServerScriptService.Factory.Sessions`, ergänzt reine atomare Transformationen und eine lokale Veröffentlichungssperre. [41 Fälle](../../tools/tests/p04-05-sessions.luau) lokal sowie je Studio Edit/Server bestanden, zusätzlich je 130 Regressionen; [Beleg](../evidence/P04-05.md). Version 36 gespeichert. Kein Backend-Adapter, keine automatische Spieleranbindung und weiterhin **`ready=false`**.

Der geschlossene äußere Umschlag lautet `{sessionVersion=1, revision, sessionId, expiresAt, data}`. `data` bleibt der unveränderte Profiles-v1-Umschlag mit State2. `revision` ist die getrennte **Speicherrevision**; sie steigt bei Erwerb, Schreiben/Erneuern und Freigabe. Frei bedeutet exakt `sessionId="", expiresAt=0`; die Speicherrevision wird nicht zurückgesetzt. Zeitangaben sind sichere ganzzahlige UTC-Sekunden; Sitzungskennungen kommen eindeutig vom Server.

| API | Vertrag |
| --- | --- |
| `acquire(current, owner, expectedRevision, token, now, ttl, seed?)` | Aktuellen atomaren Wert prüfen; nur freie oder abgelaufene Sitzung übernehmen. `seed` ausschließlich bei `current=nil` und erwarteter Revision 0 verwenden; kein eigener Initializer/Fallback. Vorhandene Daten aus `current` erhalten. |
| `write(current, owner, expectedRevision, token, now, ttl, candidate)` | Eigentümer, Speicherrevision und noch gültigen Besitz gemeinsam prüfen. Geänderter Profilinhalt verlangt höhere State-Revision; identische Daten dürfen die Lease erneuern. Ablaufzeit wird dabei nicht verkürzt. |
| `release(current, owner, expectedRevision, token, now)` | Dieselben Besitzprüfungen; Besitz löschen, Speicherrevision erhöhen, aktuelles Profil unverändert erhalten. Nimmt keine neue Datenkopie entgegen. |
| `newGate(owner)` → `begin(token)`, `publish(ticket, saved, now)`, `close(ticket)`, `snapshot(now)` | Privater Versuchsschlüssel schützt nach Yields vor alten Veröffentlichungen. Nur gleiche aktuelle Sitzung und steigende Speicherrevision übernehmen; private Daten und Ausgaben sind abgetrennt. Ein neuer Versuch/Schließen entwertet alte Antworten. |

Transformationen laufen **im** nicht yieldenden atomaren Backend-Callback; Ablehnung bricht dort durch `nil` ab. Kein vorheriges Check mit anschließendem `SetAsync`. `now` muss bei **jedem** Callback/Retry frisch nach einem Backend-Yield bestimmt werden. Eine erzeugte Record-Kopie bedeutet noch keine Speicherung. P04-06 muss echte Bestätigung/Unklarheit behandeln und ausschließlich bestätigte Antworten an das Gate weitergeben. Lease-Dauer, Erneuerungstakt und Uhrabweichungen sind vor echten Profilen festzulegen.

State-/Profiles-Schemata und der geschlossene Transfers-Store `{profile=...}` bleiben erhalten; Sessions-Metadaten gehören in eine äußere Grenze. Ein abgelöster Store darf weder erneut veröffentlicht noch dauerhaft gespeichert werden, auch nicht nach `expireClaims`. Hier gibt es noch keinen aktiven Store oder `ready=true`. Nackte frühere Profilumschläge werden nicht implizit migriert. Wirtschaft bleibt bis zur gesamten P04-Abnahme gesperrt.

### Speicheradapter P04-06

[Persistence.luau](../../src/server/Persistence.luau) liegt unter `ServerScriptService.Factory.Persistence`. Auf Version 38 wurden zusätzlich zu den lokalen und Studio-Suiten sieben echte DataStore-Prüfungen bestanden. [Beleg](../evidence/P04-06.md)

`dataStore(store)` bindet ausschließlich den vom vertrauenswürdigen Server ausgewählten Store. Lesen verwendet immer ein neues `DataStoreGetOptions.UseCache=false`; UpdateAsync erhält UserIds/Metadaten und bricht bei `nil` ab. `new(owner, backend, clock?)` besitzt privat den letzten bestätigten Sessions1-Record. API: `load(token, ttl, initializer?)`, `save(candidateEnvelope, ttl)`, `release()`, `reconcile()`, `snapshot()`.

Eine Steuerung bearbeitet höchstens einen laufenden Zugriff. Vor Yields steht `inFlight=true`; konkurrierende Aufrufe erhalten `BUSY`. Erst eine vollständige validierte Backend-Antwort, die exakt dem eingereichten Transformresultat entspricht, wird bestätigt. Der Kandidat ist vor dem Backend-Aufruf kopiert, und jede Callback-Wiederholung prüft den aktuellen Wert mit frischer UTC-Zeit. Reader-Fehler erlauben keinen Initializer. Der letzte bestätigte Stand ist unabhängig von Vorschlag, Backend-Alias und Ausgabekopie.

Exception, fehlender Callback oder unpassende Antwort setzen den Zustand `Unknown`: kein weiterer Load/Save/Release und kein automatischer Retry. `reconcile` bestätigt ausschließlich das exakte vorgeschlagene Resultat durch frisches Rücklesen. Ein unveränderter oder anderer Stand beweist nicht, dass ein verspäteter Schreibzugriff ausgeschlossen ist, und lässt den Ausgang offen. Die Steuerungszustände `Empty`/`Confirmed`/`Released`/`Unknown` setzen niemals `ready=true`.

### Implementierte Aktionsprüfung P04-02

[Actions.luau](../../src/server/Actions.luau), im Place `ServerScriptService.Factory.Actions`, prüft Übergaben **ohne Mutation**. [35 Fälle](../../tools/studio/test-p04-02-actions.luau) je Edit und Server bestehen; [Beleg](../evidence/P04-02.md). API: `checkTransfer(profile, actor, request)` liefert `ok`, stabilen Fehlercode und deutsche Rückmeldung.

Der **Server** erzeugt `actor` mit `ownerUserId`, `kind` (`Player`, `Worker`, `Band`), `carrierLocationId` und `ready`. Insbesondere `ready=true` darf erst aus bestätigt geladenem, freigegebenem Sitzungszustand kommen; künstliche Tests setzen es nur für ihre Fixtures. Ein Client darf diesen Kontext nicht liefern. Der Request enthält ausschließlich `operationId`, `expectedRevision`, `batchId`, `sourceId`, `targetId`, `quantity=1`; zusätzliche Felder werden abgewiesen.

Die Prüfung verwirft fehlende Freigabe, fremden Eigentümer, ungültigen Profilzustand, ungültige Mengen/IDs/Revisionen, unbekannte Charge oder Orte, geänderte Quelle, falschen Träger, falsche Warenstufe und ein volles Ziel. Eine Übergabe muss den zugeordneten Träger als Quelle oder Ziel verwenden; Rohstofflager → Station oder Rohstofflager → Fahrzeug direkt ist unzulässig. Ein fremder Hand-/Bandträger bleibt auch innerhalb desselben Eigentümerprofils gesperrt. Mitarbeiter und Band verwenden denselben Bestandsvertrag. Fahrzeugplätze nehmen ausschließlich Holzpaket oder Karton an, Rohstoff-/Lieferantenplätze nur Holz, Fertiglager nur Karton.

Diese Funktion ist **keine Freigabe einer realen Weltaktion**: physische Nähe/Zonen, Maschinenzustand und feste Bandverbindungen müssen die späteren Serverhandler aus der tatsächlichen Szene prüfen. Remotes und echte Profilfreigabe fehlen weiterhin. P04-03 ergänzt die gemeinsame Claim-/Zusageprüfung; Transfers wertet vorhandene Belege vor einer erneuten Revisionsprüfung aus.

### Implementierte Umbuchung P04-03

[Transfers.luau](../../src/server/Transfers.luau), im Place `ServerScriptService.Factory.Transfers`, bearbeitet ausschließlich künstlichen Serverzustand. [36 Fälle mit 211 Aufrufen](../../tools/studio/test-p04-03-transfers.luau) je Edit/Server bestanden; [Beleg](../evidence/P04-03.md). Alle Akteure verwenden denselben `store = {profile = ...}` und lesen nach einem Übergang die aktuelle Profilreferenz. Ein Kandidat kopiert das kleine Profil vollständig, wird validiert und durch genau einen Referenzwechsel veröffentlicht. Keine Yields oder externen Aufrufe innerhalb dieses Übergangs; alte/frozen Profile werden nicht verändert, ein gefrorener Store wird abgewiesen.

| API | Request und Ergebnis |
| --- | --- |
| `new(profile)` | Validiert/kopiert ein künstliches Profil in einen gemeinsamen Store; kein automatischer Spielerstart. |
| `reserve(store, actor, request, now, ttlSeconds)` | Request wie bei Actions; Quelle und Ziel sperren, Ware bleibt an der Quelle. `RESERVED` mit `claimId = operationId`, `expiresAt`, neuer Revision. |
| `commit(store, actor, request, now)` | Request ausschließlich `operationId`, `expectedRevision`, `claimId`. Claim erneut prüfen; genau eine Charge umbuchen, Claim verbrauchen, Zusagen/Beleg/Revision gemeinsam ändern. |
| `cancel(store, actor, request, now)` | Derselbe Request-Typ mit eigener Vorgangs-ID; nur unverbuchten aktiven Claim löschen, keine Warenbewegung. |
| `expireClaims(store, now)` | `EXPIRED` mit Anzahl `expired`; nur abgelaufene Claims entfernen. Bei mindestens einer Löschung Revision einmal erhöhen, sonst nichts ändern. |

`actor` enthält zusätzlich eine stabile, vom Server gesetzte `actorId`, etwa `Player/101` oder `Worker/one`. Eigentümer, Identität, Art und zugeordneter Träger binden Claim und Beleg. `now` und `ttlSeconds` sind vertrauenswürdige endliche Serverwerte, niemals Clientangaben; `now >= expiresAt` gilt als abgelaufen. Der Zeitursprung über Sitzungen bleibt vor Persistenz festzulegen.

| Map in Schema 2 | Geschlossener Record und Invariante |
| --- | --- |
| `claims[claimId]` | `id`, `actorId`, `actorKind`, `carrierId`, `batchId`, `sourceId`, `targetId`, `quantity=1`, `expiresAt`. Die Charge liegt weiterhin an der Quelle; beide Plätze sind gegen überlappende Claims gesperrt. Passender Reserve-Beleg ist erforderlich. |
| `reservations[originId]`: Return | `kind=Return`, `batchId`, `actorId`, `actorKind`, `carrierId`, `recipeId`, `recipeVersion`, `stage`, `quantity=1`. Ursprung leer, Charge am gebundenen Träger, Warenangaben unverändert. Pro Charge höchstens ein Return. |
| `reservations[rawSlotId]`: Delivery | `kind=Delivery`, `batchId`, `purchaseOperationId`. Garantierter leerer Rohstoffplatz für dieselbe Holzcharge, die nur beim Lieferanten, auf einem Träger oder im Fahrzeug liegt. In P04-03 ausschließlich künstliche Kaufidentität; echte Kaufbeleg-/Geldbindung folgt mit der Kaufaktion. |
| `receipts[operationId]` | `actorId`, `actorKind`, `ownerUserId`, `carrierId`, `action` (`Reserve`, `Commit`, `Cancel`), exakter kopierter `request`, ursprüngliches kopiertes `result`. Ein Abschluss verweist auf genau einen passenden früheren Reserve-Beleg; Actor/Hop/Reihenfolge müssen stimmen. Höchstens ein Abschluss je Claim; abgeschlossene Claims dürfen nicht wieder aktiv erscheinen. |

Pickup erstellt Return am jetzt leeren Ursprung. Normale Ablage entfernt diesen Return; physische Rückgabe ersetzt ihn durch dieselbe Charge. Stationsausgänge akzeptieren ausschließlich diese exakte Rückgabe. Ein Abbruch/Ablauf eines späteren Ablage-Claims erhält getragene Ware und Return. Delivery bleibt über Lieferant → Hand → Fahrzeug → Hand bestehen und wird erst durch Entladung genau auf den garantierten Rohstoffplatz verbraucht. Andere Charge oder anderer Rohstoffplatz ist unzulässig.

`Actions.checkTransfer(profile, actor, request, now?, ownClaimId?)` prüft diese Sperren auch direkt schreibfrei. Ohne `now` gelten alle noch eingetragenen Claims vorsorglich als aktiv. Ein Commit darf ausschließlich seinen eigenen in Identität und vollständigem Hop passenden Claim ignorieren; ein fremder Claim oder ein bloßer allgemeiner Freigabeschalter umgeht keine Sperre. Transfers verwendet genau diesen gemeinsamen Prüfeinstieg.

Identischer Replay liefert den historischen Beleg **vor** Revision, aktuellem Warenort oder Claim-Ablauf und erzeugt keinen neuen Claim. Dieselbe ID mit verändertem Request einschließlich `expectedRevision` oder anderem Actor ergibt `OPERATION_CONFLICT`. Ein fehlgeschlagener Versuch verändert nichts. Historische Belege werden noch nicht gelöscht; Aufbewahrung/Größenbegrenzung und Schema-Migration gehören vor echten Profilen zur Persistenzarbeit. `COMMITTED` bestätigt hier nur Serverzustand, keinen dauerhaften Save. Reservierte Maschinenausgänge erhalten ihren eigenen Record erst mit dem Maschinenlauf.

### Spielgeldkauf P05-02

[Purchases.buy](../../src/server/Purchases.luau) erhält einen autorisierten Serverakteur, die Vorgangs-ID, erwartete Bestandsrevision und die registrierten Auflagen. Alte Claims zählen bis zur Bereinigung vorsorglich als belegt. Geldabzug, neue Charge am Lieferanten, Delivery am Rohstoffplatz sowie der `Purchase`-Beleg werden als ein Kandidat gespeichert. Der Beleg teilt den Vorgangs-ID-Raum mit den bisherigen Transferbelegen. Der Testpreis beträgt 60. Künftige Preisänderungen ändern historische Belege nicht.

Eine neue Kaufzusage muss zum gespeicherten Beleg, zur selben Charge und zum selben Rohstoffplatz passen. Nach Verbrauch der Zusage bleibt der spätere Commit an genau diesen Platz als Nachweis erhalten. Ältere künstliche P04-Zusagen ohne Kaufbeleg bleiben lesbar. Die neue Belegvariante erweitert das bisherige Schema 2 vor dem ersten produktiven Profil. Ältere Validatoren weisen neue Kaufbelege ab. Ein Rückwechsel auf älteren Code mit bereits gespeicherten Käufen benötigt vor einem produktiven Einsatz eine eigene Versionsstrategie. [Prüfbeleg](../evidence/P05-02.md)

Der Server prüft Akteur, Berechtigung, erwarteten Ausgangszustand, gültige Menge, passenden Ort und Zielkapazität. Der Vorgang reserviert die Quelle und bei Bedarf den Zielplatz. Die Umbuchung entfernt Ware von der Quelle und weist sie im selben Änderungsschritt dem Ziel zu. Animation und Wegsuche laufen außerhalb dieses Schritts. Wiederholungen mit derselben Vorgangs-ID und denselben Eingaben geben das vorhandene Ergebnis zurück. Reservierungen laufen kontrolliert ab oder werden bei Abbruch freigegeben.

Beim Einkauf werden Spielgeld und neu bereitgestellte Ware gemeinsam verbucht. Die Charge entsteht am Lieferantenabholplatz. Eine Station reserviert vor dem Materialverbrauch Platz für ihr Ergebnis. Ein volles Fertigwarenlager erzeugt sichtbaren Rückstau bis zu den Stationen. Ein interner Fertigungsjob steht für einen Maschinenlauf, während der Spieler auf Bestand produziert und erst danach einen Abnehmer wählt.

## Fahrzeuge und Verkäufe

Ein- und Ausladen prüfen Eigentümer, Ladezone, Kapazität des Zielorts und die physisch erreichbare Übergabestelle. Für Lieferungen prüft der Server, ob der beobachtete Fahrtverlauf plausibel ist und die Ware am passenden Ziel entladen wird. Ein behaupteter Standort, eine Berührung oder eine Clientmeldung allein ist für die Auszahlung unzureichend. Normale Beschaffungs- und Verkaufswege erfolgen als Fahrten.

Der [Fahrtnachweis](../../src/server/Trips.luau) beginnt für einen bestätigten Karton am Werkstatthof. Der Server simuliert das Fahrzeug und beobachtet seine Bewegung bis zur Käuferzone. Nach mindestens 0,5 s Stillstand mit beiden Ladepunkten in der Zone kann der Server die Ankunft für Eigentümer, Fahrzeug, Ladeplatz, Charge und Käufer lesen. Bei Positionssprüngen, Beobachtungslücken oder geänderter Ladung verfällt der betreffende Nachweis. Die Abfrage prüft die aktuelle Zone und den bestätigten Bestand erneut.

| Kanal | Preisbildung und Abschluss |
| --- | --- |
| Möbelhändler | Der Server berechnet den bekannten Modellpreis für die bestätigte Stückzahl. |
| Privatkunde | Die mögliche Erlösspanne und der Händlervergleich sind vor der bindenden Wahl sichtbar. Der Server legt das Zufallsergebnis nach Bestätigung einmal für die Verkaufs-ID fest. |

Eine verbindliche Verkaufs-ID referenziert die reservierte Ware und den festgelegten Preis. Schreibwiederholungen und Wiederbeitritt verwenden denselben gespeicherten Betrag. Das endgültige Ergebnis wird erst nach bestätigter Speicherung gezeigt. Warenabgang, Geldgutschrift und Abschlussstatus gehören in dieselbe geprüfte Änderung desselben Spielerprofils. Bei unklarem Schreibausgang wird der gespeicherte Vorgang vor einem erneuten Versuch geprüft. Ein bereits abgeschlossener Verkauf liefert den vorhandenen Beleg. Die Transaktion ist auf ein Spielerprofil begrenzt.

### Verkauf P07

[Sales.luau](../../src/server/Sales.luau) verkauft genau einen Karton je Vorgang und ändert Bestand und Geld ausschließlich über bestätigte Saves des Eigentümerprofils. Die Weltanbindung besteht bisher nur im Studio-Demo [start-p05-09-line-demo.luau](../../tools/studio/start-p05-09-line-demo.luau). [12 lokale Fälle](../../tools/tests/p07-sales.luau) laufen über [run-p07.mjs](../../tools/tests/run-p07.mjs) mit speicherinternem atomarem Backend.

[State](../../src/server/State.luau) führt höchstens einen offenen Verkauf im optionalen Profilfeld `pendingSale`: `id`, `buyer` (`Dealer`, `Private`), `vehicleId`, `slotId`, `batchId`, `carrierId`, `quoteMin`, `quoteMax`, `dealerValue` und verborgener `seed`. Der Validator verlangt einen Karton an der Spielerhand mit exaktem Return an `slotId`, einen Platz mit Präfix `Vehicle.<vehicleId>.`, `seed` von 0 bis `MAX_SALE_SEED=16777215` und noch keinen Beleg unter derselben ID. Beim Händler gilt `quoteMin = quoteMax = dealerValue`.

Der Abschluss schreibt `receipts[saleId]` mit `action=Sale`, Request `{operationId, expectedRevision}` und `SaleResult` (`revision`, Käufer, Fahrzeug, Platz, Charge, `quantity=1`, `amount`, Spanne, Händlerwert). `amount` liegt in der Spanne, die Charge fehlt danach im Bestand. Je Charge ist höchstens ein Sale-Beleg zulässig, sonst `DUPLICATE_SALE`. Purchase-, Reserve- und Commit-Belege verkaufter Chargen bleiben gültige Historie. Verkaufs-IDs haben höchstens 88 Bytes (`MAX_SALE_ID_LENGTH`), damit abgeleitete Umbuchungs-IDs wie `<saleId>/cancel/reserve` die ID-Grenze von 128 einhalten. Wie der Kaufbeleg erweitert dies Schema 2 ohne Versionswechsel; ältere Validatoren weisen beides ab.

| API | Vertrag |
| --- | --- |
| `open(controller, actor, request, arrival, now, lease, seedOverride?)` | Request genau `id`, `buyer`, `vehicleId`, `slotId`, `batchId`. `arrival` muss in Eigentümer, Fahrzeug, Platz, Charge und Käufer übereinstimmen. Reserve und Commit bringen den Karton vom Anhängerplatz in die Hand; Spanne, Händlerwert und Seed werden mitgespeichert. `OPEN` mit Angebot ohne Seed und Betrag. |
| `cancel(controller, actor, saleId, now, lease)` | Vor der Bindung: Karton über Reserve und Commit zurück auf seinen eigenen Platz, keine Zahlung. `CANCELLED`; eine Wiederholung erkennt den Beleg `<saleId>/cancel/commit`. |
| `settle(controller, actor, saleId, lease)` | Bindende Übergabe in einer Profiländerung: Charge und Return entfernen, `amount` gutschreiben, Sale-Beleg speichern, Revision +1. `SOLD` mit Beleg erst nach bestätigtem Save. Claims auf Charge, Platz oder Hand ergeben `SALE_TRANSFER_PENDING`. |
| `resume(controller, actor, saleId?)` | Klärt einen unklaren Schreibausgang zuerst über `reconcile`, meldet dann `SOLD` mit Beleg, `OPEN` mit Angebot oder `NONE`. |

Alle Aufrufe liefern `{ok, code, message, unknown, offer?, receipt?}`. `Sales.PRICES` enthält für `Hocker01` den Händlerwert 100 und die Privatspanne 80–120. `seedOverride` ist ausschließlich ein Server-Testeingang, nie ein Spielerwert.

Ablauf: Öffnen → Tragen → Bestätigen oder Abbrechen. Im Käuferhof öffnet E am Anhängerplatz den Verkauf. Der Spieler trägt den Karton zur Annahme und bestätigt dort mit gehaltenem E. Legt er ihn auf seinen eigenen Anhängerplatz zurück, bricht der Verkauf ab; andere Plätze lehnt die Weltanbindung ab. Solange `pendingSale` besteht, verlässt der Karton die Hand nur über `cancel` oder `settle`; eine gewöhnliche Umbuchung scheitert an der Validierung. Die Hand hat Kapazität 1, daher gilt ein Karton je Verkauf. Ein zweiter Verkauf ergibt `SALE_BUSY`.

Der private Zufallswert gehört zu Karton und Käufer: `Sales.seedFor(batchId, buyer)` leitet ihn per FNV-1a aus einem serverseitigen Schlüssel ab, `open` speichert ihn verborgen. Abbrechen und erneutes Öffnen, Wiederbeitritt oder eine neue Anlieferung desselben Kartons zum selben Käufer ergeben deshalb immer denselben Betrag. `settle` berechnet `amount = quoteMin + seed % (quoteMax − quoteMin + 1)`; beim Händler ergibt das 100. Weil der Wert vor der Bindung feststeht, liefern Wiederholungen, unklare Writes und Wiederbeitritt denselben Betrag; kein Versuch würfelt neu. Der Spieler sieht vor der Bindung nur Spanne und Händlerwert, den Betrag erst nach bestätigtem Abschluss.

Ein vorhandener Sale-Beleg beantwortet `open`, `cancel` und `settle` vor jeder Bestandsprüfung mit `SOLD`. Anderer Akteur oder andere Angaben unter derselben ID ergeben `OPERATION_CONFLICT`, auch ein nachträglicher Wechsel zum Händler. `open` mit der offenen ID liefert dasselbe Angebot ohne Schreibzugriff. Nach unklarem Save antworten `open`, `cancel` und `settle` mit `NOT_CONFIRMED`, bis `resume` den Stand geklärt hat; gutgeschrieben wird genau einmal.

Das Modul prüft bereiten Spielerakteur mit eigenem bestätigtem Sitzungsbesitz, geschlossenen Request, Serverzeit, den übergebenen Ankunftsnachweis, Karton mit Menge 1 auf dem Platz dieses Fahrzeugs, Preis sowie Revisions- und Geldüberlauf. Die Weltanbindung prüft vorher beide Ladepunkte in der Käuferzone, freie Hand, Reichweite zum bewegten Ladeplatz und `Trips.arrival` für genau diesen Platz. Beim Abbruch prüft sie Eigentümer und Stillstand des Gespanns sowie die Reichweite zum eigenen Platz, nach einem Gespannersatz alternativ zu dessen Bergungsauflage. Beim Abschluss prüft sie den richtigen Käufer, die Reichweite zur Annahme und eine Abholung in derselben Live-Sitzung (`openedHere`).

[Trips](../../src/server/Trips.luau) behält bei offenem Verkauf die Fahrtspur des Platzes, setzt Stillstand und Ankunft aber zurück. Nach einem Abbruch liegt der Karton mit derselben Fahrt wieder auf dem Platz. Er gilt erst nach erneutem Stillstand in der aktuellen Zone wieder als angekommen. Die Demo beobachtet die Fahrt in einem eigenen 0,25-s-Takt, der auch während laufender Speicherungen weiterläuft. Sonst hätte eine langsame DataStore-Antwort von über 1 s alle Fahrtspuren verworfen. Nur ein unklarer Schreibausgang setzt die Beobachtung zurück. Diesen klärt der Takt alle 2 s über `Sales.resume`.

Bekannte Grenze: `openedHere` lebt nur im Speicher der Live-Sitzung. Nach Wiederbeitritt bleibt der offene Verkauf mit Karton in der Hand im Profil erhalten, die Weltanbindung verweigert den Abschluss aber mit `PICKUP_REQUIRED`. Der Karton muss zurück auf seinen Anhängerplatz und erneut angeliefert werden. Ein vor dem Wiederbeitritt geöffneter Verkauf ist daher ohne neue Lieferung nicht abschließbar. Der Preis ändert sich dabei nicht. In Studio mit DataStore-Scope über einen Serverwechsel geprüft ([P07-Beleg](../evidence/P07.md)).

Die lokalen Fälle decken ab: keine Reservierung oder Zahlung ohne passende Ankunft, für fremde oder nicht bereite Akteure, für Holz oder bei Zusatzfeldern; Öffnen mit Return und Händlerwert ohne offengelegten Seed; Replay und `SALE_BUSY`; Abbruch ohne Zahlung mit wieder verkaufbarem Karton; Händlerabschluss mit 100 genau einmal; erzwungene Privatwerte 80 und 120 ohne Neuwurf oder Käuferwechsel; unklaren Abschluss mit Klärung über `resume`; Fortsetzung in neuer Sitzung mit gleichem Seed; gesperrte Umbuchung aus der Hand und `SALE_TRANSFER_PENDING`; gültige Kauf- und Transferhistorie verkaufter Chargen; Abweisung beschädigter Verkaufsrecords; derselbe Zufallswert nach Abbruch, neuer Sitzung und erneuter Anlieferung sowie Streuung über die ganze Spanne.

### Materialvorschuss P07-07

[`Purchases.advance`](../../src/server/Purchases.luau) nutzt dieselben bestätigten Lieferanten- und Rohstoffplätze wie der Kauf. Ein bereiter Spieler mit eigenem bestätigtem Profil braucht Guthaben unter dem Materialpreis, einen leeren Bestand und weder einen offenen Verkauf noch einen offenen Vorschuss. Der Server speichert Holzpaket, Delivery-Zusage, `Advance`-Beleg und `state.advance` gemeinsam. Das Guthaben ändert sich dabei nicht. Dieselbe Vorgangs-ID liefert denselben Beleg, eine zweite ID wird bei offenem Vorschuss abgewiesen. Ein unklarer Save sperrt weitere Anforderungen bis zur Klärung.

Beim Verkauf derselben Charge hält der Server zunächst den Fehlbetrag für den nächsten Einkauf zurück. Der verbleibende Erlös tilgt bis zum gespeicherten Materialwert. `Sales.settle` speichert die Nettogutschrift, den Warenabgang, den geschlossenen Vorschuss und den Verkaufsbeleg gemeinsam. `amount` enthält den Bruttoerlös. Für eine Vorschusscharge dokumentieren `repaid` und `balanceBefore` die Verrechnung. Schema-2-Belege aus P07-06 bleiben ohne diese Felder lesbar.

### Anstellung P08-01

[`Workers.hire`](../../src/server/Workers.luau) prüft bestätigten Sitzungsbesitz, Eigentümer, erwartete State-Revision und Guthaben. Der erste bestätigte Kauf zieht 120 Spielgeld ab und ergänzt `progress.firstWorker={price,revision}` im selben Save. Ein weiterer Antrag liefert diese vorhandene Freischaltung. Alte Profile ohne `firstWorker` bleiben gültig und starten ohne Anstellung. Die Demo lässt den Antrag nur in Reichweite am Fertiglager zu.

J am Sägeausgang speichert `firstWorker.assigned=true` mit neuer Bestandsrevision. Der Mitarbeiter verwendet ausschließlich seinen Kapazität-1-Träger `Worker.First`. Der Aufnahme-Claim bindet `Saege.Output`, den Träger und `Montage.Input` per `nextTargetId`. Nach Ankunft am Ausgang ersetzt ein Save den Aufnahme-Claim mit einem gewöhnlichen Ablage-Claim. Im selben Save wechselt der Bausatz auf den Träger und reserviert den leeren Ausgang für die Rückgabe. Konkurrierende Übergaben prüfen alle reservierten Orte. Erst die Ankunft am Montageeingang erlaubt den Commit und gibt den Rückgabeplatz frei.

Nach zwei erfolglosen Wegversuchen gibt der Mitarbeiter den Claim frei und pausiert. Getragene Ware geht bei erreichbarem Rückweg physisch an den zugesagten Sägeausgang. Bei versperrtem Rückweg bleibt sie sichtbar beim Mitarbeiter. Der Eigentümer kann sie dort mit G übernehmen. Der gemeinsame Übergabekern bindet die bestehende Rückgabezusage an die Spielerhand, ohne einen Zwischenort zu buchen. Bei Wiederbeitritt erscheint der bereits angestellte Träger am Wartepunkt. Die Demo prüft seinen realen Trägerpunkt beim Wiederaufbau, löst den alten Auftrag und versucht die physische Rückgabe. [Prüfbeleg](../evidence/P08.md#p08-07--wiederbeitritt-und-prüfung-der-linie)

## Speichern und Wiederherstellen

Persistenz gehört zum ersten Bestandsnachweis. Das Profil trennt bestätigte Speicherdaten von laufender Darstellung. Revision und Sitzungszuordnung schützen vor verspäteten Schreibvorgängen älterer Sitzungen. Startdaten entstehen ausschließlich nach einer erfolgreichen Prüfung, dass für den Spieler noch kein Profil existiert. Kann das Profil nicht geladen werden, bleiben wirtschaftliche Aktionen gesperrt. Bei unklarem Ergebnis bleibt der betroffene Verkauf bis zur Prüfung offen.

Unverbuchte Übergaben bleiben an ihrer Quelle. Bereits verbuchte Ware bleibt am bestätigten Ort. Nach Wiederbeitritt werden Fahrzeugladung und Lager gemeinsam aus dem Profil rekonstruiert. Kann ein bestätigter Ort technisch nicht wiederhergestellt werden, wird die Ware an einem dokumentierten physischen Abholpunkt bereitgestellt. Abholung und anschließende Fahrt sind weiterhin nötig. Beim Wiederherstellen eines Maschinenlaufs darf dieselbe Charge nur als laufender Input oder als fertiger Output vorliegen.

[VehicleRecovery](../../src/server/VehicleRecovery.luau) rekonstruiert das Gespann mit den gespeicherten Fahrzeug- und Ladeplatz-IDs an einem Startpunkt vor der nächsten Lieferung. Bei Holz auf dem Anhänger oder in der Hand mit Rückgabe an den Anhänger startet es am Lieferantenhof. Die übrigen Fälle starten am Werkstatthof. Für einen ausgefallenen Anhängerplatz übernimmt sein exklusiver Bergungsplatz vorübergehend dieselbe logische ID. Eine aktive Rückgabe an diesen Ladeplatz gilt auch am Bergungsplatz. Erst die bestätigte physische Ablage auf dem Ersatzgespann macht es zum aktiven Ladepunkt. Die Fahrtbeobachtung folgt der tatsächlich am Gespann dargestellten Ladung.

### Platzzuordnung P04-07

[Recovery.plan](../../src/server/Recovery.luau) nimmt eine frische `Persistence.snapshot()` aus dem bestätigten, gültigen Sitzungsbesitz und zwei vom Server aus der Welt ermittelte Zuordnungen an. Die erste enthält die vorhandenen normalen Auflagen. Die zweite enthält erreichbare, exklusive Abholpunkte für denselben logischen Platz innerhalb seiner regulären Übergabezone. Ohne Bestätigung, bei fehlenden zugesagten Auflagen oder einer physischen Doppelzuordnung verweigert der Planer die Ausgabe für das gesamte Profil. Er erhält Chargen-ID, Menge, Stufe, Geld, logischen Ort und beide Revisionen. Aufruf und Auswertung dürfen nicht durch einen Yield oder Sitzungswechsel getrennt werden.

Unverbuchte Claims verschieben beim Laden keine Charge. Ablauf bleibt bei `Transfers.expireClaims` und wird zusammen mit dem Bestand über den normalen Speicherweg bestätigt. Auf Carrier und Band wird derselbe Träger rekonstruiert. Bei dessen Verlust bleibt der bloße Ersatzpunkt gesperrt. Die Weltanbindung führt dann den physischen Rückgabeweg zum exakt zugesagten Ursprung aus und verbraucht Return erst mit der bestätigten Rückgabe. Für Machine und StationProcess stellt P04 nur die gespeicherte Stufe am ursprünglichen Platz dar. Die Jobphase kommt mit P05. Für VehicleSlot und andere Plätze darf ein Ersatzpunkt keine Ankunft, Fahrt oder Entladung bestätigen. Der Client erhält weder die Registry noch das Modul. [Prüfbeleg](../evidence/P04-07.md)

Der letzte bestätigte Save bestimmt den Wiederherstellungsstand nach einem Absturz. Verlust von Änderungen seit dieser Bestätigung ist möglich. Ein späterer Rebirth darf erst nach Klärung offener Verkäufe, Reservierungen und Ladungen stattfinden. Zurückgesetzte und dauerhafte Inhalte werden gemeinsam in einer neuen Profilrevision gespeichert. Konkrete Reset-Regeln gehören in die spätere Rebirth-Phase.
