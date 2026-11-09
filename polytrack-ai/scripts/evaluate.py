"""Phase 4/5: evaluate a trained model, log times, record a video.

Modes (output in models/<run>/eval/, file names carry model + mode, nothing is overwritten across modes):
  default         deterministic policy (argmax), --episodes runs, visible, video   -> <model>_det.json/.webm
  --search N      N runs sampling from the policy (seeded), headless, no video; keeps the fastest
                  finished run and stores its action sequence                          -> <model>_search.json, <model>_best_actions.json
  --replay        replays <model>_best_actions.json frame-exactly (lockstep) in real time, visible,
                  with video, and checks the finish time is reproduced                -> <model>_best_run.json/.webm

With control_mode: lockstep the simulation is deterministic, so a stored action sequence reproduces
its run exactly.
Usage: python scripts/evaluate.py --model models/<run>/best_time.zip [--episodes 2 | --search 30 | --replay]
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
from pathlib import Path

import torch
import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from stable_baselines3 import PPO  # noqa: E402

from env import ACTION_NAMES, PolyTrackEnv  # noqa: E402


def latest_run_model() -> Path:
    runs = sorted((ROOT / "models").glob("*/"), key=lambda p: p.stat().st_mtime, reverse=True)
    for r in runs:
        for name in ("best_time.zip", "best_progress.zip", "latest.zip"):
            if (r / name).exists():
                return r / name
    raise FileNotFoundError("no trained model in models/")


def summarize(ep, info, actions, ret, t0, env):
    return {
        "episode": ep, "end": info.get("end_reason"), "finished": bool(info.get("finished")),
        "finish_time_s": info.get("finish_time_s"), "progress_m": round(info.get("progress_m", 0), 1),
        "track_length_m": round(env.path.length, 1), "checkpoints": info.get("checkpoint"),
        "steps": info.get("steps"), "steer_changes": info.get("steer_changes"),
        "steer_changes_per_100_steps": round(100 * info.get("steer_changes", 0) / max(info.get("steps", 1), 1), 1),
        "wall_impulse": round(info.get("wall_impulse", 0.0)),
        "return": round(ret, 2), "wall_s": round(time.time() - t0, 1),
        "action_counts": {n: actions.count(i) for i, n in enumerate(ACTION_NAMES) if actions.count(i)},
    }


def line(res):
    fin = f"{res['finish_time_s']:.3f}s" if res["finished"] else "nicht im Ziel"
    return (f"{fin}, {res['progress_m']}/{res['track_length_m']} m, cp {res['checkpoints']}, "
            f"Lenkwechsel/100 {res['steer_changes_per_100_steps']}, Ende {res['end']}")


def run_episode(env, choose, pace_s: float = 0.0):
    obs, info = env.reset()
    done, ret, actions, t0 = False, 0.0, [], time.time()
    while not done:
        t_step = time.perf_counter()
        a = choose(obs, len(actions))
        if a is None:
            break
        obs, r, term, trunc, info = env.step(int(a))
        actions.append(int(a))
        ret += r
        done = term or trunc
        if pace_s:  # real-time playback for the video
            rest = pace_s - (time.perf_counter() - t_step)
            if rest > 0:
                env.page.wait_for_timeout(rest * 1000)
    return info, actions, ret, t0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model")
    ap.add_argument("--episodes", type=int, default=2)
    ap.add_argument("--search", type=int, default=0, help="sampled runs, keep the fastest")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--replay", action="store_true", help="replay the stored best action sequence")
    ap.add_argument("--no-video", action="store_true")
    ap.add_argument("--track-path", help="reference line the model was trained with (default: config.yaml)")
    args = ap.parse_args()

    model_path = (Path(args.model) if args.model else latest_run_model()).resolve()
    out = model_path.parent / "eval"
    out.mkdir(parents=True, exist_ok=True)
    stem = model_path.stem
    mode = "search" if args.search else "best_run" if args.replay else "det"
    video_dir = out / f"_video_tmp_{mode}"
    print(f"[eval] Modell {model_path} | Modus {mode}")

    cfg = yaml.safe_load((ROOT / "config.yaml").read_text(encoding="utf-8"))["env"]
    if args.track_path:
        cfg["track_path"] = args.track_path
    visible = mode != "search"
    cfg.update(headless=not visible, watch=visible)
    record = visible and not args.no_video
    if record:
        cfg["record_video_dir"] = str(video_dir)
    env = PolyTrackEnv(cfg)
    model = PPO.load(model_path, device="cpu")
    pace = 1.0 / cfg["control_hz"] if mode == "best_run" else 0.0

    results, best = [], None
    try:
        if mode == "best_run":
            stored = json.loads((out / f"{stem}_best_actions.json").read_text(encoding="utf-8"))
            seq = stored["actions"]
            info, actions, ret, t0 = run_episode(env, lambda o, i: seq[i] if i < len(seq) else None, pace)
            res = summarize(0, info, actions, ret, t0, env)
            res["expected_finish_s"] = stored["finish_time_s"]
            res["reproduced"] = res["finished"] and abs((res["finish_time_s"] or 0) - stored["finish_time_s"]) < 1e-9
            results.append(res)
            print(f"[eval] Replay: {line(res)} | erwartet {stored['finish_time_s']:.3f}s, reproduziert: {res['reproduced']}")
        else:
            n = args.search or args.episodes
            for ep in range(n):
                if args.search:
                    torch.manual_seed(args.seed + ep)
                    choose = lambda o, i: model.predict(o, deterministic=False)[0]  # noqa: E731
                else:
                    choose = lambda o, i: model.predict(o, deterministic=True)[0]  # noqa: E731
                info, actions, ret, t0 = run_episode(env, choose)
                res = summarize(ep, info, actions, ret, t0, env)
                res["seed"] = args.seed + ep if args.search else None
                results.append(res)
                print(f"[eval] Episode {ep}: {line(res)}")
                if res["finished"] and (best is None or res["finish_time_s"] < best["finish_time_s"]):
                    best = {**res, "actions": actions}
            if args.search and best is not None:
                (out / f"{stem}_best_actions.json").write_text(json.dumps({
                    "model": str(model_path.relative_to(ROOT)), "seed": best["seed"],
                    "finish_time_s": best["finish_time_s"], "control_hz": cfg["control_hz"],
                    "action_names": ACTION_NAMES, "actions": best["actions"]}), encoding="utf-8")
        blocked = list(env.browser.blocked) if env.browser else []
    finally:
        video_src = None
        page = getattr(env, "page", None) if env.browser else None
        if record and page is not None and page.video:
            video_src = page.video.path()
        env.close()

    finished = [r for r in results if r["finished"]]
    summary = {
        "model": str(model_path.relative_to(ROOT)), "mode": mode, "control_mode": cfg.get("control_mode"),
        "control_hz": cfg["control_hz"], "track_path": cfg.get("track_path"),
        "runs": len(results), "finished_runs": len(finished),
        "best_finish_s": min((r["finish_time_s"] for r in finished), default=None),
        "episodes": results, "blocked_backend_requests": blocked,
    }
    (out / f"{stem}_{mode}.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    if video_src and Path(video_src).exists():
        dst = out / f"{stem}_{mode}.webm"
        shutil.move(video_src, dst)
        shutil.rmtree(video_dir, ignore_errors=True)
        print(f"[eval] Video: {dst}")
    print(f"[eval] {len(finished)}/{len(results)} im Ziel, Bestzeit: {summary['best_finish_s']} "
          f"-> {out / f'{stem}_{mode}.json'}")


if __name__ == "__main__":
    main()
