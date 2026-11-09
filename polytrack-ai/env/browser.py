"""Playwright wrapper for the official PolyTrack build on itch.io.

- Blocks every write request to the PolyTrack backend (leaderboard submit, verifyRecordings,
  profile) so no bot times can ever reach the online leaderboard.
- Injects env/hooks.js into the game iframe, which exposes window.__pt (see docs/game_state.md).
"""
from __future__ import annotations

import time
from pathlib import Path

from playwright.sync_api import Frame, Page, Route, sync_playwright

GAME_URL = "https://kodub.itch.io/polytrack"
GAME_FRAME_HOST = "html-classic.itch.zone"
BACKEND_HOST = "vps.kodub.com"
HOOKS_JS = (Path(__file__).parent / "hooks.js").read_text(encoding="utf-8")
WORKER_CACHE_DIR = Path(__file__).resolve().parents[1] / "logs" / "cache"

# Prepended to simulation_worker.bundle.js when time_scale_patch=True. Scales the worker's
# performance.now(); physics still runs in fixed 1 ms steps, so only wall-clock speed changes.
# Must be registered before the worker's own onmessage so the control message is swallowed.
WORKER_TIME_PATCH = """(()=>{const n=performance.now.bind(performance);let s=1,r=n(),v=r;
performance.now=()=>{const t=n();v+=(t-r)*s;r=t;return v};
self.addEventListener('message',e=>{const d=e.data;if(d&&d.__ptTimeScale!==undefined){performance.now();s=+d.__ptTimeScale;e.stopImmediatePropagation();}});})();
"""

# Lockstep stepping (frame-exact control without keyboard / real time).
# WORKER_INTERNALS_ANCHOR is the spot in simulation_worker.bundle.js (0.6.3, minified) right after the
# message handler is installed; there `e` is the worker's car list and `n(car, controls)` advances one
# car by one physics frame (1 ms) and returns its 227-byte state buffer (carId + CarState).
WORKER_INTERNALS_ANCHOR = "$o.length=0,onmessage=r;"
# Qa = recording class (Qa.deserialize(text)), tr = recording-controls wrapper (getControls(frame));
# both are module-level in the worker bundle and used by the game itself for replays/ghosts.
WORKER_INTERNALS_EXPOSE = WORKER_INTERNALS_ANCHOR + "self.__ptInternals={cars:e,step:n,Qa:Qa,Rec:tr};"
WORKER_LOCKSTEP_PATCH = """(()=>{
self.addEventListener('message',ev=>{const d=ev.data;if(!d||d.__ptStep===undefined)return;
ev.stopImmediatePropagation();const I=self.__ptInternals;if(!I)return;
const car=I.cars.find(c=>c.id===d.carId);if(!car||!car.userControls)return;
car.isPaused=true;                      // the real-time loop must not move this car any more
if(!car.hasStarted){car.hasStarted=true;car.targetSimulationFrames=null;}
const c={up:!!d.up,right:!!d.right,down:!!d.down,left:!!d.left,reset:!!d.reset};
Object.assign(car.userControls,c);car.userControls.buffer.length=0;
const bufs=[];for(let k=0;k<d.frames&&car.frames<5999999;k++){bufs.push(I.step(car,c));car.frames++;}
if(bufs.length)postMessage({messageType:10,carStateBuffers:bufs},{transfer:bufs});  // 10 = UpdateResult
});
// Replay a recorded run (leaderboard ghost) on the player car, frame-exact: {__ptReplay, carId, recording, frames}
self.addEventListener('message',ev=>{const d=ev.data;if(!d||d.__ptReplay===undefined)return;
ev.stopImmediatePropagation();const I=self.__ptInternals;if(!I)return;
const car=I.cars.find(c=>c.id===d.carId);if(!car)return;
if(!car.__ptRec){const r=I.Qa.deserialize(d.recording);if(!r){postMessage({__ptReplayError:'deserialize'});return;}car.__ptRec=new I.Rec(r);}
car.isPaused=true;if(!car.hasStarted){car.hasStarted=true;car.targetSimulationFrames=null;}
const bufs=[];for(let k=0;k<d.frames&&car.frames<5999999;k++){bufs.push(I.step(car,car.__ptRec.getControls(car.frames)));car.frames++;}
if(bufs.length)postMessage({messageType:10,carStateBuffers:bufs},{transfer:bufs});
});
// Drive the player car with an explicit per-frame control array (bitmasks, as below):
// {__ptStepFrames, carId, controls: Uint8Array}
self.addEventListener('message',ev=>{const d=ev.data;if(!d||d.__ptStepFrames===undefined)return;
ev.stopImmediatePropagation();const I=self.__ptInternals;if(!I)return;
const car=I.cars.find(c=>c.id===d.carId);if(!car||!car.userControls)return;
car.isPaused=true;if(!car.hasStarted){car.hasStarted=true;car.targetSimulationFrames=null;}
const bufs=[];for(let k=0;k<d.controls.length&&car.frames<5999999;k++){const m=d.controls[k];
const c={up:!!(m&1),right:!!(m&2),down:!!(m&4),left:!!(m&8),reset:!!(m&16)};
bufs.push(I.step(car,c));car.frames++;}
if(bufs.length)postMessage({messageType:10,carStateBuffers:bufs},{transfer:bufs});
});
// Read a recording's per-frame controls (for imitation learning): {__ptGetControls, recording, frames}
// -> {__ptControls: Uint8Array, bit0 up, bit1 right, bit2 down, bit3 left, bit4 reset}
self.addEventListener('message',ev=>{const d=ev.data;if(!d||d.__ptGetControls===undefined)return;
ev.stopImmediatePropagation();const I=self.__ptInternals;if(!I)return;
const r=I.Qa.deserialize(d.recording);if(!r){postMessage({__ptControls:null});return;}
const rec=new I.Rec(r);const out=new Uint8Array(d.frames);
for(let f=0;f<d.frames;f++){const c=rec.getControls(f);out[f]=(c.up?1:0)|(c.right?2:0)|(c.down?4:0)|(c.left?8:0)|(c.reset?16:0);}
postMessage({__ptControls:out},{transfer:[out.buffer]});
});})();
"""


