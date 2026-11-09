"""Phase 3: PPO training on PolyTrack with several browsers in parallel.

Usage: python scripts/train.py [--config config.yaml] [--timesteps N] [--n-envs N] [--resume models/<run>/latest.zip]
Watch:  Env 0 opens a visible browser (train.watch_first). TensorBoard:
        .venv\\Scripts\\tensorboard --logdir logs
Stop with Ctrl+C: the current model is saved as models/<run>/latest.zip.
"""
from __future__ import annotations

import argparse
import copy
import json
import sys
import time
from datetime import datetime
from pathlib import Path

import numpy as np
import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from stable_baselines3 import PPO  # noqa: E402
from stable_baselines3.common.callbacks import BaseCallback, CallbackList, CheckpointCallback  # noqa: E402
from stable_baselines3.common.vec_env import SubprocVecEnv, VecMonitor, VecNormalize  # noqa: E402

from env import PolyTrackEnv  # noqa: E402
from env.shared_browser import SharedBrowser  # noqa: E402


def make_env_fn(env_cfg: dict, rank: int, watch: bool, stagger_s: float, config_file: str | None = None):
    def _init():
        import signal
        signal.signal(signal.SIGINT, signal.SIG_IGN)  # Ctrl+C is handled by the main process (saves, then closes envs)
        cfg = copy.deepcopy(env_cfg)
        cfg["headless"] = not watch
        cfg["watch"] = watch
        cfg["config_file"] = config_file  # reward weights hot-reload
        time.sleep(rank * stagger_s)  # stagger itch.io page loads (rate limit)
        return PolyTrackEnv(cfg)
    return _init


