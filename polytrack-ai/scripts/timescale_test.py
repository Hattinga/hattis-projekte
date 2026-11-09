"""Phase 1.5: can the game clock be sped up, and does physics stay identical?

For each time scale: restart the race (T), hold W from frame 0 until `--frames` physics frames,
record the player trajectory every 100 frames, measure sim-seconds per wall-second, and compare
positions against the scale-1 run.

Usage: python scripts/timescale_test.py [--scales 1,2,4,8,16] [--frames 4000] [--headed]
"""
import argparse
import json
import math
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from env.browser import PolyTrackBrowser  # noqa: E402


def run_once(b: PolyTrackBrowser, scale: float, frames: int, timeout_s: float = 120):
    page, f = b.page, b.game_frame()
    b.set_time_scale(1)
    page.keyboard.press("KeyT")           # full restart (VehicleStartReset)
    page.wait_for_timeout(1500)
    b.set_time_scale(scale)
    f.evaluate("window.__pt.startTrace(100)")
    t0 = time.perf_counter()
    page.keyboard.down("KeyW")
    snap = None
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        snap = b.snapshot()
        if snap.get("ready") and snap["frames"] >= frames:
            break
        page.wait_for_timeout(20)
    wall = time.perf_counter() - t0
    page.keyboard.up("KeyW")
    rows = f.evaluate("window.__pt.stopTrace()")
    b.set_time_scale(1)
    reached = snap["frames"] if snap and snap.get("ready") else 0
    return {"scale": scale, "frames": reached, "wall_s": wall,
            "sim_per_wall": (reached / 1000) / wall if wall else 0,
            "trace": {r[0]: r[1:] for r in rows}}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scales", default="1,2,4,8,16")
    ap.add_argument("--frames", type=int, default=4000)
    ap.add_argument("--headed", action="store_true")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    scales = [float(s) for s in args.scales.split(",")]

    with PolyTrackBrowser(headless=not args.headed, time_scale_patch=True) as b:
        b.open_game()
        b.page.wait_for_timeout(8000)
        b.page.mouse.click(640, 450)  # focus game
        results = [run_once(b, s, args.frames) for s in scales]
        blocked = list(b.blocked)

    ref = next(r for r in results if r["scale"] == 1.0)["trace"]
    report = []
    for r in results:
        common = sorted(set(ref) & set(r["trace"]))
        diffs = [math.dist(ref[k][:3], r["trace"][k][:3]) for k in common]
        report.append({
            "scale": r["scale"], "frames": r["frames"], "wall_s": round(r["wall_s"], 2),
            "sim_s_per_wall_s": round(r["sim_per_wall"], 2),
            "compared_frames": len(common),
            "max_pos_diff_vs_1x": max(diffs) if diffs else None,
            "pos_at_end": r["trace"].get(max(common)) if common else None,
        })
    for row in report:
        print(json.dumps(row))
    print("blocked requests:", blocked)
    if args.out:
        Path(args.out).write_text(json.dumps({"report": report, "results": results}, indent=1))


if __name__ == "__main__":
    main()
