# Möbelfabrik Tycoon

Konzept und Council-Evaluation | Version 1.1 | 6. November 2026

**Arbeitstitel:** Werkstück. Der endgültige Name ist offen.

## 1. Entscheidung und Projektziel

> **Empfehlung: Go für einen begrenzten Prototyp.** Eine vollständige Produktion ist erst nach einem überzeugenden Spiel- und Art-Nachweis sinnvoll. Dieses Dokument ist die ausgearbeitete Konzeptgrundlage; die Prüfungen darin stehen noch aus.

Du beginnst als einziger Arbeiter einer kleinen Möbelwerkstatt. Mit einem Quad holst du Holz vom Lieferanten, trägst es in der Fabrik zwischen Stationen und produzierst Möbel auf Lager. Fertige Ware fährst du zu Möbelhändlern oder Privatkunden. Später übernehmen Mitarbeiter bekannte Arbeiten; Förderbänder verbinden die Stationen. Größere Fahrzeuge bis zum Lkw erweitern deine Transportmöglichkeiten.

**Das zentrale Versprechen:** Du kennst jede Arbeit in deiner Fabrik und kannst beobachten, wie dein Betrieb diese Arbeit zunehmend selbst erledigt. Möbel entstehen nachvollziehbar aus Bauteilen; Ausbau verändert sowohl die Werkstatt als auch deinen Arbeitsalltag.

**Drei Entwicklungsstufen:**

1. **Selbst herstellen:** Material tragen, Stationen versorgen, Produkte fertigstellen.
2. **Ein Team organisieren:** Transport und passende Stationsarbeit zuweisen.
3. **Produktion planen:** Bänder verbinden, Produktmix, Lager und Verkaufswege abstimmen.

Die stärksten Argumente sind die sichtbare Verwandlung von Material zu Möbeln und die persönlich erlebte Entlastung durch Automation. Die größten Risiken sind monotone Laufarbeit, Leerlauf nach Automation und der Aufwand für glaubwürdige Assets.

**Zuerst beweisen wir zwei Dinge:** Ein kleiner Produktionsablauf macht in allen drei Stufen Sinn; ein Möbelstück samt Maschinen und Gebäudeecke erreicht die gewünschte gestalterische Qualität.

**Neu in Version 1.1:** Dauerproduktion ohne vorherige Kundenaufträge, Händler- und Privatverkauf sowie physischer Fahrzeugtransport vom Quad bis zum Lkw. Damit werden die auftragsbezogenen Annahmen aus Version 1.0 ersetzt.

**Lesepfad:** Kapitel 2-3 klären Vorgaben und Council. Kapitel 4-8 beschreiben Produktion, Verkauf, Logistik und Fortschritt. Kapitel 9-10 definieren Art und Technik. Kapitel 11-14 enthalten Umfang, Prüfungen, Debatte und nächste Entscheidungen. Quellen stehen in Kapitel 15.

---

## 2. Vorgaben, Wünsche und Annahmen

### Vom Nutzer vorgegeben

- Ein interaktiver Roblox-Tycoon mit eigener Möbelproduktion.
- Rohmaterial wird eingekauft und anfangs eigenhändig zwischen Stationen transportiert.
- Mitarbeiter übernehmen später Arbeiten und Transport; Förderbänder kommen als weitere Entwicklungsstufe hinzu.
- Weitere Möbelstücke sollen den Betrieb erweitern; Rebirths sollen neue Möglichkeiten freischalten.
- Die Produktion läuft auf Lager, ohne vorher Kundenaufträge auszuwählen.
- Fertige Möbel werden an Möbelhändler oder Privatpersonen verkauft. Beim Privatverkauf kann der Erlös höher oder niedriger ausfallen.
- Ware wird tatsächlich mit Fahrzeugen transportiert: anfangs Quad, später bis zum Lkw. Regelmäßige Warenwege werden nicht durch Teleport ersetzt.
- Ein Shop gehört zur gewünschten Spielrichtung. Seine konkrete Bedeutung ist noch offen.
- Assets müssen als zusammengehörige, glaubwürdig gebaute Gegenstände wirken. Als früheres Problem wurde ein unpassend auf einem Haus sitzendes Dach beschrieben.

### Vorschläge des Councils

Eine eigene Werkstatt pro Spieler und feste Maschinenplätze bilden den vorläufigen Rahmen. Ein kleiner Quad-Anhänger macht den Einstieg mit Möbelkartons glaubwürdig. Händler bieten einen bekannten Preis, Privatkunden einen Zufallserlös relativ dazu. Privatkunden sind zunächst NPCs. Gewöhnliche Möbelmodelle erscheinen im normalen Fortschritt; Rebirths eröffnen größere Fertigungszweige. Eine leicht stilisierte Tischlerei ist der vorgeschlagene Look.

Diese Festlegungen sind **Konzeptentscheidungen des Councils und noch keine ausdrücklichen Nutzerfreigaben**. Das gilt besonders für Reset-Regeln, Shop-Art, Zielgeräte und freie Platzierung.

### Vorläufige Zielvorstellung

Angesprochen werden sollen Spieler, die gern selbst mitarbeiten und anschließend Abläufe verbessern. Ein Alterssegment, eine Marktgröße und ein Einnahmeziel wurden nicht festgelegt. PC und Touch werden im Entwurf berücksichtigt; konkrete Geräte und Leistungsziele sind später zu bestimmen.

Das Spiel startet mit einer kompakten Werkstatt statt einer großen offenen Welt. Der erste Ausbau bleibt räumlich überschaubar, damit Materialfluss, Mitarbeiterwege und Fortschritt verständlich sind.

### Shop sauber unterscheiden

