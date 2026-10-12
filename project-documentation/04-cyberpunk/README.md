# Cyberpunk 2077 on iPhone: documentation index

> Not piracy: no game files are included; you need your own copy. MIT-licensed. See [../NOTICE.md](../NOTICE.md).

This folder tells the full story of phase 8 of machprobe: getting the unchanged
macOS arm64 build of Cyberpunk 2077 (Steam app 1091500, build 20383525) to run
on a physical iPhone 18 Pro. It covers the steps, the progress, every bug we
hit, how each one was found, its root cause and its fix.

Status at the end of the documented work (repository HEAD `5e022eb`, 10 Oct 2026):
the game runs end to end on the phone from a copied level-50 save, with driving,
Xbox-style controller input, touch controls, and roughly 30-40 fps at 1564x720 in
the city. Known open problems are listed in `known-issues.md`.

## Ground rules that shaped the work

- Game data is never in the repository. The user supplies their own retail copy
  (Steam, DRM-free according to the user). The build reads the install at
  `~/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077/` and
  packages only the arm64 executables and frameworks, which are hash-checked at
  launch against `build/cyberpunk/thin/SHA256SUMS`. Game bytes are not modified.
- The layer is ours: a custom Mach-O loader plus iOS adapters for the macOS APIs
  the game calls (AppKit, CoreGraphics, IOKit, Metal, libcurl, Security).
- Phone-side scratch is always the app's own container. The user's saves are
  copied from the Mac; the phone's `user.gls` (EULA acceptance) is never overwritten.
- App ID: `research.machprobe.CP2077`. It was split off the shared `STKHost` ID on
  10 Oct after another app was installed over it and wiped the container (see
  bug 27 in `bug-log.md`).

## Files in this folder

| File | What it covers |
|------|----------------|
| `README.md` | This index and the milestone timeline |
| `bring-up-journal.md` | Chronological log, milestone by milestone: what was tried, what worked |
| `bug-log.md` | Master table of every Cyberpunk bug: symptom, how found, root cause, fix, files, commit |
| `memory.md` | Where the RAM and address space go, the limits, VM tags, budget telemetry, the open leak hunt |
| `performance.md` | GPU-bound findings, layer overhead, VSync discovery, recommended settings, heat |
| `input-and-controls.md` | Touch controls, mouse look, the virtual stick, controller support, known problems |
| `known-issues.md` | Open problems, planned next steps, and documentation drift found while writing this |

Source of truth for code: `phase8/` (runtime in `phase8/runtime/`, host in
`phase8/host/Main.m`, tooling in `phase8/tools/`). Shared adapters that
Cyberpunk uses also live in `phase5/runtime/` (Input, Lifecycle) and
`phase6/runtime/` (Desktop, AppKitExtras). Loader core is `runtime/`.
Working notes and the handoff are in `CONTEXT.md` at the repository root.

## Milestone timeline

All commits are on branch `phase6-supertuxkart`. Dates are commit dates.

| # | Milestone | Date | Key commits | Result |
|---|-----------|------|-------------|--------|
| 1 | Loader and lean host prepared; Mac load-only check passes | 9 Oct | `e831216` | 5 images load: 685,682 rebases, 71,348 binds, 7,458 initializers (no `--run` on the Mac) |
| 2 | Game data copied to the phone and verified | 9 Oct | `0908351` (adds `phase8/tools/push_resume.py`) | Archive, engine and r6 folders in the app's Documents, resumable copy (the copy ran before `d5c3f08`; the commit only carries the tool) |
| 3 | First device boot: link fix for AppKit class | 9 Oct | `d5c3f08` | Guest links and starts; first on-device crash inspected |
| 4 | Main menu reached | 9 Oct | `0908351` | Address-space rationing, case-insensitive paths, heap cap |
| 5 | Main-menu load passes (libcurl) | 9 Oct | `b5dd60b` | Offline libcurl keeps request state; the menu loads |
| 6 | Input reaches the game (taps, keys, focus) | 9 Oct | `2dee2ac`, `e43a29b`, `e348889`, `a9bb2bc` | Menus clickable, touch controls work |
| 7 | Night City, first drive | 9 Oct | `538ebc6` | Spill-over heaps, 8 GB then 3 GB memsize budget, input diagnostics |
| 8 | Native-resolution rendering | 9 Oct | `3455929` | 1956x900 with aspect-correct modes |
| 9 | Playable: own save, driving, controller | 9 Oct | `11a407d` (CONTEXT) | Level-50 save, Xbox controller, touch pad |
| 10 | Performance and memory telemetry | 9 Oct | `25bef28`, `04c412a`, `0cb6e9e` | TLS fast path, grow-on-demand heaps, thermal and texture census |
| 11 | Tuned settings; 60 fps cap found | 10 Oct | `aa32a9b` | `phase8/config-recommended-UserSettings.json`; VSync "60" bug explained |
| 12 | Own icon from the user's install | 10 Oct | `ed2227a` | Icon generated at build time, never stored in the repo |
| 13 | Own App ID after the shared-ID wipe | 10 Oct | `5e022eb` | `research.machprobe.CP2077`; data restored from the Mac copy |

Open after milestone 13: frame-pacing cap at 60 fps, memory creep of about 1.4 MB/s
(malloc-small), touch-pad rebuild, resolution sweep, in-app Steam download. See
`known-issues.md`.

## Reading order

1. `bring-up-journal.md` for the story.
2. `bug-log.md` for the table of bugs and fixes.
3. `memory.md` and `performance.md` for the two areas still in progress.
4. `input-and-controls.md` for what the user touches on the phone.
5. `known-issues.md` for what is next.
