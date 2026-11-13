# Hockerrezept und Stationsübergaben

Stand 12. November 2026. Entwurfsvertrag für **P01-01**, **P01-02** und **P01-06**, Rezept `Hocker01`, Version 1. Die Mengen, Zeiten und Kapazitäten sind vorläufige Prüfwerte. Sie sind noch nicht als Spielcode oder Stationsmodelle umgesetzt.

[Spielkern](CORE.md) · [Wirtschaft](ECONOMY.md) · [Zustandsregeln](../technical/STATE.md) · [Prüfbeleg](../evidence/P01-01-02.md)

[Waren und Maßblatt P01-03/P01-05](DIMENSIONS.md) · [Verladekette P01-04](LOGISTICS.md) · [Ergänzende Papierabnahme P01-03 bis P01-06](../evidence/P01-03-06.md)

## P01-01 · Rezept und Mengenbilanz

Eine Charge beginnt als **ein Holzpaket für einen Hocker**. Es enthält einen Sitzrohling, vier Beinrohlinge und vier Zargenrohlinge. Der Zuschnitt macht daraus einen vollständigen Bausatz mit **neun Holzbauteilen**: eine Sitzplatte, vier Beine und vier Zargen. Jedes Teil ist Bestandteil dieser Charge und kein zusätzlich entnehmbarer Inventarposten. Das Paket ist für dieses Rezept vollständig vorportioniert; separate Verschnittware gehört nicht zum ersten Prüfmodell.

Der offene Bausatzträger, Verbindungsmittel, Finishmittel und der Karton sind im Prototyp pauschal bereitgestellte Stationshilfsmittel. Sie benötigen keinen Einkauf und belegen keinen zusätzlichen Warenplatz. Es gibt keine verdeckte Lagerbedingung für diese Hilfsmittel. Nur das Holzpaket wird als Rohstoff gebucht; die Holzmenge bleibt über alle Zustände vollständig im Produkt. Eigenständige Verbrauchsgüter oder leere Trägerrückläufe würden später ein ausdrücklich erweitertes Rezept benötigen.

| Schritt / Station | Eingang pro Lauf | Ausgang pro Lauf | Bearbeitung | Eingangspuffer | Laufplätze | Ausgangspuffer |
| --- | --- | --- | --- | --- | --- | --- |
| Zuschnitt / Säge | 1 Holzpaket: 1 Sitzrohling + 4 Beinrohlinge + 4 Zargenrohlinge | 1 offener Bausatzträger: 1 Sitzplatte + 4 Beine + 4 Zargen | 6 s | 1 Holzpaket | 1 | 1 vollständiger Bausatz |
| Montage / Montagebank | 1 vollständiger Bausatz mit 9 Teilen | 1 montierter Rohhocker mit denselben 9 Teilen | 8 s | 1 Bausatz | 1 | 1 Rohhocker |
| Finish / Finishplatz | 1 Rohhocker | 1 fertiger Hocker | 6 s | 1 Rohhocker | 1 | 1 fertiger Hocker |
| Verpackung / Packtisch | 1 fertiger Hocker | 1 geschlossener Hockerkarton mit genau 1 Hocker | 4 s | 1 fertiger Hocker | 1 | 1 Hockerkarton |

Ein Lauf verarbeitet immer eine vollständige Charge. Teilpakete, lose Einzelbeine und Mischbausätze sind in diesem Rezept unzulässig. Alle Stationen derselben Werkstatt greifen auf den gemeinsamen serverseitigen Bestand zu; ein Zähler am Modell führt keinen zweiten Bestand.

Die Chargen-ID, der Eigentümer und die Rezeptversion bleiben vom Holzpaket bis zum Karton erhalten. Ein Warenposten mit Menge `1` wechselt seine Verarbeitungsstufe; die neun eingebetteten Holzteile werden nicht als neun weitere Warenposten gezählt. Start und Ende eines Laufs folgen den atomaren Umbuchungen aus STATE: Eingang → laufender Input → Ergebnis am Ausgang. Während des Laufs bleibt das Werkstück am Arbeitsbereich sichtbar, ohne dass bereits ein zweiter fertiger Output existiert.

**Bilanz einer Charge:** 1 Holzpaket → 1 Bausatz mit 9 Teilen → 1 Rohhocker → 1 fertiger Hocker → 1 Karton mit 1 Hocker. Die reine Stationszeit beträgt **24 s**; Tragen, Ablegen, Fahren und Warten kommen hinzu. Im isolierten Wirtschaftstest ist dies die Charge mit Einkauf 60 und Händlererlös 100 aus ECONOMY. Die Stationszeiten ändern keine Preise und lösen keine Auszahlung aus.

