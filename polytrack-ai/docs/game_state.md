# PolyTrack – Spielzustand zur Laufzeit

Stand: 2026-10-15, **PolyTrack 0.6.3** (offizielle Version, `https://kodub.itch.io/polytrack`).
Alle Angaben unten stammen aus dem ausgelieferten Code dieser Version (`main.bundle.js`,
`simulation_worker.bundle.js`) und sind mit Live-Tests bestätigt, sofern nicht anders markiert.
Bei einem Spiel-Update können sich Modul-IDs und Nachrichtenformat ändern → Hooks prüfen
(`window.__pt.gameVersion` muss `"0.6.3"` sein).

## Aufbau

| Teil | Ort |
|---|---|
| itch.io-Seite | `https://kodub.itch.io/polytrack`, Spiel startet per Klick auf `.load_iframe_btn` |
| Spiel-iframe | `iframe#game_drop` → `https://html-classic.itch.zone/html/19260993/index.html` |
| Hauptlogik + Rendering (Three.js) | `main.bundle.js` (Webpack, Global `self.webpackChunk`) |
| Physik | Web Worker `simulation_worker.bundle.js` + WASM `lib/polytrack_physics.js` / `polytrack_physics.wasm` |
| Backend | `https://vps.kodub.com/v6/…` |

Die Physik läuft **nicht** im Haupt-Thread, sondern in einem Web Worker mit festen
**1-ms-Schritten (1000 Frames/s)**. Pro Spieler-Auto schickt der Worker nach jedem Schritt einen
Zustandspuffer an den Haupt-Thread, der ihn decodiert und rendert. Zeit = `frames / 1000` s
(`maxFrames = 5999999` → 99:59.999).

Es laufen zwei Simulation-Worker: einer im Echtzeitmodus (`isRealtime: true`, das gefahrene Auto)
und einer im Nicht-Echtzeitmodus (Replays / Verifikation).

## Zugriffsweg 1: Worker-Nachrichten (Zustand des Autos)

`env/hooks.js` ersetzt im iframe `window.Worker` durch einen Wrapper (vor dem Laden des Spiels,
per Playwright `add_init_script`). Für Worker mit `simulation_worker` in der URL:

* **ausgehend** (`worker.postMessage`), Enum `messageType` (identisch in beiden Bundles):
  `Init=0, Verify=1, TestDeterminism=2, CreateCar=3, DeleteCar=4, StartCar=5, ControlCar=6,
  PauseCar=7, VerifyResult=8, DeterminismResult=9, UpdateResult=10`
  * `Init { version, isRealtime, trackParts, … }`
  * `CreateCar { carId, trackData, carRecording, … }` – `carRecording == null` ⇒ vom Spieler
    gesteuertes Auto (Replays/Ghosts haben eine Aufnahme). → `__pt.player = {workerId, carId}`
  * `ControlCar { carId, up, right, down, left, reset }` – so gibt das Spiel Tasteneingaben an die Physik weiter
* **eingehend** `UpdateResult { carStateBuffers: ArrayBuffer[] }`: je Puffer
  `int32 carId (LE)` + CarState, Puffer in Simulationsreihenfolge (mehrere Frames pro Nachricht).

### CarState-Binärformat (Spiegel von Webpack-Modul `3899`, Export `VO`)

Little Endian, Reihenfolge:

| Feld | Typ | Bedeutung |
|---|---|---|
| frames | uint24 | Physik-Frames seit Rennstart (1 Frame = 1 ms) |
| speedKmh | float32 | Geschwindigkeit in km/h (negativ = rückwärts) |
| flags | uint8 | bit0 hasStarted, bit1 hasFinished, bit2 hasCheckpointToRespawnAt, bit3–6 Radkontakt 0–3 |
| finishFrames | uint24 | nur wenn hasFinished: Zielzeit in Frames |
| nextCheckpointIndex | uint16 | Anzahl eingesammelter Checkpoints = Index des nächsten |
| position | 3×float32 | Weltposition x, y, z (y = oben) |
| quaternion | 4×float32 | Rotation x, y, z, w |
| nImpulses | uint8 | ≤ 4 |
| collisionImpulses | nImpulses×float32 | Kollisionsstärken dieses Frames |
| wheelContact | je Rad mit Kontakt 6×float32 | Kontaktpunkt + Normale |
| wheelSuspensionLength / -Velocity / wheelDeltaRotation / wheelSkidInfo | je 4×float32 | |
| steering | float32 | aktueller Lenkeinschlag |
| controls | uint8 | bit0 up, bit1 right, bit2 down, bit3 left, bit4 reset, bit5 brakeLight |

### Abgeleitete Werte

* **Fahrtrichtung:** `forward = q · (0,0,1)` → `yaw = atan2(fwd.x, fwd.z)`.
  Bestätigt: Startquaternion auf Summer 1 = (0, 0.707, 0, −0.707) → forward (−1,0,0), das Auto fährt in −x.
* **Rennzeit:** `frames / 1000` s, **Ziel:** `finishFrames != null`, Zielzeit `finishFrames / 1000` s.
* **Fortschritt:** `nextCheckpointIndex` (0 … totalCheckpoints). Das Spiel nutzt dasselbe Feld
  für die HUD-Anzeige „x/3“ (`getNextCheckpointIndex()`); im Live-Test zeigte es 0/3 und blieb vor
  dem ersten Checkpoint bei 0. *Das Hochzählen beim Durchfahren ist im Code belegt, aber noch nicht
  live gesehen – bitte beim Probe-Lauf bestätigen.*