| Shop-Art | Vorläufiger Status |
|---|---|
| Rohstoffe und Betriebsausrüstung mit Spielgeld | Bestandteil des Grundablaufs; konkrete Oberfläche offen. |
| Eigener Möbelverkaufsraum mit Kunden | Mögliche Erweiterung; der Verkauf an Händler und Privatkunden erfolgt zunächst an deren Übergabeplätzen. |
| Robux-Shop | Unentschieden und außerhalb des Prototyps; keine Preise oder Umsatzannahmen. |

Die funktionale Entwicklung durch Personal und Bänder soll im vorgeschlagenen Modell vollständig erspielbar sein.

---

## 3. Council und Bewertungsmethode

Fünf tatsächliche Subagents bewerteten das Vorhaben aus unterschiedlichen Rollen. Die Koordination und endgültige Zusammenführung übernahm der Hauptagent. Wegen der verfügbaren Parallelplätze erfolgte die Arbeit in Gruppen.

| Rolle | Prüfauftrag |
|---|---|
| Skeptiker | Jede Kernannahme angreifen; monotone Arbeit, Rebirth-Zwang, Scope und Asset-Risiko aufdecken. |
| Verteidiger | Den stärksten tragfähigen Entwurf formulieren und begründete Kritik aufnehmen. |
| Technik | Materialzustände, sichere Übergaben, Mitarbeiter, Bänder, Speichern und Machbarkeit eingrenzen. |
| Art Direction | Glaubwürdige Konstruktion, gemeinsame Formensprache und konkrete Asset-Abnahme definieren. |
| Spielerlebnis | Einstieg, Interaktion, Wirtschaft, Automation und langfristigen Fortschritt prüfen. |

### Zwei Bewertungsrunden

In Runde 1 entstanden eigenständige Reviews. Skeptiker, Verteidiger und Technik begannen; Art und Spielerlebnis prüften anschließend auch deren Einwände. In Runde 2 erhielten alle fünf Gegenpositionen und eine gemeinsame Synthese. Jedes Mitglied ergänzte eine Gegenrede und ein endgültiges Votum in seiner eigenen Datei.

Die Rollen sind bewusst gesetzte Blickwinkel. Es handelt sich um **keine externen menschlichen Fachgutachten und keine unabhängige Marktforschung**. Übereinstimmung im Council ist ein Designurteil, kein Nachweis für Spielspaß oder wirtschaftlichen Erfolg.

### Bewertungsmaßstab

Ein Einwand ist besonders wichtig, wenn er den gewünschten Kern beschädigt: selbst erlebte Herstellung, spürbare Entlastung oder glaubwürdige Optik. Lösungen werden bevorzugt, wenn sie mit einem kleinen Ausschnitt geprüft werden können. Mehr Modelle, Shops oder Währungen ersetzen diesen Nachweis nicht.