## Puffer und Start eines Laufs

Jede Station besitzt je einen markierten Eingangsplatz, einen Arbeitsbereich und einen Ausgangsplatz. Der Eingang darf bereits die nächste Charge aufnehmen, während eine andere verarbeitet wird. Die Laufkapazität bleibt eins.

Der Server startet selbstständig, sobald eine vollständige passende Charge im Eingang liegt, kein Lauf aktiv ist und der Ausgang weder belegt noch reserviert ist. Er reserviert den Ausgang **vor** dem Materialverbrauch und ordnet den Eingang im selben bestätigten Schritt dem Lauf zu. Die Dauer beginnt danach. Zum Laufende wird der reservierte Platz genau einmal mit dem Ergebnis belegt und die Reservierung ersetzt; eine Wiederholung erzeugt kein zweites Ergebnis.

| Stationssituation | Eingang belegt | Lauf aktiv | Ausgang belegt | Ausgang reserviert | Zulässige nächste Aktion |
| --- | --- | --- | --- | --- | --- |
| Leer | 0 | 0 | 0 | 0 | Passende Charge ablegen |
| Bearbeitung | 0 oder 1 | 1 | 0 | 1 | Nächsten Eingang füllen, falls frei; aktuellen Lauf beenden lassen |
| Ergebnis wartet | 0 oder 1 | 0 | 1 | 0 | Ergebnis abholen; ein vorhandener Eingang wartet unverbraucht |
| Ergebnis wird getragen | 0 oder 1 | 0 | 0 | 1 | Zielablage oder physische Rückgabe abwarten; kein neuer Lauf |
| Ausgang wieder frei | 1 | 0 | 0 | 0 | Nächster Lauf startet selbstständig |

Belegter und reservierter Ausgang teilen dieselbe Kapazität: `belegt + reserviert <= 1`. Die Reservierung ist kein zusätzliches Warenstück. Während eines Laufs darf niemand fremde Ware in dessen Ausgang stellen. Ein freier Eingang ist keine Erlaubnis, den laufenden Auftrag zu ersetzen.

Es ist kein Kundenauftrag und kein erneutes Startkommando pro Möbel nötig. Fortlaufende Produktion bedeutet Verarbeitung vorhandener Eingänge bis zum Rückstau. In der Handarbeitslinie muss der Spieler jede Strecke zwischen den Stationen und zum Lager selbst zurücklegen. Eine freie nachfolgende Station holt keine Ware automatisch von einem entfernten Ausgang.

## P01-02 · Vier Stationen

Für jede Station gelten dieselben drei örtlichen Bezeichnungen: `Input`, `Process`, `Output`. Aus Sicht des davorstehenden Bedieners liegt die Eingangsablage links, der Arbeitsbereich mittig und die Ausgangsablage rechts. Ein Pfeil zeigt die lokale Warenrichtung. Markierungen kombinieren Text und Form; Farbe unterstützt sie lediglich.

Ein Übergabepunkt ist der Auflagemittelpunkt eines eindeutig markierten Warenplatzes. Die Unterseitenmitte des Pakets, Trägers, Hockers oder Kartons ruht dort. Hand und später Personal setzen die Ware auf genau diesen Platz; ein Band übernimmt oder übergibt an demselben Platz und hält dafür die Kapazitätsprüfung ein. Es gibt keine zusätzliche versteckte Automationsablage. Die Handseite bleibt vom Bediengang erreichbar, die Warenrichtung bleibt für einen späteren Bandanschluss frei.

