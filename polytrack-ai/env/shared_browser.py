"""One shared headless Chromium for several envs (each env attaches via CDP and gets its own context).

Saves the per-browser processes (browser, GPU, network, utility) for every env. The game itself still
runs in one renderer per context, so CPU use drops much less than RAM.
"""
from __future__ import annotations

import json
import os
import socket
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path

from playwright.sync_api import sync_playwright

FLAGS = [
    "--headless=new",
    "--mute-audio",
    "--autoplay-policy=no-user-gesture-required",
    "--no-first-run",
    "--no-default-browser-check",
    # all envs live in one browser: never throttle a context because it counts as "in the background"
    "--disable-background-timer-throttling",
    "--disable-renderer-backgrounding",
    "--disable-backgrounding-occluded-windows",
]


def _headless_shell() -> str | None:
    """Playwright's lean chrome-headless-shell (what launch(headless=True) uses) - less RAM than Chrome."""
    root = Path(os.environ.get("PLAYWRIGHT_BROWSERS_PATH") or Path.home() / "AppData/Local/ms-playwright")
    hits = sorted(root.glob("chromium_headless_shell-*/chrome-headless-shell-*/chrome-headless-shell*"))
    hits = [h for h in hits if h.suffix in (".exe", "")]
    return str(hits[-1]) if hits else None


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class SharedBrowser:
    def __init__(self, port: int | None = None):
        self.port = port or _free_port()
        self.proc: subprocess.Popen | None = None
        self.profile = tempfile.TemporaryDirectory(prefix="polytrack_shared_")

    @property
    def endpoint(self) -> str:
        return f"http://127.0.0.1:{self.port}"

    def start(self, timeout_s: float = 30) -> "SharedBrowser":
        exe, flags = _headless_shell(), [f for f in FLAGS if f != "--headless=new"]
        if exe is None:  # fall back to full Chrome in new headless mode (needs more RAM)
            with sync_playwright() as p:
                exe, flags = p.chromium.executable_path, FLAGS
        self.proc = subprocess.Popen(
            [exe, f"--remote-debugging-port={self.port}", f"--user-data-dir={self.profile.name}", *flags,
             "about:blank"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.time() + timeout_s
        while time.time() < deadline:
            try:
                with urllib.request.urlopen(f"{self.endpoint}/json/version", timeout=1) as r:
                    json.load(r)
                    return self
            except OSError:
                time.sleep(0.3)
        self.stop()
        raise RuntimeError("shared Chromium did not open its debugging port")

    def alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        self.proc = None
        try:
            self.profile.cleanup()
        except OSError:
            pass  # Chromium may still hold files for a moment on Windows

    def __enter__(self):
        return self.start()

    def __exit__(self, *exc):
        self.stop()
