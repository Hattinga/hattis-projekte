// Injected into every frame via Playwright add_init_script. Only acts inside the game iframe.
// Verified against PolyTrack 0.6.3 (see docs/game_state.md). Read-only: never changes game state.
(() => {
  if (!location.hostname.endsWith("itch.zone")) return;
  if (window.__pt) return;

  const MSG_INIT = 0, MSG_CREATE_CAR = 3, MSG_DELETE_CAR = 4, MSG_UPDATE_RESULT = 10;

  const pt = (window.__pt = {
    gameVersion: null,
    workers: [],           // {id, isRealtime, playerCars:Set}
    workerObjects: [],
    timeScale: 1,
    trace: null,
    waiters: [],
    collisionSum: 0,       // running totals over all physics frames of the player car (env takes deltas)
    collisionFrames: 0,
    collisionMax: 0,
    player: null,          // {workerId, carId}
    state: null,           // last decoded carState of the player car
    stateWallTime: null,   // performance.now() (main thread) when state arrived
    updates: 0,
    track: null,           // Track instance (webpack module 6762, export A)
    errors: [],
  });

  // Mirror of the game's CarState decoder (webpack module 3899, export VO).
  function decodeCarState(e) {
    const n = new DataView(e.buffer, e.byteOffset, e.byteLength);
    let i = 0;
    const frames = e[i] | (e[i + 1] << 8) | (e[i + 2] << 16); i += 3;
    const speedKmh = n.getFloat32(i, true); i += 4;
    const f = e[i]; i += 1;
    const hasStarted = !!(f & 1), hasFinished = !!(f & 2), hasCheckpointToRespawnAt = !!(f & 4);
    const contact = [!!(f & 8), !!(f & 16), !!(f & 32), !!(f & 64)];
    let finishFrames = null;
    if (hasFinished) { finishFrames = e[i] | (e[i + 1] << 8) | (e[i + 2] << 16); i += 3; }
    const nextCheckpointIndex = n.getUint16(i, true); i += 2;
    const position = { x: n.getFloat32(i, true), y: n.getFloat32(i + 4, true), z: n.getFloat32(i + 8, true) }; i += 12;
    const quaternion = { x: n.getFloat32(i, true), y: n.getFloat32(i + 4, true), z: n.getFloat32(i + 8, true), w: n.getFloat32(i + 12, true) }; i += 16;
    const nImp = n.getUint8(i); i += 1;
    const collisionImpulses = [];
    for (let k = 0; k < nImp; k++) { collisionImpulses.push(n.getFloat32(i, true)); i += 4; }
    const wheelContact = [null, null, null, null];
    for (let k = 0; k < 4; k++) if (contact[k]) {
      wheelContact[k] = {
        position: { x: n.getFloat32(i, true), y: n.getFloat32(i + 4, true), z: n.getFloat32(i + 8, true) },
        normal: { x: n.getFloat32(i + 12, true), y: n.getFloat32(i + 16, true), z: n.getFloat32(i + 20, true) },
      };
      i += 24;
    }
    const arr4 = () => { const a = []; for (let k = 0; k < 4; k++) { a.push(n.getFloat32(i, true)); i += 4; } return a; };
    const wheelSuspensionLength = arr4(), wheelSuspensionVelocity = arr4(), wheelDeltaRotation = arr4(), wheelSkidInfo = arr4();
    const steering = n.getFloat32(i, true); i += 4;
    const c = e[i];
    const controls = { up: !!(c & 1), right: !!(c & 2), down: !!(c & 4), left: !!(c & 8), reset: !!(c & 16) };
    return {
      frames, speedKmh, hasStarted, finishFrames, nextCheckpointIndex, hasCheckpointToRespawnAt,
      position, quaternion, collisionImpulses, wheelContact, wheelSuspensionLength,
      wheelSuspensionVelocity, wheelDeltaRotation, wheelSkidInfo, steering,
      brakeLightEnabled: !!(c & 32), controls,
    };
  }

  // --- Optional render throttle (unwatched training browsers): cap main-thread requestAnimationFrame.
  // Physics runs in the worker with its own clock and is not affected.
  const renderFps = Number(window.__ptRenderFps || 0);
  if (renderFps > 0) {
    const nativeRaf = window.requestAnimationFrame.bind(window);
    const interval = 1000 / renderFps;
    let last = 0;
    window.requestAnimationFrame = (cb) => {
      const wait = Math.max(0, last + interval - performance.now());
      return setTimeout(() => nativeRaf((t) => { last = performance.now(); cb(t); }), wait);
    };
    window.cancelAnimationFrame = (id) => clearTimeout(id);
    pt.renderFps = renderFps;
  }

  // --- Worker interception: track the human-controlled car, decode its state updates ---
  const NativeWorker = window.Worker;
  let nextWorkerId = 0;
  window.Worker = function (url, opts) {
    const w = new NativeWorker(url, opts);
    if (!String(url).includes("simulation_worker")) return w;
    const info = { id: nextWorkerId++, isRealtime: null, playerCars: new Set() };
    pt.workers.push(info);
    pt.workerObjects.push(w);
    w.__ptInfo = info;

    const nativePost = w.postMessage.bind(w);
    w.postMessage = function (msg, ...rest) {
      try {
        if (msg && typeof msg === "object") {
          if (msg.messageType === MSG_INIT) { info.isRealtime = msg.isRealtime; pt.gameVersion = msg.version; }
          else if (msg.messageType === MSG_CREATE_CAR && msg.carRecording == null) {
            info.playerCars.add(msg.carId);
            pt.player = { workerId: info.id, carId: msg.carId };
            pt.state = null;
          } else if (msg.messageType === MSG_DELETE_CAR) {
            info.playerCars.delete(msg.carId);
          }
        }
      } catch (err) { pt.errors.push(String(err)); }
      return nativePost(msg, ...rest);
    };

    w.addEventListener("message", (ev) => {
      const d = ev.data;
      if (!d || d.messageType !== MSG_UPDATE_RESULT || !pt.player || pt.player.workerId !== info.id) return;
      try {
        const bufs = d.carStateBuffers;
        // buffers are in simulation order; the last one for our car is the newest frame
        for (let k = bufs.length - 1; k >= 0; k--) {
          const u = new Uint8Array(bufs[k]);
          const carId = u[0] | (u[1] << 8) | (u[2] << 16) | (u[3] << 24);
          if (carId !== pt.player.carId) continue;
          pt.state = decodeCarState(u.subarray(4));
          pt.stateWallTime = performance.now();
          pt.updates++;
          break;
        }
        // Collision impulses of every physics frame (not just the newest): read straight from the
        // buffer layout (see decodeCarState) without decoding the rest.
        for (const b of bufs) {
          const u = new Uint8Array(b);
          if ((u[0] | (u[1] << 8) | (u[2] << 16) | (u[3] << 24)) !== pt.player.carId) continue;
          const dv = new DataView(b);
          const flags = u[4 + 7];
          let off = 4 + 3 + 4 + 1 + ((flags & 2) ? 3 : 0) + 2 + 12 + 16;
          const n = u[off]; off += 1;
          if (n > 0) {
            let s = 0;
            for (let k = 0; k < n; k++) s += Math.abs(dv.getFloat32(off + 4 * k, true));
            pt.collisionSum += s;
            pt.collisionFrames += 1;
            if (s > pt.collisionMax) pt.collisionMax = s;
          }
        }
        if (pt.waiters.length && pt.state) resolveWaiters(false);
        if (pt.trace) {
          for (const b of bufs) {
            const u = new Uint8Array(b);
            const carId = u[0] | (u[1] << 8) | (u[2] << 16) | (u[3] << 24);
            if (carId !== pt.player.carId) continue;
            const s = decodeCarState(u.subarray(4));
            if (s.frames % pt.trace.every === 0) pt.trace.rows.push([s.frames, s.position.x, s.position.y, s.position.z, s.speedKmh]);
          }
        }
      } catch (err) { pt.errors.push(String(err)); }
    });
    return w;
  };
  window.Worker.prototype = NativeWorker.prototype;

  // --- Webpack access: capture the Track instance (module 6762, class with getCheckpoints) ---
  const TRACK_MODULE = 6762;
  function hookWebpack() {
    const chunks = self.webpackChunk;
    if (!chunks || chunks.push === Array.prototype.push) return false;
    let req = null;
    chunks.push([["__pt_probe"], {}, (r) => { req = r; }]);
    if (!req) return false;
    pt.require = req;
    try {
      const Track = req(TRACK_MODULE).A;
      const orig = Track.prototype.getStartTransform;
      Track.prototype.getStartTransform = function (...a) { pt.track = this; return orig.apply(this, a); };
      pt.TrackClass = Track;
    } catch (err) { pt.errors.push("webpack hook: " + err); }
    return true;
  }
  const iv = setInterval(() => { if (hookWebpack()) clearInterval(iv); }, 50);

  pt.trackInfo = () => {
    const t = pt.track;
    if (!t) return null;
    const s = pt.TrackClass.partSize;
    const conv = (p) => ({
      x: p.x * s + p.detector.center[0], y: p.y * s + p.detector.center[1], z: p.z * s + p.detector.center[2],
      order: p.checkpointOrder, rotation: p.rotation, rotationAxis: p.rotationAxis, size: p.detector.size,
    });
    return {
      partSize: s,
      totalCheckpoints: t.getTotalNumberOfCheckpointIndices(),
      checkpoints: t.getCheckpoints().map(conv),
      finishes: t.getFinishes().map((p) => ({
        x: p.x * s + p.detector.center[0], y: p.y * s + p.detector.center[1], z: p.z * s + p.detector.center[2],
      })),
      start: t.getStartTransform(),
    };
  };

  // Resolve once the player car reached `target` physics frames (or finished), or after timeoutMs.
  // One round trip per env step instead of polling.
  function resolveWaiters(force) {
    const s = pt.state;
    pt.waiters = pt.waiters.filter((w) => {
      if (force || (s && (s.frames >= w.target || s.finishFrames != null)) || performance.now() >= w.deadline) {
        w.resolve(pt.snapshot());
        return false;
      }
      return true;
    });
  }
  pt.waitFrames = (target, timeoutMs = 2000) => new Promise((resolve) => {
    pt.waiters.push({ target, resolve, deadline: performance.now() + timeoutMs });
    setTimeout(() => resolveWaiters(false), timeoutMs + 5);
    resolveWaiters(false);
  });

  // Lockstep: advance the player car by exactly `frames` physics frames with fixed controls (needs the
  // worker patch from env/browser.py). Resolves with the snapshot after the last of those frames.
  pt.stepPlayer = (ctrl, frames) => {
    if (!pt.player) return Promise.resolve(pt.snapshot());
    const start = pt.state ? pt.state.frames : 0;
    const p = pt.waitFrames(start + frames, 5000);
    pt.workerObjects[pt.player.workerId].postMessage({
      __ptStep: true, carId: pt.player.carId, frames,
      up: !!ctrl.up, right: !!ctrl.right, down: !!ctrl.down, left: !!ctrl.left, reset: !!ctrl.reset,
    });
    return p;
  };

  // Replay a leaderboard recording on the player car (frame-exact), `frames` physics frames per call.
  pt.replayPlayer = (recording, frames) => {
    if (!pt.player) return Promise.resolve(pt.snapshot());
    const start = pt.state ? pt.state.frames : 0;
    const p = pt.waitFrames(start + frames, 10000);
    pt.workerObjects[pt.player.workerId].postMessage({ __ptReplay: true, carId: pt.player.carId, recording, frames });
    return p;
  };

  // Drive the player car with an explicit per-frame control bitmask array; resolves after the last frame.
  pt.stepFrames = (masks) => {
    if (!pt.player || !masks.length) return Promise.resolve(pt.snapshot());
    const start = pt.state ? pt.state.frames : 0;
    const p = pt.waitFrames(start + masks.length, 20000);
    pt.workerObjects[pt.player.workerId].postMessage({ __ptStepFrames: true, carId: pt.player.carId, controls: Uint8Array.from(masks) });
    return p;
  };

  // Per-frame controls of a recording (array of bitmasks: 1 up, 2 right, 4 down, 8 left, 16 reset)
  pt.getRecordingControls = (recording, frames) => new Promise((resolve, reject) => {
    if (!pt.player) { reject(new Error("no worker yet")); return; }
    const w = pt.workerObjects[pt.player.workerId];
    const onMsg = (ev) => {
      if (!ev.data || ev.data.__ptControls === undefined) return;
      w.removeEventListener("message", onMsg);
      resolve(ev.data.__ptControls ? Array.from(ev.data.__ptControls) : null);
    };
    w.addEventListener("message", onMsg);
    w.postMessage({ __ptGetControls: true, recording, frames });
    setTimeout(() => { w.removeEventListener("message", onMsg); reject(new Error("timeout")); }, 30000);
  });

  // Freeze/unfreeze the player car's physics via the game's own PauseCar message (messageType 7,
  // {carId, isPaused}; see simulation worker). Used to stop the clock while the learner updates.
  pt.pausePlayer = (isPaused) => {
    if (!pt.player) return false;
    pt.workerObjects[pt.player.workerId].postMessage({ messageType: 7, carId: pt.player.carId, isPaused: !!isPaused });
    return true;
  };

  // Record every Nth physics frame of the player car (debug / determinism checks)
  pt.startTrace = (every = 100) => { pt.trace = { every, rows: [] }; };
  pt.stopTrace = () => { const r = pt.trace ? pt.trace.rows : []; pt.trace = null; return r; };

  // Time scale: only works when env/browser.py was started with time_scale_patch=True
  // (it prepends a performance.now() scaler to simulation_worker.bundle.js).
  pt.setTimeScale = (s) => {
    for (const w of pt.workerObjects) w.postMessage({ __ptTimeScale: s });
    pt.timeScale = s;
  };

  // Compact snapshot for Python polling
  pt.snapshot = () => {
    const s = pt.state;
    if (!s) return { ready: false, player: pt.player, updates: pt.updates, errors: pt.errors.slice(-3) };
    const q = s.quaternion;
    // forward = q * (0,0,1); verified: start quaternion (0,.707,0,-.707) -> (-1,0,0) = driving direction on Summer 1
    const forward = {
      x: 2 * (q.x * q.z + q.w * q.y),
      y: 2 * (q.y * q.z - q.w * q.x),
      z: 1 - 2 * (q.x * q.x + q.y * q.y),
    };
    return {
      ready: true,
      frames: s.frames,
      timeS: s.frames / 1000,
      speedKmh: s.speedKmh,
      hasStarted: s.hasStarted,
      finished: s.finishFrames != null,
      finishTimeS: s.finishFrames == null ? null : s.finishFrames / 1000,
      nextCheckpointIndex: s.nextCheckpointIndex,
      hasCheckpointToRespawnAt: s.hasCheckpointToRespawnAt,
      position: s.position,
      quaternion: q,
      forward,
      yawRad: Math.atan2(forward.x, forward.z),
      steering: s.steering,
      wheelsOnGround: s.wheelContact.filter((w) => w).length,
      collisionSum: pt.collisionSum,
      collisionFrames: pt.collisionFrames,
      controls: s.controls,
      updates: pt.updates,
      ageMs: performance.now() - pt.stateWallTime,
    };
  };
})();
