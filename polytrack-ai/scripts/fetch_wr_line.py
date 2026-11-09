"""Get the driving line of a leaderboard run (default: #1 = world record) for the current track.

Reads (GET only) the public leaderboard and the run's recording from the PolyTrack backend - the same
requests the game makes for its ghost/spectate feature - then replays the recorded inputs frame-exactly
in the game's own physics worker and samples the car position. Nothing is ever sent/uploaded.

Usage: python scripts/fetch_wr_line.py [--rank 1] [--name summer1_wr] [--every 25]
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from env.browser import PolyTrackBrowser  # noqa: E402
from env.track import TrackPath  # noqa: E402

API = "https://vps.kodub.com/v6/"
VERSION = "0.6.3"


def get_json(frame, endpoint: str, **params) -> object:
    """GET from inside the official game page (the server only serves the official client)."""
    url = API + endpoint + "?" + urllib.parse.urlencode({"version": VERSION, **params})
    res = frame.evaluate("""async (url) => { const r = await fetch(url, {method: 'GET'});
        return {status: r.status, text: await r.text()}; }""", url)
    if res["status"] != 200:
        raise SystemExit(f"GET {endpoint} -> HTTP {res['status']}: {res['text'][:200]}")
    return json.loads(res["text"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rank", type=int, default=1)
    ap.add_argument("--name", default="summer1_wr")
    ap.add_argument("--every", type=int, default=25)
    ap.add_argument("--only-verified", default="true")
    args = ap.parse_args()

    with PolyTrackBrowser(headless=True, time_scale_patch=True, log_blocked=True, allow_leaderboard_read=True) as b:
        f = b.open_game()
        f.wait_for_function("window.__pt.player !== null && window.__pt.track !== null", timeout=180000)
        track_id = f.evaluate("window.__pt.track.getTrackData().getId()")
        print("trackId:", track_id)

        lb = get_json(f, "leaderboard", trackId=track_id, skip=args.rank - 1, amount=1, onlyVerified=args.only_verified)
        print("leaderboard total:", lb["total"])
        entry = lb["entries"][0]
        print(f"rank {args.rank}: {entry['nickname']}  {entry['frames'] / 1000:.3f}s  id={entry['id']}  "
              f"verified={entry.get('verifiedState')}")
        recs = get_json(f, "recordings", ids=str(entry["id"]))
        recording = recs[0]["recording"]
        print("recording length:", len(recording), "chars")

        f.evaluate(f"window.__pt.startTrace({args.every})")
        snap = None
        for _ in range(10000):
            snap = f.evaluate("([r, n]) => window.__pt.replayPlayer(r, n)", [recording, 1000])
            if snap.get("finished") or snap.get("frames", 0) > entry["frames"] + 2000:
                break
        rows = f.evaluate("window.__pt.stopTrace()")
        print(f"replay: finished={snap.get('finished')} time={snap.get('finishTimeS')}s "
              f"(leaderboard {entry['frames'] / 1000:.3f}s) cp={snap.get('nextCheckpointIndex')}")
        if not snap.get("finished"):
            raise SystemExit("replay did not finish - recording/physics mismatch, line not saved")

        fin = int(round(snap["finishTimeS"] * 1000))
        pts = np.array([r[1:4] for r in rows if r[0] <= fin])
        path = TrackPath(pts, "wr")
        out = ROOT / "tracks" / f"{args.name}.json"
        path.save(out, {"source": "leaderboard replay", "rank": args.rank, "nickname": entry["nickname"],
                        "finish_time_s": snap["finishTimeS"], "leaderboard_frames": entry["frames"],
                        "trackId": track_id, "every_frames": args.every})
        print(f"saved {out}: {len(path.points)} points, {path.length:.0f} m")
        print("blocked backend requests from the page:", b.blocked)


if __name__ == "__main__":
    main()
