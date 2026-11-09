# PolyTrackEnv (Phase 2)

`env/polytrack_env.py`, Konfiguration in `config.yaml` → `env:`.

## Ablauf

* Eine Env = ein eigener Chromium (Playwright) mit dem offiziellen Spiel, Leaderboard-Sperre und
  Hooks aus Phase 1 (`docs/game_state.md`).
* `reset()`: alle Tasten loslassen, dann **T**. T legt nach einer gefahrenen Runde ein neues Spieler-Auto an,
  die Env wartet darauf. Bei einem noch nicht gestarteten Rennen ist nichts zurückzusetzen.
* Die Rennuhr startet erst mit der ersten Eingabe. Schritte davor kosten keine Spielzeit,
  zählen aber für den Stillstands-Abbruch.

## Steuerfrequenz

**20 Hz in Simulationszeit** (`control_hz`). Jeder Schritt setzt die Tasten der Aktion und wartet per
`__pt.waitFrames(ziel)` (ein Round-Trip, kein Polling), bis die Physik `1000 / control_hz = 50`
Frames weiter ist. Gemessen (sichtbarer Browser, dieser Laptop, 2 × 120 Schritte):

| Frames pro Schritt | Anteil |
|---|---|
| 50 | 92 % |
| 51 | 4 % |
| 60–72 | 4 % (Browser kurz mit Rendern beschäftigt) |

Die Eingaben kommen ein paar Frames nach dem Zielframe an. Das Spiel stempelt sie selbst,
nichts geht verloren, aber exakt frame-genau ist es nicht. Läuft in Echtzeit (1 Sim-s ≈ 1 Wand-s).
Präziser und schneller ginge es im Lockstep über die Worker-Nachrichten `PauseCar`/`ControlCar`
statt Tastatur (noch nicht umgesetzt).

### Lockstep-Steuerung (Standard seit 2026-10-22)

`control_mode: lockstep`. Beim Laden ersetzt `env/browser.py` im Worker-Skript (0.6.3, minifiziert) die
einmalige Stelle `$o.length=0,onmessage=r;` und legt dort die Autoliste `e` und die Schritt-Funktion
`n(car, controls)` des Spiels offen. Ein vorangestellter Handler nimmt `{__ptStep, carId, frames, up, …}`
entgegen. Er hält das Auto für die Echtzeit-Schleife pausiert, rechnet genau `frames` Physik-Frames mit
festen Eingaben und schickt die Zustände im spieleigenen Format zurück (`messageType 10`). In Python ruft
`__pt.stepPlayer(ctrl, 50)` das in einem Roundtrip auf.

Gemessen (`tests/test_lockstep.py`): 104/104 Schritte exakt 50 Frames, zwei Läufe bitgenau gleich,
~90 Schritte/s mit einer Instanz (Tastatur bei 3×: ~37). Reines Gas ergibt dieselben Werte wie per
Tastatur (Schritt 40: 31,2 m, 38 km/h). Fehlt die Ankerstelle (z. B. nach einem Spiel-Update), wird der
Patch mit Warnung übersprungen; `control_mode: keyboard` funktioniert dann weiter.

### CPU-Last und Render-Drossel

Ein unsichtbarer (headless) Browser rendert das Spiel per Software-GL. Gemessen bei 320×200:
**~12 CPU-Kerne** ohne Drossel, ~3 Kerne bei 5 FPS, ~0,7 Kerne bei 1 FPS. `headless_render_fps`
deckelt deshalb `requestAnimationFrame` im Spiel-Frame. Physik (Worker) und Eingaben (ereignisgesteuert
über `controlCar`) hängen nicht davon ab. Nur der Rennstart wird pro gerendertem Bild geprüft
(`(up || down) && !hasStarted → start()`). Er verzögert sich also um bis zu 1/FPS Sekunden Wanduhrzeit,
bevor die Rennuhr läuft. Das sichtbare Env rendert ungedrosselt.

