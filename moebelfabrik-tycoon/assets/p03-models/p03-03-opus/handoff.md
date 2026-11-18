# P03-03 · Gebaeudeecke01, Außenprobe Wand/Fenster/Dach v0.2

17. November 2026 · Claude Opus 5.5 · **Lokales technisches Blender-Muster, keine Art-Freigabe, kein Roblox-Import. P03-03 ist nicht abgeschlossen.**
Ausschnitt einer Gebäudebucht nach Referenzblatt `assets/p03-reference/reference.md` (G1–G12, GJ1–GJ7). Es handelt sich weder um die Starthalle noch um eine Tor- oder Layoutentscheidung.

Stand v0.2 = v0.1 plus Korrekturen aus dem Lead-Review (Prüfstände SHA E3151973…, FD1C72AA…). Endstand `tools/build.py` SHA-256 `A5B95E2455A09099264AAD8ADB48E6F7677DA3C4972C43DC16A6F08921D7391B`.

## Dateien (alle unter `.local/p03-03-opus/output/`)

| Datei | Inhalt |
| --- | --- |
| `tools/build.py` | Eigenständiges bpy-Skript, Stufen `build, regress, check, save, export, roundtrip, render`. Pfade relativ zu `__file__` oder `P03_PACKAGE_DIR`. |
| `p03-03-gebaeudeecke01-v01.blend` | Nur die eigene Szene `P03-03_Gebaeudeecke01` (per `bpy.data.libraries.write`). Inhalt nachgelesen: 1 Szene, 50 Objekte. |
| `exports/Gebaeudeecke01.fbx` | Root-Empty und 32 Mesh-Teile, **932 Dreiecke**, 117.932 Byte |
| `exports/ControlCube_1m.fbx` | 1-m-Prüfkörper, Unterseite 0, 12 Dreiecke, 11.708 Byte |
| `checks.json` | **141 Prüfungen**, jeweils mit `expected`, gemessenem `measured` und `pass`; Roblox-Koordinaten |
| `regression-ownership.json` | Ergebnis der Eigentums-Regression |
| `fbx-roundtrip.json` | Isolierter Blender-Rückimport beider FBX |
| `manifest.json` | Teile, Material, Dreiecke, `detail_decisions` und letzte Läufe |
| `renders/*.png` | 13 Ansichten (siehe unten) |

Sicherung des ursprünglichen Live-Zustands: `.local/p03-03-opus/before-p03-03.blend` (96.685 Byte, unverändert). Die ungespeicherte Szene `Scene` (Cube, Light, Camera) war vor und nach allen Läufen gleich und ist wieder die Fensterszene; der Dateipfad ist weiterhin leer.

## Einheiten, Achsen, Pivot

- Blender 5.1.1, Meter, `scale_length 1.0`, +Z oben, Front +Y. Abbildung **(Blender X,Y,Z) → (Roblox X,Z,−Y)**. Alle Maße unten sind Roblox-Meter.
- Pivot nach **D-G0**: (0;0;0) liegt an der äußeren vorderen linken Wandecke am Boden. Das Referenzblatt legt diesen Architekturpivot ausdrücklich fest; er hat deshalb Vorrang vor der allgemeinen Konvention „Bodenmitte“. Der Root-Empty `Gebaeudeecke01` liegt bei 0 mit Einheitsmatrix. Alle Teile sind an Ort und Stelle modelliert und haben keine Modifier; die geprüften Meshdaten sind also das exportierte Mesh (Prüfung `NO_MODIFIERS`).
- Weil die Front nach −Z zeigt, erscheint die Ecke X=0 einem Betrachter vor der Front **rechts**.
- FBX: `axis_forward=-Z`, `axis_up=Y`, `global_scale=1.0`, `apply_unit_scale=True`, `FBX_SCALE_NONE`, Flat Shading, Auswahlexport. Den Studfaktor 25/7 genau einmal anwenden; der 1-m-Körper muss in Roblox **3,571429 Studs** messen.
- Gesamthülle: X −0,30…5,10 · Y 0…4,50 · Z −0,25…3,25 = **5,40 × 4,50 × 3,50 m**.

## Teile, Maße, Material, Dreiecke

U(X) = 4,26 − 0,50·|X − 2,40|.