* Das Rennen startet erst mit der ersten Eingabe (`hasStarted`), vorher bleibt `frames = 0`.

## Zugriffsweg 2: Webpack (Streckendaten)

`self.webpackChunk.push([["__pt_probe"], {}, req => …])` liefert die Webpack-`require`-Funktion.

* Modul **`6762`**, Export `A` = Track-Klasse (statisch `partSize = 5`) mit
  `getCheckpoints()`, `getCheckpointOrders()`, `getTotalNumberOfCheckpointIndices()`,
  `getFinishes()`, `getStart()`, `getStartTransform()`.
* Die Instanz wird abgefangen, indem `Track.prototype.getStartTransform` umwickelt wird
  (das Spiel ruft ihn beim (Neu)start auf) → `__pt.track`.
* Weltkoordinaten eines Checkpoints = `part.x/y/z * partSize + detector.center`.
  *Ziel-Positionen werden aktuell ohne Detector-Offset ausgegeben (nur Teil-Position × partSize).*

Beispiel Summer 1 (live gelesen): 3 Checkpoints, Reihenfolge 0 → (180, 57.2, 0),
1 → (−170, 2.2, 0), 2 → (−100, 12.2, −80); Start (318.65, 55.35, 20).

## Tasten (Default-Belegung, aus `defaultKeyBindings()`)

| Aktion | Tasten |
|---|---|
| Gas | W / ↑ |
| Bremse/Rückwärts | S / ↓ |
| Links / Rechts | A / ← , D / → |
| Respawn am letzten Checkpoint | **R** / Enter |
| **Rennen komplett neu starten** | **T** / Backspace |
| Pause | P / Leertaste |

⚠️ Abweichung von der Projekt-Spezifikation: **R** ist nur der Checkpoint-Reset; für einen
Episoden-Reset braucht es **T**.

## Leaderboard-Schutz

Gefundene Schreib-Endpunkte (alle `POST`, `application/x-www-form-urlencoded`):

| Endpunkt | Funktion im Code | Inhalt |
|---|---|---|
| `POST https://vps.kodub.com/v6/leaderboard` | `submitLeaderboard()` | userToken, nickname, trackId, frames, **recording** |
| `POST https://vps.kodub.com/v6/verifyRecordings` | `verifyRecordings()` | Aufnahmen zur Verifikation |
| `POST https://vps.kodub.com/v6/user` | `submitUserProfile()` | Nickname/Land/Auto-Stil |

`env/browser.py` blockiert per `context.route("**://vps.kodub.com/**")` **jede** Nicht-GET-Anfrage
sowie alle Pfade mit `leaderboard` oder `verifyRecordings` (auch GET). Getestet: ein `fetch`-POST
auf `/v6/leaderboard` und ein XHR-POST auf `/v6/verifyRecordings` aus dem Spiel-Frame wurden beide
abgebrochen (`[guard] blocked …`), ohne dass etwas das Netz erreicht hat.

Hinweis: Playwright-Route-Handler laufen nur, solange die Event-Loop läuft. In eigenem Code deshalb
`page.wait_for_timeout()` statt `time.sleep()` verwenden. Sonst hängen die Requests (nicht
durchgelassen, aber das Spiel wartet).

## Zeitbeschleunigung (nur getestet, nicht eingebaut)

Mechanik im Worker: Ein Tick (requestAnimationFrame, plus `setInterval` 60 Hz als Fallback) liest
`performance.now()`, addiert die Differenz (max. **0,1 s pro Tick**) auf einen Akkumulator und rechnet
so viele 1-ms-Schritte, wie hineinpassen. Die Physik selbst ist zeitunabhängig.

Test (`scripts/timescale_test.py`): `browser.py(time_scale_patch=True)` stellt dem Worker-Skript einen
`performance.now()`-Skalierer voran (Faktor per `postMessage({__ptTimeScale})`). Dann wird Gas von
Frame 0 bis Frame ~4000 gehalten und die Trajektorie alle 100 Frames verglichen (headless, dieser Laptop):

| Faktor | Sim-Sekunden pro echter Sekunde | max. Positionsabweichung zu 1× |
|---|---|---|
| 1× | 0,93 | 0,0 |
| 2× | 1,76 | 0,0 |
| 4× | 3,12 | 0,0 |
| 8× | 4,22 | 0,0 |
| 16× | 5,07 | 0,0 |

* Die Physik bleibt **bitgenau gleich**, weil die Schritte fest sind. Die Beschleunigung ist also stabil.
* Die Grenze liegt bei etwa 5–6×: Die 0,1-s-Kappe pro Tick bei ~60 Ticks/s ergibt maximal 6×.
* Einschränkung: Eingaben bekommen im Worker einen Zeitstempel nach der (skalierten) Uhr.
  Bei hohem Faktor wird die Eingabe-Latenz von Python/Playwright in Sim-Frames also größer.
* Alternative für später (nicht umgesetzt): Der Worker hat `PauseCar`. Damit ließe sich das
  Auto Frame-genau im Lockstep steuern, mit direkten `ControlCar`-Nachrichten statt Tastatur.

## Dateien

* `env/hooks.js` – Worker-/Webpack-Hooks, `window.__pt.snapshot()`, `trackInfo()`, Trace, Zeitfaktor
* `env/browser.py` – Playwright-Wrapper (Leaderboard-Sperre, Hook-Injection, optionaler Worker-Patch)
* `scripts/probe.py` – Live-Ausgabe beim manuellen Fahren
* `scripts/timescale_test.py` – Beschleunigungstest
* `scripts/recon.py` – lädt die Seite und speichert Requests/Bundles zur Analyse