| Station | Eingang und Eingangsablage | Arbeitsbereich | Ausgang und Ausgangsablage | Sichtbare Rückmeldung |
| --- | --- | --- | --- | --- |
| **Säge** | `Saege.Input`: 1 Holzpaket auf flacher, als „Holzpaket“ markierter Auflage | `Saege.Process`: Paket auf der Zuschnittauflage; Bearbeitung nur im Arbeitsbereich | `Saege.Output`: 1 offener Träger mit sichtbar vollständigem Satz aus Sitz, 4 Beinen und 4 Zargen | „Holzpaket fehlt“, „Zuschnitt · 6 s“ mit Restzeit oder „Bausatz abholen“; Symbol zeigt Paket → Teile |
| **Montagebank** | `Montage.Input`: 1 vollständiger offener Bausatzträger auf als „Bausatz · 9 Teile“ markierter Fläche | `Montage.Process`: Teile werden sichtbar als Hocker zusammengefügt | `Montage.Output`: 1 standsicher abgelegter Rohhocker auf eigener Auflage | „Bausatz fehlt“, „Montage · 8 s“ mit Restzeit oder „Rohhocker abholen“; rohe Verbindungen bleiben erkennbar |
| **Finishplatz** | `Finish.Input`: 1 Rohhocker auf als „Rohhocker“ markierter Standfläche | `Finish.Process`: Hocker steht auf der Finishauflage | `Finish.Output`: 1 fertiger Hocker auf eigener Standfläche | „Rohhocker fehlt“, „Finish · 6 s“ mit Restzeit oder „Fertigen Hocker abholen“; sichtbare Oberfläche und Stufenschild unterscheiden roh/fertig |
| **Packtisch** | `Packen.Input`: 1 fertiger Hocker auf als „Fertiger Hocker“ markierter Fläche | `Packen.Process`: Hocker bleibt bis zum Schließen der Verpackung räumlich nachvollziehbar | `Packen.Output`: 1 geschlossener Karton auf flacher Auflage | „Fertiger Hocker fehlt“, „Verpacken · 4 s“ mit Restzeit oder „Hockerkarton abholen“; Karton trägt Hockersymbol und „1 Hocker“ |

Die Auflagen müssen die gesamte Grundfläche der jeweiligen Ware tragen; Ein- und Ausgang dürfen sich weder gegenseitig noch mit dem Arbeitsbereich überlagern. Außenmaße, Arbeitshöhe, Greifraum und lokale Koordinaten sind als Sollwerte im [Maßblatt P01-03/P01-05](DIMENSIONS.md) festgelegt und werden anschließend am Stationsmodell geprüft. Dieser Vertrag behauptet keine bereits eingebauten oder im Spiel vermessenen Anschlüsse.

## Gemeinsame Handgriffe und Rückmeldungen

Die zulässige Handfolge ist Rohstoffablage → Hand → `Saege.Input`, anschließend jeweils Stationsausgang → Hand → nächster Stationseingang und zuletzt `Packen.Output` → Hand → Fertiglager. Pro Handtransport wird genau eine vollständige Charge getragen. Das Rohstoff- und Fertiglager sind eigene Orte mit separat festzulegender Slotzahl; sie sind keine zusätzlichen Stationsausgänge. Die genaue Lager- und Verladekette folgt in P01-04.

Spätere Mitarbeiter verwenden dieselbe Folge mit einem sichtbaren Träger. Ein Förderband verbindet einen bestehenden Ausgang mit dem nächsten Eingang über einen sichtbaren Bandabschnitt. Diese Transportarten ändern weder Rezept, akzeptierte Warenzustände noch Stationskapazität. Aufnahme und Ablage verwenden für alle Akteure die gemeinsamen Reservierungen und Umbuchungen aus STATE.

| Situation | Sichtbarer Zustand und Rückmeldung | Aufenthaltsort und Fortsetzung |
| --- | --- | --- |
| Passende Ware wird abgelegt | Eingangsplatz zeigt die bestätigte Charge; bei freiem Ausgang beginnt die Bearbeitung | Ware wechselt einmal vom Träger zum Eingang und anschließend zum Lauf |
| Falsche Stufe, falsches Rezept oder unvollständiger Bausatz | „Hier wird [erwartete Ware] benötigt“; keine Startanimation | Ware bleibt unverändert am bisherigen Ort, etwa sichtbar in der Hand |
| Eingang belegt oder reserviert | „Eingang belegt – Platz freimachen“ | Getragene Ware bleibt auf ihrem Träger; bestehender Eingang bleibt erhalten |
| Ausgang belegt | „Ausgang voll – [Ergebnis] abholen“ hat Vorrang vor einer Leerlaufmeldung | Nächster Eingang bleibt unverbraucht liegen; erst bestätigte Zielablage gibt den rückgabereservierten Ausgang für den nächsten Start frei |
| Kein passender Eingang und Ausgang frei | „[Eingangsware] fehlt“ | Kein Verbrauch, kein Lauf; Nachschub muss physisch zum Eingang gelangen |
| Zwei Akteure greifen auf dieselbe Charge oder denselben Platz zu | Nur eine Reservierung gewinnt; andere Aktion meldet „Ware oder Platz bereits reserviert“ | Es entsteht kein zweiter Träger und kein zusätzlicher Bestand |
| Übergabe wird wiederholt oder abgebrochen | Bestätigte Wiederholung liefert dasselbe Ergebnis; vor Aufnahme kann die vorläufige Reservierung gelöst werden | Nach Aufnahme bleibt Ware auf dem Träger und der Rückgabeplatz reserviert, bis Zielablage oder physische Rückgabe bestätigt ist |
| Fertiglager ist voll | „Fertiglager voll – Lagerplatz freimachen“ an der Ablage | Bei abgewiesener Ablage bleibt der Karton auf dem Träger; ein nicht abgeholter Packausgang erzeugt Rückstau |

