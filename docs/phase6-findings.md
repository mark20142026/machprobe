# Phase 6 findings — SuperTuxKart 1.5 on the iOS VM (multi-image guests)

Status: **unchanged official SuperTuxKart 1.5 runs and is playable on the vphone
iOS 27 VM** (custom-trust research installation): menus, offline profile, kart
and track selection, races driven with a hardware keyboard, ~55–60 fps at the
native 2796×1290 resolution (STK's own counter 42/58/60 min/avg/max while
driving; host frame counter 53–60 last-second frames). In-race footprint 369 MB.
Audio, touch-only controls and ordinary signing are not claimed.

## Target (VERIFIED)
`SuperTuxKart-1.5-mac-signed.zip` (GitHub release 1.5, 2025-10-20), archive
SHA-256 `c266acdb…b303`. Universal app; 19 arm64 images (supertuxkart + 18
bundled dylibs) thinned to `build/stk/thin`, hashes in `SHA256SUMS`; every image
hash is re-verified inside the iOS container at launch. Data (5,585 files,
761 MiB) is pushed unchanged to the app's Documents. No target source read.

## Loader: guest groups (VERIFIED on macOS and iOS)
`runtime/group.c`, `image.c` map/link/start phases. One link unit: map all
members, link all (imports naming a member's install name, or an `@`-relative
name with the same basename, bind to that member's hashed exports), register
ObjC metadata (classes + compiled categories), run initializers dependencies
first and the executable last. Weak definitions coalesce in member order;
special bind ordinals; guest `dlopen/dlsym/dladdr/dlerror` see members (SDL
dlopens MoltenVK). dyld-compatibility fixes found by this target: wrapped
negative `DO_BIND_ADD_ADDR_ULEB` deltas; fixup streams ending without DONE.
Totals: 99,395 rebases, 20,735 binds, 1,441 selectors, 390 initializers.
Control: the same 19 images render races correctly on the Mac through the
loader (macOS harness `build/phase6/stk-load`, `STKMacHarness.app`).

## iOS packaging
One signed container per image. Each container also carries the guest's
`__unwind_info` with every image-relative offset shifted by the container
offset, because libunwind asks dyld first and dyld sees the container
(28k functions; 189 DWARF-mode functions are not covered).

## Root causes on the way to correct rendering (VERIFIED by on-device probes)
1. **Legacy Mac feature-set profile** (Phase 5.5, for wgpu border colours)
   made the macOS MoltenVK enable BC/DXT formats; the paravirtual GPU reports
   no BC support (`bc_textures: 0`). STK's host disables the profile; STK
   then uses ASTC. Lesson: never fake capability *bundles*.
2. **Placement MTLHeaps**: resources sub-allocated in MoltenVK heaps came out
   corrupted; MoltenVK's documented `MVK_CONFIG_USE_MTLHEAP=0` fixes it.
3. **GPU defect: indexed-draw `baseVertex` truncated to 16 bits** on the
   "Apple Paravirtual device GPU" (sweep: 65535 ok; 65536→0, 100000→34464,
   182000→50928, u16 and u32 indices alike; `phase6/tests/VertexFormatProbe.m`).
   STK packs meshes in one buffer; the karts (~vertex 182k) fetched other
   meshes' vertices (spikes) while early-loaded track meshes (<65536) were
   fine. `phase5_5/runtime/BaseVertex.m` detects the defect at startup and
   rewrites draws with baseVertex ≥ 65536 by advancing each per-vertex buffer
   by baseVertex×stride, drawing with baseVertex 0 and restoring offsets.
   Limitation: `[[vertex_id]]` then excludes the base.
Ruled out by experiment: integer/half/packed vertex formats, two-stream fetch,
MSL translation (byte-identical dumps Mac vs iOS), Vulkan capability set,
Metal event/fence synchronization.

## Platform adapters added (phase6/runtime)
Import probe (link-only, zero unresolved after adapters), Desktop.m
(CoreGraphics display model on the single iOS screen, CVDisplayLink period,
ForceFeedback/IOBluetooth/Apple Events honestly unavailable, measured
constant values e.g. kCGDisplayShowDuplicateLowResolutionModes =
"kCGDisplayResolution"), AppKitExtras.m (window/view methods SDL needs,
AppKit responder chain separate from UIKit's, delegate auto-subscription to
window notifications — needed for SDL keyboard focus, mouse confinement,
interpretKeyEvents: with standard key bindings, backing-scale conversions).
Lifecycle: UIKit starts first; the guest's main loop is entered from a
run-loop timer (a main-queue block would starve dispatch_async(main)), and
`nextEventMatchingMask:` spins the run loop (SDL's iOS SDL_main pattern).
`NSApp` stays nil until the first `+sharedApplication` so SDLApplication
becomes the shared instance.

## Diagnostics built (reusable)
Selector survey mode, hang watchdog + periodic main-thread stack sampler
(symbolized through the loader's dladdr), encoder/pipeline draw probe,
CAMetalLayer drawable frame counter, `env.json`/`arguments.json` launch
options, `tools/vphone_install.py` and `tools/vphone_push_tree.py`.

## Performance note
Writing the diagnostics JSON on every key event caused 18-fps seconds while
driving; traces are now coalesced to ≤2 writes/s. GPU ~50% busy while racing.

## Not done / unverified
Audio (the VM has no output route, as in Phase 5.5). Touch-only controls: the
generic virtual key overlay is not visible over SDL's view (keyboard play
verified). Ordinary signing. DWARF-only unwind entries in containers.
