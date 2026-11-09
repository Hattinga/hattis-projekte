"""Reference path along the track: arc-length progress, heading error, lateral offset, lookahead.

The path is either a recorded driving line (scripts/record_path.py -> tracks/<name>.json) or,
as a fallback, straight segments start -> checkpoints (in order) -> finish from the game's own
track data. The fallback is coarse on tracks whose road leaves the direct line between checkpoints.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np


class TrackPath:
    def __init__(self, points: np.ndarray, source: str):
        pts = np.asarray(points, dtype=np.float64)
        # drop consecutive duplicates (standing still while recording)
        keep = np.concatenate([[True], np.linalg.norm(np.diff(pts, axis=0), axis=1) > 0.5])
        self.points = pts[keep]
        if len(self.points) < 2:
            raise ValueError("path needs at least 2 distinct points")
        seg = np.diff(self.points, axis=0)
        self.seg_len = np.linalg.norm(seg, axis=1)
        self.seg_dir = seg / self.seg_len[:, None]
        self.cum = np.concatenate([[0.0], np.cumsum(self.seg_len)])
        self.length = float(self.cum[-1])
        self.source = source

    # --- construction ---
    @classmethod
    def from_track_info(cls, info: dict) -> "TrackPath":
        start = info["start"]["position"]
        cps = sorted(info["checkpoints"], key=lambda c: c["order"])
        # several parts can share one order (wide checkpoints) -> average them
        by_order: dict[int, list] = {}
        for c in cps:
            by_order.setdefault(c["order"], []).append((c["x"], c["y"], c["z"]))
        pts = [(start["x"], start["y"], start["z"])]
        pts += [tuple(np.mean(v, axis=0)) for _, v in sorted(by_order.items())]
        fin = info["finishes"]
        if fin:
            p = np.array(pts[-1])
            nearest = min(fin, key=lambda f: np.linalg.norm(np.array((f["x"], f["y"], f["z"])) - p))
            pts.append((nearest["x"], nearest["y"], nearest["z"]))
        return cls(np.array(pts), "checkpoints")

    @classmethod
    def from_file(cls, path: str | Path) -> "TrackPath":
        data = json.loads(Path(path).read_text())
        return cls(np.array(data["points"]), f"file:{Path(path).name}")

    # --- queries ---
    def project(self, pos, hint_seg: int | None = None, window: tuple[int, int] = (3, 15)):
        """Project a 3D position onto the path.

        With hint_seg, only segments [hint-window0, hint+window1] are searched, so progress cannot
        jump to a different part of the track where it crosses over/under itself.
        Returns (arc_length_s, segment_index, distance_to_path, signed_lateral_xz).
        """
        p = np.asarray(pos, dtype=np.float64)
        n = len(self.seg_len)
        if hint_seg is None:
            lo, hi = 0, n
        else:
            lo, hi = max(0, hint_seg - window[0]), min(n, hint_seg + window[1] + 1)
        a = self.points[lo:hi]
        d = self.seg_dir[lo:hi]
        t = np.clip(np.einsum("ij,ij->i", p - a, d), 0, self.seg_len[lo:hi])
        proj = a + d * t[:, None]
        dist = np.linalg.norm(proj - p, axis=1)
        k = int(np.argmin(dist))
        i = lo + k
        s = float(self.cum[i] + t[k])
        # signed lateral offset in the xz plane: right = dir x up = (-dz, 0, dx), + = right of travel
        dx, dz = self.seg_dir[i][0], self.seg_dir[i][2]
        rx, rz = p[0] - proj[k][0], p[2] - proj[k][2]
        lateral = float(dx * rz - dz * rx)
        return s, i, float(dist[k]), lateral

    def project_route(self, pos, hint_seg: int | None, near=(3, 15), far_m: float = 100.0,
                      jump_max_dist: float = 6.0):
        """Like project(), but lets progress jump ahead along the line (shortcuts) when the car is
        clearly on a later part of it (within jump_max_dist), searching up to far_m ahead."""
        near_res = self.project(pos, hint_seg, window=near)
        if hint_seg is None or far_m <= 0:
            return near_res
        far_segs = max(near[1], int(far_m / max(float(self.seg_len.mean()), 1e-6)))
        far_res = self.project(pos, hint_seg, window=(0, far_segs))
        if far_res[0] > near_res[0] + 1.0 and far_res[2] <= jump_max_dist and far_res[2] < near_res[2]:
            return far_res
        return near_res

    def arc_lengths_of(self, points) -> list[float]:
        """Arc length of each point (in order), searching only forward from the previous one."""
        out, lo = [], 0
        for q in points:
            s, seg, _, _ = self.project(q, hint_seg=lo, window=(0, len(self.seg_len)))
            out.append(s)
            lo = seg
        return out

    def tangent(self, seg: int) -> np.ndarray:
        return self.seg_dir[min(seg, len(self.seg_dir) - 1)]

    def point_at(self, s: float) -> np.ndarray:
        s = float(np.clip(s, 0, self.length))
        i = int(np.clip(np.searchsorted(self.cum, s, side="right") - 1, 0, len(self.seg_len) - 1))
        return self.points[i] + self.seg_dir[i] * (s - self.cum[i])

    def save(self, path: str | Path, meta: dict | None = None):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        Path(path).write_text(json.dumps({"points": self.points.round(3).tolist(), **(meta or {})}))