| Teil(e) | Lage / Maß (Roblox m) | Material | Δ |
| --- | --- | --- | ---: |
| FrontWall | X 0…4,80, Y 0…2,90, Z 0…0,24; Fensteröffnung 1,00…2,20 × 1,00…2,20 plus Bankschlitz X 0,96…2,24 / Y 0,96…1,00 durchgehend; Außenecken 5 mm gefast | P03_WallPaint | 140 |
| SideWall_L/R | X 0…0,24 bzw. 4,56…4,80; Z 0,24…3,00; Y 0…2,90 | WallPaint | 12+12 |
| Plate_Front/L/R | Y 2,90…3,00, Stumpfstoß bei Z=0,24 | P03_WoodRaw | 3×12 |
| Wedge_L/R | Z 0,24…3,00; Y 3,00…U(X), Höhe 0,06/0,18 | WoodRaw | 12+12 |
| GableFill | Z 0…0,24, Y 3,00…U(X) | WallPaint | 16 |
| Rafter1–4_L/R | Achsen Z 0,12/1,12/2,12/2,88, Breite 0,08, Y U…U+0,16; X −0,28…2,40…5,08; lotrechter Gehrungsschnitt am First | WoodRaw | 8×12 |
| Sheathing_L/R | U+0,160…U+0,184; **X −0,28…5,08, Z −0,23…3,23** (D-G21) | WoodRaw | 12+12 |
| Skin_L/R | U+0,184…U+0,196; **X −0,28…5,08, Z −0,23…3,23** (D-G21); Firstlinie 4,456 | P03_MutedGreen | 12+12 |
| Fascia_L/R | X −0,30…−0,28 bzw. 5,08…5,10; **U(−0,30)−0,004 = 2,906 … U+0,196**, außen 0,200 hoch, Oberseite in der Hautoberfläche; 45°-Gehrung | P03_MachineSteel | 12+12 |
| Verge_Front/Rear | Z −0,25…−0,23 bzw. 3,23…3,25; **U−0,004 … U+0,196** (0,200 lotrecht) | MachineSteel | 20+20 |
| RidgeCap / RidgeEnd_Front/Rear | Profil (2,28;4,396)/(2,40;4,494)/(2,52;4,396), Spitze 4,500; Endkappen 0,006 | MachineSteel | 20 + 12+12 |
| WindowFrame | außen 1,01…2,19 (1,18), Z 0,04…0,18; **gestuftes Profil mit Falz** (D-G22) | MutedGreen | 344 |
| WindowSeal | Fuge 0,01, Z 0,06…0,16 | P03_Seal (#202224) | 64 |
| Glass | X/Y 1,07…2,13, Z 0,107…0,113 | P03_Glass | 12 |
| Sill | X 0,96…2,24, Y 0,96…1,00, Z −0,04…0,24 | MachineSteel | 20 |

**Summe 932 Dreiecke** (v0.1: 732; +200 durch das gestufte Rahmenprofil), 32 Meshes, 6 Materialslots, keine Wort- oder Text-Meshes.

## Korrekturen aus dem Review und bewusste Detailentscheidungen

1. **Glasfalz (G10/G11/GJ6) – D-G22.** Der Rahmen ist jetzt gestuft und nicht mehr ein Ring mit konstantem Querschnitt:
   - Außenteil Z 0,040…0,113 mit Lichtmaß **1,06** (1,07…2,13, Profil 0,06). Seine Innenflächen sind die Falz-Seitenwände.
   - Hinterer Anschlag Z 0,113…0,180 mit lichter Weite **1,04** (1,08…2,12).
   - Das Glas 1,06 × 1,06 × 0,006 liegt mit einem 0,010 breiten umlaufenden Band auf der Falzschulter bei Z=0,113 auf.
   - Unverändert bleiben Öffnung 1,20, Rahmen außen 1,18, Lichtmaß 1,06 im Außenteil und auf Glasebene, Glaslage und Laibung 0,04/0,06.
   - Die lichte Durchsicht von innen beträgt 1,04; das ist die bewusste Abweichung D-G22.
   - Eine Glasleiste vor dem Glas ist nicht modelliert.

   Prüfung `GJ6_glass_rebate`, gemessen an den Meshes, mit Sondenpositionen aus den gemessenen Glasgrenzen:
   - Glas-Z 0,107/0,113.
   - 8 Rahmenflächen bei Z=0,113, die zum Glas zeigen, Fläche **0,042 m²** (= 1,06² − 1,04²), alle innerhalb des Glasumrisses.
   - Hinter dem Randband liegen **80/80** Sondenpunkte im Rahmen, hinter dem freien Glas **0/40**.
   - 0,5 mm außerhalb aller vier Glaskanten liegen **160/160** Punkte im Rahmen; vor dem Glasband **0/20** (vorn offen).

   Gegenproben im Live-Blender: Glas 2 mm abgehoben → 0/80 Bandkontakt, Fehlschlag. Glas 2 mm kleiner → 0/160 Kantenkontakt und Schulter nicht mehr unter dem Glas, Fehlschlag. Danach zurückgesetzt, wieder 141/141.
2. **Traufe/Ortgang 0,200 (G6/G7) – exaktes Referenzprofil wiederhergestellt, D-G21 für die Dachschichten.**
   - Fascia und Verge reichen jetzt **jeweils für sich** von U−0,004 bis U+0,196. Gemessen am Brett allein: außen 2,906…3,106 = **0,200**, Oberseite in der Ebene U+0,196 (Abweichung ≤ 1,5·10⁻⁷).
   - Die frühere Zählung „Brett 0,188 + Hautkante 0,012“ ist entfallen.
   - **D-G21:** Schalung **und** Metallhaut enden an der Innenseite der 0,020-Bretter. Tatsächlich gedeckt sind X −0,28…5,08 und Z −0,23…3,23 (gemessen in `DG21_layer_coverage`). Das ist an jedem Rand 0,020 weniger als die nominelle G5-Hülle −0,30…5,10 / −0,25…3,25.
   - Diesen Streifen schließen die Bretter. Die Hülle über Haut, Schalung, Fascia, Verge und Firstkappe ist gemessen geschlossen (`DG21_envelope_closed`).
   - Haut und Brett stoßen stumpf: Die Hautstirn bei X=−0,28 (Y 3,104…3,116) liegt auf der Brettinnenseite (2,906…3,116). Die Oberseiten sind koplanar; es gibt kein überlappendes Volumen (`NO_PENETRATION`).
   - Folge am First: Über Z −0,25…−0,23 bzw. 3,23…3,25 sitzen Firstkappe und Endkappen auf der Oberkante des Ortgangbretts, die in derselben Ebene 4,456 liegt.
3. **Eigentumsschutz.** `cleanup_owned()` prüft vor **jeder** Löschung, ob die Szene das Eigentumsflag trägt und keine fremden Objekte enthält; sonst bricht es mit `OwnershipError` ab, ohne etwas zu löschen. Die Regression (Stufe `regress`, Ergebnis in `regression-ownership.json`) ist bestanden:
   - **(A)** Eine nicht eigene Szene gleichen Namens mit Sentinel-Mesh-Objekt und einem Sentinel mit gesetztem Eigentumsflag überlebt vollständig.
   - **(B)** Die eigene Szene mit einem fremden Objekt bricht ab; die Objektzahl bleibt 51 → 51.
   - Danach werden nur die Sentinels entfernt (keine Reste). Name der eigenen Szene und Fensterszene sind wiederhergestellt, `Scene` ist nachweislich unverändert (Schnappschuss der Transformationen).
4. **Öffnungsmaß (G9).** Die Messung ist jetzt getrennt:
   - `G9_raw_wall_cutout` misst nur den Wandkörper: lichte Höhe inklusive Bankschlitz **1,24**, Schlitzbreite **1,28**.
   - `G9_finished_opening` misst Wand und Bank zusammengebaut, mit Strahlen von fünf Punkten vorn, mittig und hinten: **1,20 × 1,20**, Unterkante = Bankoberkante 1,00.
   - Erwartungswert, Messwert und Ergebnis stimmen jetzt in jeder Prüfung überein.
5. **Gehrungsprofil (GJ4)** – aufgezeichnet, nicht wegdefiniert. Gemessen an den Gehrungsflächen beider Meshes in der 45°-Ebene, für alle vier Ecken gleich:
   - Gemeinsame Außenkante 2,906…3,106 und gemeinsame Oberkante 3,116; die Ortgang-Gehrungsfläche liegt vollständig auf der Traufgehrungsfläche.
   - **Die Flächen sind nicht identisch.** An der Innenecke liegt die waagrechte Traufunterkante bei 2,906, die steigende Ortgangunterkante bei 2,916.
   - Dadurch bleibt je Ecke ein freiliegendes Dreieck der Traufstirn: 10 mm hoch, 28,3 mm lang, **1,414·10⁻⁴ m²** (Fascia 0,005798 m², Verge 0,005657 m²). Es ist nur von unten in der Innenecke sichtbar.

Unveränderte Auslegungen aus v0.1 (bitte weiter vom Lead/Art bestätigen):
- Sparrenfuß lotrecht an der Brettinnenseite.
- Bankschlitz im Wandkörper.
- Offene Felder zwischen Giebelfüllung bis U(X) und Schalung neben Sparren 1; kein Flugsparren im Ortgangüberstand.
- Firstkappe steiler (≈39°) mit Linienauflage an den Füßen.
- Schraub- und Nagelmarken, Fensterteilung und Hautstruktur nicht modelliert.
- Zusätzlicher Materialslot `P03_Seal`.

## Ausgeführte Tests (Endlauf im Live-Blender 5.1.1 über MCP)

- Alle Stufen `build → regress → check → save → export → roundtrip → render` in einem Lauf ausgeführt.
- Regression: **bestanden**.
- **141/141 Prüfungen** bestanden: Hüllen, Ebenen, GJ1–GJ7, D-G21/22, Meshgesundheit (geschlossen, konsistente Windung, Volumen > 0), keine Durchdringung bei dichter Abtastung, `NO_MODIFIERS`.
- Blend geschrieben und nachgelesen: enthält nur die eigene Szene.
- FBX: beide Exporte `FINISHED`. Isolierter Rückimport jeweils in eine temporäre Szene, die danach mit allen Daten entfernt wurde (keine `.001`-Reste):
  - Gebäude: Blender-Hülle (−0,30; −3,25; 0)…(5,10; 0,25; 4,50), 32 Meshes, **932/932 Dreiecke**.
  - Würfel: 1 × 1 × 1, 12/12 Dreiecke.
  - Das ist eine Blender-Prüfung, **kein Roblox-Nachweis.**
- Renders (EEVEE), alle mit `look` gesichtet:
  - Übersichten: front, side_left, top, three_quarter, rear_cutaway.
  - Anschlussdetails: detail_gj2_bearing, detail_gj4_eaves_verge (Ortgang jetzt bündig mit der Haut), detail_gj5_ridge, detail_gj6_window, detail_gj6_window_rear.
  - Neu: **detail_gj6_rebate_front**, **detail_gj6_rebate_rear** (Anschlagstufe und Glas sichtbar) und **detail_gj6_section**, ein Schnitt durch den unteren Rahmen bei X=1,60 über die Kamera-Clip-Ebene. Er zeigt Stufe, aufliegendes Glas, Dichtung, Bank und Wand. Weil die Schnittflächen nicht geschlossen sind, ist das Innere der Teile dunkel zu sehen.
  - Die Detailbilder tragen Freestyle-Konturen.
- Bekannte Darstellungsgrenze: Die rechte Dachfläche wirkt in detail_gj5_ridge durch streifende Himmelsspiegelung grau. Das betrifft nur das Präsentationslicht, nicht das Material.

Wiederholen (in Blender):

```python
p = r"…\.local\p03-03-opus\output\tools\build.py"
exec(compile(open(p, encoding="utf-8").read(), p, "exec"), {"__file__": p, "__name__": "__main__"})
# optional im globals-Dict: "P03_STAGES": ("build","regress","check"), "P03_RENDER_ONLY": ["detail_gj6_section"]
```

## Offen – Roblox-QA und Art-Abnahme (P03-05/06/07, Studio-Rolle bzw. Lead/Nutzer)

- Import mit dem 1-m-Körper (3,571429 Studs); Pivot und Root, Front −Z, Hülle 19,286 × 16,071 × 12,500 Studs.
- Normalen und Flat Shading, Materialzuordnung bzw. -farben, Glas-Transparenz (die FBX-Alpha-Übernahme ist ungeprüft), Z-Fighting an koplanaren Stoßflächen (Hautoberseite/Brettoberseite, GJ1-Fuge) aus Spielentfernung.
- Kollisionshülle festlegen; Fensteröffnung und offener Rückschnitt sind ein Prüfschnitt.
- Neutrale Roblox-Nahaufnahmen GJ2/GJ4/GJ5/GJ6, normale Spielkamera, kleine Bildschirmansicht.
- Art-Abnahme nach ART einschließlich der Entscheidungen D-G21, D-G22 und des aufgezeichneten Gehrungsprofils (GJ4).
- **P03-03 bleibt offen**, bis die importierten Roblox-Ansichten abgenommen sind.
- Kein Commit, kein Push, kein Upload, keine Studio-Änderung und keine Änderung außerhalb von `.local/p03-03-opus/` durch diese Aufgabe.
