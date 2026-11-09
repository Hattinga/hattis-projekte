"""Lockstep control check: exact 50 frames per step, bit-identical repeat runs, speed.

Run: python tests/test_lockstep.py
"""
import sys
import time
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import yaml  # noqa: E402

from env import ACTION_NAMES, PolyTrackEnv  # noqa: E402

A = {n: i for i, n in enumerate(ACTION_NAMES)}
PLAN = ["gas+straight"] * 30 + ["gas+left"] * 6 + ["gas+straight"] * 20 + ["gas+right"] * 8 + ["gas+straight"] * 40


def run(env):
    env.reset()
    deltas, last = Counter(), 0
    t0 = time.perf_counter()
    for a in PLAN:
        _, _, term, trunc, info = env.step(A[a])
        f = env.snap["frames"]
        deltas[f - last] += 1
        last = f
        if term or trunc:
            break
    wall = time.perf_counter() - t0
    p = env.snap["position"]
    return (p["x"], p["y"], p["z"], env.snap["speedKmh"]), deltas, len(PLAN) / wall, info


def test_lockstep():
    cfg = yaml.safe_load((ROOT / "config.yaml").read_text(encoding="utf-8"))["env"]
    cfg.update(headless=True, control_mode="lockstep")
    env = PolyTrackEnv(cfg)
    try:
        r1 = run(env)
        r2 = run(env)
        for i, (pos, deltas, sps, info) in enumerate((r1, r2)):
            print(f"run {i}: end pos/speed {pos}, frames/step {dict(deltas)}, {sps:.0f} steps/s, "
                  f"sim {info['time_s']:.2f}s, progress {info['progress_m']:.1f} m, end {info['end_reason']}")
        assert r1[0] == r2[0], "runs differ -> not deterministic"
        assert set(r1[1]) == {50}, f"frames per step not exact: {r1[1]}"
        print("OK: frame-exact and bit-identical")
    finally:
        env.close()


if __name__ == "__main__":
    test_lockstep()
