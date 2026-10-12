# Phase 6: SuperTuxKart 1.5 on the iOS VM (multi-image guest groups)

Dates: 2026-10-07. Commits `da59c42`, `fb8ad11`, `c74c865`, `cd4145c`. Sources:
`docs/phase6-findings.md`, `progress.md` (the Phase 6 work log), and the
`phase6/` directory. `progress.md` records this phase as started 7 October by
the agent working on it, and gives a numbered task board.

## Goal

Run the unchanged official SuperTuxKart 1.5 macOS release on the iOS VM at 30
fps or better, playable. SuperTuxKart is a multi-library application: 19 arm64
images (the executable and 18 bundled dylibs). The loader handled one image per
guest until now, so the first requirement was loading several images as one unit.

## Target

- `SuperTuxKart-1.5-mac-signed.zip` (GitHub release 1.5, 2025-10-20), about
  715 MB. Universal app. The 19 arm64 images are thinned into `build/stk/thin`,
  and their hashes are in `SHA256SUMS`. Each image's hash is re-verified inside
  the iOS container at launch.
- All images are `LC_DYLD_INFO_ONLY`, with install names of the form
  `@executable_path/../libs/<name>`. MoltenVK is not linked. SDL `dlopen`s it.
- Data: 5,585 files, 761 MiB, pushed unchanged into the app's Documents.
- Treated as closed source. No target source was read.

## What was built

| Path | Contents |
|---|---|
| `runtime/group.c`, `runtime/image.c` (shared) | Guest groups. Phases: map all members, link all members, register metadata, run initializers dependencies first and the executable last. Hashed exports, special bind ordinals, weak coalescing in member order, guest `dlopen`/`dlsym`/`dladdr`/`dlerror`, libunwind dynamic sections, `MH_DYLIB` admission (opt-in). |
| `runtime/Extended.c` (shared, from Phase 4) | Applies compiled Objective-C categories. |
| `phase6/tools/build.py` | Builds one signed container per image, with each image's `__unwind_info` rebased (`--quick` for fast builds). Produces `STKHost.ipa`. |
| `phase6/tools/vm.py`, `tap.py` | Install, launch, report, logs, probes, screenshots, and input taps against the VM. |
| `tools/vphone_install.py`, `tools/vphone_push_tree.py` | Install and resumable parallel data push through the VM host API (no UI). |
| `phase6/host/Main.m`, `LoadCLI.m`, `config-seed.xml` | iOS host (UIKit-first launch) and macOS harness. |
| `phase6/runtime/Desktop.m` | CoreGraphics display model for the single iOS screen, `CVDisplayLink` period, honest "unavailable" answers for ForceFeedback, IOBluetooth and Apple Events. |
| `phase6/runtime/AppKitExtras.m` | Window and view methods SDL needs, responder chain separate from UIKit's, window-delegate notifications (needed for SDL keyboard focus), mouse confinement, `interpretKeyEvents:`. |
| `phase6/runtime/Policy.c`, `Survey.m`, `Watchdog.m`, `DrawProbe.m`, `FrameCounter.m` | Host policy and diagnostics: selector survey, hang watchdog with a main-thread stack sampler, encoder and pipeline draw probe, and a drawable frame counter. |
| `phase6/tests/VertexFormatProbe.m` | Sweep test for indexed-draw `baseVertex` on the device GPU. |
| `phase5_5/runtime/BaseVertex.m` | Startup detection and workaround for the 16-bit `baseVertex` defect (shared with Phase 5.5 code). |
| `phase6/runtime/GameControls.m` | Added in Phase 7, not Phase 6. |

## How it was done

The task board in `progress.md` shows the order:

1. Inspected the release and split the arm64 slices (7 Oct).
2. Built guest groups on macOS first. The 19-image group reached the game's GUI
   on the Mac harness, with `render_driver="vulkan"`. The guest's `dlopen` then
   loaded MoltenVK 1.3 and created a Vulkan device and swapchain in SDL's
   `CAMetalLayer`.
3. Packaged each image as its own signed container.
4. Built the iOS host. The guest's main loop is entered from a run-loop timer.
   `NSApp` stays nil until the first `+sharedApplication`, so SDL's application
   class becomes the shared instance.
5. Installed without UI through the VM host API (`vphone_install.py`).
6. Found and fixed each rendering and input problem with on-device probes (below),
   and drove the game with a hardware keyboard.
7. Pushed the data (about 8 to 10 s with 6 to 8 workers; 20 s with 2 workers and
   16 s with 12), and made the push resumable.

## Problems and bugs

