"""Phase 2 checks: gymnasium env_checker + one episode with random actions.

Run: python tests/test_env.py   (or: python -m pytest tests -s)
Opens one headless browser (~20 s to load the game).
"""
import sys
import time
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import yaml  # noqa: E402
from gymnasium.utils.env_checker import check_env  # noqa: E402

from env import ACTION_NAMES, PolyTrackEnv  # noqa: E402


def make_env():
    cfg = yaml.safe_load((ROOT / "config.yaml").read_text(encoding="utf-8"))["env"]
    return PolyTrackEnv(cfg)


def test_env_checker_and_random_episode():
    env = make_env()
    try:
        t0 = time.time()
        check_env(env, skip_render_check=True)
        print(f"env_checker ok ({time.time() - t0:.1f}s)")

        obs, info = env.reset(seed=0)
        print("path:", info["path_source"], f"{env.path.length:.0f} m", "| obs:", obs.round(2))
        total, steps, acts = 0.0, 0, Counter()
        t0 = time.time()
        frames0 = None
        while True:
            a = env.action_space.sample()
            acts[ACTION_NAMES[a]] += 1
            obs, r, term, trunc, info = env.step(a)
            assert env.observation_space.contains(obs), obs
            if frames0 is None and env.snap.get("hasStarted"):
                frames0 = env.snap["frames"]
            total += r
            steps += 1
            if term or trunc:
                break
        wall = time.time() - t0
        print(f"episode: {steps} steps, return {total:.2f}, end={info['end_reason']}, "
              f"sim {info['time_s']:.2f}s, wall {wall:.1f}s, progress {info['progress_m']:.1f} m, "
              f"cp {info['checkpoint']}")
        print("actions:", dict(acts))
        print("blocked:", env.browser.blocked)
    finally:
        env.close()


if __name__ == "__main__":
    test_env_checker_and_random_episode()