class RacingCallback(BaseCallback):
    """Freezes the game clocks during PPO updates and logs racing stats + best models."""

    def __init__(self, run_dir: Path, vecnorm: VecNormalize | None, config_file: Path | None = None):
        super().__init__()
        self.config_file = config_file
        self._cfg_mtime = None
        self.run_dir = run_dir
        self.vecnorm = vecnorm
        self.best_file = run_dir / "best.json"
        best = json.loads(self.best_file.read_text()) if self.best_file.exists() else {}
        self.best_time = best.get("best_time") or float("inf")
        self.best_progress = best.get("best_progress") if best.get("best_progress") is not None else -1.0
        self.ends: dict[str, int] = {}
        self.t0 = time.time()
        self.n0 = None

    def _reload_ppo(self):
        """ent_coef / learning_rate from config.yaml, applied live (checked once per rollout)."""
        if self.config_file is None:
            return
        try:
            mtime = self.config_file.stat().st_mtime
            if mtime == self._cfg_mtime:
                return
            self._cfg_mtime = mtime
            ppo = (yaml.safe_load(self.config_file.read_text(encoding="utf-8")) or {})["train"]["ppo"]
            if float(ppo["ent_coef"]) != self.model.ent_coef:
                self.model.ent_coef = float(ppo["ent_coef"])
                print(f"[train] ent_coef -> {self.model.ent_coef}")
            lr = float(ppo["learning_rate"])
            if self.model.lr_schedule(1.0) != lr:
                self.model.learning_rate = lr
                self.model.lr_schedule = lambda _: lr
                print(f"[train] learning_rate -> {lr}")
        except Exception as e:  # noqa: BLE001 - half-saved file etc.
            print(f"[train] config reload skipped: {e}")

    def _on_rollout_start(self) -> None:
        self._reload_ppo()
        if self.n0 is None:  # measure speed of this session only (resume starts at a high step count)
            self.n0, self.t0 = self.num_timesteps, time.time()
        self.training_env.env_method("freeze", False)

    def _on_rollout_end(self) -> None:
        self.training_env.env_method("freeze", True)
        for k, v in self.ends.items():
            self.logger.record(f"race/end_{k}", v)
        self.logger.record("race/best_progress_m", self.best_progress)
        if self.best_time < float("inf"):
            self.logger.record("race/best_finish_s", self.best_time)
        self.logger.record("time/steps_per_wall_s", (self.num_timesteps - self.n0) / max(time.time() - self.t0, 1e-6))

    def _save(self, name: str):
        self.model.save(self.run_dir / name)
        if self.vecnorm is not None:
            self.vecnorm.save(self.run_dir / f"{name}_vecnormalize.pkl")
        self.best_file.write_text(json.dumps({
            "best_time": None if self.best_time == float("inf") else self.best_time,
            "best_progress": self.best_progress, "num_timesteps": self.num_timesteps}))

    def _on_step(self) -> bool:
        for info, done in zip(self.locals["infos"], self.locals["dones"]):
            if not done:
                continue
            reason = info.get("end_reason") or "unknown"
            self.ends[reason] = self.ends.get(reason, 0) + 1
            prog = float(info.get("progress_m", 0.0))
            self.logger.record_mean("race/ep_progress_m", prog)
            self.logger.record_mean("race/ep_checkpoints", info.get("checkpoint", 0))
            if "wall_impulse" in info:
                self.logger.record_mean("race/wall_impulse_per_ep_k", info["wall_impulse"] / 1000.0)
            if info.get("steps"):
                self.logger.record_mean("race/steer_changes_per_100_steps",
                                        100 * info.get("steer_changes", 0) / info["steps"])
            if info.get("finished") and info.get("finish_time_s") is not None:
                t = float(info["finish_time_s"])
                self.logger.record_mean("race/finish_time_s", t)
                if t < self.best_time:
                    self.best_time = t
                    self._save("best_time")
                    print(f"[train] neue Bestzeit {t:.3f}s bei {self.num_timesteps} Schritten")
            if prog > self.best_progress + 5:
                self.best_progress = prog
                self._save("best_progress")
                print(f"[train] neuer Bestfortschritt {prog:.0f} m bei {self.num_timesteps} Schritten")
        return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=str(ROOT / "config.yaml"))
    ap.add_argument("--timesteps", type=int)
    ap.add_argument("--n-envs", type=int)
    ap.add_argument("--resume")
    ap.add_argument("--init", help="start a NEW run from pre-trained weights (e.g. models/<bc>/bc_init.zip)")
    args = ap.parse_args()

    cfg = yaml.safe_load(Path(args.config).read_text(encoding="utf-8"))
    tc, ec = cfg["train"], cfg["env"]
    n_envs = args.n_envs or tc["n_envs"]
    total = args.timesteps or tc["total_timesteps"]
    resume = args.resume or tc.get("resume")
    resume_norm = None
    if resume:
        rp = Path(resume)
        # models/<run>/best_progress.zip -> best_progress_vecnormalize.pkl
        # models/<run>/checkpoints/ppo_29997_steps.zip -> ppo_vecnormalize_29997_steps.pkl
        for cand in (rp.with_name(rp.stem + "_vecnormalize.pkl"),
                     rp.with_name(rp.stem.replace("ppo_", "ppo_vecnormalize_", 1) + ".pkl")):
            if cand.exists():
                resume_norm = cand
                break
    if tc.get("run_name"):
        run = tc["run_name"]
    elif resume:  # continue in the run folder the model came from
        rp = Path(resume).resolve()
        run = (rp.parent.parent if rp.parent.name == "checkpoints" else rp.parent).name
    elif args.init:  # fresh run that starts from pre-trained weights (behaviour cloning)
        run = f"{cfg.get('track', 'track')}_bcft_{datetime.now():%Y%m%d_%H%M%S}"
    else:
        run = f"{cfg.get('track', 'track')}_{datetime.now():%Y%m%d_%H%M%S}"
    run_dir = ROOT / "models" / run
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "config.yaml").write_text(yaml.safe_dump(cfg, allow_unicode=True), encoding="utf-8")
    print(f"[train] run {run}: {n_envs} Envs, {total} Schritte, Modelle in {run_dir}")

    shared = None
    if tc.get("shared_browser", False):
        # unwatched envs attach to one shared headless Chromium (own context each) instead of own browsers
        shared = SharedBrowser().start()
        ec = {**ec, "cdp_endpoint": shared.endpoint}
        print(f"[train] gemeinsamer Browser für die unsichtbaren Envs: {shared.endpoint}")
    fns = [make_env_fn(ec, i, watch=(i == 0 and tc.get("watch_first", True)), stagger_s=8,
                       config_file=str(Path(args.config).resolve())) for i in range(n_envs)]
    venv = SubprocVecEnv(fns, start_method="spawn")
    venv = VecMonitor(venv)
    vecnorm = None
    if tc.get("normalize_reward", True):
        if resume_norm is not None:
            vecnorm = VecNormalize.load(str(resume_norm), venv)
            print(f"[train] Reward-Normalisierung geladen: {resume_norm.name}")
        else:
            vecnorm = VecNormalize(venv, norm_obs=False, norm_reward=True, gamma=tc["ppo"]["gamma"])
            meta_file = Path(args.init).resolve().parent / "bc_meta.json" if args.init else None
            if meta_file is not None and meta_file.exists():
                # same reward scale the value head was pre-trained with
                meta = json.loads(meta_file.read_text(encoding="utf-8"))
                vecnorm.ret_rms.var[...] = meta["ret_var"]
                vecnorm.ret_rms.count = meta["ret_count"]
                print(f"[train] Reward-Skala aus Vortraining: {meta['reward_scale']:.2f}")
        venv = vecnorm

    ppo_kw = dict(tc["ppo"])
    if resume:
        # values from config.yaml override the saved ones (rollout buffer is rebuilt with them)
        override = {k: ppo_kw[k] for k in ("learning_rate", "gamma", "n_steps", "batch_size", "ent_coef")}
        model = PPO.load(resume, env=venv, tensorboard_log=str(ROOT / "logs"), **override)
        if vecnorm is not None:
            vecnorm.gamma = ppo_kw["gamma"]
        print(f"[train] PPO-Werte aus config: {override}")
        model.verbose = 1
        # total_timesteps is the target for the whole run, not "this many more"
        total = max(total - model.num_timesteps, 0)
        print(f"[train] fortgesetzt von {resume} bei {model.num_timesteps} Schritten, noch {total}")
    elif args.init:
        model = PPO.load(args.init, env=venv, tensorboard_log=str(ROOT / "logs"), **ppo_kw)
        model.verbose = 1
        model.num_timesteps = 0
        print(f"[train] Start mit vortrainierten Gewichten: {args.init} | PPO-Werte: {ppo_kw}")
    else:
        model = PPO("MlpPolicy", venv, verbose=1, seed=tc.get("seed", 0),
                    tensorboard_log=str(ROOT / "logs"), **ppo_kw)

    callbacks = CallbackList([
        CheckpointCallback(save_freq=max(tc["checkpoint_every"] // n_envs, 1), save_path=str(run_dir / "checkpoints"),
                           name_prefix="ppo", save_vecnormalize=vecnorm is not None),
        RacingCallback(run_dir, vecnorm, config_file=Path(args.config).resolve()),
    ])
    try:
        model.learn(total_timesteps=total, callback=callbacks, tb_log_name=run,
                    reset_num_timesteps=not resume, progress_bar=False)
    except KeyboardInterrupt:
        print("\n[train] abgebrochen – speichere latest")
    finally:
        model.save(run_dir / "latest")
        if vecnorm is not None:
            vecnorm.save(run_dir / "latest_vecnormalize.pkl")
        print(f"[train] gespeichert: {run_dir / 'latest.zip'}")
        try:
            venv.close()
        except (EOFError, BrokenPipeError, OSError):
            pass
        if shared is not None:
            shared.stop()


if __name__ == "__main__":
    np.set_printoptions(precision=3, suppress=True)
    main()
