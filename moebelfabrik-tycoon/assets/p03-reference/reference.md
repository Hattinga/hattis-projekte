# P03-01 · Technisches Referenzblatt

13. November 2026 · lokales Übergabepaket v0.1 · **Gestaltungsvorschlag, noch keine Art-Freigabe**

[Zeichnung](reference.svg) · [ausgeführte Prüfungen](checks.json)

Das Paket bereitet Fables Modellierungsbriefing für Hocker, Säge und eine neue Gebäudeecke vor. Es enthält keine finalen Modelle, keinen Export und keine Änderung an Studio, Blender, Plan oder Status. Der Lead übernimmt die geprüften Artefakte. Fable bleibt für wichtige Assets bevorzugt; Codex liefert dieses Briefing und die technische Prüfung.

## Quellen und Entscheidungskennzeichnung

| Kennung | Quelle / Verbindlichkeit |
| --- | --- |
| V1 | [DIMENSIONS](../../docs/design/DIMENSIONS.md), P01-03/P01-05: Einheiten, Achsen, Hüllen, Hocker-Einzelteile, Packlage und Stationsauflagen. Bestehender lokaler Maßvertrag. |
| V2 | [ART](../../docs/design/ART.md): glaubwürdige leicht stilisierte Tischlerei, Palette, sichtbare Anschlüsse, konsistente Maserung, Fable-Präferenz und Prüfung erst nach Import. Bestehende Gestaltungsrichtung. |
| V3 | [P02-06](../../docs/evidence/P02-06.md), räumliche Vorgaben: Stationen/Waren unverändert; FableWorkshop nur Vergleich; Hallentor/Halle offen. Maßübergabe, keine Art-Freigabe. |
| V4 | [P03](../../docs/plan/00-start.md#p03--art-muster-im-test-place), insbesondere P03-01: Hauptformen und Verbindungen nachvollziehbar kennzeichnen. |
| D-H / D-S / D-G | In diesem Blatt neu vorgeschlagene Gestaltung für Hocker, Säge und Gebäudeecke. Diese Entscheidungen sind keine vorhandenen Quellenwerte und benötigen Übernahme durch den Lead bzw. die Art-Abnahme. |

Es wurden keine externen Bildreferenzen und keine Webquellen verwendet. Maßverträge stammen ausschließlich aus den obigen Projektdateien. Alles darüber hinaus wird als D-Entscheidung benannt. Die Dach- und Tormaße der kleinen FableWorkshop werden **nicht** für das neue Gebäude verwendet. Der ältere Offen-Vermerk zu P02-02 im P02-06-Beleg ist durch den aktuellen STATUS überholt; dieses Paket führt keinen neuen Raumtest aus.

## Einheiten, Ansichten und Übergabe

Führend: Meter, Außenmaße **X × Y × Z**. Faktor **25/7 Studs/m**, genau einmal anwenden. 1-m-Prüfkörper nach Import: **3,571429 Studs**. Grobraster 0,05 m, Detailraster 0,005 m; kleinere Fasen und Metallstärken sind ausdrücklich bemaßte Materialdetails innerhalb bestehender Hüllen.

Roblox: +Y oben, -Z markierte Vorderseite. Blender: Meter, +Z oben; Zuordnung **(Blender X,Y,Z) → (Roblox X,Z,-Y)**. Alle folgenden Koordinaten sind Roblox-Zielkoordinaten in Metern. Die SVG benutzt orthogonale Ansichten sowie eine als schematisch gekennzeichnete Raumansicht; die Maßzahlen führen. Unterschiedliche Ansichtsmaßstäbe sind jeweils angegeben.

| Asset | Pivot und Orientierung | Nennhülle m | Sollhülle Studs |
| --- | --- | --- | --- |
| Hocker01 | (0;0;0), Mitte der Fußaufstandsebene; Front -Z | 0,40 × 0,45 × 0,40 | 1,429 × 1,607 × 1,429 |
| Saege01 | (0;0;0), Mitte der Stationsgrundfläche; Bedienseite -Z; Fluss -X → +X | 2,40 × 1,45 × 0,80 | 8,571 × 5,179 × 2,857 |
| Gebaeudeecke01 | (0;0;0), äußere vordere linke Wandecke am Boden; Front -Z, Gebäude längs +Z | 5,40 × 4,50 × 3,50 inklusive Dach | 19,286 × 16,071 × 12,500 |

Der Architekturpivot ist eine neue modulare Eckentscheidung D-G0; er folgt nicht dem Warenpivot. Der Gebäude-Grundkörper beginnt bei X/Z = 0; das Dach überragt ihn in negative X/Z. Der Maschinenpivot ist kein Transferpunkt. Transferpunkte bleiben (-0,80;0,90;0), (0;0,90;0), (+0,80;0,90;0). Keine Ware wird für eine Ansicht oder einen Transfer skaliert.

Für die spätere Modellübergabe benötigt: bearbeitbare Quelle, getrennte Modellnamen, Einheiten und Materialslots, neutrale Gesamtansichten, Front/Seite/Draufsicht, Dreiviertel, Anschlussdetails und einen 1-m-Prüfkörper. P03-05/06 prüfen Import, Pivot, Normalen, Material und Kollision am tatsächlichen Modell; hier ist davon nichts als bestanden markiert.

## Hocker01 · neun Holzteile, vier Beine

### Hauptformen und lokale Maßverträge

| ID | Hauptform | Menge und Lage | Herkunft |
| --- | --- | --- | --- |
| H1 | Sitzplatte | 1 × 0,40 × 0,025 × 0,40; X/Z ±0,20; Y 0,425…0,450 | V1 |
| H2 | Gerade Beine | 4 × 0,035 × 0,425 × 0,035; Mittelpunkte X/Z jeweils ±0,1625; Y 0…0,425 | V1 |
| H3 | X-Zargen | 2 × 0,29 × 0,06 × 0,02; X ±0,145; Y 0,30…0,36; Z-Mitte ±0,1625 | V1; Achslage konkretisiert |
| H4 | Z-Zargen | 2 × 0,02 × 0,06 × 0,29; X-Mitte ±0,1625; Y 0,30…0,36; Z ±0,145 | V1; um 90° gedreht |
| H5 | Kantenbehandlung | Maximal 0,001 m abtragende Fase; keine neuen überstehenden Wülste, kein Spreizen der Beine | D-H1, innerhalb V1 |

**Holzanzahl: 1 + 4 + 2 + 2 = 9.** Metallverbindungen sind keine zusätzlichen Holzteile. Rohhocker und Finish verwenden dieselben Positionen, dieselbe Topologie und dieselbe Hülle.

### Anschlüsse

| ID | Verbindung | Ausführung und sichtbarer Nachweis | Herkunft |
| --- | --- | --- | --- |
| HJ1 | Sitz ↔ vier Beinköpfe | Beinkopf bei Y=0,425 liegt flächig an der Sitzunterseite an; keine Luft. Pro Bein ein versenkter Schraubkopf Ø0,010 an der Sitzoberseite bei X/Z=±0,1625, Schaft Ø0,005, Länge 0,060 nach unten. Oberkante bündig, vollständig innerhalb Holz. | Kontakt V1; Schraublösung D-H2 |
| HJ2 | Zarge ↔ Bein | Stirnflächen der 0,29-m-Zargen stoßen ohne offene Fuge an die Beininnenseiten. Pro Zargenende eine versenkte Schraube Ø0,005 × 0,060, Kopf Ø0,010 auf der äußeren Beinfläche. X-Zargen: Schraubachse X bei Y=0,315; Z-Zargen: Achse Z bei Y=0,345. 0,030 m Höhenversatz vermeidet Kreuzung der Schrauben. Leimstoß als geschlossene Kontaktfläche; sichtbare Materialkante, keine künstliche Spalte. | Kontakt V1; Verbindung D-H3 |
| HJ3 | Oberflächen | Roh: helles mattes Holz. Finish: gleicher Hocker, wärmerer ruhiger Farbton und etwas klarere Kante. Stufenschild und geometrisches Symbol innerhalb der Hülle, ohne neuen Handgriff. | Richtung V2; genaue Farbabstimmung D-H4 |

Schrauben beginnen bündig auf der äußeren Fläche und reichen in die Zarge bzw. den Beinkopf. Sitzschrauben enden bei Y=0,390, über den Zargen; die beiden waagrechten Schraubfamilien liegen bei Y=0,315 bzw. 0,345. Es gibt keine herausstehenden Verbindungsteile, keine angesetzten Holzdübel und keine Verlängerung der Nennzargen. Das ist der vorgeschlagene sichtbare Anschluss für das Spielmodell, kein bereits modelliertes oder statisch geprüftes Möbel.

### Warenhüllen und Packlage bleiben unverändert

| Zustand | Außenmaß m | Unveränderliche Passung |
| --- | --- | --- |
| Holzpaket | 0,60 × 0,15 × 0,45 | innen 0,58 × 0,13 × 0,43; Holzgrundriss 0,57 × 0,425 |
| Offener Träger | 0,60 × 0,18 × 0,50 | Boden 0,01; nutzbar 0,58 × 0,48; niedriger Rand Y=0,03; offene Griffe bis Y=0,18 |
| Roh/Finish-Hocker | 0,40 × 0,45 × 0,40 | kein Größenwechsel zwischen den Zuständen |
| Karton | 0,46 × 0,51 × 0,46 | innen 0,44 × 0,49 × 0,44; Hockerunterseite Y=0,03, allseitig 0,02 Luft zur Innenhülle |

Packlage V1, unverändert: Sitz X=-0,285…+0,115, Z=±0,20, Y=0,01…0,035. Beine längs Z=±0,2125, X-Unterkanten 0,130/0,170/0,210/0,250, Breite 0,035, Y=0,01…0,045. Zargen auf Sitz: X=-0,225…+0,065, Z-Mitten -0,105/-0,035/+0,035/+0,105, Breite 0,06, Y=0,035…0,055. Keine Änderung an Trägergriffen oder Polsterzugaben.

**Konsistenzrechnung:** Gestell außen 2×0,1625+0,035=0,36; Sitzüberstand (0,40-0,36)/2=0,02. Beinzwischenraum 2×0,1625-0,035=0,29, genau Zargenlänge. Sitzhöhe 0,425+0,025=0,450. Karton: (0,44-0,40)/2=0,02 seitlich; untere Luft 0,03-0,01=0,02; obere Luft 0,50-(0,03+0,45)=0,02. Paketluft mindestens (0,58-0,57)/2=0,005 in X und (0,43-0,425)/2=0,0025 in Z.

**Benötigte Modellansichten:** Front und Seite für vier gerade Beine/Zargenhöhe, Draufsicht ohne und mit Sitz, Anschluss HJ1/HJ2, Roh/Finish nebeneinander sowie offener Träger mit allen neun erkennbaren Teilen. Von normaler Spielkamera müssen die Stufen auseinanderzuhalten sein.

## Saege01 · drei Auflagen, freier Übergabemodus

### Hauptformen

| ID | Hauptform / Raum | Maß und Lage m | Herkunft |
| --- | --- | --- | --- |
| S1 | Gesamthülle | X=-1,20…+1,20; Y=0…1,45; Z=-0,40…+0,40 | V1/V3 |
| S2 | Tisch, tragend | 2,40 × 0,08 × 0,80; Y=0,80…0,88 | D-S1, innerhalb V1 |
| S3 | Drei Auflageplatten | je 0,70 × 0,02 × 0,60, Y=0,88…0,90; Mitten X=-0,80/0/+0,80, Z=0 | Grundfläche/Höhe V1; Plattendicke D-S2 |
| S4 | Untergestell | Vier Füße 0,10 × 0,80 × 0,10; Mitten X=±1,10, Z=±0,35; Oberkante Y=0,80 am Tisch. Querstege unter Tisch, Querschnitt 0,06, vollständig Y≤0,80. | D-S3 |
| S5 | Motor-/Blattgehäuse | 0,50 × 0,45 × 0,40; X=±0,25, Y=0,35…0,80, Z=±0,20; oben am Tisch verschraubt | D-S4 |
| S6 | Sägeblatt, geparkt | Ø0,30, Dicke 0,005; Ebene XY, Mitte (0;0,62;0); Y=0,47…0,77. Im Gehäuse, unter Tisch. | D-S5 |
| S7 | Schutzhaube, geparkt | 0,38 × 0,45 × 0,08; X=±0,19, Y=0,95…1,40, Z=0,31…0,39. Untere Führungsstützen Y=0,90…0,95, ebenfalls Z≥0,31. | D-S6 |
| S8 | Hintere Leiste / Status | Hintere Stahlleiste Z=0,31…0,39; Bedien-/Statusplatte X=0,55…0,95, Y=1,05…1,45. Alles außerhalb der Auflagenprismen. | D-S7 |
| S9 | Warenfreiräume | Drei Prismen: je 0,70 × 0,55 × 0,60, von Y=0,90 bis 1,45, um die drei Auflagenmitten. **Keine feste Geometrie im Inneren.** | V1/V3 |

Diese Auswahl zeigt eine stationäre Säge mit zurückgezogenem Blatt und rückseitig geparkter Haube. Das Blatt ist im normalen Übergabebild verborgen; ein Gehäuseausschnitt bzw. die separate Detailansicht erklärt seine Lage. Die kleine Statusplatte erreicht die Hüllhöhe 1,45 m. Ein Statussymbol darf nicht auf Farbe allein beruhen.

### Verbindungen und Warenweg

| ID | Verbindung | Vorgeschlagene Darstellung | Herkunft |
| --- | --- | --- | --- |
| SJ1 | Füße ↔ Tisch / Querstege | Flächiger Kontakt bei Y=0,80; dunkle versenkte Schraubköpfe. Querstege schließen ohne schwebende Enden an Beine an. | D-S8 |
| SJ2 | Platten ↔ Tisch | Drei bündige, fest verschraubte Auflagen; Schraubköpfe nicht über Y=0,90. 0,10 m Zwischenraum, 0,05 m äußerer Rand. | Kontakt/Abstände V1; Schraubbild D-S9 |
| SJ3 | Motor ↔ Tisch / Blatt ↔ Welle | Gehäuseoberseite berührt Tischunterseite Y=0,80. Achse des Blatts entlang Z bei Y=0,62; separate Blattrotation im Modell möglich, aber keine Animation in P03-01. | D-S10 |
| SJ4 | Haube ↔ hintere Führung | Geparkte Haube ruht auf zwei Stützen, die direkt an der hinteren Leiste ansetzen; minimale Distanz zum freien Warenraum 0,01 m in Z. | D-S11 |
| SJ5 | Eingang → Prozess → Ausgang | -X nach +X; drei Pfeile und Symbole, Beschriftung EIN / PROZESS / AUS. Markierung flach bzw. eingelassen. Vorderseite -Z bleibt zugänglich. | Transferlage V1; Grafik D-S12 |

**Wichtige Abnahmegrenze:** Dieses Muster spezifiziert den freien **Übergabemodus**. Ein aktiver Schnitt mit Blatt-/Haubenbewegung, Verriegelung und notwendigem Freimachen der Prozessauflage ist noch nicht entworfen oder freigegeben. Fable soll hierfür getrennte Objektgruppen/Pivots vorbereiten, jedoch keine ungeprüfte Schutzeinheit in die feste Warenhülle stellen. P03-02 muss die konkrete Prozessdarstellung gesondert klären. Ein unveränderter beladener Träger darf nicht durch ein angehobenes Blatt gezeichnet werden.

**Konsistenzrechnung:** 3×0,70+2×0,10+2×0,05=2,40. Trägerreserve (0,70-0,60)/2=(0,60-0,50)/2=0,05. Kartonoberkante 0,90+0,51=1,41; Reserve 1,45-1,41=0,04. Blattoberkante 0,62+0,15=0,77; Abstand Tischunterseite 0,80-0,77=0,03. Hauben-Z-Minimum 0,31 minus Warenraum-Z-Maximum 0,30 =0,01. Kein Gehäuse, Ständer oder Schraubkopf ragt über die Auflage in das freie Prisma.

**Benötigte Modellansichten:** Front/Seite/Draufsicht im Übergabemodus; transparenter Freiraum mit Paket, Träger, Hocker und Karton jeweils einzeln auf jeder Auflage; Detail von SJ1/SJ3/SJ4; normale Spielkamera von -Z. Nach Import vor allem Y=0,90, Slotmitten und freien Raum messen. Kollisionshülle des Unterbaus endet spätestens an Y=0,90; sie darf nicht als voller Stationsquader bis 1,45 exportiert werden.

## Gebaeudeecke01 · eigenständige Außenprobe

**Neue D-G-Entscheidung:** Ein 3,00 m tiefer Gebäudebucht-Ausschnitt mit 4,80 m breitem Giebel, zwei tragenden Seitenwänden und einer Fensterfront; die Rückseite ist ein offener Prüfschnitt. Die linke vordere Ecke bildet das Anschlussdetail. Dies ist kein Entwurf der Start-Halle, keine Festlegung ihrer Tiefe und kein Entwurf eines Tors. Der Fensterbucht-Ausschnitt ersetzt weder die offene 4-m-Torfrage noch die Hallenkehre.

### Hauptformen und maßliche Festlegung

| ID | Hauptform | Festlegung m | Herkunft |
| --- | --- | --- | --- |
| G1 | Verputzte Wände | Wandstärke 0,24. Front: X=0…4,80, Z=0…0,24; Seiten: X=0…0,24 bzw. 4,56…4,80, Z=0,24…3,00. Rechteckiger Wandkörper Y=0…2,90. Kein überlappender Doppelblock in der Ecke. | D-G1 |
| G2 | Ring-/Wandplatte | Auflagerholz 0,24 breit, Y=2,90…3,00, flächig auf dem Wandkopf; Ecken bündig gestoßen. | D-G2 |
| G3 | Auflagerkeile und Giebelfüllung | Seitenkeile von Y=3,00 bis U(X); links X=0…0,24, rechts 4,56…4,80. Frontfüllung Y=3,00…U(X), z=0…0,24. Seitenkeile beginnen erst Z=0,24. | D-G3 |
| G4 | Sparrenpaare | Unterkante U(X)=4,26-0,50×abs(X-2,40); vertikale Tiefe 0,16, Breite entlang Z=0,08; Achsen Z=0,12/1,12/2,12/2,88. Zwei Hälften mit gemeinsamer Kontaktlinie am First X=2,40. | D-G4 |
| G5 | Dachschalung / Metallhaut | Schalung U+0,160…U+0,184; Metallhaut U+0,184…U+0,196. X=-0,30…5,10; Z=-0,25…3,25. Dachneigung arctan(0,50)=26,565°. | D-G5 |
| G6 | Traufe | 0,30 seitlicher Überstand ab äußerer Wand; 0,020 starke Blende innerhalb X=-0,30…-0,28 bzw. 5,08…5,10. Blendenhöhe 0,20; Oberkante bündig mit Metalldach, Unterkante U-0,004. | D-G6 |
| G7 | Ortgang | 0,25 vor Front / hinter Prüfschnitt; Blende 0,020 entlang Z innerhalb der Dachhülle, 0,20 vertikale Höhe, folgt derselben Dachkontur. Traufe/Ortgang mit Gehrung in gemeinsamer Außenkante. | D-G7 |
| G8 | Firstabschluss | First X=2,40; Dachhaut trifft ohne offene Naht bei Y=4,456. Abdeckung 0,24 breit, 0,006 vertikal dick; untere Profilpunkte (X;Y)=(2,28;4,396)/(2,40;4,494)/(2,52;4,396), äußere Spitze Y=4,500. Endkappen innerhalb Z=-0,25…3,25. | D-G8 |
| G9 | Fensteröffnung | Frontöffnung X=1,00…2,20; Y=1,00…2,20; durch gesamte 0,24-m-Wand. 1,20 × 1,20. | D-G9 |
| G10 | Fensterrahmen | Außen 1,18 × 1,18, X/Y=1,01…2,19; Z=0,04…0,18; Profilbreite 0,06. 0,01 umlaufende Anschlussfuge mit zurückgesetzter Dichtung. | D-G10 |
| G11 | Glas | 1,06 × 1,06 × 0,006; X/Y=1,07…2,13, Z=0,107…0,113; im Rahmenfalz, grünlich-kühler ruhiger Spiegelwert. | D-G11 |
| G12 | Fensterbank | X=0,96…2,24; Y=0,96…1,00; Z=-0,04…0,24. 0,04 Vorsprung nach vorn; kleine abtragende Außenfase innerhalb Hülle. | D-G12 |

Die Frontöffnung wird aus dem Wandkörper ausgespart, nicht mit einer Glasscheibe auf einer geschlossenen Wand nachgebildet. Wand und Laibung bleiben von außen und von der offenen Rückseite erkennbar.

### Anschlüsse, Lagerung und Abschluss

| ID | Verbindung | Geschlossener Anschluss | Herkunft |
| --- | --- | --- | --- |
| GJ1 | Front ↔ Seitenwand | Front belegt Z≤0,24, Seiten beginnen Z=0,24. Ein gemeinsamer Eckstoß ohne durchdringende Außenflächen. Putzkante leicht gefast, keine offene vertikale Naht. | D-G13 |
| GJ2 | Wand ↔ Ringplatte ↔ Keil ↔ Sparren | Wandtop 2,90 = Plattenunterseite; Plattentop 3,00 = Keilunterseite; Keiltop U(X) = Sparrenunterseite. Keilhöhe links 0,06…0,18, rechts symmetrisch. Gleiches Kontaktprofil über die komplette Wandbreite. | D-G14 |
| GJ3 | Sparren ↔ Schalung ↔ Haut | Flächige Höhenlinien U+0,160 bzw. U+0,184; Schraub-/Nagelmarken bündig. Sparren am First auf Gehrung, keine Überlappung zweier ungekürzter Dachhälften. | D-G15 |
| GJ4 | Dach ↔ Traufe / Ortgang | Gemeinsame Dachoberkante und kontrollierter unterer Blendenabschluss. Gehrung an vorderen Ecken; keine Lücke zwischen schrägem Ortgang und waagrechter Traufe. | D-G16 |
| GJ5 | Firsthaut ↔ Abdeckung | Zwei Dachflächen teilen X=2,40/Y=4,456. Kappenfüße liegen bei X=2,28/2,52 direkt auf Y=4,396; bündige Befestigung an den Füßen. Abdeckung und Endkappen schließen die sichtbare Naht. | D-G17 |
| GJ6 | Wand ↔ Fensterrahmen ↔ Glas | 0,01 Dichtfuge; Rahmen sitzt 0,04 hinter der Außenputzfläche. 0,06 Profil lässt 1,06 Lichtmaß. Glas berührt umlaufenden Falz; Laibungstiefe vor Rahmen 0,04 und hinter Rahmen 0,06. | D-G18 |
| GJ7 | Fenster ↔ Bank | Bankoberkante Y=1,00 ist Öffnungsunterkante; Rahmenunterkante 1,01, dazwischen 0,01 Dichtung. Bank reicht bis zur hinteren Wandfläche; keine frei schwebende Vorderkante. | D-G19 |

**Konsistenzrechnung:** U(0)=3,06, U(0,24)=3,18; über Platte Y=3,00 ergeben sich 0,06/0,18 m Keilhöhe. U(2,40)=4,26; plus 0,16+0,024+0,012 ergibt 4,456 m Dachhaut. Bei X=-0,30: U=2,91, Dachhaut=3,106; Blende unten 2,906, genau 0,20 m hoch. Dachgesamtbreite 4,80+2×0,30=5,40; Tiefe 3,00+2×0,25=3,50. Fenster 1,20-2×0,01=1,18; Lichtmaß 1,18-2×0,06=1,06. Erste und letzte Sparrenachse liegen je 0,12 m von den Giebelseiten des Wandgrundkörpers entfernt; jeder Sparren liegt an beiden Seitenwänden auf.

**Benötigte Modellansichten:** Front (Giebel, Fenster), linke Seite (Traufe, Wandkopf), Draufsicht (Dachüberstände), Dreiviertel von außen, offener Rückschnitt und Nahdetails GJ2/GJ4/GJ5/GJ6. Prüfen: keine schwebende Auflagerkante, keine Durchdringung am First, durchgehende Trauf-/Ortganglinie und reale Fensterlaibung. In der SVG sind Front, Seitenansicht, Auflagerdetail und schematische Raumansicht enthalten.

## Materialpalette und Lesbarkeit

| Materialslot | Farbe | Einsatz / sichtbare Eigenschaft | Ursprung |
| --- | --- | --- | --- |
| WallPaint | #E8E0D1 | ruhiger warmer Putz, geringe Struktur | V2 |
| WoodRaw | #C59664 | Hocker roh, Auflagerholz; matt | V2 |
| WoodFinish | #B8824E | Hocker fertig; etwas wärmer, gleiche Holzgeometrie | D-H4 |
| MachineSteel | #34383C | Stahlgestell, Blattgehäuse, Schrauben, Dachkanten/First | V2 |
| MutedGreen | #788678 | Maschinenblenden, Fensterrahmen und gestrichene Dachhaut | V2 |
| SafetyOrange | #D88B3D | Sägehaube, flache Rand-/Pfeilmarkierungen; Formsymbol ergänzen | V2 |
| Glass | #B9CCD0 | leicht getöntes Glas; Reflexion sparsam | D-G20 |

Maserung: Sitz entlang X, Beine entlang Y, Zargen entlang ihrer Längsachse. Gleiche Holztexturgröße über alle neun Teile; lange Holzrichtung bleibt auch in der Packlage erhalten. Holzfasern und Anschlussfugen bleiben aus Spielentfernung ruhig. Keine prozeduralen Details auf Kollisionskörpern. Rauheit, finale Texturauflösung, Dreieckszahl und Performancebudget werden erst am konkreten Muster abgestimmt und sind hier nicht als gemessen dargestellt.

## Prüfung und Übergabegrenze

Die ausgeführten Papier-/Dateiprüfungen stehen mit Ergebnissen in checks.json. Geprüft werden Geometrieverträge, Packluft, drei freie Warenprismen, Dachkontakte, Fensterabstufung, XML/SVG-Integrität und visuelle Lesbarkeit des gerasterten SVG. Negativfälle: drei Beine/zehn Holzteile, expandierte Fase, angehobenes Blatt im Träger, rückseitige Haube bei Z<0,30, falsche Slotmitte, schwebender Dachkeil und falsche Importskalierung müssen als Vertragsbruch erkennbar sein.

Noch offen und nicht als P03-Abnahme zu zählen:

- Lead/Art: D-H-, D-S- und D-G-Vorschläge übernehmen bzw. konkret ändern; das Paket selbst hat keine Nutzerfreigabe.
- Fable: Hocker/Säge und Gebäudeecke nach P03-02/03 modellieren, Anschlüsse im tatsächlichen Mesh prüfen. Schutz- und Schnittdarstellung der Säge separat konkretisieren.
- Studio-Rolle: P03-05/06 Import mit 1-m-Prüfkörper, Warenproben und Ansichten; gemeinsame Wirkung erst P03-07.
- Nutzer: Hallentor/Hallentiefe bzw. Ausfahrstrategie und reales schwächeres Testgerät bleiben unverändert offen. Keine Gebäudeentscheidung dieses Pakets löst diese Fragen.

Keine Gitaktion, kein Commit/Push/Merge/Publish und kein Schreiben an getrackten Projektdateien gehört zu diesem lokalen Arbeitsauftrag.
