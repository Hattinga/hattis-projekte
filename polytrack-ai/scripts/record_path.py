"""Record a reference driving line: drive one clean lap yourself, the path is saved on finish.

Usage: python scripts/record_path.py --name summer1 [--every 50]
T restarts the attempt (recording starts over). The file goes to tracks/<name>.json and is used by
PolyTrackEnv via config.yaml -> env.track_path.
"""
import argparse
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from env.browser import PolyTrackBrowser  # noqa: E402
from env.track import TrackPath  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--every", type=int, default=50, help="sample every N physics frames (ms)")
    args = ap.parse_args()
    out = ROOT / "tracks" / f"{args.name}.json"

    with PolyTrackBrowser(headless=False) as b:
        print("Lade PolyTrack ...")
        f = b.open_game()
        f.wait_for_function("window.__pt.player !== null", timeout=30000)
        print("Bereit. Fahr eine saubere Runde bis ins Ziel (T = Neustart). Ctrl+C bricht ab.")
        f.evaluate(f"window.__pt.startTrace({args.every})")
        last_frames = 0
        try:
            while True:
                snap = b.snapshot()
                if snap.get("ready"):
                    if snap["frames"] < last_frames:  # restarted with T
                        f.evaluate(f"window.__pt.startTrace({args.every})")
                        print("\nNeustart – Aufnahme beginnt von vorn.")
                    last_frames = snap["frames"]
                    print(f"\rt={snap['timeS']:7.3f}s  cp={snap['nextCheckpointIndex']}  "
                          f"v={snap['speedKmh']:6.1f} km/h", end="", flush=True)
                    if snap["finished"]:
                        rows = f.evaluate("window.__pt.stopTrace()")
                        fin = snap["finishFrames"] if "finishFrames" in snap else int(snap["finishTimeS"] * 1000)
                        pts = np.array([r[1:4] for r in rows if r[0] <= fin])
                        info = b.track_info()
                        path = TrackPath(pts, "recorded")
                        path.save(out, {"track_checkpoints": info["totalCheckpoints"],
                                        "finish_time_s": snap["finishTimeS"], "every_frames": args.every})
                        print(f"\nZiel in {snap['finishTimeS']:.3f}s – {len(path.points)} Punkte, "
                              f"{path.length:.0f} m gespeichert: {out}")
                        break
                b.page.wait_for_timeout(100)
        except KeyboardInterrupt:
            print("\nabgebrochen, nichts gespeichert")
        print("blocked backend requests:", b.blocked)


if __name__ == "__main__":
    main()
