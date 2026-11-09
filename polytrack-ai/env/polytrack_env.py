"""Gymnasium environment for PolyTrack (official build, driven through Playwright).

Control: fixed `control_hz` in *simulation* time. Each step presses the keys of the chosen action
and waits until the physics has advanced 1000/control_hz frames (1 frame = 1 ms). Inputs reach the
physics worker a few ms after the target frame (browser round trip), so they land a few frames late;
the game timestamps them itself, nothing is lost.

Actions (Discrete 9): throttle {gas, brake, none} x steer {left, straight, right}.
Reset: T (VehicleStartReset = full race restart). R would only respawn at the last checkpoint.
"""
from __future__ import annotations

import json
import math
import time
from pathlib import Path

import gymnasium as gym
import numpy as np
from gymnasium import spaces

from .browser import PolyTrackBrowser
from .track import TrackPath

ROOT = Path(__file__).resolve().parents[1]

THROTTLE = [("KeyW",), ("KeyS",), ()]          # gas, brake/reverse, none
STEER = [("KeyA",), (), ("KeyD",)]             # left, straight, right
ACTIONS = [t + s for t in THROTTLE for s in STEER]
ACTION_NAMES = [f"{tn}+{sn}" for tn in ("gas", "brake", "none") for sn in ("left", "straight", "right")]

# action_space "keys16": the action IS the key bitmask (1 up, 2 right, 4 down, 8 left) -> all 16
# combinations, incl. gas+brake and left+right which top players use.
KEY_BITS = (("KeyW", 1), ("KeyD", 2), ("KeyS", 4), ("KeyA", 8))
ACTIONS16 = [tuple(k for k, bit in KEY_BITS if m & bit) for m in range(16)]
ACTION_NAMES16 = ["+".join(n for n, bit in (("up", 1), ("right", 2), ("down", 4), ("left", 8)) if m & bit) or "none"
                  for m in range(16)]

DEFAULTS = {
    "track_path": None,
    "headless": True,
    "watch": False,
    "control_hz": 20,
    "max_episode_s": 60,
    "no_progress_s": 4,
    "max_off_track_m": 25,
    "lookahead_m": [10, 25, 50],
    "no_reverse": True,
    "brake_min_kmh": 10,
    "reward": {
        "progress_per_m": 0.1, "time_per_step": -0.01, "standstill": -0.1, "standstill_kmh": 5,
        "reverse": -0.2, "checkpoint": 2.0, "crash": -10.0, "finish_base": 20.0, "finish_time_bonus": 80.0,
        "steer_change": -0.03, "wall_hit_per_1000": 0.0, "wall_hit_cap": 10.0, "speed_bonus": 0.0,
    },
}


