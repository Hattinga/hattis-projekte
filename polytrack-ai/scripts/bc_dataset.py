"""Imitation data from the top leaderboard runs: (observation, action) pairs in our env's action space.

1. Reads the top K runs of the current track (GET from inside the official game page, like the in-game
   leaderboard) and decodes each recording's per-frame controls with the game's own recording class.
2. Maps the controls onto our discrete 9 actions at control_hz (per step: majority vote of the frames)
   and drives them through PolyTrackEnv (lockstep), recording obs/action/reward.
Nothing is uploaded; the game's automatic leaderboard POST on finish stays blocked.

Usage: python scripts/bc_dataset.py [--top 10] [--out demos/summer1_top10.npz]
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.parse
from pathlib import Path

import numpy as np
import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from env import ACTION_NAMES, PolyTrackEnv  # noqa: E402
from env.browser import PolyTrackBrowser  # noqa: E402

API, VERSION = "https://vps.kodub.com/v6/", "0.6.3"


def page_get(frame, endpoint, **params):
    url = API + endpoint + "?" + urllib.parse.urlencode({"version": VERSION, **params})
    res = frame.evaluate("""async (url) => { const r = await fetch(url);
        return {status: r.status, text: await r.text()}; }""", url)
    if res["status"] != 200:
        raise SystemExit(f"GET {endpoint} -> HTTP {res['status']}")
    return json.loads(res["text"])


def fetch_demos(top: int) -> list[dict]:
    with PolyTrackBrowser(headless=True, time_scale_patch=True, log_blocked=False,
                          allow_leaderboard_read=True) as b:
        f = b.open_game()
        f.wait_for_function("window.__pt.player !== null && window.__pt.track !== null", timeout=180000)
        track_id = f.evaluate("window.__pt.track.getTrackData().getId()")
        lb = page_get(f, "leaderboard", trackId=track_id, skip=0, amount=top, onlyVerified="true")
        entries = lb["entries"]
        recs = page_get(f, "recordings", ids=",".join(str(e["id"]) for e in entries))
        demos = []
        for e, r in zip(entries, recs):
            ctrl = f.evaluate("([rec, n]) => window.__pt.getRecordingControls(rec, n)",
                              [r["recording"], e["frames"] + 100])
            demos.append({"nickname": e["nickname"], "frames": e["frames"], "controls": ctrl})
            print(f"  {e['nickname']:<20} {e['frames'] / 1000:.3f}s  {len(ctrl)} frames")
        return demos


def to_keys16(masks: list[int]) -> int:
    """Per key majority over one step's frames -> key bitmask 0..15 (action of action_space keys16)."""
    return sum(bit for bit in (1, 2, 4, 8) if sum(1 for m in masks if m & bit) * 2 > len(masks))


def to_action(masks: list[int]) -> int:
    """Majority vote over one step's frames, throttle and steering independently."""
    up = sum(m & 1 for m in masks); dn = sum((m >> 2) & 1 for m in masks)
    rt = sum((m >> 1) & 1 for m in masks); lf = sum((m >> 3) & 1 for m in masks)
    half = len(masks) / 2
    throttle = 0 if up > half and up >= dn else 1 if dn > half else 2      # gas, brake, none
    steer = 0 if lf > half and lf >= rt else 2 if rt > half else 1         # left, straight, right
    return throttle * 3 + steer


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=10)
    ap.add_argument("--out", default="demos/summer1_top10.npz")
    ap.add_argument("--fetch-only", action="store_true")
    args = ap.parse_args()

    cache = ROOT / "demos" / f"summer1_top{args.top}_controls.json"
    if cache.exists():
        demos = json.loads(cache.read_text(encoding="utf-8"))
        print(f"[bc] {len(demos)} Aufnahmen aus {cache.name}")
    else:
        print(f"[bc] Top {args.top} Aufnahmen holen ...")
        demos = fetch_demos(args.top)
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps(demos), encoding="utf-8")
    if args.fetch_only:
        return

    cfg = yaml.safe_load((ROOT / "config.yaml").read_text(encoding="utf-8"))["env"]
    cfg.update(headless=True, control_mode="lockstep", action_space="keys16")
    env = PolyTrackEnv(cfg)
    fps = env.frames_per_step
    obs_l, act_l, rew_l, ep_l, stats = [], [], [], [], []
    try:
        for i, d in enumerate(demos):
            ctrl = d["controls"]
            # the car follows the EXACT recorded inputs (so every observation lies on the expert's real
            # trajectory); the label of each step is the key combination held for most of its frames
            blocks = [ctrl[k:k + fps] for k in range(0, len(ctrl), fps)]
            obs, _ = env.reset()
            o, a, rw = [], [], []
            info = {}
            for blk in blocks:
                act = to_keys16(blk)
                o.append(obs)
                a.append(act)
                obs, r, term, trunc, info = env.step_exact(blk, act)
                rw.append(r)
                if term or trunc:
                    break
            ok = bool(info.get("finished"))
            stats.append({"nickname": d["nickname"], "orig_s": d["frames"] / 1000,
                          "replayed_s": info.get("finish_time_s"), "end": info.get("end_reason"),
                          "progress_m": round(info.get("progress_m", 0), 1), "steps": len(a)})
            print(f"[bc] {d['nickname']:<20} original {d['frames'] / 1000:.3f}s -> nachgefahren: "
                  f"{info.get('finish_time_s')} ({info.get('end_reason')}, {info.get('progress_m', 0):.0f} m)")
            if ok:  # only runs that still finish after discretisation are good teachers
                obs_l += o; act_l += a; rew_l += rw; ep_l += [i] * len(a)
    finally:
        env.close()

    out = ROOT / args.out
    out.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(out, obs=np.array(obs_l, np.float32), actions=np.array(act_l, np.int64),
                        rewards=np.array(rew_l, np.float32), episode=np.array(ep_l, np.int64))
    (out.with_suffix(".json")).write_text(json.dumps({"control_hz": cfg["control_hz"], "action_space": "keys16",
                                                      "stats": stats, "action_names": env.action_names},
                                                     indent=1), encoding="utf-8")
    counts = np.bincount(np.array(act_l, np.int64), minlength=16) if act_l else []
    print(f"[bc] {len(act_l)} Paare aus {len(set(ep_l))} Fahrten -> {out}")
    print("[bc] Aktionen:", {env.action_names[k]: int(c) for k, c in enumerate(counts) if c})


if __name__ == "__main__":
    main()