Eine Charge behält das bei ihrem Start zugeordnete Rezept. Das erste Prüfmodell bietet nur `Hocker01`; eine Änderung der Auswahl darf begonnene Ware nicht umdeuten. Die folgenden Regeln ergänzen die gemeinsamen Umbuchungen aus STATE. Spieltests, Konkurrenztests und Wiederherstellung sind durch diese Papierprüfung noch nicht bestanden.

## Rückgabeplatz während des Transports

Beim bestätigten Aufnehmen liegt die Charge ausschließlich auf dem sichtbaren Träger. Der bisherige Quellslot bleibt leer und als **Rückgabeplatz genau dieser Charge** reserviert, bis die Ablage an einem zulässigen Ziel oder die physische Rückgabe abgeschlossen ist. Es entsteht weder zusätzliche Ware noch ein zusätzlicher Slot. Ein solcher Stationsausgang sperrt den nächsten Lauf genauso wie ein belegter Ausgang.

Bei erfolgreicher Zielablage oder bestätigtem Verkauf wird die Rückgabereservierung im selben Änderungsschritt freigegeben. Bei Rückgabe wird sie durch die wieder abgelegte ursprüngliche Charge ersetzt. Diese Rückgabe darf keine neue Ware einschleusen und bleibt für dieselbe unveränderte Charge auch nach einem Rezeptwechsel zulässig. Eine normale neue Ablage in einen Stationsausgang bleibt unzulässig.

Vor Aufnahme dürfen vorläufige Reservierungen kontrolliert auslaufen. **Nach Aufnahme** darf weder Timeout noch Abbruch den Rückgabeplatz einfach freigeben. Der Spieler kann den bestätigten Transport fortsetzen oder zum Ursprung zurücklaufen. Bei Verlust des Trägers muss die Wiederherstellung die Charge am gespeicherten Träger oder genau einmal am reservierten Ursprung rekonstruieren und die Reservierung passend abschließen; die reguläre Fahrt zum Ziel bleibt erforderlich. Die Umsetzung wird später mit dem gespeicherten Bestand geprüft.

Diese konservative Regel gilt auch für Personal- und Bandträger. Sie begrenzt den Durchsatz, solange ein Transport seinen Ursprung blockiert, hält aber den Rückweg eindeutig. Handware kann so auch bei vollem Fertiglager und vollem Anhänger abgelegt werden: zum reservierten Ursprung zurücktragen und Hände freimachen. Kartons auf dem Fahrzeug werden ausgeliefert; Holzpakete werden auf die bereits beim Kauf garantierten Rohstoffplätze entladen. Danach kann Lagerware verladen und die Linie von hinten geräumt werden. Die [Verladekette](LOGISTICS.md) sperrt Einkäufe ohne solchen Entladeplatz. Es wird kein zusätzlicher Notlagerplatz vorausgesetzt.

## P01-06 · Stoppfälle und nächster Handgriff