class PolyTrackEnv(gym.Env):
    metadata = {"render_modes": []}

    def __init__(self, config: dict | None = None):
        super().__init__()
        cfg = {**DEFAULTS, **(config or {})}
        cfg["reward"] = {**DEFAULTS["reward"], **(config or {}).get("reward", {})}
        self.cfg = cfg
        self.rw = cfg["reward"]
        self.frames_per_step = int(round(1000 / cfg["control_hz"]))
        # per-step reward terms were tuned at 20 Hz; scale them so their effect per sim second stays the same
        self.step_scale = 20.0 / cfg["control_hz"]
        self.max_frames = int(cfg["max_episode_s"] * 1000)
        self.lookahead = list(cfg["lookahead_m"])

        self.keys16 = cfg.get("action_space") == "keys16"
        self.actions = ACTIONS16 if self.keys16 else ACTIONS
        self.action_names = ACTION_NAMES16 if self.keys16 else ACTION_NAMES
        self.action_space = spaces.Discrete(len(self.actions))
        # speed, sin/cos heading error, lateral, progress, time, steering, fwd.y, wheels, cp fraction,
        # + per lookahead point: forward/right/up offset in car frame
        self.obs_dim = 10 + 3 * len(self.lookahead)
        self.observation_space = spaces.Box(-10.0, 10.0, shape=(self.obs_dim,), dtype=np.float32)

        self.browser: PolyTrackBrowser | None = None
        self.path: TrackPath | None = None
        self.track_info: dict | None = None
        self._pressed: set[str] = set()

    # ------------------------------------------------------------------ browser
    def _ensure_browser(self):
        if self.browser is not None:
            return
        headless = self.cfg["headless"] and not self.cfg["watch"]
        # small viewport for unwatched instances: the game renders every frame (software GL when headless)
        viewport = (1280, 800) if not headless else tuple(self.cfg.get("headless_viewport", (320, 200)))
        render_fps = 0 if not headless else self.cfg.get("headless_render_fps", 0)
        self.browser = PolyTrackBrowser(headless=headless, viewport=viewport, log_blocked=False,
                                        render_fps=render_fps, time_scale_patch=True,
                                        record_video_dir=self.cfg.get("record_video_dir"),
                                        cdp_endpoint=self.cfg.get("cdp_endpoint") if headless else None).start()
        self.browser.open_game()
        self.frame = self.browser.game_frame()
        self.page = self.browser.page
        # wait until the race scene exists (player car created), then focus the game canvas
        self._wait_js("window.__pt.player !== null", 180000)
        # keyboard focus: click the game iframe itself (works for any viewport size)
        self.page.locator("iframe#game_drop").click(position=None, timeout=10000)
        # physics clock speed-up (worker performance.now scaled; fixed 1 ms steps -> identical physics)
        self.browser.set_time_scale(self.cfg.get("time_scale", 1))

    def _wait_js(self, expr: str, timeout_ms: int):
        self.frame.wait_for_function(expr, timeout=timeout_ms)

    def _set_keys(self, keys: tuple[str, ...]):
        want = set(keys)
        for k in self._pressed - want:
            self.page.keyboard.up(k)
        for k in want - self._pressed:
            self.page.keyboard.down(k)
        self._pressed = want

    def _load_path(self):
        self.track_info = self.frame.evaluate("window.__pt.trackInfo()")
        tp = self.cfg.get("track_path")
        if tp and (ROOT / tp).exists():
            self.path = TrackPath.from_file(ROOT / tp)
        else:
            self.path = TrackPath.from_track_info(self.track_info)
        self.total_cp = int(self.track_info["totalCheckpoints"])
        # arc length of every checkpoint (by order) on the line: progress is capped at the next
        # uncollected one, so a shortcut that skips a checkpoint earns nothing
        by_order: dict[int, list] = {}
        for c in self.track_info["checkpoints"]:
            by_order.setdefault(c["order"], []).append((c["x"], c["y"], c["z"]))
        pts = [np.mean(v, axis=0) for _, v in sorted(by_order.items())]
        self.cp_s = self.path.arc_lengths_of(pts)

    # ------------------------------------------------------------------ gym API
    def reset(self, *, seed=None, options=None):
        super().reset(seed=seed)
        attempts = self.cfg.get("reset_attempts", 10)
        for attempt in range(attempts):
            try:
                return self._reset()
            except Exception as e:  # noqa: BLE001
                print(f"[env] reset failed (attempt {attempt + 1}: {type(e).__name__}: {str(e)[:160]})")
                self._kill_browser()
                # flaky networks (DNS hiccups, connection resets): back off instead of failing fast
                time.sleep(min(60, 10 * (attempt + 1)))
        raise RuntimeError(f"PolyTrackEnv: reset failed {attempts} times")

    def _reset(self):
        self._ensure_browser()
        self._set_keys(())
        # T on a driven race creates a new player car (CreateCar -> __pt.state = null).
        # On a race that never started T does nothing, and nothing needs resetting.
        driven = self.frame.evaluate("window.__pt.state !== null")
        if driven:
            old_player = self.frame.evaluate("JSON.stringify(window.__pt.player)")
            self.page.keyboard.press("KeyT")
            self._wait_js(f"JSON.stringify(window.__pt.player) !== {old_player!r}", 10000)
            self.page.wait_for_timeout(100)
        if self.path is None:
            self._load_path()

        snap = self.browser.snapshot()
        if not snap.get("ready"):
            snap = self._idle_snapshot()
        self.seg = None
        self.s, self.seg, _, _ = self._project(snap)
        self.best_s = self.s
        self.last_progress_frame = 0
        self.steps = 0
        self.last_cp = snap.get("nextCheckpointIndex", 0)
        self.ep_return = 0.0
        self.last_steer = (False, False)  # (left key, right key)
        self.steer_changes = 0
        # collision counters in the page are running totals -> remember the baseline
        self.coll_base = float(self.frame.evaluate("window.__pt.collisionSum"))
        self.wall_impulse_ep = 0.0
        self._reload_reward()
        self.snap = snap
        return self._obs(snap), self._info(snap)

    def _reload_reward(self):
        """Pick up reward weights edited in config.yaml while training runs (checked once per episode)."""
        path = self.cfg.get("config_file")
        if not path:
            return
        try:
            p = Path(path)
            mtime = p.stat().st_mtime
            if mtime == getattr(self, "_cfg_mtime", None):
                return
            self._cfg_mtime = mtime
            import yaml
            env_cfg = (yaml.safe_load(p.read_text(encoding="utf-8")) or {}).get("env", {})
            self.rw = {**DEFAULTS["reward"], **env_cfg.get("reward", {})}
            for k in ("max_off_track_m", "no_progress_s", "route_jump_m", "route_jump_max_dist"):
                if k in env_cfg:
                    self.cfg[k] = env_cfg[k]
            ts = env_cfg.get("time_scale")
            if ts is not None and ts != self.cfg.get("time_scale"):
                self.set_time_scale(ts)
                print(f"[env] time_scale -> {ts}")
        except Exception as e:  # noqa: BLE001 - keep old weights on a half-saved/broken file
            print(f"[env] reward reload skipped: {e}")

    def step(self, action):
        try:
            return self._step(action)
        except Exception as e:  # noqa: BLE001 - browser crash/hang: restart it on the next reset
            print(f"[env] step failed ({type(e).__name__}: {str(e)[:200]}), restarting browser")
            self._kill_browser()
            info = {"end_reason": "error", "error": str(e)[:200], "progress_m": 0.0, "time_s": 0.0,
                    "finished": False, "checkpoint": 0}
            return np.zeros(self.obs_dim, dtype=np.float32), 0.0, False, True, info

    def _kill_browser(self):
        try:
            if self.browser is not None:
                self.browser.close()
        except Exception:  # noqa: BLE001
            pass
        self.browser = None
        self._pressed = set()

    def step_exact(self, masks: list[int], action: int):
        """Advance with an explicit per-frame key bitmask list (imitation data); `action` is only used
        for bookkeeping (steering-change count). Same reward/termination as step()."""
        return self._step(action, exact_masks=masks)

    def _step(self, action, exact_masks: list[int] | None = None):
        keys = self.actions[int(action)]
        # no reversing: below brake_min_kmh the brake key alone (= reverse when slow) is dropped;
        # gas+brake together is a driving technique and stays
        if self.cfg.get("no_reverse", True) and "KeyS" in keys and "KeyW" not in keys and \
                self.snap.get("speedKmh", 0.0) < self.cfg.get("brake_min_kmh", 10):
            keys = tuple(k for k in keys if k != "KeyS")
        prev = self.snap
        if exact_masks is not None:
            snap = self.frame.evaluate("(m) => window.__pt.stepFrames(m)", list(exact_masks))
            if not snap.get("ready"):
                snap = self._idle_snapshot()
        elif self.cfg.get("control_mode") == "lockstep":
            # frame-exact: the worker advances exactly frames_per_step physics frames with these controls
            ctrl = {"up": "KeyW" in keys, "down": "KeyS" in keys, "left": "KeyA" in keys, "right": "KeyD" in keys}
            snap = self.frame.evaluate(f"window.__pt.stepPlayer({json.dumps(ctrl)}, {self.frames_per_step})")
            if not snap.get("ready"):
                snap = self._idle_snapshot()
        elif prev.get("ready") and prev["hasStarted"]:
            self._set_keys(keys)
            target = prev["frames"] + self.frames_per_step
            snap = self.frame.evaluate(f"window.__pt.waitFrames({target}, 3000)")
        else:
            self._set_keys(keys)
            # race clock starts with the first input; until then physics frames stand still
            self.page.wait_for_timeout(1000 / self.cfg["control_hz"] / max(self.cfg.get("time_scale", 1), 1))
            snap = self.browser.snapshot()
            if not snap.get("ready"):
                snap = self._idle_snapshot()
        self.steps += 1

        s, seg, dist, _ = self._project(snap)
        ds = s - self.s
        self.s, self.seg = s, seg
        r = self.rw
        k = self.step_scale
        reward = r["progress_per_m"] * ds + r["time_per_step"] * k
        v = snap.get("speedKmh", 0.0)
        if abs(v) < r["standstill_kmh"]:
            reward += r["standstill"] * k
        if v < -1:
            reward += r["reverse"] * k
        # wall contact: sum of the game's collision impulses over all physics frames of this step.
        # Measured per 50-frame step: free driving 0, scraping/pushing a wall ~400-570, hard hit 3000-10000.
        coll = float(snap.get("collisionSum", self.coll_base))
        impulse = max(0.0, coll - self.coll_base)
        self.coll_base = coll
        self.wall_impulse_ep += impulse
        reward += r.get("wall_hit_per_1000", 0.0) * min(impulse / 1000.0, r.get("wall_hit_cap", 10.0))
        # speed bonus: only the velocity component along the track direction counts
        if snap.get("hasStarted"):
            reward += r.get("speed_bonus", 0.0) * k * max(0.0, v * self._heading_cos(snap)) / 300.0
        # clean driving: every change of steering direction (left/straight/right) costs a little
        steer = ("KeyA" in keys, "KeyD" in keys)
        if steer != self.last_steer and snap.get("hasStarted"):
            reward += r.get("steer_change", 0.0)
            self.steer_changes += 1
        self.last_steer = steer
        cp = snap.get("nextCheckpointIndex", 0)
        if cp > self.last_cp:
            reward += r["checkpoint"] * (cp - self.last_cp)
        self.last_cp = cp

        frames = snap.get("frames", 0)
        if s > self.best_s + 1.0:
            self.best_s = s
            self.last_progress_frame = frames
        terminated = truncated = False
        reason = None
        if snap.get("finished"):
            t = snap["finishTimeS"]
            reward += r["finish_base"] + r["finish_time_bonus"] * max(0.0, 1 - t / self.cfg["max_episode_s"])
            terminated, reason = True, "finish"
        elif dist > self.cfg["max_off_track_m"]:
            reward += r["crash"]
            terminated, reason = True, "crash"
        elif frames >= self.max_frames:
            truncated, reason = True, "timeout"
        elif self._stalled(snap):
            truncated, reason = True, "no_progress"

        self.ep_return += reward
        self.snap = snap
        info = self._info(snap)
        info.update(progress_m=s, dist_to_path=dist, end_reason=reason, steer_changes=self.steer_changes,
                    steps=self.steps, wall_impulse=self.wall_impulse_ep)
        if terminated or truncated:
            self._set_keys(())
        return self._obs(snap), float(reward), terminated, truncated, info

    def set_time_scale(self, scale: float):
        self.cfg["time_scale"] = scale
        if self.browser is not None:
            self.browser.set_time_scale(scale)

    def freeze(self, frozen: bool = True):
        """Stop/resume the physics clock (PauseCar) e.g. while PPO updates between rollouts."""
        if self.browser is None or self.cfg.get("control_mode") == "lockstep":
            return  # lockstep: the car only moves when stepped, unpausing would let real time move it
        try:
            self.frame.evaluate(f"window.__pt.pausePlayer({'true' if frozen else 'false'})")
            if not frozen:
                # frames advanced between the last step and the pause -> next step counts from here
                snap = self.browser.snapshot()
                if snap.get("ready"):
                    self.snap = snap
        except Exception:  # noqa: BLE001
            pass

    def close(self):
        if self.browser is not None:
            try:
                self._set_keys(())
            except Exception:  # noqa: BLE001 - browser may already be gone
                pass
            self.browser.close()
            self.browser = None

    # ------------------------------------------------------------------ helpers
    def _stalled(self, snap) -> bool:
        limit = self.cfg["no_progress_s"]
        if snap.get("hasStarted"):
            return (snap["frames"] - self.last_progress_frame) >= limit * 1000
        # not started yet: count wall steps instead of frames
        return self.steps >= limit * self.cfg["control_hz"]

    def _idle_snapshot(self) -> dict:
        st = self.track_info["start"] if self.track_info else None
        pos = st["position"] if st else {"x": 0, "y": 0, "z": 0}
        q = st["quaternion"] if st else {"_x": 0, "_y": 0, "_z": 0, "_w": 1}
        qx, qy, qz, qw = q["_x"], q["_y"], q["_z"], q["_w"]
        fwd = {"x": 2 * (qx * qz + qw * qy), "y": 2 * (qy * qz - qw * qx), "z": 1 - 2 * (qx * qx + qy * qy)}
        return {"ready": True, "frames": 0, "timeS": 0.0, "speedKmh": 0.0, "hasStarted": False,
                "finished": False, "finishTimeS": None, "nextCheckpointIndex": 0, "position": pos,
                "forward": fwd, "steering": 0.0, "wheelsOnGround": 4}

    def _project(self, snap):
        p = snap["position"]
        s, seg, dist, lat = self.path.project_route(
            (p["x"], p["y"], p["z"]), hint_seg=self.seg,
            far_m=self.cfg.get("route_jump_m", 0.0), jump_max_dist=self.cfg.get("route_jump_max_dist", 6.0))
        cp = snap.get("nextCheckpointIndex", 0)
        if getattr(self, "cp_s", None) and cp < len(self.cp_s):
            s = min(s, self.cp_s[cp] + 5.0)  # no credit past a checkpoint that was not collected
        return s, seg, dist, lat

    def _heading_cos(self, snap) -> float:
        """cos of the angle between car forward and the path tangent (xz plane)."""
        f = np.array([snap["forward"]["x"], 0.0, snap["forward"]["z"]])
        t = self.path.tangent(self.seg)
        t = np.array([t[0], 0.0, t[2]])
        n = np.linalg.norm(f) * np.linalg.norm(t)
        return float(f @ t / n) if n > 1e-6 else 0.0

    def _obs(self, snap) -> np.ndarray:
        p = np.array([snap["position"][k] for k in "xyz"])
        f = np.array([snap["forward"][k] for k in "xyz"])
        fh = np.array([f[0], 0.0, f[2]])
        fh /= max(np.linalg.norm(fh), 1e-6)
        right = np.array([-fh[2], 0.0, fh[0]])
        tan = self.path.tangent(self.seg)
        th = np.array([tan[0], 0.0, tan[2]])
        th /= max(np.linalg.norm(th), 1e-6)
        # heading error: angle from path tangent to car forward (xz plane)
        sin_e = th[0] * fh[2] - th[2] * fh[0]
        cos_e = float(th @ fh)
        _, _, _, lateral = self.path.project(p, hint_seg=self.seg)
        obs = [
            snap["speedKmh"] / 300.0,
            sin_e, cos_e,
            lateral / 10.0,
            self.s / self.path.length,
            snap["frames"] / self.max_frames,
            float(snap.get("steering", 0.0)),
            f[1],
            snap.get("wheelsOnGround", 4) / 4.0,
            snap.get("nextCheckpointIndex", 0) / max(self.total_cp, 1),
        ]
        for d in self.lookahead:
            rel = self.path.point_at(self.s + d) - p
            obs += [rel @ fh / 50.0, rel @ right / 50.0, rel[1] / 20.0]
        return np.clip(np.array(obs, dtype=np.float32), -10, 10)

    def _info(self, snap) -> dict:
        return {
            "time_s": snap.get("timeS", 0.0), "speed_kmh": snap.get("speedKmh", 0.0),
            "checkpoint": snap.get("nextCheckpointIndex", 0), "finished": bool(snap.get("finished")),
            "finish_time_s": snap.get("finishTimeS"), "path_source": self.path.source if self.path else None,
        }
