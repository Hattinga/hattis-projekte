# Sprache und Beschriftungen

Nutzerentscheidung vom 16. November 2026: **Englisch und Deutsch**. Englisch ist Quell-/Fallbacksprache; die Zielanzeige folgt der Spielersprache. Übersetzbare Wörter werden von Meshes und Texturen getrennt, Formen und Pfeile bleiben sprachneutral. [Art-Vertrag](../design/ART.md#sprache-und-beschriftung).

## P03-05-Umsetzung

Die [Importkopie](../../assets/p03-models/p03-05-import/handoff.md) enthält fünf FBX ohne acht gebackene Wort-Meshes. [labels.json](../../assets/p03-models/p03-05-import/labels.json) liefert semantischen Schlüssel, relative Position, Rechts-/Oben-/Normalenvektor und verfügbare Schildfläche. Die alten deutschen Blender-Vorschauen bleiben als historischer Entwurf erhalten.

[label-p03-05-probe.luau](../../tools/studio/label-p03-05-probe.luau) baut native `SurfaceGui`/`TextLabel`-Beschriftungen und eine `LocalizationTable` namens `FactoryLabels`. Beide GUI-Ebenen verwenden `AutoLocalize=true` und `RootLocalizationTable`. Die Tabelle enthält `en-us`, `de-de` und `de`; Quelltexte bleiben englisch. Eine serverweite Sprachumschaltung wird nicht verwendet. Der spätere manuelle Sprachwähler gehört zur Spieleroberfläche.

| Schlüssel | English | Deutsch |
| --- | --- | --- |
| `stool.raw` | RAW | ROH |
| `stool.finished` | FINISHED | FERTIG |
| `kit.parts` | PARTS KIT | BAUSATZ |
| `saw.name` | SAW 01 | SÄGE 01 |
| `saw.status` | CLEAR | FREI |
| `saw.input` | IN | EIN |
| `saw.process` | PROCESS | PROZESS |
| `saw.output` | OUT | AUS |

Text nutzt die physische Schildfläche mit `TextScaled`; Farbe wird aus dem linearen Blender-Material nach sRGB umgerechnet. Anker sind unsichtbar, verankert, ohne Kollision/Touch/Query und zählen nicht als neue Warenplätze. Meter-/Achsenzuordnung wie bei den Modellen. Die Locale- und Textlayer-Prüfung auf acht künstlichen Modellwurzeln bestand in Studio Edit, inklusive der realen nativen Translator-Ausgaben für beide Sprachen. Die tatsächliche Lesbarkeit und automatische Clientanzeige auf den importierten Modellen muss nach dem Upload geprüft werden; sie ist damit noch nicht abgenommen.

## Weitere Spielertexte

Spätere Bedienoberflächen, Rückmeldungen und Maschinenzustände verwenden ebenfalls semantische Schlüssel. Die vorhandenen Servermodule liefern stabile Aktionscodes und interne deutsche Fallbackmeldungen. Diese Fallbacktexte sind keine fertige mehrsprachige Spieleroberfläche; ein zukünftiger Client darf sie nicht als alleinige UI-Übersetzung verwenden. Noch keine weltweite/Cloud-Übersetzungstabelle oder neue Spieloberfläche veröffentlicht.
