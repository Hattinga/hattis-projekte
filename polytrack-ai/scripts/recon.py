"""Recon: load the official itch.io page, list frames and network requests, save game JS for reading.

Usage: python scripts/recon.py <out_dir> [--headed] [--seconds N]
"""
import json
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

URL = "https://kodub.itch.io/polytrack"


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    headed = "--headed" in sys.argv
    seconds = int(sys.argv[sys.argv.index("--seconds") + 1]) if "--seconds" in sys.argv else 20

    requests = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=not headed, args=["--mute-audio"])
        page = browser.new_page(viewport={"width": 1280, "height": 800})

        def on_response(resp):
            req = resp.request
            entry = {"method": req.method, "url": req.url, "status": resp.status,
                     "type": req.resource_type, "frame": req.frame.url if req.frame else None}
            if req.method != "GET":
                entry["post"] = (req.post_data or "")[:500]
            requests.append(entry)
            if req.resource_type == "script" and "itch" not in req.url.split("/")[2][:4]:
                try:
                    body = resp.body()
                    name = req.url.split("?")[0].rstrip("/").split("/")[-1] or "index.js"
                    (out / name).write_bytes(body)
                except Exception as e:  # noqa: BLE001
                    entry["save_error"] = str(e)

        page.on("response", on_response)
        page.goto(URL, wait_until="domcontentloaded")

        # itch.io shows a "Run game" button for click-to-launch embeds
        for sel in [".load_iframe_btn", "button:has-text('Run game')"]:
            btn = page.locator(sel)
            if btn.count():
                btn.first.click()
                break

        time.sleep(seconds)
        frames = [{"name": f.name, "url": f.url} for f in page.frames]
        page.screenshot(path=str(out / "screenshot.png"))
        browser.close()

    (out / "frames.json").write_text(json.dumps(frames, indent=2))
    (out / "requests.json").write_text(json.dumps(requests, indent=2))
    print(json.dumps(frames, indent=2))
    print(len(requests), "requests")
    for r in requests:
        if r["method"] != "GET" or r["type"] in ("xhr", "fetch", "websocket"):
            print(r["method"], r["status"], r["type"], r["url"][:160])


if __name__ == "__main__":
    main()
