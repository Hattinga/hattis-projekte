# Werkstatt – gewaehltes Fable-Modell

Fable 5.2, Runde 2. Jonas waehlte am 11. November 2026 Modell A. Originalquelle und Erzeugungsskript liegen in `source/`, die Exporte in `export/`. Originaldateien sind unveraendert und mit dem Vergleichsordner per SHA-256 abgeglichen.

- `source/workshop.blend` ist die fuehrende Modellquelle. Kein Live-Blender-Zugriff fuer die Importvorbereitung.
- `export/workshop.glb` ist der gepruefte Upload: 45 Quellmeshes, 153 Material-Primitives, 13.080 Dreiecke, 22 Materialien, keine Bildtexturen.
- Das private Werkstatt-Asset hat ID `106051543998570`, Revision 1. Ein einziger Modell-Upload, Freigabe Approved. Kein erneuter Upload zum Wiederaufnehmen.
- `upload.json` nennt Operation, Konto, Ziel-Place und Einwilligung. Der damals freigegebene Upload-Ordner war der Vergleichsordner, nicht automatisch dieser Archivordner.
- Die Studio-Kopie liegt unter `Workspace.FableWorkshop`. Sie enthaelt 153 MeshParts und 21 separate, unsichtbare Kollisionskoerper.

Bei einem erneuten Einfuegen des vorhandenen Assets kommen der Originalmassstab, die verworfenen Farben und unfixierten Teile zurueck. Das Importasset ist als Package verknuepft; die Reparaturen gelten fuer die aktuelle Studio-Kopie. Kein Package-Update oder Neuveroeffentlichen der reparierten Kopie beauftragt.

Zum Wiederherstellen einer frisch eingefuegten Kopie `FableWorkshop` dient `tools/studio/prepare-workshop.luau`. Vorher Ziel-Place, Edit-Modus und Sicherung pruefen. Der Helfer ist ein einmaliges Studio-Werkzeug, kein Spielskript. Er bricht bei einer bereits vorbereiteten Kopie ab und stellt Farben, Massstab, Lage, Verankerung, Kollision, Ansicht und reduzierten Umgebungsglanz wieder her.

Beleg und offene Punkte stehen in `docs/evidence/COMP-R2-IMPORT.md`.