| Symptom | How it was found | Root cause | Fix | Commit |
|---|---|---|---|---|
| Bind streams with negative address deltas were not decoded | Loader comparison with dyld encoding (found while loading the 19 images) | The linker writes negative `DO_BIND_ADD_ADDR_ULEB` deltas as modulo 2^64. | Accept the wrapped deltas. | `da59c42` |
| Fixup stream rejected because it ended without `DONE` | Loader log | Some streams end at the stream's end. | Accept streams without `DONE`. | `da59c42` |
| Starting the guest from a main-queue block starved later main-queue work (`dispatch_async(main)`) | Stalled start (the findings do not give the exact trace) | A long-running main-queue block blocks the main run loop. | Enter the guest from a run-loop timer. | `da59c42` |
| `NSApp` was nil when SDL looked for it | Guest call on `NSApp` | SDL's application class must become the shared instance. | `NSApp` is left nil until the first `+sharedApplication`, so `SDLApplication` becomes it. | `da59c42` |
| Keyboard crash in `interpretKeyEvents:` | Crash log | Missing responder behaviour. | Implemented the standard key bindings path. | `fb8ad11` |
| MoltenVK advertised BC/DXT texture formats that the VM GPU cannot sample | Device capability report (`bc_textures: 0` on the paravirtual GPU) | The legacy Mac feature-set profile (added in Phase 5.5) made MoltenVK enable those formats. | STK's host disables the profile. STK then uses ASTC. | `fb8ad11` |
| Placement heap resources corrupted | Visual corruption | MoltenVK placement heaps on this GPU. | `MVK_CONFIG_USE_MTLHEAP=0`. | `fb8ad11` |
| Karts drew other meshes' vertices (spikes), while early track meshes were fine | Draw probe, then a vertex-format sweep | The VM GPU truncates indexed-draw `baseVertex` to 16 bits: 65535 works, 65536 becomes 0, 100000 becomes 34464, 182000 becomes 50928. STK packs meshes in one buffer, and karts sit above 65,536. | `BaseVertex.m` detects the defect at startup and rewrites draws with `baseVertex >= 65536` by advancing each per-vertex buffer offset. Limit: `[[vertex_id]]` then excludes the base. | `fb8ad11` |
| SDL did not get keyboard focus | Input test | SDL takes focus from `windowDidBecomeKey:`, which the window delegate did not receive. | Window delegates now receive window notifications. | `c74c865` |
| Mouse confinement and mouse location did not match AppKit behaviour | Input test | The adapter lacked the AppKit cursor and location behaviour SDL expects. | Virtual cursor clamp; `mouseLocationOutsideOfEventStream`. | `c74c865` |
| 18 fps seconds while driving | Frame timing | The diagnostics JSON was rewritten on every key event. | Traces coalesced to at most two writes per second. | `c74c865` |
| Many keys did nothing | Input test with a full keyboard | The adapter mapped only letters, digits, arrows, Return, Escape, Backspace and Space. | Full USB HID to Apple virtual-key map, including punctuation, function keys, keypad and modifiers as `flagsChanged`. | `cd4145c` |

**Ruled out by experiment** (`docs/phase6-findings.md`): integer, half and packed
vertex formats; two-stream fetch; MSL translation (byte-identical dumps on the
Mac and on iOS); the Vulkan capability set; Metal event and fence
synchronization.

**Still open at the end of the phase:** audio (no VM route); the generic touch
overlay was not visible over SDL's view (keyboard play was verified); ordinary
signing; DWARF-only unwind entries (189 functions) not covered by the container
unwind info.

## Results / evidence

- The unchanged game runs on the VM: menus, offline profile, kart and track
  selection, and races, driven with a hardware keyboard.
- Native resolution 2796 x 1290. STK's own counter shows 42 / 58 / 60 fps
  (min / average / max) while driving. The host frame counter shows 53 to 60
  fps. The findings call this "~55 to 60 fps".
- In-race footprint 369 MB. GPU was about 50 percent busy while racing.
- The same 19 images render races on the Mac through the loader (macOS harness
  `build/phase6/stk-load`). This is a control for the loader, not for the VM.
- Screenshots: `docs/evidence/phase6-ios-main-menu.jpg`,
  `docs/evidence/phase6-ios-race.jpg`. Constants used by the adapter:
  `docs/evidence/phase6-desktop-constants.txt`.
- Totals reported by the loader for this group: 99,395 rebases, 20,735 binds,
  1,441 selectors and 390 initializers.

Not established: audio, touch-only controls, ordinary signing and sustained
memory behaviour. Both the Phase 5.5 legacy Metal profile and the custom-trust
installation remain research dependencies on the VM.

## What it unlocked next

- Multi-image guest groups. This is the loader feature that Phases 7 and 8
  rely on. Cyberpunk 2077 loads five images in the same way.
- Shared AppKit and SDL adapters, reused in Phase 8 (`phase6/runtime/AppKitExtras.m`
  and `Desktop.m`).
- The `BaseVertex` workaround is VM-only. The physical iPhone did not show the
  defect (Phase 7).
- The lesson recorded in the findings: do not fake capability bundles. The
  legacy Mac profile had been enabled for Veloren's border sampling and broke
  textures in STK.
- The phone route: the same package was signed with a development profile and
  installed over USB (Phase 7).