| Fall | Stationszustand und eindeutiger Warenort | Rückmeldung | Nächster möglicher Handgriff |
| --- | --- | --- | --- |
| Ausgang voll | Kein neuer Lauf; Ergebnis auf `Output`, Folgecharge unverbraucht auf `Input` | „Ausgang voll – [Ergebnis] abholen“ | Ergebnis physisch zum nächsten freien Ziel tragen; nach Zielablage kann der nächste Lauf starten |
| Ausgang als Rückgabeplatz reserviert | Ergebnis ausschließlich auf Hand/Personal/Band, Ausgang leer reserviert | „Transport läuft – Ausgang reserviert“ | Zum Ziel bringen oder dieselbe Charge physisch zurücklegen |
| Lauf aktiv | Laufender Input auf `Process`, Ausgang für dessen Ergebnis reserviert; nächste Charge darf am Eingang warten | Bearbeitung und Restzeit; gegebenenfalls „Nächste Charge wartet“ | Freien Eingang füllen oder Lauf abwarten; reservierten Ergebnisplatz nicht belegen |
| Eingang voll oder reserviert | Vorhandene Eingangscharge beziehungsweise deren Rückgabeplatz bleibt erhalten; zusätzliche Ware bleibt auf ihrem Träger | „Eingang belegt – Platz freimachen“ | Verarbeiten lassen oder einen unbegonnenen Eingang mit freier Hand entnehmen und korrekt ablegen |
| Nachschub fehlt | Arbeitsbereich leer, kein Verbrauch; andere Ware bleibt an ihren bestätigten Orten | „[Eingangsware] fehlt“ | Passende Ware physisch nachliefern; kein automatisches Holen von entfernten Ausgängen |
| Falsche Ware | Keine Ablage, kein Lauf; falsche Stufe/Teilmenge/Rezeptzuordnung unverändert auf Träger oder Quelle | „Hier wird [Ware / Rezept] benötigt“ | Zur passenden Station bringen oder am reservierten Ursprung zurückgeben |
| Fertiglager voll | Getragener Karton bleibt auf Träger; übrige Kartons an Ausgang/Lager. Aktiver Packlauf darf auf reserviertem Ausgang enden | „Fertiglager voll – Lagerplatz freimachen“ | Handkarton gegebenenfalls zurückgeben; Lagerware verladen und ausliefern; Stau vom Packausgang rückwärts räumen |
| Unberechtigter oder konkurrierender Zugriff | Höchstens eine Reservierung gewinnt; Charge hat weiter genau einen Ort | „Keine Berechtigung“ / „Ware oder Platz reserviert“ | Berechtigten Zugriff oder Freigabe abwarten; keine Ersatzware erzeugen |
| Übergabe abgebrochen oder wiederholt | Vor Aufnahme Quelle; nach Aufnahme Träger plus leerer Rückgabeplatz; nach Ablage Ziel. Wiederholung liefert bestehenden Abschluss | „Übergabe abgebrochen“ beziehungsweise bestätigtes Ergebnis | Vom bestätigten Ort fortsetzen oder zurücktragen; kein erneutes Laufende erzeugen |

### Rezeptwechsel ohne Umdeuten alter Ware

Im ersten Prüfmodell gibt es nur `Hocker01`. Die folgenden Regeln beschreiben die spätere Auswahl, ohne eine zweite Rezeptdefinition oder neue Materialmengen einzuführen:

1. Begonnen ist eine Charge ab ihrem bestätigten ersten Säge-Start. Lauf, Zeiten, Rezeptversion und Ausgangsreservierung dieser Charge bleiben erhalten. Auch alte Bausätze und Rohhocker auf Trägern oder in nachgelagerten Stationseingängen werden nach ihrer gespeicherten Rezeptversion weiterbearbeitet.
2. Die Auswahl gilt für die Annahme neuer, noch nicht begonnener Holzchargen an der Säge. Rohmaterial im Lager oder in der Hand wird dadurch weder umgewandelt noch gelöscht. Ein bereits zugeordnetes Holzpaket behält seine Rezeptzuordnung.
3. Ein Wechsel auf ein inkompatibles Rezept wird abgewiesen, wenn ein unbegonnenes Paket am Sägeeingang liegt oder dessen Sägeeingang als Rückgabeplatz reserviert ist: „Eingang zuerst freimachen oder vorhandene Charge beginnen lassen“. Die bisherige Auswahl bleibt aktiv. Entnahme und Rückgabe derselben Charge bleiben erreichbar; nur die Auswahl ist gesperrt.
4. Ein bereits gestarteter alter Lauf und alte nachgelagerte Zwischenprodukte sperren den Wechsel nicht. Ihre Stationsannahme prüft das gespeicherte Chargenrezept statt nur die neue Linienauswahl. Neue Chargen starten erst mit den für ihre Auswahl passenden Zutaten und freien Plätzen.
5. Auswahl und Säge-Start werden serverseitig eindeutig geordnet: Startet die alte Charge zuerst, bleibt sie alt und der Wechsel ist danach erlaubt. Steht sie noch unbegonnen im Eingang, wird der inkompatible Wechsel abgewiesen. Keine Reihenfolge darf Ware vernichten, kopieren oder in einer unzulässigen Stufe liegen lassen.

Die Papierprüfung verfolgt Stau, Rückgabe und Wechsel mit einer symbolischen zweiten Auswahl. Tatsächlicher Rezeptwechsel im Spiel wird erst mit dem zweiten Rezept geprüft. Alle Laufzeit-, Konkurrenz- und Speicherfälle bleiben offen bis zu ihrer Implementierung.
