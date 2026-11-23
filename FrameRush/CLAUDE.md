# FrameRush — Claude Development Instructions

## Mission
Build **FrameRush**, a lightweight, Windows-only, open-source HDMI capture viewer in **Rust**. Primary use case: display a PlayStation 5 through an inexpensive UGREEN USB capture dongle at **1920×1080, ideally 60 fps**, listen to its audio through the PC headset while Discord runs, and share the viewer window on Discord.

**Top priority: minimize measured end-to-end latency without sacrificing stability.** Never claim zero latency. Hardware capture buffering, USB transfer, rendering, display scanout, and audio buffering impose limits. The specific UGREEN model, supported formats, and latency are not yet verified.

## User's development environment
- Windows desktop; Intel Core i7-14700K, NVIDIA RTX 5060 Ti, 32 GB DDR4.
- Capture device: newly purchased UGREEN USB HDMI capture card advertised as 1080p; exact SKU, USB mode, 60 fps support, and available pixel formats must be discovered at runtime.
- PS5 HDMI output. For gameplay capture, PS5 HDCP must be disabled in Settings > System > HDMI. Protected content is not capturable; do not suggest bypassing protection.
- One monitor for the game viewer, second monitor for Discord. Audio output should use the PC headset.

## Technical direction
- Rust stable, Cargo, Windows-only (`x86_64-pc-windows-msvc`).
- Prefer native **Windows Media Foundation** for UVC device enumeration and capture; use the `windows` crate. If the actual device requires DirectShow or another interface, explain and document the evidence before switching.
- Begin with a simple reliable renderer (e.g. `winit` + `wgpu`, or native D3D11 when necessary). Optimize for direct GPU upload and minimal frame copies only after profiling.
- Audio: capture the device's audio endpoint, if exposed, and play through the selected Windows output using WASAPI; account for device clock drift and underflows. Avoid accidental microphone monitoring or feedback.
- Structured logging via `tracing`; configuration via `serde` if needed.
- Pin dependency versions in Cargo.lock; avoid unnecessary crates and abstractions.
- Use Windows APIs with narrowly scoped `unsafe` blocks, documented invariants, explicit HRESULT/error handling, and correct COM threading/lifetimes.

## Core behavior
1. Enumerate video capture devices and show friendly names plus device identifiers.
2. Enumerate supported capture modes: resolution, frame rate, pixel format (e.g. NV12, YUY2, MJPEG), and transport constraints. Do not assume 1080p60 exists.
3. Let the user select device and mode, start/stop preview, and toggle borderless fullscreen.
4. Render the **newest completed frame**; use a bounded queue (ideally latest-frame mailbox) and drop stale frames instead of building latency.
5. Display measured input FPS, rendered FPS, dropped frames, and capture-to-present timing where timestamps permit. Clearly distinguish software timing from true HDMI-to-photon latency.
6. Route capture audio to the selected playback device, with mute and volume controls.
7. Ensure the window is capturable through Discord's application/window sharing. Do not build Discord integration for MVP.
8. Handle unplug/replug, unsupported formats, device-in-use, sleep/resume, and shutdown without crashes.

## Latency engineering rules
- Do not use fixed sleeps or long buffering in the critical video path without a measured reason.
- Never let rendering block capture callbacks; keep capture, rendering, and audio work appropriately separated.
- Prefer latest-frame semantics to unbounded channels.
- Track timestamps at capture callback, frame-ready, GPU submission, and presentation when feasible; note that GPU presentation timestamps and external HDMI timing may be unavailable.
- Benchmark with OBS/PotPlayer on the **same device, format, display refresh, and conditions**. A high-speed-camera or LED/photodiode setup is needed to establish true end-to-end latency.
- Evaluate VSync on/off and tearing tradeoffs rather than promising one setting is universally best.
- Prioritize stable 60 fps and consistent frame pacing over misleading headline latency figures.
- Do not conflate 60 Hz input with a guarantee of 60 fps output.

## Architecture (incremental, not dogmatic)
- `src/main.rs`: startup, CLI/app wiring.
- `src/capture/`: device discovery, mode negotiation, frame delivery.
- `src/render/`: GPU initialization, textures, present path.
- `src/audio/`: device enumeration, capture, monitoring.
- `src/metrics/`: frame counters, latency timestamps, telemetry.
- `src/ui/`: device selection, preview controls, overlay (add only as needed).
- `src/error.rs`: typed errors and user-facing diagnostics.

Do not create empty modules just to match this layout. Start minimal and refactor when functionality warrants it.

## Development workflow
1. Inspect the repository and summarize its current state before editing.
2. Implement in small, independently testable milestones.
3. Before major architectural changes, state the tradeoff and why it improves reliability or latency.
4. Provide complete, compiling code; never invent crate APIs, Windows interfaces, capture modes, or benchmark results.
5. Run `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, and `cargo test` when supported by the environment. Report exactly what ran and what could not be tested.
6. Keep a short README with prerequisites, device limitations, build/run steps, and troubleshooting.
7. Keep commits focused and avoid unrelated refactoring.

## Milestones
Order changed on 2026-11-23: a complete, runnable prototype is built first **without** the capture card (synthetic source); the real UGREEN hardware is integrated afterwards.

### M0 — Synthetic prototype (no hardware)
A `VideoSource` trait with a synthetic 1920×1080 @ 60 fps source (animated test pattern with frame counter). GPU viewer with `winit` + `wgpu`: resizable window, borderless fullscreen, FPS/drop/timing overlay, latest-frame mailbox, no unbounded queues. Media Foundation prepared only as device/format enumeration — no invented formats, no untested capture path. Tests for the mailbox.

### M1 — Device probe (with hardware)
List capture devices and all available media types on the real UGREEN card. Print an explicit diagnostic for the selected device.

### M2 — Live preview from the capture card
Implement the Media Foundation `VideoSource` (mode selection, sample reading, stride/format handling) for the formats the device actually reports, and render it through the existing viewer. Prefer correctness and stable frame delivery over premature optimizations.

### M3 — Low-latency video path
Detailed timing on real hardware, configurable present mode, buffer recycling/zero-copy only after profiling. Benchmark against a baseline (OBS/PotPlayer).

### M4 — Audio monitoring
Capture HDMI audio if available and play it on the PC headset. Expose output selection, mute, volume, and basic underrun diagnostics.

### M5 — Usability and packaging
Remember settings, handle hotplug/recovery, improve diagnostics, and produce a distributable Windows executable.

## Definition of done for MVP
- Detects the actual capture card and reports supported modes accurately.
- Displays stable live video at the best genuinely supported mode.
- Supports fullscreen and is shareable through Discord.
- Reports measured FPS and drops, with no unbounded backlog.
- Provides useful errors and clean shutdown.
- Audio is a subsequent milestone unless implemented reliably earlier.

## First task for Claude
Start with **M0** (synthetic prototype). Then **M1**: with the card connected, run the device/format listing, record the real results, and only then implement the Media Foundation capture path for the formats actually reported. Explain any Windows SDK/COM prerequisites. Do not claim to have tested the UGREEN card unless hardware results are provided.
