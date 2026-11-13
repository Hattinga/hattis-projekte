# Start und Musterprobe

Dieser Abschnitt führt von der Projektumgebung bis zur abgenommenen Musterprobe. Der [Spielkern](../design/CORE.md) enthält die verbindlichen Spielregeln. Aufgabenstand und Evidenz werden nach [STATUS](../workflow/STATUS.md) geführt.

## P00 · Umgebung und Arbeitsstand

**Abhängigkeit.** Startpaket.

- [x] **P00-01** Studio-Ziel und Bearbeitungsweg festlegen. Test-Place mit Name, eindeutiger Kennung oder lokalem Pfad sowie dem vorgesehenen Bearbeitungsweg dokumentieren. Erreichbarkeit prüfen und den Ort für spätere Import- und Spieltests festhalten. Abgenommen, wenn sich der richtige Teststand eindeutig öffnen lässt.
- [x] **P00-02** Git-Stand und führende Quelle pro Artefakt festlegen. Arbeitszweig, Ausgangscommit und Zuständigkeit für Skripte, Place und Assetquellen eintragen. Einen separaten Snapshot des Ausgangs-Place mit Datum und Versionsbezug sichern. Abgenommen, wenn Snapshot und Wiederherstellungsweg auffindbar sind und die Quelle für jede Änderung eindeutig ist.
- [ ] **P00-03** Ein tatsächlich verfügbares schwächeres Testgerät bestimmen. Gerät, Eingabeart, Auflösung und Grafikstufe festhalten. Abgenommen, wenn die geplanten Lesbarkeits- und Fahrtests auf diesem Gerät reproduzierbar durchgeführt werden können.
- [x] **P00-04** Evidenzorte nach [STATUS](../workflow/STATUS.md) eintragen. Für Art-Ansichten, kurze Fahrvideos und Testprotokolle je Ablage und Zuordnung zur Aufgaben-ID festlegen. Abgenommen, wenn ein fremder Bearbeiter den Stand, das Prüfergebnis und die zugehörige Aufnahme zusammenfindet.

Beleg fuer P00-01, P00-02 und P00-04: [Studio-Einrichtung](../evidence/P00-STUDIO-SETUP.md). P00-03 bleibt offen.

## P01 · Rezept, Übergaben und Maßvertrag

**Abhängigkeit.** P00.

- [x] **P01-01** Das Hockerrezept als nachvollziehbare Tabelle festhalten. Rohstoffmengen, Zwischenprodukte, Ausgabe, Verarbeitungsdauer und vorläufige Puffergrenzen je Schritt benennen. Abgenommen, wenn sich eine vollständige Charge vom Holzpaket bis zum Hockerkarton ohne fehlende oder zusätzliche Einheiten nachvollziehen lässt.
- [x] **P01-02** Säge, Montagebank, Finishplatz und Packtisch beschreiben. Je Station Ein- und Ausgang, Ablagefläche, zulässigen Warenzustand und sichtbare Rückmeldung festlegen. Abgenommen, wenn Stationen und Ware eindeutig zusammenpassen und Hand, Personal sowie Band denselben Übergabepunkt verwenden können.
- [x] **P01-03** Warenzustände und Träger zuordnen. Holzpaket, offener Bausatzträger, montierter Rohhocker, fertiger Hocker und geschlossener Karton erhalten je Darstellung, Außenmaße, Bezugspunkt und zulässige Transportarten. Abgenommen, wenn eine Charge über alle Zustände erkennbar bleibt und Behälter samt Inhalt zusammenpassen.
- [x] **P01-04** Die Verladekette zeichnen. Lieferantenabholung, Fahrzeugladeplatz, Fabrikablage, Fertiglager und beide Verkaufsübergaben als getrennte Orte markieren. Abgenommen, wenn jedes Verladen und Entladen Quelle, Ziel und zulässige Menge besitzt und die Auszahlung erst der tatsächlich erfolgten Übergabe folgt.
- [x] **P01-05** Das gemeinsame Maßblatt anlegen. Avatar, Hocker, Stationen, Trays, Karton, Quad, Anhänger, Tor und Fahrkorridor in einer Ansicht vergleichen. Raster, Einheiten, Bezugspunkte und geplanten Importmaßstab festhalten. Abgenommen, wenn sich Ladehöhe, Durchfahrt, Werkstückauflage und Dachanschluss aus den Angaben prüfen lassen.
- [x] **P01-06** Stoppfälle mit erwarteter Rückmeldung beschreiben. Volle Puffer, falsche Ware, fehlender Nachschub und Rezeptwechsel erhalten je erwarteten Stationszustand und nächsten möglichen Handgriff. Abgenommen, wenn Ware bei jeder beschriebenen Unterbrechung einen eindeutigen, sichtbaren Aufenthaltsort behält.