Headless taktet der Worker per `setInterval` mit ~60 Hz, also in Paketen von ~16–17 Frames. Ein Schritt
dauert deshalb 50 oder ~66 Frames (gemessen ca. 70 % / 30 %). Die Eingaben stempelt der Worker trotzdem
auf den richtigen Frame.

### Kein Rückwärtsfahren

`no_reverse: true`: Unter `brake_min_kmh` (10 km/h) wird die Bremstaste ignoriert. S aus dem Stand
oder bei Rückwärtsbewegung wirkt also nicht, Bremsen bei Fahrt schon.

## Aktionen – `Discrete(9)`

| | links (A) | gerade | rechts (D) |
|---|---|---|---|
| **Gas (W)** | 0 | 1 | 2 |
| **Bremse (S)** | 3 | 4 | 5 |
| **nichts** | 6 | 7 | 8 |

## Referenzlinie und Fortschritt

`env/track.py`: Polyline mit Bogenlänge. Fortschritt `s` = Projektion der Autoposition auf die Linie.
Gesucht wird nur in der Nähe des letzten Segments, damit `s` an Kreuzungen und Brücken nicht springt.

* **Aufgenommen** (empfohlen): `python scripts/record_path.py --name summer1`, dann eine saubere Runde
  fahren → `tracks/summer1.json` (Punkt alle 50 Frames). `config.yaml → env.track_path`.
  Summer 1 aufgenommen am 2026-10-15: Runde 25,991 s, 506 Punkte, 1382 m. Abgefahren mit seitlich
  versetzten Punkten steigt `s` stetig bis 1382 m, ohne Sprünge an Kreuzungen/Brücken.
* **Fallback**: gerade Strecken Start → Checkpoints (Reihenfolge) → Ziel aus den Spieldaten.
  Auf Summer 1 grob, weil die Straße Schleifen fährt (Linie 1013 m lang). Das Auto ist schnell
  > 10 m von der Linie entfernt, ohne falsch zu fahren.

## Beobachtung – `Box(-10, 10, (19,))`, float32

| # | Wert | Normierung |
|---|---|---|
| 0 | Geschwindigkeit | km/h / 300 |
| 1, 2 | sin / cos des Winkels zwischen Fahrtrichtung und Linie (xz-Ebene) | – |
| 3 | seitlicher Abstand zur Linie (+ = rechts) | m / 10 |
| 4 | Fortschritt | s / Linienlänge |
| 5 | Rennzeit | Frames / max_episode |
| 6 | Lenkeinschlag (vom Spiel) | – |
| 7 | Nickwinkel (forward.y) | – |
| 8 | Räder mit Bodenkontakt | / 4 |
| 9 | eingesammelte Checkpoints | / Anzahl |
| 10–18 | Punkte 10 / 25 / 50 m voraus auf der Linie, relativ zum Auto: vorne, rechts, oben | /50, /50, /20 |

## Belohnung (pro Schritt, Werte in `config.yaml`)

* `+0.1` pro Meter Fortschritt entlang der Linie (rückwärts entsprechend negativ)
* `−0.01` pro Schritt (Zeitdruck)
* `−0.1` bei Stillstand (|v| < 5 km/h), `−0.2` bei Rückwärtsfahrt (v < −1 km/h)
* `+2` pro Checkpoint
* `−10` bei Absturz/Abflug (> 25 m von der Linie)
* Ziel: `+20 + 80 · (1 − Zeit / 60 s)`, also schneller = mehr

## Episodenende

| Grund | Typ |
|---|---|
| Ziel erreicht | terminated |
| > 25 m von der Linie | terminated (Absturz) |
| 60 Sim-Sekunden | truncated |
| 4 s kein neuer Bestfortschritt (> 1 m) | truncated |

## Tests

`python tests/test_env.py`: `gymnasium.utils.env_checker.check_env` plus eine Episode mit Zufallsaktionen.
Ergebnis 2026-10-15: env_checker ok; Zufallsepisode 137 Schritte / 6,9 Sim-s, Ende `no_progress`,
keine geblockten Requests (kein Zieleinlauf).
