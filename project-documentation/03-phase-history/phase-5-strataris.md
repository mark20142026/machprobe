# Phase 5: unchanged Strataris gameplay (AppKit and Metal adapters)

Dates: 2026-10-01. Commits `d1e2146` (opt-in chained fixups, tagged rebases) and
`cebead4` (Strataris runs in the iOS research host). Sources:
`docs/phase5-report.md`, `docs/phase5-findings.md`, `docs/evidence/phase5/`
(numbered evidence `02` to `24`).

## Goal

Run the official Strataris v1.0.1 macOS game (an AppKit and Metal application)
in the iOS VM with its executable bytes unchanged, and get as far as real
gameplay. This was the first game in the project. It required AppKit lifecycle,
window, menu, keyboard and Metal behaviour that Phase 4's SwiftUI app did not
need.

## What was built

| Path | Contents |
|---|---|
| `runtime/` | Opt-in chained fixup support (`DYLD_CHAINED_PTR_64_OFFSET`) with bounded ordinary imports, rebases and weak imports, plus high8 tag handling. Tests in `phase3/tests/fixups.c`. |
| `phase5/runtime/Lifecycle.m/.h` | Application adapter. `NSApplication.run` enters UIKit. Launch notifications reach the guest's own delegate. |
| `phase5/runtime/Window.m/.h` | Generic window properties, first-responder tracking and content presentation. |
| `phase5/runtime/Menu.m/.h` | Maps guest `NSMenu` and `NSMenuItem` objects to `UIMenu` actions that call the original selectors. |
| `phase5/runtime/MetalCompat.m/.h` | Device adapter. Managed storage is changed to Shared on unified-memory devices, on a copied descriptor only. |
| `phase5/runtime/Input.m/.h`, `Controls.m` | Virtual-key input (Mac virtual-key events to `keyDown:`/`keyUp:`), touch-position adapter, and preliminary desktop control mappings. |
| `phase5/runtime/AppKitCompat.m/.h` | AppKit globals and classes the guest imports, with values measured on native AppKit. |
| `phase5/runtime/Updater.m` | Explicitly declines self-update. Does not run Sparkle. |
| `phase5/runtime/Observe.m`, `Policy.c/.h` | Frame and audio observations; policy for the phase. |
| `phase5/host/Main.m`, `phase5/tools/build.py`, `vm.py` | Host, packaging around the original slice, and VM install and report. |
| `phase5/tests/metal.m`, `test_phase5.py` | Executable integrity test and a GPU texture upload, blit and readback test under sanitizers. |

The target's ARM64 slice starts at offset 1,015,808 and is 951,360 bytes long.
It is macOS, minimum 14.0, SDK 26.5. The original signature and the notarization
ticket were checked. The original `.app` and its main executable were kept
unchanged.

## How it was done

The findings file records the chronology as 11 numbered steps, each with a
piece of evidence:

1. The runtime rejected the compiled metadata, then the chained fixups. The
   Phase 4 metadata policy was reused, and opt-in chained fixups were added.
2. Ordinary chained imports, rebases and weak imports were bounded. High-byte
   tagged pointers needed a second correction, using the SDK's fixup-chain
   header as the reference.
3. Missing framework imports were resolved. AppKit string and font-weight
   constants were measured against native AppKit rather than guessed.
4. `_main` reached `NSApplication.setDelegate:` and failed. The application
   adapter was added.
5. The guest built `NSMenu` objects. The menu adapter mapped them to UIKit menus.
6. Sparkle's controller initializer was needed during startup. Self-update was
   declared unavailable in the container.
7. The guest created its own `MTKView` subclass and renderer. Metal rejected
   `storageMode = 1` (Managed). The device adapter translated it to Shared.
8. Gameplay queried `mouseLocationOutsideOfEventStream` on the physical window.
   A touch-position adapter was added.
9. The title screen, briefing, cockpit, movement and firing were then observed.
10. The K shortcut opened a desktop keyboard-configuration sheet. The physical
    window does not implement AppKit sheets, so the path failed. The host's K
    shortcut was removed at the user's request.