Rezept und Stationsvertrag für P01-01/P01-02: [PRODUCTION](../design/PRODUCTION.md), [erster Papierbeleg](../evidence/P01-01-02.md). [Maßvertrag](../design/DIMENSIONS.md), [Verladekette](../design/LOGISTICS.md) und Stoppfälle ergänzen die Phase. Die [abschließende Papierabnahme P01-03 bis P01-06](../evidence/P01-03-06.md) bestätigt auch QA-P01-01; Spiel-, Fahr- und Artprüfungen bleiben offen.

## P02 · Begehbare und befahrbare Greybox

**Abhängigkeit.** P01. P02 und P03 können parallel beginnen.

- [x] **P02-01** Im festgelegten Test-Place Boden, Wege und Maßraster mit einfachen Stellvertretern abstecken. Avatarmaß und Toröffnung aus P01 übernehmen. Abgenommen, wenn die Greybox im vereinbarten Maßstab liegt und der passende Teststand im Status verlinkt ist.
- [ ] **P02-02** Vier Stationen sowie Rohstoff- und Fertiglager aufstellen. Eingänge, Ausgänge und Übergabeflächen für Hand, Mitarbeiter und das erste gerade Band markieren. Abgenommen, wenn ein Spieler die vollständige Folge mit einem Werkstückstellvertreter in sinnvoller Reihenfolge ablaufen kann.
- [x] **P02-03** Lieferant, Fabrik, Händler und Privatkundenplatz über einen kurzen Rundkurs verbinden. Ladeplätze, Einfahrten und Wendeflächen an den jeweiligen Zielen markieren. Abgenommen, wenn jedes Ziel über eine zusammenhängende Straße erreichbar ist und ein Rückweg zur Fabrik besteht.
- [x] **P02-03R** Den Kartenentwurf gemäß Nutzerklärung als organisch gewachsene Stadt ohne Spiegelung überarbeiten. Mehrere Tischlereien, Wohnviertel, Gewerbe, Läden und Lieferhöfe in einen glaubwürdigen Grundriss mit Haupt-/Nebenstraßen einordnen. Abgenommen, wenn die Stadtwirkung, verteilten Standorte und Warenwege im neuen Grundriss nachvollziehbar sind. Die vorhandene Ring-Greybox ist nur der frühere technische Nachweis; die Stadtüberarbeitung hat Vorrang vor P02-04.
- [x] **P02-04** Quad und Anhänger für den Fahrtest durch einen lenkbaren Stellvertreter mit passenden Außenmaßen darstellen. Holzpaket und Hockerkarton auf der Ladefläche platzieren. Abgenommen, wenn Ladefläche, Anhängerkupplung, Fahrzeughülle und Last als räumliche Einheit geprüft werden können.
- [x] **P02-05** Die beladene Strecke abfahren. Engste Kurve, Tor, Ladehöhe und Wendemanöver beobachten und Blockaden beheben. Abgenommen, wenn der Stellvertreter alle vier Orte über die Straße erreicht und der Avatar an jeder Übergabe mit Ware Platz hat.
- [ ] **P02-06** Grundriss und Fahrnachweis sichern. Ein beschrifteter Übersichtsstand zeigt Stationsfolge, Lagerslots und Straßenroute. Eine Aufnahme dokumentiert die Fahrt mit sichtbarer Last. Abgenommen, wenn daraus die räumlichen Vorgaben für P03 und die spätere Integration hervorgehen.

[P02-01-Beleg](../evidence/P02-01.md): Maßraster, Referenzhüllen und unabhängige Fußprobe bestanden; Test-Place als Version 7 gespeichert. Stationsfolge und Fahrprüfung bleiben offen. Der vorhandene Spawn schneidet die Sollanfahrt und muss vor der Fahrfreigabe berücksichtigt werden.

[P02-03-Beleg](../evidence/P02-03.md): eigenständige Spielkarte mit vier angeschlossenen Zielen, Grundstücken und neuer Hallenprobe als Version 10 gespeichert; Spawn auf das echte Fabrikgrundstück versetzt. Vergleichswerkstatt und Stationsfeld sind nur Testobjekte. Nutzerpriorität ist das Mapdesign; die separate Trageabnahme P02-02 bleibt offen. Fahrzeugfahrt folgt in P02-04/P02-05.