Die Einzelreviews einschließlich Gegenreden liegen nachvollziehbar im Unterordner **council/**. Kapitel 13 dokumentiert, welche Widersprüche den Entwurf tatsächlich verändert haben.

**Änderungsstand 1.1:** Die fünf ursprünglichen Reviews bleiben als Bewertungsverlauf erhalten. Der Nachtrag 06 ersetzt ihre auftragsbezogenen Vorschläge durch die späteren Nutzervorgaben. Spielerlebnis, Technik und Art Direction prüften die Auswirkungen von Dauerproduktion, Privatverkauf und Fahrzeuglogistik ergänzend. Die ursprünglichen Voten sind keine erneute Vollbewertung dieser Fassung.

---

## 4. Spielablauf und Produktfamilien

### Eine durchgehende Produktionskette

**Material kaufen → beim Lieferanten verladen → zur Fabrik fahren → zuschneiden → montieren → Oberfläche bearbeiten → verpacken → Fertigwaren lagern → zum Käufer fahren → verkaufen.**

Die erste Linie stellt Holzhocker her. Du stellst das aktive Möbelrezept ein und versorgst die Stationen fortlaufend. Ein Startvorrat beim Lieferanten ermöglicht den ersten Durchlauf; danach wird Nachschub selbst gekauft. Die Produktionsansicht zeigt Materialbedarf, Bestand und Kapazität. Es braucht keinen vorher bestellten Kunden.

Verpackte Möbel belegen sichtbare Fertigwarenplätze. Solange Material und freier Ausgang vorhanden sind, arbeitet die versorgte Linie weiter. Ein volles Lager stoppt sie kontrolliert. Begonnene Chargen behalten ihren Zustand; beim Rezeptwechsel wird angezeigt, was vorher noch fertiggestellt werden muss.

| Station | Sichtbarer Eingang und Ausgang |
|---|---|
| Säge | Holzpaket wird zum geordneten Bausatz aus Sitzfläche und Beinen. |
| Montagebank | Bausatz wird zum erkennbaren, noch unbehandelten Hocker. |
| Finishplatz | Rohmöbel erhält eine wählbare Oberfläche. Schleifen und Lackieren sind anfangs ein zusammengefasster Arbeitsschritt. |
| Packtisch | Fertiger Hocker wird im passenden Karton für Lager und Fahrzeugtransport vorbereitet. |

Die aufgeführten Zustände sind ein vereinfachtes Spielrezept. Materialmengen und Verarbeitungszeiten werden erst im Prototyp abgestimmt.

### Die Handhabung

Aufnehmen, Abladen und Starten erfolgen über klare kontextbezogene Aktionen. Der Spieler trägt ein verständliches Arbeitslos, etwa einen Bausatz. Beschläge gehören zunächst als Behälter oder Rezeptbestandteil dazu. Es gibt keine Pflicht, jede Schraube einzeln zu bewegen.

Stationen zeigen benötigten Eingang, laufende Arbeit und verfügbaren Ausgang. Ablehnen einer falschen Lieferung erklärt den Grund und erhält die Ware. Produktzustand und Ziel werden mit Form, Symbol und Text erkennbar; Farbe ergänzt diese Informationen. Auf Touch ist präzises Ziehen einzelner Kleinteile keine Voraussetzung.

### Inhalt wächst in Familien

| Familie | Neue Möglichkeiten |
|---|---|
| Einfache Holzmöbel | Hocker, Beistelltisch, offenes Regal. Gemeinsame Materialien, andere Bauteile und Kapazitätsbedarfe. |
| Kastenmöbel | Nachttisch, Kommode, Schrank. Türen, Rückwände und Beschläge kommen als weitere Inputs zusammen. |
| Polstermöbel | Zuerst gepolsterter Hocker, später Sessel und Sofa. Holzrahmen trifft auf Polster und eine Stofflinie. |

Ein Farbwechsel ist eine Variante. Eine neue Familie soll zusätzliche Material- oder Kapazitätsentscheidungen schaffen. Neue Möbel dürfen weiterhin vertraute Bauteile und Stationen verwenden.

---

## 5. Verkauf: Möbelhändler und Privatkunden

### Du entscheidest über deinen fertigen Bestand

Produktion und Verkauf sind getrennte Abläufe. Du stellst Möbel her, lagerst sie und wählst anschließend Verkaufsmenge und Abnehmer. Die Ware wird auf ein Fahrzeug geladen und tatsächlich zum Käufer gebracht. Ausgezahlt wird erst bei der bestätigten Übergabe am passenden Ort.

| Verkaufsweg | Vorgeschlagenes Verhalten |
|---|---|
| Möbelhändler | Bekannter Preis pro Modell und Stückzahl. Planbarer Vergleichswert für Nachschub und Investitionen. |
| Privatkunden | Zufälliger Erlös, der über oder unter dem entsprechenden Händlerwert liegen kann. Vor der Bestätigung sind Menge und mögliche Auszahlungsspanne sichtbar. |

Die zwei Verkaufswege und das private Preisrisiko stammen vom Nutzer. Der feste Händlerpreis, die angezeigte Spanne und das genaue Zufallsverfahren sind Vorschläge für ihre Umsetzung. Privatkunden werden zunächst als NPC-Abnehmer behandelt.

### Wann das private Risiko entsteht

Du bringst die Ware zum Privatkunden und siehst vor der verbindlichen Übergabe den Händlervergleich sowie die mögliche Privatspanne. Erst mit der Bestätigung wird der Erlös einmal ermittelt und der Verkauf abgewickelt. Vor der Bestätigung kannst du abbrechen; ein bereits enthülltes schlechtes Ergebnis lässt sich nicht kostenlos gegen den Händlerpreis tauschen.

**Reines Erklärbeispiel:** Beim Händler bringen dieselben Möbel 100 Spielgeld, beim Privatkunden könnten es 70 bis 150 sein. Diese Zahlen legen weder Preise noch Wahrscheinlichkeiten fest. Verteilung, Ziehung pro Stück oder Verkaufscharge und durchschnittlicher Mehrerlös bleiben Balancingfragen.

### Wirtschaft und Rückmeldung

Die Abrechnung zeigt Stückzahl, Verkaufskanal, Erlös und Händlervergleich. Für Grundmöbel wird eine positive Händlermarge gegenüber den Rohstoffkosten vorgeschlagen. Wer nach einem schlechten Privatverkauf zu wenig Betriebskapital hat, braucht eine begrenzte Wiederanlaufhilfe. Deren Regeln müssen einen endlos nutzbaren Geldkreislauf verhindern.

Der Privatverkauf benötigt keinen zusätzlichen Spieleinsatz. Konkrete Robux-Angebote sind weiterhin offen. Zufall darf weder durch erneutes Verbinden noch durch wiederholtes Bestätigen desselben Verkaufs neu ausgelöst werden. Die technische Grundlage steht in Kapitel 10.

---

## 6. Fahrzeuglogistik: vom Quad zum Lkw

### Zwei Ebenen gehören zusammen

**Innerhalb der Fabrik:** Du trägst Material zwischen Stationen; später übernehmen Mitarbeiter und Förderbänder diese Wege.

**Außerhalb der Fabrik:** Fahrzeuge bringen Rohstoffe vom Lieferanten zur Werkstatt und fertige Möbel von dort zu Händlern oder Privatkunden. Regelmäßige Beschaffung und Auslieferung finden auf tatsächlichen Fahrwegen statt. Ein Kauf legt Ware zunächst beim Lieferanten bereit; er füllt das Fabriklager nicht aus der Ferne.

### Fahrzeugentwicklung

| Stufe | Transportidee |
|---|---|
| Anfang: Quad | Kleiner Anhänger oder passende Ladefläche für Holzpakete, Bausätze und kleine Möbelkartons. |
| Mittlere Stufe: Pickup oder Transporter | Vorschlag für größere Ladungen und weniger Fahrten; genaue Fahrzeuge noch offen. |
| Später: Lkw | Große Warenmengen und passende Ladeflächen für größere Möbel oder Paletten. |

Quad und Lkw sind Nutzervorgaben. Anhänger und mittlere Fahrzeugstufe sind Council-Vorschläge. Kapazität wird über nachvollziehbare Ladeplätze und Größenklassen abgestimmt. Ein Fahrzeugupgrade soll sich an transportierter Menge und passenden Produkten bemerkbar machen.

### Laden, fahren, übergeben

Du trägst Ware bis zum Fahrzeug und setzt sie in einen freien Ladeplatz. Die befestigte Ladung bleibt unterwegs sichtbar. Am Ziel wird sie zur richtigen Lager- oder Übergabefläche entladen. Mitarbeiter können später das Beladen übernehmen; zusätzliche Fahrer sind eine offene Erweiterung und würden weiterhin echte Fahrten benötigen.

Große Schränke passen nicht auf den Quad-Anhänger. Tore, Ladezonen und Wendeflächen werden zusammen mit den Fahrzeugen dimensioniert. Der erste Test benötigt eine kurze befahrbare Verbindung zwischen Lieferant, Fabrik, Händler und einem Privatkundenplatz. Eine ganze Stadt gehört dafür noch nicht zum Umfang.

Bei Fahrzeug- oder Verbindungsfehlern wird Ladung konsistent aus dem bestätigten Stand wiederhergestellt. Ein dokumentierter Bergungsfall kann einen physischen Abholpunkt verwenden. Er zählt als technische Ausnahme und führt weder zu routinemäßiger Teleportlogistik noch zu automatischem Fernverkauf.

---

## 7. Progression, Mitarbeiter und Förderbänder

### Stufe 1: Du erledigst den Materialfluss

Kurze Wege verbinden Lager, Säge, Montage, Finish und Verpackung. Verkaufte Lagerware finanziert Nachschub und bringt den Spieler näher an eine konkrete Verbesserung. Die nächste Beschaffungstour wird mit dem vorhandenen Betriebskapital geplant. Sichtbare Zwischenprodukte erklären, wo Zeit und Kapazität gebraucht werden.

### Stufe 2: Mitarbeiter übernehmen bekannte Aufgaben

Der erste Mitarbeiter erhält einen festen Transportweg zwischen zwei Stationen. Später sind Anlieferung, Verpackung und andere Strecken mögliche Aufgaben. Bedienpersonal wird nur an Stationen ergänzt, deren Spielablauf tatsächlich Bedienung benötigt.

Zuweisungen zeigen Quelle, Ziel und Status: arbeitet, wartet auf Material, Ziel voll oder Weg blockiert. Transportaufträge werden reserviert, damit zwei Träger dieselbe Ware nicht gleichzeitig übernehmen. Ein umgesetzter Mitarbeiter behält eine sinnvolle Aufgabe, auch wenn sein alter Weg später ein Band bekommt.

### Stufe 3: Bänder verbinden die Produktion

Im ersten Test verbindet ein gerades Band zwei feste Stationsanschlüsse. Es transportiert offene Teileträger oder passende Kartons. An einem vollen Ziel hält der Transport vor einem sichtbaren Puffer an. Nachschub und Ausgangskapazität bleiben nachvollziehbar.

Freies Verlegen, Kurven, Weichen, mehrere Ebenen und Kreuzungen sind spätere Ausbaustufen. Große Möbel benötigen passende Montagewagen, Paletten oder größere Transportlinien. Produkte verändern beim Stationswechsel nicht plötzlich ihren Maßstab.

### Was der Spieler danach macht

Eine automatisierte Linie darf zufriedenstellend von selbst laufen. Der nächste Reiz entsteht durch eine bewusste Wahl: das produzierte Modell ändern, Lagerware verkaufen, eine Transporttour planen, Personal umverteilen oder einen Engpass ausbauen.

**Beispiel:** Hocker und Beistelltisch benötigen dieselbe Montagebank. Der Tisch bindet sie länger und belegt mehr Ladeplatz, hat aber einen anderen Verkaufswert. Der Spieler entscheidet über Produktmix, Losgrößen, Lagerausbau und Transportkapazität. Danach wählt er den planbaren Händlerverkauf oder das private Preisrisiko.

Die Prüfung fragt nach freiwilliger Weiterplanung und erlebter Kontrolle. Dauernde Eingaben sind kein Selbstzweck. Zufällige Defekte oder zusätzliche Nachfüllpflichten werden nicht als automatische Lösung für Leerlauf vorausgesetzt.

---

## 8. Rebirths und langfristige Entwicklung

### Vorschlag: eine größere Werkstatt eröffnen

Ein Rebirth wird als freiwilliger Betriebsneustart mit neuem Fertigungszweig inszeniert. Beispielsweise öffnet die nächste Werkstatt die Kastenmöbelproduktion; ein späterer Schritt ermöglicht Polster und Stoffverarbeitung. Die genaue Reihenfolge und Zahl der Rebirths bleiben offen.

Gewöhnliche Modelle, Farben und Varianten werden auch innerhalb des laufenden Betriebs freigeschaltet. Rebirths schaffen einen größeren neuen Zusammenhang im Materialfluss. Ihre Voraussetzungen sollen den vorhandenen Betrieb prüfen; exakte Kosten und Mengen werden später abgestimmt.

| Bleibt dauerhaft | Wird neu aufgebaut |
|---|---|
| Freigeschaltete Möbelrezepte und Designs | Aktive Maschinen und Betriebsaufstellung außerhalb des Starterpakets. |
| Gespeicherte Layout-Baupläne | Laufende Materialbestände und betriebliche Geldreserve nach klarer Vorschau. |
| Erschlossene Fertigungsarten und kosmetische Inhalte | Personal außerhalb des festgelegten Grundteams; genaue Regel vorab anzeigen. |
| Gekaufte Fahrzeuge und Fahrzeugfreischaltungen als Vorschlag | Fahrzeugstandort und neue Ladezonen werden der Werkstattstufe angepasst. |

### Wiederaufbauhilfe gehört zum System

Ein Layout-Bauplan allein finanziert keine Maschine. Der Vorschlag umfasst deshalb Material für einen vollständigen ersten Zyklus, die benötigten Basisstationen und einen ersten Transporthelfer. Ein nutzbares Transportfahrzeug bleibt verfügbar. Der Spieler soll den bekannten Abschnitt überprüfbar schneller überwinden.

Dieses Starterpaket wird vor einem Rebirth vollständig angezeigt. Zusätzlich zeigt die Vorschau, welche konkreten Dinge verschwinden und was neu hinzukommt. Laufende Transporte, Fahrzeugladung und verbindliche Verkäufe müssen vorher konsistent abgeschlossen oder geregelt werden. Ein bereits festgelegter Privatpreis wird durch Rebirth nicht neu gewürfelt.

### Was dieser Vorschlag noch beweisen muss

Ein Papiervergleich und später zwei spielbare Neustartvarianten prüfen, ob das zusätzliche Produktionssystem den Neustart rechtfertigt. Gemessen wird auch, wie lange der bekannte Abschnitt erneut dauert und ob der Spieler die Verlustliste richtig versteht.

Falls Spieler ihren aufgebauten Betrieb lieber behalten, ist ein zusätzlicher Hallenflügel eine zu prüfende Alternative. Der Kernwunsch nach neuer Möbelproduktion bleibt dabei erhalten. Die Rebirth-Entscheidung ist noch kein implementiertes oder getestetes System.

---

## 9. Art Direction und Asset-Qualität

### Stilvorschlag: glaubwürdige, leicht stilisierte Tischlerei

Helles Holz, gestrichene Wände, dunkler Maschinenstahl und geordnete Arbeitsplätze geben der Werkstatt eine gemeinsame Sprache. Kanten, Materialgrößen und Bauteildicken passen zusammen. Gezielte Gebrauchsspuren erklären Arbeitsbereiche. Der Look ist ein Vorschlag, keine bereits freigegebene Gestaltung.

**Palette:** Wandweiß #E8E0D1 · Holz #C59664 · Metall #34383C · Grün #788678 · Sicherheitsorange #D88B3D.

Das bekannte Problem mit dem Hausdach wird ausdrücklich Teil der Probe. Benötigt wird eine kleine Gebäudeecke mit Wand, Fenster und Dach: sichtbare Wandstärke, passende Rahmen, gleichmäßiger Dachüberstand und sauber geschlossene Dachflächen. Türen, Möbel und Maschinen werden neben dem Avatar auf gemeinsamen Maßstab geprüft.

Modulare Bauteile erhalten ein gemeinsames Raster und passende Drehpunkte. Roblox beschreibt diese Grundlagen für sauber kombinierbare Umgebungen. Die tatsächlichen Maße bestimmen wir an unserer Probe. [S1]

### Die gemeinsame Muster-Szene

- Ein Hocker als Bausatz, Rohmöbel und fertiges Möbel.
- Säge, Montagebank, Finishplatz und Packtisch mit passenden Arbeitsbereichen.
- Holzpaket, offener Teileträger, passender Karton, Wagen und eine Bandverbindung.
- Boden, Innenraumecke und eine kleine Außenkante mit Fenster und Dach.
- Quad, kleiner Anhänger und ein Ladeplatz werden gemeinsam mit Avatar, Tor, Hockerkarton und Fahrweg auf glaubwürdigen Maßstab geprüft.

Reine Materialzustände dürfen dieselbe Geometrie nutzen. Ein zweites Möbel soll später eine andere Silhouette und Bauweise erhalten, während Beschläge, Materialien und Teile sinnvoll wiederverwendet werden.

### Abnahmekriterien

**Passungen:** Beine treffen den Sitz plausibel, Regalböden passen in Seitenteile und bewegliche Teile besitzen Platz. Keine schwebenden Bauteile, offenen Dachnähte oder unbeabsichtigten Durchdringungen.

**Material:** Maserung folgt dem Bauteil; Holzstruktur und Kantenmaß bleiben konsistent. Rohholz, Lack und Metall sind aus normaler Spielentfernung unterscheidbar. UV-Verzerrungen und auffällige Textursprünge werden geprüft.

**Ansichten:** neutrale Dreiviertelansicht, Nahaufnahme kritischer Übergänge, Außenansicht und tatsächliche Spielkamera. Danach Vergleich bei kleiner Bildschirmansicht, reduzierten Grafikdetails und mehreren Abständen.

Die Nutzerbewertung dieser Probe ist ein zukünftiges Art-Gate. Ein kuratiertes Assetpack bleibt eine Option für passende Umgebungsteile; Stil, Maßstab, Nutzungsrechte und enthaltene Komponenten sind vorher zu prüfen. Neue Meshes müssen zusätzlich die aktuellen Roblox-Importspezifikationen erfüllen. [S2]

---

## 10. Technisches Konzept

### Ein Bestand, drei Transportarten

Der Server führt Chargen mit ID, Eigentümer, Produkttyp, Menge, Verarbeitungsstufe und genau einem Ort: Lieferant, Lager, Träger, Station, Band oder Fahrzeugladeplatz. Fahrzeugladung besitzt Fahrzeug-ID und Slot. Sichtbare Modelle stellen den Bestand dar. Physikalischer Kontakt allein erzeugt weder Ware noch Geld. Clientgesteuerte Physik benötigt serverseitige Kontextprüfung. [S3, S4]

Eine Station besitzt Rezept, Puffer und die Zustände frei, bereit, arbeitet oder Ausgang voll. Ein Maschinenlauf reserviert seinen Ausgangsplatz vor dem Verbrauch. Volle Lager stoppen die Zufuhr. Der interne Fertigungsjob bezeichnet eine Charge; eine Auswahl von Kundenbestellungen existiert nicht.

### Übergaben und Mitarbeiter

Der Server prüft Eigentum, Nähe, Stufe, Mengen, Quellbestand und Zielkapazität, auch beim Beladen. Reservierte Übergaben werden gemeinsam verbucht; Animation oder Wegsuche liegt außerhalb der Umbuchung. Ein Verkauf reserviert konkrete Fertigware. Wiederholte Vorgangs-IDs erzeugen keine Zusatzware oder zweite Auszahlung.

Mitarbeiter verwenden dieselben Übergaben. Blockierte Routen erhalten einen sichtbaren Status und begrenzte Wiederholungen. Ein Abbruch löst Reservierungen: ungebuchte Ware bleibt an der Quelle, übernommene Ware am letzten physischen Ort und muss abgeholt werden. Roblox-Wegsuche unterstützt Routen um Hindernisse; Timeout und lokale Bergung sind eigene Entwurfsentscheidungen. [S5]

### Bänder, Speichern und Fehler

Bandfortschritt und Zielreservierung werden logisch geführt; Clients zeigen die Bewegung. Ein voller Puffer stoppt die Zufuhr. Die erste Version arbeitet mit festen Stellplätzen und einer festen Verbindung.

Gespeichert werden Schema-Version, Profilrevision, Sitzung, Geld, Rezepte, Maschinen, Personal, Layout, Fahrzeugladung und logische Waren. Pfade und Animationen werden neu aufgebaut. `UpdateAsync` unterstützt Änderungen an einem Schlüssel; Sitzungsmanagement und Fehlerbehandlung bleiben zusätzlich nötig. [S6]

Bei einem Ladefehler darf kein leerer Standardstand über den bestehenden Speicherstand geschrieben werden. Bei unklarem Save bleiben Verkäufe und Rebirth gesperrt. Nach einem Absturz gilt der letzte bestätigte Stand; absolute Verlustfreiheit wird nicht versprochen.

### Physische Verkäufe und einmaliger Privatpreis

Auszahlung benötigt passende Käuferzone, reservierte Fracht und bestätigte Entladung. Position und Berührungen allein genügen nicht; auch der Fahrtverlauf muss plausibel sein. Fernverkauf entfällt. Beim Privatverkauf wird der Betrag einmal pro verbindlicher Verkaufs-ID bestimmt und mit der reservierten Ware festgehalten. Schreibwiederholungen verwenden denselben Betrag. Warenabgang, Gutschrift und Abschluss werden im selben Profil aktualisiert. Ein unklarer Schreibausgang wird zuerst geprüft. Wiederbeitritt setzt das vorhandene Ergebnis fort; Rebirth wartet auf dessen Abschluss.

### Leistungsgrenzen werden gemessen

Keine Physiksimulation jedes Holzstücks als Wirtschaftssystem. Sichtbare Waren werden begrenzt und wiederverwendet. Plot-, NPC- und Produktmengen ergeben sich aus Tests auf vereinbarten echten Geräten. Streaming und lokale Modellverfügbarkeit müssen berücksichtigt werden. Ein Emulator allein ersetzt diese Messungen nicht. [S7, S8]

---

## 11. Erste spielbare Version und Umfang

### Stufe A: Spiel- und Art-Nachweis

Eine Werkstatt, ein Hockerrezept, Holz, vier Stationen einschließlich Verpackung und ein Fertigwarenlager. Ein Quad mit kleinem Anhänger fährt zwischen Lieferant, Fabrik, Händler und einem Privatkundenplatz. Der Spieler produziert ohne Kundenauftrag, lädt sichtbar und verkauft erst am Ziel. Händlerpreis und privater Zufallserlös werden beide geprüft. Danach erlebt er einen NPC-Transport und eine gerade Bandverbindung in der Fabrik.

Diese Automationsstufen werden für die Prüfung beschleunigt freigeschaltet oder als getrennte Teststände bereitgestellt. Das ist ein Testaufbau, keine Festlegung des späteren Tempos. Die gemeinsame Muster-Szene aus Kapitel 9 prüft parallel den Look.

**Bestandteil von Stufe A:** klare Interaktionen, Ladeplätze, Lager- und Stationsstatus, Verkaufsabrechnung, Wiederanlauf und Save/Load. Geprüft werden volle Lager, parallele Übergaben, Fahrten, Entladung und Abbruch eines Privatverkaufs.

### Stufe B: erste Managemententscheidung

Nach bestandenem Kernnachweis kommt ein Beistelltisch hinzu. Beide Produkte teilen eine begrenzte Station und unterscheiden sich in Material, Kapazitätsbedarf, Ladeplatz oder Verkaufswert. Der Spieler entscheidet über Produktmix, Losgröße, Lager und die nächste Verkaufstour.

Hier prüfen wir, ob nach Automation freiwillig eine neue Betriebsentscheidung entsteht. Erst danach lohnt sich eine weitere Möbelserie.

### Stufe C: langfristiger Nachweis

Ein neuer Fertigungszweig und die Rebirth-Vorschau werden erst nach Stufe B konkret erprobt. Reset und Wiederaufbau benötigen sichere Speicherung und den Test der Wiederanlaufhilfe. Danach folgen zusätzliche Räume, Varianten und umfangreichere Logistik.

### Bewusst später

Freie Bandnetze, beliebig verschiebbare Maschinen, komplette Sofaproduktion, große Stadt, zusätzliche Fahrzeugstufen, Transport-KI, eigener Showroom, Spielerhandel, Offline-Produktion und Robux-Käufe sind Erweiterungen. Das erste Fahrzeug und beide einfachen Verkaufswege gehören bereits zum Kernnachweis.

**Bau-Reihenfolge:** Bestände und Übergaben → manuelle Kette mit Lager → Quad und kurze Route → beide Verkaufswege → NPC und Band → Speichern und Fehlertests → zweites Rezept. Fehlerverhalten und Datenmodell werden von Anfang an mitgedacht. Art-Probe und Fahrzeug-/Ladungsmaßstab werden früh gemeinsam geprüft.

---

## 12. Prüfung, Risiken und Abbruchkriterien

Alle Werte unten sind **vorgeschlagene interne Prüfschwellen**. Es wurden noch keine Testpersonen beobachtet, Assets abgenommen oder Leistungswerte gemessen. Fünf Personen liefern frühe Hinweise, keine Aussage über Markterfolg.

| Gate | Vorgeschlagener Nachweis |
|---|---|
| G1 - Einstieg | Vier von fünf neuen Personen produzieren das erste Möbel ohne Kundenauftrag, finden Nachschub und verstehen das Fertiglager. |
| G2 - Freiwilligkeit | Mindestens drei setzen freiwillig die Produktion fort; Gründe für Abbruch oder Langeweile werden festgehalten. |
| G3 - Automation | Nach dem Band ändern mindestens drei selbst sinnvoll Rezept, Lager, Nachschub oder Verkaufszeitpunkt. Eine Pause darf bewusst gewählt sein. |
| G4 - Art | Die gemeinsame Szene besteht die Passungs- und Materialprüfung; der Nutzer akzeptiert anschließend den Look aus Spielkamera und Außenansicht. |
| G5 - Bestand | Doppelklicks, zwei Träger, volles Ziel, Abbruch und Wiederbeitritt erzeugen in definierten Wiederholungstests keine Zusatzware oder doppelte Zahlung. |
| G6 - Neustart | Personen können Gewinne und Verluste erklären; erster Zyklus ist nach Rebirth finanziert und der bekannte Einstieg messbar kürzer. |
| G7 - Verkauf | Händlerwert, private Spanne und bindende Übergabe werden verstanden. Gute und schlechte Ergebnisse sowie Wiederbeitritt zahlen eindeutig und nur einmal. |
| G8 - Fahrt | Die vollständige Tour mit sichtbarer Ladung gelingt. Ware erscheint erst nach tatsächlichem Transport im Ziellager; Auszahlung folgt erst nach Übergabe. |

### Weitere Pflichtprüfungen

Ladefehler und veraltete Serverstände dürfen keinen neueren Stand überschreiben. Volles Lager, Rezeptwechsel und Rohstoffmangel stoppen die Linie verständlich. Fehlkäufe und schlechte Privatverkäufe brauchen eine begrenzte, nicht ausnutzbare Wiederanlaufhilfe.

Ein tatsächliches schwächeres Referenzgerät wird festgelegt. Darauf werden Tragen, Ablage, Statusanzeigen und spätere begrenzte Mehrplot-Last geprüft. Erst die Messung bestimmt zulässige NPC-, Waren- und Plotmengen; derzeit gibt es kein Leistungsversprechen.

### Konsequenzen bei Scheitern

Bei unklarem Einstieg werden Wege, Hinweise und Chargengrößen überarbeitet. Bei Leerlauf nach Automation werden Produktwahl und Kapazitätsentscheidung geprüft. Bei Art-Mängeln bleiben Proportionen und Anschlüsse im Fokus. Weitere Möbel werden erst nach dem jeweiligen Nachweis ergänzt.

Nach zwei gezielten Überarbeitungen desselben Ausschnitts prüft das Council einen grundlegenden Richtungswechsel, falls weiterhin nur Laufarbeit, passives Warten oder ein unbefriedigender Look übrigbleiben. Technische Duplikate und unsicheres Laden sind Freigabeblocker.

---

## 13. Council-Debatte und Entscheidungen

### Einwand: Automation schafft das Spiel ab

Der Skeptiker hält dies für das größte Risiko. Der Verteidiger betont dagegen, dass Entlastung und zeitweise Ruhe Teil der Belohnung sein dürfen. Spielerlebnis verlangt echte Anschlussentscheidungen. In Fassung 1.1 entstehen sie aus Produktmix, Lagerbestand, Transportkapazität und Verkaufsweg.

**Entscheidung:** Ruhe ist erlaubt. Wir prüfen freiwillige Weiterplanung und erlebte Kontrolle. Stufe B erhält dafür zwei Produkte mit einer sichtbaren gemeinsamen Engstelle. Ein Zwang zu ständigen Eingaben wird nicht vorausgesetzt.

### Einwand: Eine Innenecke beweist keine gute Architektur

Art Direction widersprach dem zunächst kleineren Vorschlag des Verteidigers. Das beschriebene Dachproblem bleibt an einer reinen Innenraumszene unsichtbar.

**Entscheidung:** Die Muster-Szene enthält zusätzlich eine kleine Außenkante mit Wand, Fenster und Dach. Es wird dafür noch keine vollständige Map gebaut.

### Einwand: Ein Grundrezept prüft keine Managementtiefe

Der Verteidiger startete mit einem Hocker und einem Arbeiter. Technik und Skeptiker forderten auch eine Bandprobe, weil sie zum zentralen Versprechen gehört. Ein zweites Produkt würde den allerersten Nachweis vergrößern.

**Entscheidung:** Stufe A prüft Hocker, Hand, NPC und Band; Stufe B ergänzt den Beistelltisch. Der Umfang bleibt gestuft, alle drei Automationsarten werden tatsächlich geprüft.

### Einwand: Layout behalten reicht beim Rebirth nicht

Spielerlebnis und Skeptiker verlangen eine echte Wiederanlaufhilfe. Der Verteidiger übernimmt diese Korrektur.

**Entscheidung:** Rezepte, Designs und Baupläne bleiben. Das Starterpaket finanziert die Grundstationen, Material für einen Zyklus und einen Transporthelfer. Vor dem Reset werden Verlust und Gewinn konkret aufgelistet.

### Voten zur ursprünglichen Council-Fassung

| Mitglied | Urteil und Grenze |
|---|---|
| Skeptiker | Bedingtes Go für den gestuften Prototyp; kein Go für Gesamtproduktion. Freiwillige Entscheidungen nach Automation bleiben sein Veto. |
| Verteidiger | Go für zwei Prüfstufen; produktive Ruhe darf bestehen. Wiederaufbauhilfe und echte Fertigungsunterschiede sind erforderlich. |
| Technik | Bedingtes Go; Bestandskonsistenz, sichere Übergaben und geschütztes Laden sind Freigabegrenzen. |
| Art Direction | Go für die gemeinsame Muster-Szene; Serienproduktion erst nach Passungs-, Spielkamera- und Technikprüfung. |
| Spielerlebnis | Bedingtes Go; ein verständlicher Anfang und sinnvolle, freiwillige Weiterplanung müssen nachgewiesen werden. |

Das Council empfiehlt damit einen Prüfauftrag, keine vorweggenommene Erfolgserklärung. Die Gegenreden bleiben in den Einzelreviews erhalten.

---

## 14. Offene Fragen und nächste Schritte

### Vor Beginn der Umsetzung entscheiden

1. **Look:** Wie stark stilisiert soll die Werkstatt sein? Zwei bis drei konkrete Möbel- und Gebäudereferenzen auswählen und die gemeinsame Probe daran ausrichten.
2. **Shop:** Sind Ausrüstungskauf, begehbarer Möbelverkauf oder Robux-Angebote gemeint? Die drei Systeme getrennt priorisieren.
3. **Geräte:** Welche echten Geräte müssen funktionieren? Daraus Eingabe- und Leistungstests ableiten.
4. **Platzierung:** Feste Slots sind der Prototyp-Vorschlag. Späteres freies Bauen als eigene Entscheidung behandeln.
5. **Rebirth:** Wie viel des vorhandenen Betriebs soll aufgegeben werden? Verlustliste und Starterpaket gemeinsam festlegen.
6. **Privatpreis:** Auszahlungsspanne, Wahrscheinlichkeiten und Ziehung pro Stück oder Verkaufscharge abstimmen. Händlervergleich und bindende Übergabe müssen verständlich sein.
7. **Fahrzeuglogistik:** Anhänger, sichtbare Ladeplätze, Route und spätere Fahrzeuggrößen dimensionieren. Wer später fahren kann, bleibt offen.

### Konkretes nächstes Arbeitspaket

Zuerst wird die Hockerlinie mit Inputs, Ausgängen, Lager und Transportformaten festgelegt. Parallel entstehen Referenzwahl und Maßstabstest für Hocker, Station, Tür, Quad-Anhänger und Gebäudeecke. Danach folgen Art-Probe, Handkette und die kompakte Fahrzeugroute mit beiden Verkaufswegen.

Nach den ersten Prüfungen werden Mitarbeiter und feste Bandverbindung ergänzt. Anschließend folgt das zweite Möbel als gezielter Test von Produktmix, Lagerplatz und Transportkapazität. Die Entscheidungen werden an beobachteten Problemen korrigiert.

### Noch nicht behauptet oder geleistet

Es gibt durch dieses Dokument keine implementierte Fabrik, keine neuen Blender-Assets und keine bestandenen Roblox-Import-, Mobile-, Sicherheits- oder Speichertests. Alte Assets wurden nicht angesehen. Ihre Probleme wurden anhand der Nutzerbeschreibung in die Abnahmekriterien übersetzt.

Zeitplan, Teamkapazität und Budget sind nicht bekannt. Eine belastbare Aufwands- oder Einnahmenschätzung wäre deshalb verfrüht. Das Dokument ist als fertige Konzeptfassung nutzbar; die genannten Produktentscheidungen bleiben bewusst überprüfbare Vorschläge.

---

## 15. Quellen und Evidenzgrenzen

Offizielle Roblox-Dokumentation wurde am 6. November 2026 als Grundlage herangezogen. Sie belegt technische Funktionen und Grundsätze. Rezepte, Fortschritt, Palette, Testschwellen und Council-Voten sind eigene Entwurfsentscheidungen.

- **[S1] Modulare Umgebungen:** [Assemble modular environments](https://create.roblox.com/docs/tutorials/use-case-tutorials/modeling/assemble-modular-environments). Raster, Drehpunkte und zusammenpassende Module.
- **[S2] Mesh-Vorgaben:** [General specifications](https://create.roblox.com/docs/art/modeling/specifications). Technische Anforderungen vor dem Import; aktuelle Werte vor der Assetproduktion erneut prüfen.
- **[S3] Physik und Vertrauen:** [Network ownership](https://create.roblox.com/docs/scripting/security/network-ownership). Risiken clientgesteuerter Physik.
- **[S4] Serverseitige Prüfung:** [Client-server boundary](https://create.roblox.com/docs/scripting/security/client-server-boundary). Prüfung von Kontext, Berechtigungen, Eingaben und Aktionshäufigkeit.
- **[S5] Mitarbeiterwege:** [Pathfinding](https://create.roblox.com/docs/characters/pathfinding). Navigation und Umgang mit blockierten Wegen.
- **[S6] Speicherung:** [Data stores](https://create.roblox.com/docs/cloud-services/data-stores). Serverseitige Speicherung, Fehlerbehandlung und Aktualisierung eines Schlüssels.
- **[S7] Leistungsplanung:** [Design for performance](https://create.roblox.com/docs/performance-optimization/design). Messungen und Gerätebezug für die Leistungsplanung.
- **[S8] Weltverfügbarkeit:** [Instance streaming](https://create.roblox.com/docs/workspace/streaming). Nachladen von Weltinhalten und Konsequenzen für lokale Referenzen.

### Council-Unterlagen

- council/01_skeptiker.md
- council/02_verteidiger.md
- council/03_technik.md
- council/04_art_direction.md
- council/05_spielerlebnis.md
- council/06_nachtrag_dauerproduktion.md

Die ersten fünf Dateien enthalten Rollenbewertungen und Gegenreden zur ursprünglichen Fassung. Datei 06 dokumentiert die spätere Änderung zu Dauerproduktion, Privatverkauf und Fahrzeugtransport. Die technischen und gestalterischen Ergänzungen wurden in den Haupttext eingearbeitet. Fassung 1.0 liegt unverändert im Unterordner history/.

### Grenzen der Aussage

Es wurde kein Marktvergleich mit veröffentlichten Spielen durchgeführt. Das erwähnte Clothing-Spiel wurde nicht identifiziert oder analysiert. Aus seiner Beschreibung übernehmen wir den gewünschten interaktiven Produktionsablauf. Für dieses Projekt liegen keine eigenen Nutzungsdaten vor. Begriffe wie Go, Gate und MVP bezeichnen interne Entscheidungen und geplante Prüfungen.
