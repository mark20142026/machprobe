# Phase 5.5 findings — work in progress

Status: **not complete**. Initial Veloren gameplay and rendering are verified in the custom-trust iOS research installation. Audio, sustained traversal and ordinary signing remain outstanding.
The target is treated as closed source. Only its official executable/resources,
release metadata, our code, Apple runtime documentation and vphone documentation
have been inspected. Original target code has not been rebuilt or patched.

## Preserved release (VERIFIED)

Official rolling weekly asset: `weekly-macos-aarch64-2026-09-30T23_33.zip`,
created 2026-10-01 08:01:45 UTC. The rolling GitHub release's older publication
date is not the date of this asset.

- [Author download redirect](https://download.veloren.net/latest/macos/aarch64/weekly)
- [Exact distributed archive](https://github.com/veloren/veloren/releases/download/weekly/weekly-macos-aarch64-2026-09-30T23_33.zip)
- Archive SHA-256: `7cfaab24fed27a1c62cf4ba0b2021d579b087b0d97394dea1716850ea21e5ba1`.
- Main executable SHA-256: `786b7ba15f46982a1bfbd3af53373c505d5dce0efb344dfe19a159b7e6e00b1d`.
- Main executable: 75,697,760 bytes, thin ARM64 ALL, MH_EXECUTE, macOS 11.0 minimum,
  SDK 15.5, linker ad-hoc signature. No developer Team ID.
- Distribution contains loose `veloren-voxygen`, `veloren-server-cli` and assets,
  rather than an `.app`. Complete original-file hashes and binary inspections
  are in `evidence/phase5.5/`. Original archive/extraction remain under
  `build/phase5.5/original/`.
- Assets include 4,752 vox files, 2,855 ron files, 1,342 ftl files, 898 png files,
  639 ogg files, 67 glsl files and 13 ttf files. Inventory is not proof they load.

## Chronological loader experiments (VERIFIED on macOS unless specified)

The first attempt used the Phase 5 policy and failed on its 64 MiB image limit.
Each numbered evidence file records the next observed boundary:

1. File too large. Added per-host bounded size policy: default 64 MiB unchanged,
   Phase 5.5 opts into 128 MiB; hard ceiling 512 MiB.
2. TLS/terminators rejected. Actual executable contains 45 TLS descriptors,
   initialized TLS and zero-fill TLS, plus `_tlv_bootstrap` and `_tlv_atexit`.
3. IOKit outside the whitelist. Admitted the additional exact dylib paths found
   in the binary; admission alone does not implement their APIs on iOS.
4. Nonempty legacy weak-bind stream rejected. Added single-main-guest weak
   definition lookup, followed by declared host libraries. This is not general
   multi-guest dylib symbol coalescing.
5. The default 8,192 rebases were insufficient. Phase 5.5 explicitly opts into
   a bounded 1,048,576 fixups per kind; earlier hosts retain their previous bound.
6. A legacy rebase contained a high-byte tag, `0x80000001033d94ee`. Preserve the
   tag while validating/rebasing the address portion, as already done for the
   chained format used by Phase 5.
7. Legacy bind opcode 0x60 requires signed addends. Added bounded SLEB128 decoding,
   positive/negative addends and overflow rejection.
8. Main executable loads: 146,786 rebases, 1,517 bindings. Initializers complete.
9. Rust startup obtained the host's argv. Added optional guest arguments used by
   `_NSGetArgc`/`_NSGetArgv` during guest entry and initializers. Guest `--help`
   now prints its actual command-line interface. `--version` is not an option
   accepted by this distributed executable.

The macOS harness deliberately uses host frameworks to separate loader failures
from iOS API differences. None of these results proves iOS gameplay.

## TLS design and evidence

DOCUMENTED: SDK `mach-o/loader.h` defines the on-disk three-word TLV descriptor.
Apple's [ARM64 TLV thunk](https://github.com/apple-oss-distributions/dyld/blob/main/libdyld/threadLocalHelpers.s)
requires preservation beyond ordinary C calls. SDK `mach-o/dyld.h` documents
`_tlv_atexit` on macOS and iOS.

VERIFIED: `runtime/tls.c` supplies a register-preserving thunk, aligned per-thread
storage copied from the relocated template, and host TLV teardown registration.
One cleanup registration precedes guest destructor registrations, so storage is
released after guest callbacks, including callbacks using TLS from other images.
Template size/alignment and descriptors are checked. TLS initializer-function
sections remain unsupported. Only mapped data descriptors change, never code or
the original file.

VERIFIED: the synthetic ARM64 macOS guest checks initialized/zero/aligned state,
thread isolation and guest destructor callbacks in 288 worker threads across 12
load/close cycles under ASan/UBSan in the host. Each image unloads after workers
join. The same fixture verifies weak definitions and arguments during startup.
Guest code itself is not sanitizer-instrumented in this test.

Outstanding TLS on the main thread pins the image for process lifetime rather
than allowing dangling destructor code. Close requires guest threads to have
finished. This is safe retention, not a claim of complete unload support.

## Host and security dependencies

VERIFIED: this Mac has no valid code-signing identities (`security find-identity
-v -p codesigning`). vphone's custom-trust installer can support research runs;
it does not exercise ordinary provisioning/installd admission. This limitation
still prevents claiming the normal-signing success criterion.

UNTESTED: ordinary iOS signing and sandbox independence, working guest audio, controller input and thorough memory/performance/stress behavior. Later sections record iOS TLS-driven startup, Metal rendering, original asset loading and initial world gameplay.
No host security setting or VM bootstrap was changed.

## What Veloren exposed that Strataris did not

VERIFIED: a substantially larger image and relocation population, native Darwin
TLS, legacy weak-definition coalescing, tagged legacy relocations, signed bind
addends and runtime acquisition of process arguments. Its dependencies also
include IOKit, CoreAudio, Carbon and other desktop frameworks outside the prior
surface. A dependency's presence does not prove which calls execute in gameplay.

## What remains between this runtime and Cyberpunk 2077

UNTESTED pending Veloren: full iOS framework admission, dynamic Objective-C class
lookup, large-image container memory layout, exceptions/unwinding, real graphics
resource/shader/pipeline workload, concurrency, audio, streaming assets, sustained
world traversal, memory pressure, controller input and normal sandbox/signing.
This is an interim list, not a completed readiness audit or a prediction of
Cyberpunk compatibility. No Cyberpunk binary or source has been inspected.

## First iOS attempt (VERIFIED, custom-trust research installation)

The iOS host launched as PID 1521, verified the original SHA-256 inside the
container, and reached `invalid resident guest range`. Veloren's `__DATA` has a
zero-fill tail, so guest virtual memory spans more bytes than the original file.
The old embedded loader assumes contiguous file and virtual offsets. No guest
entry or graphics was executed in this attempt. Evidence: `14-ios-resident-range.json`.
The vphone window's Apps > Install App Package uploaded the 26 MiB IPA through
its existing transfer support; no VM restart/bootstrap/tool installation was needed.

## Signed capacity and iOS guest Metal enumeration (VERIFIED)

The container now preserves all original file bytes followed by extra signed RW
capacity. Executable pages stay untouched. The loader copies non-executable
segments to their original virtual offsets within that capacity and zeroes BSS;
it restores the initial contiguous bytes on unload. A synthetic large-BSS guest
passes twelve embedded load/unload cycles with byte-for-byte memory restoration,
TLS workers and ASan/UBSan (`container-tests.txt`). Existing earlier containers
remain supported.

The next iOS failures were data imports `NSAppKitVersionNumber` and
`NSAppearanceNameAqua`. The compatibility profile reports AppKit 11.0 (2022), not
the iOS version and not full AppKit coverage. Related string identifiers were
measured on the host (`desktop-constants.txt`) and supplied by our runtime.

Unresolved **lazy function** imports can now opt into precompiled failure entries.
They abort and name the import on first actual use; they never return fabricated
success. Eager data imports still must resolve before entry. Currently 38 desktop
functions are deferred; see `17-ios-deferred-imports.txt`. Deferral is unsupported
functionality, not API compatibility.

The actual unchanged Veloren `list-wgpu-devices` command then ran in iOS and
printed `Apple Paravirtual device GPU`, returning zero. PID 1610, 146,786 rebases,
1,517 bindings; hash matches the preserved executable. Evidence:
`17-ios-device-enumeration.json`, `17-ios-device-stdout.txt`.
This verifies guest execution and its own wgpu device enumeration through host
Metal. It does **not** verify rendering, pipelines, gameplay, audio or performance.
`MTLCopyAllDevices` resolved directly from the iOS host. The installed iOS SDK
header explicitly marks it available since iOS 18.0; it is not a desktop-only SPI.
Ordinary-device validation is still pending. Runtime compilation is ARM64 iOS, not Catalyst.

## Normal startup, assets and dynamic classes (VERIFIED)

All 10,654 copied resource files (435,429,176 bytes) match originals by SHA-256.
The unmodified guest found the asset tree on iOS. Its own panic report identifies
build `6162d956 [2026-09-30]`. The first normal-startup run tried to save userdata
beside the executable and received permission denied; the host launch profile
now supplies the documented `VELOREN_USERDATA` environment path inside Documents
and `VELOREN_ASSETS` pointing to the original bundle assets. This is launch
configuration, not a patched/recompiled game. Verification of the new writable
path is pending the next run. See the [official environment guide](https://book.veloren.net/players/env-vars.html)
and [userdata configuration example](https://book.veloren.net/players/server-hosting/on-the-rpi.html).

Observed fatal error: `class NSApplication could not be found`. Compiled class
imports alone are insufficient: this guest uses `objc_getClass` dynamically.
The next runtime build routes that API through the same AppKit class adapters.
It continues forwarding existing Foundation/Objective-C classes to iOS.

An earlier, nonfatal audio initialization error was `Unknown property` from the
actual cpal frontend. No audio success is claimed. These messages are in
`18-ios-stdout.txt` / `18-ios-stderr.txt`; the panic-handler's secondary NSAlert
failure must not obscure the original NSApplication error.

VERIFIED on the next iOS run: the documented userdata override creates game
logging/configuration under the normal app Documents directory. Dynamic class
lookup progresses to winit's method check: `NSApplication must have sendEvent:
method`. The next shared adapter change routes physical/on-screen keys through
`NSApplication.sendEvent:` before existing monitors/responder delivery, so a
guest which hooks that method can observe actual host input. Current-event state
is restored after delivery. This is pending iOS/regression verification.

VERIFIED regression after shared event-path changes: rebuilt and reinstalled
Strataris host, delivered a physical-keyboard Return event via vphone, and observed
its original cockpit gameplay again. Key-down/up 36 reached the guest, and the
report recorded 506 real draw callbacks over 8.84 seconds. This short sample is
not a performance benchmark. Evidence: `strataris-event-regression.json` and PNG.
The test app was terminated afterward to avoid consuming VM resources.

## iOS window and legacy Metal progression (VERIFIED / partial)

Evidence 20–34 records the observed missing window/view calls in sequence.
The shared adapter now provides frame-change notifications, a stable hardware
keyboard context, scale/layer backing, initial responder selection, drag-type
registration, window stacking and borderless geometry. Pointer events use the
same application event path as keyboard events. UIKit scene creation attaches a
window requested before the scene exists. File-drop delivery, full IME support,
and physical cursor styling remain UNTESTED/unsupported; registration alone is
not proof of those features.

VERIFIED: the independent iOS UIKit probe passes 12 checks for notifications,
scale, context ownership, responder input, held-key cleanup, registrations,
geometry and window cleanup (`38-ios-uikit-probe.json`). Run it with
`python3 phase5_5/tools/vm.py probe-uikit`. It tests adapter behavior, not gameplay.

The game now reaches its real wgpu device selection. It then rejects missing
`ADDRESS_MODE_CLAMP_TO_BORDER` (`35-ios-border-feature.txt`). The independent
native iOS Metal probe compiles a compute shader, samples a real texture and
checks 96 float components across all three border colors and nearest/linear
filtering. All six cases pass on Apple Paravirtual device GPU
(`36-ios-border-probe.json`). Run with `python3 phase5_5/tools/vm.py probe-metal`.
The driver reports Apple families through 5, no Mac family and no legacy Mac
feature set, despite implementing this particular operation correctly.

DOCUMENTED: [Apple's feature table](https://developer.apple.com/metal/capabilities/)
lists border color for Apple7/Mac2; the SDK exposes it on iOS 14+. Binary
inspection of the distributed executable's device enumeration shows legacy
`supportsFeatureSet:` calls using values 10000–10005. No target source was read.

EXPERIMENTAL / NOT FULLY VERIFIED: Phase 5.5 now offers a legacy Mac1-v1/v2
compatibility profile (10000/10001), gated by the real border probe and native
Apple5 support. Later legacy sets remain false; modern family answers remain
native. These sets bundle additional promises, including desktop texture formats;
full conformance has NOT been established. This is a research hypothesis to
continue observing actual workloads, not proof the VM supports every Mac feature.
Any gameplay reached with this profile must be labeled accordingly until the
required operations have been verified. No target code, shaders or assets change.
The next observed API differences are desktop `isLowPower`/`isHeadless` topology
queries, mapped to a single integrated iOS presentation GPU.

Original assets are now deployed under Documents/assets. The guest failed to
find an otherwise identical tree named VelorenAssets; the basename `assets`
matters to its discovery behavior. Its own logs confirm the final path. Default
incremental IPAs omit the already-deployed 435 MB tree; `--with-assets` packages
original bytes for a first installation. Userdata stays in Documents/userdata.

## Visible game UI, world generation and keyboard (VERIFIED / partial)

Evidence 43–56 records the subsequent window registry, pasteboard, running-app,
tracking rectangle, event-copy and cursor-association boundaries. The game's own
title screen renders on iOS (`51-ios-title.jpg`); touch opens its own singleplayer
world selection (`55-ios-singleplayer-world-selected.jpg`). World generation
runs terrain and economy simulation. One early generation sample had 792,659,600
bytes footprint (`56-ios-worldgen-memory.json`), not a peak or stress benchmark.

The first relative-cursor request originally trapped. The adapter now maintains
a guest virtual cursor and requests UIKit pointer lock through the public view
controller API. Camera behavior remains UNTESTED. The corrected pointer path
respects a guest view's `isFlipped`; the actual WinitView binary returns YES.
The independent iOS adapter probe passes 17 checks (`55-ios-coordinate-probe.json`).

The next run reached the game's 3D character-creation screen. Typing then exposed
Carbon TIS/UCKeyTranslate/LMGetKbdType imports. The new adapter explicitly supplies
an ANSI-US fallback; it does not claim to represent arbitrary physical layouts,
IME composition or dead keys. Native macOS US-layout comparisons cover 1,600
key/action/modifier combinations with zero differences under ASan/UBSan. Invalid
resources, insufficient output capacity and unsupported modifiers are tested.
The target's original code/resources were not changed.

Audio remains incomplete. Diagnostics prove the iOS HAL default-output query
succeeds but desktop `sfmt` (device stream format) fails. A public RemoteIO query
now supplies the actual output format. The next unsupported query is `fsz#`
(buffer-frame-size range). The current adapter work offers only the active iOS
quantum, not an invented hardware range. No audible output is claimed yet.

The current custom-trust install and experimental legacy Metal profile remain
research dependencies. Visible menus/characters do not certify gameplay,
normal signing, full Mac Metal feature-set support or device performance.

VERIFIED follow-up: letter-key events now enter `probe` in the game's real
character-name field; creating that character succeeds (evidence 60). First world
entry then exposed cursor-region invalidation (61), and the following run reached
invisible-cursor image creation before failing dynamic NSImage lookup (63). The
existing image shim is now included in dynamic class resolution and decodes guest
image bytes through UIImage. Cursor objects retain the image and hotspot; touch
has no persistent visible pointer, and full custom physical-pointer styling is
still unimplemented.

VERIFIED: 24/24 iOS input/window/cursor checks pass (65), including event copying,
window registry, cursor association/warping and cursor-region registration and
discard. The game world-entry retry remains in progress.

Instrumentation note: the initial Metal presentation observer sees real
`presentDrawable` requests but no positive `MTLDrawable.presentedTime` on this VM.
It must not infer displayed frame rate from that zero count. Separate GPU command
buffer completion counters are now being tested and explicitly labeled as GPU
completion throughput, not display timing.

## Initial world gameplay (VERIFIED in research installation)

Evidence 66–71: PID 3275 enters the saved single-player world, renders the village,
NPCs, player and HUD. Held virtual W/D move the character; a touch drag changes
the camera and triggers a weapon swing. Physical I opens the game inventory.
The original executable hash remains unchanged in the runtime report.

Between world-entry and pre-update snapshots, 4,994 GPU buffers requesting
presentation completed over 432.03 seconds, with zero reported GPU errors. This
is 11.56 completed presentation buffers/second across a mixed interaction/idle
interval, **not measured display FPS**: drawable presentedTime is zero in this VM.
Process footprint grew from 1,962,854,368 to 2,489,272,504 bytes while resident
bytes changed from 1,203,027,968 to 1,051,328,512. This is an initial observation,
not proof of a leak or stable memory ceiling. The VM reports an effectively
unlimited jetsam allowance, unlike an ordinary physical iPhone app.

Repeated cursor association requests previously serialized the report every
frame. The adapter now returns immediately when association is unchanged; the
existing two-second sampler remains. The generic virtual keyboard can be hidden
and shown so it does not cover the guest inventory. Physical input is retained.

## Independent iOS audio baseline (VERIFIED)

Evidence 73 runs no guest code, through the runtime's ordinary UIKit lifecycle.
AVAudioSession accepts Playback and activation, but reports no outputs, zero
channels, sample rate 0 and buffer duration 0. RemoteIO exists and accepts a
render callback. Its default stream rate is also 0; initialization returns
-10851 (kAudioUnitErr_InvalidPropertyValue, Apple SDK AUComponent.h). No callbacks
arrive. AudioUnit disposal succeeds. This establishes a missing usable output
route in the current VM independently of desktop HAL translation. It does not
prove the game audio adapter is complete, nor that physical iOS lacks audio.

The upstream [sound discussion](https://github.com/Lakr233/vphone-cli/discussions/280)
reports similar limitations; proposed workarounds there are not verified here.
No VM firmware, host security or audio routing has been changed. Working audio
remains pending a usable iOS route and the subsequent desktop AudioUnit/HAL tests.

## Traversal, item use and sampling (VERIFIED in research installation)

PID 3739 consumed cheese by translated secondary click (2/36 → 1/36 slots),
walked out of Ving into the forest shown as Wildgrip Weald, used the lantern,
and collected a Wood Logs object with E. The world object disappeared and the
wood appeared in inventory (2/36). The game's crafting UI also opens. These
are the original game's state changes; no custom game logic or assets were used.
Evidence 80, 82, 84 and 85 records these observations.

A bounded 20-snapshot sampler recorded about 202 seconds of this mixed traversal
and UI session: 5,157 completed buffers requesting presentation (25.53/s), zero
GPU completion errors, footprint range 2,292,074,584–2,465,532,112 bytes. This is
not display FPS, a leak clearance, or a controlled before/after optimization
comparison. Movement changed the scene and workload.

Opening Graphics settings subsequently called the deferred unsupported
CGDisplayGetDisplayIDFromUUID and intentionally aborted. Evidence 86 records
the exact failure. Disassembly of the distributed monitor methods, mapped via
Mach-O indirect symbols, also identifies the adjacent current-mode, mode-list,
size/refresh/encoding and ownership calls. The next runtime revision adds the
inverse primary-display identity mapping and a retained snapshot of only the
current UIKit display mode. No WindowServer ownership or arbitrary mode switch
is claimed. VERIFIED: the expanded iOS adapter probe passes all 32 checks,
including display identity and retained mode lifetime. The original game
now opens Graphics settings without an exception (evidence 87, 89).

VERIFIED: after the graphics-query crash and installing the adapter update,
the character inventory still contains the collected wood, while the consumed
cheese remains absent (evidence 90). This verifies persistence of these item
changes, not transactional safety of every game save operation.

## Same-process logout/re-entry (VERIFIED)

PID 3985 returned to the original title screen via Logout. The game logged
its rtsim save thread finishing and network shutdown, then reloaded the saved
world/character and resumed rendering in the same process. Footprint fell from
2,477,394,056 to 989,431,536 bytes around logout (evidence 91–93).
This demonstrates substantial cleanup, not complete memory attribution or
a leak-free lifetime. The reloaded local server emits query-server SendError
warnings; local gameplay still resumes. Internet multiplayer is untested.

The 18-snapshot logout/re-entry interval spans 176 seconds with PID/run identity
unchanged and zero reported GPU completion errors. Footprint peaked at
2,569,816,536 bytes during re-entry, then was 2,231,814,304 at the last sample.
Later, while attempting the view-distance slider, the process disappeared and
the guest was screen-off/locked. The guest agent was also a new process.
No fresh Veloren crash or Jetsam report was listed at observation time; the
last runtime report had no exception. Cause remains UNKNOWN, not evidence
of a specific loader/GPU fault or a cleared stability test (evidence 94).
The settings file still reports view distance 10; no higher-load result is
claimed. The host was relaunched successfully as PID 4909.

## Per-frame memory growth diagnosis (7 Oct)

Measured: PID 439, idle in a freshly created single-player world (night, HUD visible), 21 samples at 15 s over 300 s (evidence: `docs/evidence/phase5.5/perf/leak-counters.json`). Footprint rose 2,609,367,344 to 3,145,337,400 bytes (+536.0 MB, 1.79 MB/s) over 16,158 present requests (53.9/s): 33.2 KB/frame by endpoint difference, 29.1 KB/frame by least-squares slope; the first and second halves gave 30.2 and 36.4 KB/frame. This reproduces the earlier ~38 KB/frame estimate. Per-interval values are noisy (-46 to +160 KB/frame, footprint dipped at some samples), so the figure is only meaningful over minutes.

Wrapper-leak hypothesis: NOT supported. `wrappers_created` grew by 194,000 (12.0 per presented frame) but `wrappers_alive` stayed at 11 in 16 of 21 samples (range 11-22), with no upward trend. MPPresentBuffer wrappers are released.

Presented-handler hypothesis: NOT supported. `presented_handlers_fired` trailed `present_requests` by 0-1 at every sample (16,158 requests, 16,158 fires over the run), so drawable presented-handlers fire and nothing accumulates there. Also 9.2 command buffers complete per frame (148,113 in total) with zero failures.

Cumulative footprint-vs-frames correlation is 0.97, but frame rate was near-constant (~54/s), so this cannot separate growth per frame from growth per second; per-interval correlation is 0.06 (noise). The cause is therefore outside the present-buffer wrappers and drawable handlers: next candidates are per-frame allocations inside the legacy Metal translation (resources, textures or encoders created each frame and retained elsewhere) or the game itself. Caveats: footprint includes the world-load jump (380 MB to 2.6 GB before sampling); `window.gpu_ms_p50` reads ~4e-5 to 8e-5 ms, which is implausible as real GPU time and is not trusted. The character was created via the UI and may be flagged hardcore (a checkbox was toggled several times; end state unconfirmed).