11. The phase was stopped at the user's request, with gameplay confirmed.

## Problems and bugs

| Symptom | How it was found | Root cause | Fix | Commit |
|---|---|---|---|---|
| Compiled metadata rejected on load | Loader error on the first real game | Default policy rejects compiled metadata. | Reuse the Phase 4 metadata policy (opt-in). | `d1e2146`, `cebead4` |
| Chained fixups unsupported | Loader error | The loader did not handle `DYLD_CHAINED_PTR_64_OFFSET`. | Bounded opt-in chained fixup support. | `d1e2146` |
| Tagged high8 pointers were wrong after the first correction | Fixup check against the SDK header and synthetic tests | The high byte carries a tag that must survive rebasing. | Second correction in the fixup code, tested with positive and malformed streams. | `d1e2146` |
| `NSApplication.setDelegate:` failed in `_main` | Guest log at entry | No AppKit application object on iOS. | Application adapter; `NSApplication.run` enters UIKit. | `cebead4` |
| Menu construction failed | Guest log after launch | `NSMenu` is not a UIKit type. | Generic menu model mapped to `UIMenu`, calling the original selectors. | `cebead4` |
| Sparkle initializer needed at startup | Guest log | The app bundles Sparkle for self-update. | Updater declines updates. Sparkle is not executed. | `cebead4` |
| Metal rejected `storageMode = 1` (Managed) | Metal error on the guest's texture path (`docs/evidence/phase5/15-metal-validation.txt`, `16-managed-texture.txt`) | Managed storage is a macOS mode that the iOS unified-memory device rejects. | Copied descriptor changed to Shared on unified memory. A standalone test confirms upload, blit and exact readback. | `cebead4` |
| Gameplay could not read pointer position | Guest call on the physical window | `mouseLocationOutsideOfEventStream` is an AppKit method. | Touch-position adapter and cursor request accounting. | `cebead4` |
| K opened a keyboard sheet that failed | Labels, buttons and stack views exposed more AppKit requirements | The physical UIWindow lacks AppKit sheet API. | **Open.** Preliminary control mappings added. Host K shortcut removed at the user's request. Original game routes to sheets not disabled. | `cebead4` |
| Audio startup returned -10851 at output-node initialization | Instrumented AVAudioEngine | Output route in the VM; cause not established. | **Open.** Recorded as an observation. No mixed frames observed. | (findings only) |

## Results / evidence

- VERIFIED in the VM: title screen, briefing (B), gameplay start (Enter), cockpit,
  arrow-key movement and Space firing with visible beams. The user confirmed
  playability.
- Screens and records: `docs/evidence/phase5/16-first-screen.png`,
  `18-briefing.png`, `19-gameplay.png`, `20-gameplay.png`, `21-movement-fire.png`.
- Successful runs applied 3,957 rebases and 686 binds, with the slice hash
  checked before each launch.
- A short title-screen sample measured 326 guest draw callbacks in 5.82 s (about
  56 per second), mean callback time 11.3 ms. The report says this is a short
  sample and not a performance benchmark.
- Tests: 70 existing methods passed before this phase's additions. Two new Phase
  5 tests (slice integrity and GPU readback) passed. The full Phase 1 to 4.5
  regression was not re-run before the stop, and the report says so.

Not verified: audio, long-session stability, save and configuration persistence,
the keyboard sheet, controllers, pointer styling, ordinary-device deployment and
sandbox independence. The VM installer adds custom trust, so sandbox
independence was not established.

## What it unlocked next

- The AppKit lifecycle, menu, window and keyboard adapters, which Phase 5.5
  (Veloren) and Phase 6 (SuperTuxKart) both changed. Phase 6's commit `c74c865`
  edited `phase5/runtime/Input.m`, for example.
- The Managed-to-Shared storage adapter and its test, which later Metal work
  built on.
- A documented boundary: the desktop sheet and audio work were left open. Phase
  5 stopped at the user's request, and the report says a harder target should
  wait for an explicit decision about those gaps.
