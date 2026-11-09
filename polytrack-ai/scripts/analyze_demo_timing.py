"""How fine must control be to reproduce a top run? Replays a recording's controls exactly and
quantised to N-frame blocks (majority vote per key, mapped to our 9 actions), frame-exact in lockstep.

Usage: python scripts/analyze_demo_timing.py [--demo 0] [--blocks 1,5,10,20,25]
Needs demos/summer1_top10_controls.json (written by scripts/bc_dataset.py --fetch-only).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from env import PolyTrackEnv  # noqa: E402

MASK = {0: 1 | 8, 1: 1, 2: 1 | 2, 3: 4 | 8, 4: 4, 5: 4 | 2, 6: 8, 7: 0, 8: 2}  # action -> key bitmask


def quantise(ctrl: list[int], n: int, all_combos: bool = False) -> list[int]:
    from bc_dataset import to_action  # same mapping as the dataset
    out = []
    for k in range(0, len(ctrl), n):
        block = ctrl[k:k + n]
        if all_combos:  # every key on its own (16 combinations incl. gas+brake, left+right)
            m = sum(bit for bit in (1, 2, 4, 8) if sum(1 for x in block if x & bit) * 2 > len(block))
        else:
            m = MASK[to_action(block)]
        out += [m] * len(block)
    return out


def stats(ctrl):
    changes = sum(1 for a, b in zip(ctrl, ctrl[1:]) if a != b)
    runs, cur = [], 1
    for a, b in zip(ctrl, ctrl[1:]):
        if a == b:
            cur += 1
        else:
            runs.append(cur)
            cur = 1
    runs.sort()
    combos = {}
    for m in ctrl:
        combos[m] = combos.get(m, 0) + 1
    return changes, runs[: 10], runs[len(runs) // 2] if runs else 0, combos


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--demo", type=int, default=0)
    ap.add_argument("--blocks", default="1,5,10,20,25")
    ap.add_argument("--all-combos", action="store_true")
    args = ap.parse_args()
    sys.path.insert(0, str(ROOT / "scripts"))
    demos = json.loads((ROOT / "demos" / "summer1_top10_controls.json").read_text(encoding="utf-8"))
    d = demos[args.demo]
    ctrl = d["controls"]
    ch, shortest, median, combos = stats(ctrl)
    print(f"{d['nickname']} {d['frames'] / 1000:.3f}s: {ch} Eingabewechsel, kürzeste Haltedauern {shortest} Frames, "
          f"Median {median} Frames; Tasten-Kombis (Bitmaske:Frames) {combos}")

    cfg = yaml.safe_load((ROOT / "config.yaml").read_text(encoding="utf-8"))["env"]
    cfg.update(headless=True, control_mode="lockstep")
    env = PolyTrackEnv(cfg)
    try:
        for n in [int(x) for x in args.blocks.split(",")]:
            seq = ctrl if n == 1 else quantise(ctrl, n, args.all_combos)
            env.reset()
            snap = None
            for k in range(0, len(seq), 2000):
                snap = env.frame.evaluate("(m) => window.__pt.stepFrames(m)", seq[k:k + 2000])
                if snap.get("finished"):
                    break
            label = "exakt" if n == 1 else f"{n} Frames ({1000 // n} Hz)"
            print(f"  {label:<18}: ziel={snap.get('finished')} zeit={snap.get('finishTimeS')} "
                  f"cp={snap.get('nextCheckpointIndex')} pos=({snap['position']['x']:.0f},{snap['position']['z']:.0f})")
    finally:
        env.close()


if __name__ == "__main__":
    main()
