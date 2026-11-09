"""Learning curves from the TensorBoard logs of a run -> docs/learning_curves.png.

Usage: python scripts/report.py [--run summer1_20261015_114307]
Three small multiples sharing the step axis (no dual axes): progress per episode, finish time,
steering changes. Reference lines: own lap (recorded line) and the reported world record.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
from tensorboard.backend.event_processing.event_accumulator import EventAccumulator  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
SERIES = "#2a78d6"      # categorical slot 1 (dataviz reference palette)
INK, INK2, GRID, SURFACE = "#0b0b0b", "#52514e", "#e6e5e1", "#fcfcfb"
REFS = {"Eigene Runde 25,99 s": 25.991, "WR 22,123 s (Monstrosity, verifiziert)": 22.123}
PHASES = {1_000_704: "Lockstep, 40 Hz", 1_574_685: "WR-Linie"}


def scalars(ea, tag):
    if tag not in ea.Tags()["scalars"]:
        return np.array([]), np.array([])
    ev = ea.Scalars(tag)
    return np.array([e.step for e in ev]), np.array([e.value for e in ev])


def smooth(y, k=9):
    if len(y) < k:
        return y
    pad = np.pad(y, (k // 2, k // 2), mode="edge")
    return np.convolve(pad, np.ones(k) / k, mode="valid")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", default="summer1_20261015_114307")
    args = ap.parse_args()
    logdirs = sorted((ROOT / "logs").glob(f"{args.run}_*"))
    ea = EventAccumulator(str(logdirs[-1]), size_guidance={"scalars": 0})
    ea.Reload()

    panels = [
        ("race/ep_progress_m", "Fortschritt pro Versuch (m; Linie bis 1,57 M: eigene Runde 1382 m, danach WR-Linie 1318 m)", True),
        ("race/finish_time_s", "Rundenzeit im Ziel (s)", False),
        ("race/steer_changes_per_100_steps", "Lenkwechsel pro 100 Schritte", True),
    ]
    plt.rcParams.update({"font.size": 10, "axes.edgecolor": GRID, "axes.labelcolor": INK2,
                         "xtick.color": INK2, "ytick.color": INK2})
    fig, axes = plt.subplots(3, 1, figsize=(9, 9), sharex=True, facecolor=SURFACE)
    for ax, (tag, title, do_smooth) in zip(axes, panels):
        ax.set_facecolor(SURFACE)
        x, y = scalars(ea, tag)
        ax.set_title(title, loc="left", color=INK, fontsize=11)
        ax.grid(axis="y", color=GRID, linewidth=0.8)
        ax.spines[["top", "right"]].set_visible(False)
        if len(x) == 0:
            ax.text(0.5, 0.5, "keine Daten", transform=ax.transAxes, ha="center", color=INK2)
            continue
        if do_smooth:
            ax.plot(x, y, color=SERIES, alpha=0.25, linewidth=1)
            ax.plot(x, smooth(y), color=SERIES, linewidth=2)
        else:
            ax.plot(x, y, "o", color=SERIES, markersize=4, markeredgecolor=SURFACE, markeredgewidth=1)
            for label, val in REFS.items():
                ax.axhline(val, color=INK2, linewidth=1, linestyle="--")
                ax.text(x.min(), val, f"{label} ", va="bottom", ha="left", color=INK2, fontsize=9)
        for step, label in PHASES.items():
            if x.min() < step < x.max() * 1.01:
                ax.axvline(step, color=INK2, linewidth=1, linestyle=":")
        if ax is axes[0]:
            for step, label in PHASES.items():
                ax.text(step, ax.get_ylim()[1], f"{label} ", va="top", ha="right", color=INK2, fontsize=9)
    axes[-1].set_xlabel("Trainingsschritte")
    axes[-1].xaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda v, _: f"{v / 1e6:.1f} M"))
    fig.tight_layout()
    out = ROOT / "docs" / "learning_curves.png"
    fig.savefig(out, dpi=130, facecolor=SURFACE)
    print("saved", out)


if __name__ == "__main__":
    main()
