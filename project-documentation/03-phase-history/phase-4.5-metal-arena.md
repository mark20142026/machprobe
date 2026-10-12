# Phase 4.5: native Metal arena inside the iOS container

Dates: 2026-10-01. Commit `fd1ccdc` ("Preserve controlled macOS Metal arena and
verified iOS workload evidence"). Sources: `phase4_5/`, `docs/evidence/phase4.5/`.

**Note on sources.** Unlike the other phases, this phase has no findings or
report document in `docs/`. Its goal and conclusions below are inferred from
the code, the commit message and the evidence files. Anything not present in
those is recorded as unknown.

## Goal

Inferred: measure a Metal-heavy workload that the project itself wrote, inside
the same signed-iOS-container route used by Phase 4. The workload is a native
macOS application compiled from source in this repository, so no third-party
game was involved. The evidence set covers sustained running, relaunches, and
window reloads.

## What was built

| Path | Contents |
|---|---|
| `phase4_5/guest/Game.m`, `scene.metal`, `checker.rgba` | A native macOS app (AppKit lifecycle and events, MetalKit presentation, Metal rendering). Its comment states it has no iOS target or compatibility renderer. Draws a depth-tested scene with a checker texture and a rotating object (the state fields `spinning`, `angle` and `camera_x` in the recorded JSON). Counts frames, draws, completed command buffers, sync waits and GPU time. |
| `phase4_5/host/GameBridge.m/.h`, `Main.m` | The iOS host. It bridges the guest's window and surface calls to UIKit and reports the bridge counters (window calls, input calls, pixel copies per frame, render translation calls per frame). |
| `phase4_5/tools/build.py` | Builds the macOS guest, embeds its exact bytes in a separately signed iOS dylib (`ArenaGuest.dylib`), builds the `ArenaHost` app, and writes `ArenaHost.ipa`. |
| `phase4_5/tools/exercise.py` | Drives input in the VM (for example holding W for one second) and records state before and after. |
| `phase4_5/tools/sign_development.py` | Prepares an ordinary development IPA only when given a profile and an available identity. It refuses to run otherwise, never copies the VM's custom-trust entitlements, and does not install. |
| `phase4_5/tools/vm.py` | Install, launch and report helpers for the VM. |
| `phase4_5/tests/test_arena.py` | Six tests. The output shows `Ran 6 tests ... OK`. |

Bundle ID of the iOS host: `research.machprobe.Arena`. The guest's own macOS
bundle ID is `research.machprobe.NativeArena`.

## How it was done

1. Wrote the native macOS arena in Objective-C with Metal shaders and a checker
   texture, and built it as an ARM64 macOS app.
2. Embedded the guest's bytes unchanged in the iOS container, with a host
   record of the SHA-256 and the resource hashes (`guest.json`).
3. Installed through the VM, drove input with `exercise.py`, and recorded the
   counters.
4. Ran a long sampling pass (`performance.json`, about 245 s) and repeated
   relaunch and reload passes (`relaunch.json`, `reloads.json`).
5. Checked that the signing route stops at the identity step, rather than
   faking a development signature (`signing-identities.txt`).

## Problems and bugs

No bug log exists for this phase. The entries below are problems visible in the
evidence files. The repository does not record their causes.

| Symptom | How it was found | Root cause | Fix | Commit |
|---|---|---|---|---|
| Worst observed frame interval 2.20 s; minimum interval rate 5.7 fps | `performance.json` (`max_observed_frame_gap_seconds`, `interval_fps_min`) | Unknown. Not investigated in the repository. | None recorded. The stable-window figure (about 29.5 fps) is reported instead. | `fd1ccdc` |
| Ordinary development signing could not be tested | `signing-identities.txt` shows `0 valid identities found` | No code-signing identity on the Mac. | `sign_development.py` prepared but not run. | `fd1ccdc` |

## Results / evidence

From `docs/evidence/phase4.5/performance.json` (iOS VM, Metal API validation
enabled):

| Measure | Value |
|---|---|
| Frames over the run | 7,260 in 245.1 s; 7,259 completed |
| Overall rate | 29.6 fps |
| Stable window | 5,462 frames over 185.0 s, 29.5 fps |
| Median interval rate | 30.0 fps |
| Skipped frames | 0 |
| Guest render CPU | 0.76 ms per frame |
| Whole-process CPU | 2.45 ms per frame |
| GPU time per completed buffer | 1.79 ms |
| GPU errors | 0 |
| Footprint at end | about 56.6 MB |

The bridge counters in `sustained.json` and `reloads.json` show 0 pixel copies
per frame and 0 render-translation calls per frame. That is the evidence that
the Metal calls reached the iOS driver directly rather than through a
translation layer. The reload pass recorded 17 window calls and 245 input
calls.

The same `Game.m` source was also built for macOS. `native-verification.json`
records a passing depth-test check on the Mac (`passed: true`).

Not established: whether the 29.5 fps figure was capped by the VSync or frame
settings (unknown); ordinary signing; any stock-device behaviour.

## What it unlocked next

- A measured baseline for a Metal workload under the signed-container route.
  Later phases keep their own performance evidence in their own folders.
- A prepared, refuse-by-default route for ordinary development signing. Phase 7
  used its own signing project (`phase7/signing/`) for the first physical-device
  run, not this script.
- Phase 5 (Strataris) followed, with the Metal translation and adapters for a
  real game.
