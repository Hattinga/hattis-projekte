"""Live game-state probe: opens PolyTrack (headed, muted), you drive, values print to the console.

Usage: python scripts/probe.py [--hz 10]
Controls in game: W/A/S/D or arrows, R = respawn at last checkpoint, T = restart race.
Stop with Ctrl+C or by closing the browser window.
"""
import argparse
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from env.browser import PolyTrackBrowser  # noqa: E402


def fmt(s: dict, total_cp: int | None) -> str:
    p, fw = s["position"], s["forward"]
    c = s["controls"]
    keys = "".join(k for k, on in (("W", c["up"]), ("A", c["left"]), ("S", c["down"]), ("D", c["right"]), ("R", c["reset"])) if on) or "-"
    cp = f"{s['nextCheckpointIndex']}/{total_cp if total_cp is not None else '?'}"
    fin = f" FINISH {s['finishTimeS']:.3f}s" if s["finished"] else ""
    return (f"t={s['timeS']:7.3f}s  v={s['speedKmh']:7.2f} km/h  "
            f"pos=({p['x']:8.2f},{p['y']:7.2f},{p['z']:8.2f})  "
            f"yaw={math.degrees(s['yawRad']):7.1f}°  fwd=({fw['x']:+.2f},{fw['y']:+.2f},{fw['z']:+.2f})  "
            f"cp={cp}  wheels={s['wheelsOnGround']}  keys={keys:<4}{fin}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hz", type=float, default=10)
    args = ap.parse_args()

    with PolyTrackBrowser(headless=False) as b:
        print("Lade PolyTrack ...")
        f = b.open_game()
        print("Hooks aktiv. Fahr los (Fenster anklicken für Fokus). Ctrl+C beendet.")
        total_cp, last_player, last_cp, finished = None, None, None, False
        period_ms = 1000 / args.hz
        try:
            while not b.page.is_closed():
                snap = b.snapshot()
                player = f.evaluate("JSON.stringify(window.__pt.player)")
                if player != last_player:  # new race / new track -> reload track info
                    last_player = player
                    b.page.wait_for_timeout(200)
                    info = b.track_info()
                    if info:
                        total_cp = info["totalCheckpoints"]
                        print("\n[track]", json.dumps({k: info[k] for k in ("partSize", "totalCheckpoints", "checkpoints", "finishes")}))
                    last_cp, finished = None, False
                if snap.get("ready"):
                    if last_cp is not None and snap["nextCheckpointIndex"] != last_cp:
                        print(f"\n[checkpoint] {last_cp} -> {snap['nextCheckpointIndex']} at t={snap['timeS']:.3f}s")
                    last_cp = snap["nextCheckpointIndex"]
                    if snap["finished"] and not finished:
                        print(f"\n[finish] time={snap['finishTimeS']:.3f}s")
                    finished = snap["finished"]
                    print("\r" + fmt(snap, total_cp), end="", flush=True)
                b.page.wait_for_timeout(period_ms)
        except KeyboardInterrupt:
            pass
        except Exception as e:  # browser closed by user
            if "closed" not in str(e).lower():
                raise
        print("\nblocked backend requests:", b.blocked)


if __name__ == "__main__":
    main()