class PolyTrackBrowser:
    def __init__(self, headless: bool = False, viewport=(1280, 800), log_blocked: bool = True,
                 time_scale_patch: bool = False, render_fps: float = 0, record_video_dir: str | None = None,
                 cdp_endpoint: str | None = None, allow_leaderboard_read: bool = False):
        # opt-in for scripts/fetch_wr_line.py: lets GET /leaderboard and GET /recordings through (reading
        # ghosts, like the in-game leaderboard does). Any POST/upload stays blocked regardless.
        self.allow_leaderboard_read = allow_leaderboard_read
        self.record_video_dir = record_video_dir
        # cdp_endpoint: attach to a shared, already running Chromium (see env/shared_browser.py) and only
        # create an own context in it. A context has its own storage, so the game's "already open in
        # another tab" check (BroadcastChannel) does not trigger between envs.
        self.cdp_endpoint = cdp_endpoint
        self.ctx = None
        self.headless = headless
        self.render_fps = render_fps  # >0: cap the game's rendering (requestAnimationFrame) to this fps
        self.time_scale_patch = time_scale_patch
        self.viewport = viewport
        self.log_blocked = log_blocked
        self.blocked: list[str] = []
        self._pw = None
        self.browser = None
        self.page: Page | None = None

    # --- lifecycle ---
    def start(self) -> "PolyTrackBrowser":
        try:
            return self._start()
        except Exception:
            # a failed launch must not leave Playwright running, or every later sync_playwright()
            # fails with "Sync API inside the asyncio loop"
            self.close()
            raise

    def _start(self) -> "PolyTrackBrowser":
        self._pw = sync_playwright().start()
        if self.cdp_endpoint:
            self.browser = self._pw.chromium.connect_over_cdp(self.cdp_endpoint)
        else:
            self.browser = self._pw.chromium.launch(
                headless=self.headless,
                args=["--mute-audio", "--autoplay-policy=no-user-gesture-required"],
            )
        vp = {"width": self.viewport[0], "height": self.viewport[1]}
        ctx_kw = {"viewport": vp}
        if self.record_video_dir:
            ctx_kw.update(record_video_dir=self.record_video_dir, record_video_size=vp)
        ctx = self.ctx = self.browser.new_context(**ctx_kw)
        ctx.route(f"**://{BACKEND_HOST}/**", self._guard_backend)
        if self.time_scale_patch:
            ctx.route("**/simulation_worker.bundle.js*", self._patch_worker)
        if self.render_fps:
            ctx.add_init_script(f"window.__ptRenderFps = {float(self.render_fps)};")
        ctx.add_init_script(HOOKS_JS)
        self.page = ctx.new_page()
        return self

    def close(self):
        # each step on its own: after a crash browser.close() raises, but Playwright must still be
        # stopped, otherwise the next sync_playwright() fails ("Sync API inside the asyncio loop")
        try:
            if self.cdp_endpoint:
                # shared browser: close only our own context, never the browser the other envs use
                if self.ctx:
                    self.ctx.close()
            elif self.browser:
                self.browser.close()
        except Exception:  # noqa: BLE001
            pass
        finally:
            self.browser = None
            self.ctx = None
        try:
            if self._pw:
                self._pw.stop()
        except Exception:  # noqa: BLE001
            pass
        finally:
            self._pw = None

    def __enter__(self):
        return self.start()

    def __exit__(self, *exc):
        self.close()

    # --- leaderboard guard ---
    def _guard_backend(self, route: Route):
        req = route.request
        path = req.url.split(BACKEND_HOST, 1)[1].split("?", 1)[0]
        # Abort any write (POST: leaderboard submit, verifyRecordings, user profile) and all
        # leaderboard endpoints. Read-only GETs (user, trackOfTheWeek ...) pass through.
        read_ok = (self.allow_leaderboard_read and req.method == "GET"
                   and (path.endswith("/leaderboard") or path.endswith("/recordings")))
        if not read_ok and (req.method != "GET" or "leaderboard" in path or "verifyRecordings" in path):
            self.blocked.append(f"{req.method} {path}")
            if self.log_blocked:
                print(f"[guard] blocked {req.method} {path}")
            route.abort()
        else:
            route.continue_()

    def _patch_worker(self, route: Route):
        body = self._worker_source(route)
        if body is None:
            route.abort()
            return
        if body.count(WORKER_INTERNALS_ANCHOR) == 1:
            body = WORKER_LOCKSTEP_PATCH + body.replace(WORKER_INTERNALS_ANCHOR, WORKER_INTERNALS_EXPOSE)
        else:  # different game version: lockstep unavailable, real-time keyboard control still works
            print("[browser] WARN: worker anchor not found - lockstep control disabled")
        route.fulfill(status=200, content_type="application/javascript", body=WORKER_TIME_PATCH + body)

    def _worker_source(self, route: Route) -> str | None:
        """Official simulation_worker.bundle.js, cached on disk per URL path (flaky networks reset the
        connection; every env and every reload would otherwise fetch it again)."""
        path_part = route.request.url.split("://", 1)[1].split("?", 1)[0]
        cache = WORKER_CACHE_DIR / (path_part.replace("/", "_") or "worker.js")
        if cache.exists() and cache.stat().st_size > 100_000:
            return cache.read_text(encoding="utf-8")
        for attempt in range(4):
            try:
                resp = route.fetch(timeout=60000)
                if resp.ok:
                    text = resp.text()
                    WORKER_CACHE_DIR.mkdir(parents=True, exist_ok=True)
                    cache.write_text(text, encoding="utf-8")
                    return text
            except Exception as e:  # noqa: BLE001 - ECONNRESET etc.
                print(f"[browser] worker fetch failed ({e.__class__.__name__}), retry {attempt + 1}")
            self.page.wait_for_timeout(2000 * (attempt + 1))
        return None

    def set_time_scale(self, scale: float):
        if not self.time_scale_patch:
            raise RuntimeError("start PolyTrackBrowser with time_scale_patch=True")
        self.game_frame().evaluate(f"window.__pt.setTimeScale({float(scale)})")

    # --- game frame ---
    def open_game(self, timeout_s: float = 180, max_429_retries: int = 6) -> Frame:
        # itch.io rate-limits page loads (HTTP 429) -> back off instead of hammering
        for attempt in range(max_429_retries + 1):
            # "domcontentloaded": itch.io's full "load" (ads, trackers) can take > 30 s when several
            # contexts load at once; game readiness is checked below via the hooks anyway
            resp = self.page.goto(GAME_URL, wait_until="domcontentloaded", timeout=90000)
            if resp is None or resp.status != 429:
                break
            wait_s = min(300, 30 * 2 ** attempt)
            print(f"[browser] itch.io 429 Too Many Requests – warte {wait_s}s (Versuch {attempt + 1})")
            self.page.wait_for_timeout(wait_s * 1000)
        else:
            raise RuntimeError("itch.io keeps answering 429 Too Many Requests")
        deadline = time.time() + timeout_s
        last_err = None
        while time.time() < deadline:
            f = self.game_frame()
            if f is None:
                # itch.io click-to-launch: (re)click until the game iframe exists
                btn = self.page.locator(".load_iframe_btn")
                if btn.count() and btn.first.is_visible():
                    btn.first.click()
            else:
                try:
                    status = f.evaluate("window.__pt ? {req: !!window.__pt.require, err: window.__pt.errors} : null")
                    if status and status["req"]:
                        return f
                    last_err = status
                except Exception as e:  # frame still navigating
                    last_err = e
            self.page.wait_for_timeout(250)  # keeps Playwright's event loop (route handlers) running
        try:
            diag = self.page.evaluate("""() => ({
                btn: [...document.querySelectorAll('.load_iframe_btn')].map(b => b.outerHTML.slice(0, 120)),
                iframes: [...document.querySelectorAll('iframe')].map(i => i.src),
                frames: undefined })""")
            diag["frames"] = [f.url for f in self.page.frames]
            last_err = (last_err, diag)
            self.page.screenshot(path=str(Path(__file__).resolve().parents[1] / "logs" / "open_game_fail.png"))
        except Exception:  # noqa: BLE001
            pass
        raise TimeoutError(f"game iframe / hooks did not come up (last error: {last_err!r})")

    def game_frame(self) -> Frame | None:
        for f in self.page.frames:
            if GAME_FRAME_HOST in f.url:
                return f
        return None

    def snapshot(self) -> dict:
        return self.game_frame().evaluate("window.__pt.snapshot()")

    def track_info(self) -> dict | None:
        return self.game_frame().evaluate("window.__pt.trackInfo()")