[P02-03R-Beleg](../evidence/P02-03R.md): neue Stadtfassung mit 19 Straßen/Zufahrten, vier verteilten Tischlereien und 47 Gebäudeplatzhaltern; Graph, Gehwege und Spieleinstieg geprüft, Version 12 gespeichert. Die Ringfassung ist archiviert. Finale Art und Fahrzeugfahrten sind noch nicht abgenommen.

[P02-04-Beleg](../evidence/P02-04.md): lenkbarer Quad-/Anhänger-Stellvertreter `Workspace.P02Vehicle` mit zwei Slots, Holzpaket und Hockerkarton; Hüllen, Deck, Kupplung und Last gemessen, kurze Fahrprobe mit und ohne Fahrer bestanden, Version 17 gespeichert. Stadtstrecke, Tor, Kurven und Wenden folgen in P02-05.

[P02-05-Beleg](../evidence/P02-05.md): automatische beladene Fahrt zu Lieferant, Händler, Privatkunden und zurück ohne Blockade; Avatar mit Ware hat an allen vier Orten Platz am Anhänger; Wendekreis 6,9–7,2 m Wand zu Wand. Tordurchfahrt mit Kehre in der Halle nur mit schrägem Anlauf. Handgefahrene Runde steht aus.

## P03 · Art-Muster im Test-Place

**Abhängigkeit.** P01 und zugänglicher Test-Place aus P00. P02 liefert zusätzliche Maße für die gemeinsame Integration. Maßstab und Gestaltung richten sich nach [ART](../design/ART.md).

- [ ] **P03-01** Referenzblatt für Hocker, Säge und Gebäudeecke erstellen. Proportionen, Werkstoff, Anschlussart und entscheidende Maße markieren. Abgenommen, wenn jede sichtbare Hauptform und Verbindung auf eine Referenz oder eine dokumentierte gestalterische Entscheidung zurückgeht.
- [ ] **P03-02** Hocker und Säge als Muster ausarbeiten. Hockerbauteile, Rohmontage und Finish zeigen, Säge mit glaubwürdiger Auflage sowie verständlichem Ein- und Ausgang bauen. Abgenommen, wenn das Werkstück im Maßstab zur Maschine passt und die Zustände aus Spielentfernung erkennbar sind.
- [ ] **P03-03** Wand, Fenster und Dach als kleine Außenprobe ausarbeiten. Wandstärke, Rahmen, Dachauflager, First, Traufe und Überstand am Referenzblatt prüfen. Abgenommen, wenn Dach und Wand in Seitenansicht, Nahaufnahme und Dreiviertelansicht sauber aufeinander treffen.
- [ ] **P03-04** Quad und Anhänger gemeinsam mit Avatar, Hockerkarton und Tor prüfen. Maßgerechte Stellvertreter nach P01 verwenden und Ladefläche, Lastbegrenzung und sichtbare Befestigung zeigen. Abgenommen, wenn der Karton aufliegt, die Last ins Fahrzeugprofil passt und das beladene Gespann durch das Tor kommt.
- [ ] **P03-05** Quelldatei, Export und Übergabehinweise gemäß [Blender-Rolle](../roles/BLENDER.md) ablegen. Zuständige Studio-Rolle importiert die Probe in den Test-Place und kontrolliert Maße, Drehpunkte, Materialien und Kollision. Abgenommen, wenn die dokumentierten Werte in Roblox nachvollziehbar sind.
- [ ] **P03-06** In Roblox neutrale Nahaufnahmen, normale Spielkamera, Außenansicht und kleine Bildschirmansicht aufnehmen. Dachanschluss, Hockerverbindung, Maschinenauflage und Fahrzeugladung in der Evidenz benennen. Abgenommen, wenn jede kritische Passung am importierten Modell beurteilt werden kann.
- [ ] **P03-07** Art-Abnahme mit den Kriterien aus [ART](../design/ART.md) protokollieren. Beanstandete Passungen am Muster korrigieren und betroffene Ansichten erneut prüfen. Abgenommen, wenn die gemeinsame Wirkung in Roblox freigegeben ist. Diese Freigabe ist Voraussetzung für die Assetserie in der [Prototypabnahme](03-prototyp-abnahme.md).
