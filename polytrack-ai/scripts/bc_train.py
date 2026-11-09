"""Behaviour cloning: pre-train a PPO policy (and its value head) on the top-run demonstrations.

Policy: cross-entropy towards the expert key combination. Value: discounted return-to-go of the
demo rewards, scaled exactly like VecNormalize will scale rewards during PPO (the scale is saved and
used to seed VecNormalize, so the pre-trained value head matches from the first update).

Usage: python scripts/bc_train.py [--data demos/summer1_top10.npz] [--epochs 60]
Output: models/<run>/bc_init.zip + bc_meta.json (run = summer1_bc_<date>)
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

import numpy as np
import torch
import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from stable_baselines3 import PPO  # noqa: E402

from env import PolyTrackEnv  # noqa: E402


def discounted(rew: np.ndarray, gamma: float) -> np.ndarray:
    out, g = np.zeros_like(rew), 0.0
    for t in range(len(rew) - 1, -1, -1):
        g = rew[t] + gamma * g
        out[t] = g
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="demos/summer1_top10.npz")
    ap.add_argument("--epochs", type=int, default=60)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--holdout", type=int, default=1, help="demos kept out for validation")
    args = ap.parse_args()

    cfg_all = yaml.safe_load((ROOT / "config.yaml").read_text(encoding="utf-8"))
    ec, ppo_cfg = cfg_all["env"], cfg_all["train"]["ppo"]
    gamma = ppo_cfg["gamma"]
    d = np.load(ROOT / args.data)
    obs, act, rew, ep = d["obs"], d["actions"], d["rewards"], d["episode"]

    # reward scale as VecNormalize computes it: std of the running discounted return (ret = ret*gamma + r)
    rets = []
    for e in np.unique(ep):
        ret = 0.0
        for r in rew[ep == e]:
            ret = ret * gamma + r
            rets.append(ret)
    ret_var = float(np.var(rets))
    scale = float(np.sqrt(ret_var + 1e-8))
    clip = 10.0
    vtarget = np.concatenate([discounted(np.clip(rew[ep == e] / scale, -clip, clip), gamma) for e in np.unique(ep)])
    print(f"[bc] {len(act)} Paare, {len(np.unique(ep))} Fahrten, Reward-Skala {scale:.2f}, "
          f"Value-Ziele {vtarget.min():.2f}..{vtarget.max():.2f}")

    eps = np.unique(ep)
    val_eps = set(eps[:args.holdout].tolist())
    tr = np.array([e not in val_eps for e in ep])
    va = ~tr

    env = PolyTrackEnv({**ec, "action_space": "keys16"})  # spaces only, no browser is started
    model = PPO("MlpPolicy", env, device="cpu", seed=0, **{k: v for k, v in ppo_cfg.items()})
    pol = model.policy
    opt = torch.optim.Adam(pol.parameters(), lr=args.lr)
    O = torch.as_tensor(obs)
    A = torch.as_tensor(act)
    V = torch.as_tensor(vtarget, dtype=torch.float32)
    tri, vai = np.where(tr)[0], np.where(va)[0]
    rng = np.random.default_rng(0)
    for epoch in range(args.epochs):
        pol.train()
        rng.shuffle(tri)
        for k in range(0, len(tri), 256):
            b = tri[k:k + 256]
            values, logp, _ = pol.evaluate_actions(O[b], A[b])
            loss = -logp.mean() + 0.5 * torch.nn.functional.mse_loss(values.flatten(), V[b])
            opt.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(pol.parameters(), 0.5)
            opt.step()
        if epoch % 10 == 9 or epoch == args.epochs - 1:
            pol.eval()
            with torch.no_grad():
                def acc(idx):
                    dist = pol.get_distribution(O[idx])
                    return float((dist.distribution.probs.argmax(1) == A[idx]).float().mean())
                v_err = float(torch.nn.functional.mse_loss(pol.predict_values(O[vai]).flatten(), V[vai])) if len(vai) else 0
            print(f"[bc] Epoche {epoch + 1}: Trefferquote Training {acc(tri):.1%}, Validierung {acc(vai):.1%}, "
                  f"Value-MSE (Val.) {v_err:.3f}")

    run = f"summer1_bc_{datetime.now():%Y%m%d_%H%M%S}"
    run_dir = ROOT / "models" / run
    run_dir.mkdir(parents=True, exist_ok=True)
    model.save(run_dir / "bc_init")
    (run_dir / "bc_meta.json").write_text(json.dumps({
        "data": args.data, "pairs": int(len(act)), "reward_scale": scale, "ret_var": ret_var,
        "ret_count": len(rets), "gamma": gamma, "epochs": args.epochs, "action_space": "keys16",
        "control_hz": ec["control_hz"]}, indent=1), encoding="utf-8")
    (run_dir / "config.yaml").write_text(yaml.safe_dump(cfg_all, allow_unicode=True), encoding="utf-8")
    print(f"[bc] gespeichert: {run_dir / 'bc_init.zip'}")


if __name__ == "__main__":
    main()
