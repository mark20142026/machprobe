# machprobe progress

Updated 1 October 2026 (Asia/Nicosia).

## Current: Phase 5.5 active

Veloren loader work and iOS experiments are in progress. See the latest entry at
the end of this file and docs/phase5.5-findings.md.

## Historical: Phase 5 gameplay milestone; stopped at user request

Official Strataris v1.0.1 ARM64 macOS bytes run through the runtime in the iOS VM.
Title, briefing, cockpit, movement and firing were observed; user confirmed play.
No target source was read or rebuilt. Host K shortcut removed; optional desktop
keyboard sheets remain incomplete. Audio and normal-signing/sandbox independence
are not verified. See docs/phase5-report.md and docs/phase5-findings.md.
Phase 5.5 subsequently began with user approval.

## Historical: Phase 4 completion

The official DashboardCalculator ARM64 macOS executable runs its own SwiftUI UI
in the iOS VM through our runtime. Original buttons and logic produced 2 + 2 = 4
and 7 × 8 = 56. No target source was read or rebuilt; executable bytes are unchanged.
Original assets were generically converted to an iOS catalog. Metadata registration,
weak imports, fixups and small platform API adapters were added to our runtime.

64 local test methods pass, plus Phase 2 sanitizer reruns and a fresh eight-guest
iOS regression using the final shared runtime. Ordinary-device signing and
independence from vphone's custom trust remain unverified. No next phase started.

See [Phase 4 report](docs/phase4-report.md) and [findings](docs/phase4-findings.md).

## Historical progress before Phase 3 GUI completion

The following earlier notes are retained as history; current iOS guest execution
is recorded in `docs/evidence/phase3/verified-run.json` and the Phase 4 regression.

## Current: first iOS VM run

The official-SDK `MachProbe iOS` host now launches in the user's existing vphone
iOS 27 VM. Scene lifecycle and guest packaging were repaired. All seven original
macOS guest hashes survive installation/extraction, but registration of every
guest's embedded signature fails with errno 85 before execution. Even a
byte-identical Documents copy of the installed iOS host fails, while registration
of the installed host succeeds. No jailbreak/bootstrap or security changes were
made. The installer adds a custom-trust entitlement; this is recorded separately
from the user's report that the VM is not jailbroken.

See [the admission findings](docs/phase3-ios-admission.md) and
[measured results](docs/evidence/phase3/admission-probe.json). The new IPA is
`build/phase3-ios/MachProbe.ipa`. Guest execution/input on iOS remains blocked;
do not describe the launched UIKit host as a running macOS guest.

## Completed Phase 2 history

Phase 2 is complete. Phase 1 source/tests, the original four binaries and prior evidence are preserved. The new runtime executes all seven controlled macOS guests; UIKit buttons reach guest-owned counter logic and callbacks update the display. CoreFoundation, Foundation/Objective-C lifetime behavior, Metal device information and all 16 compute results were verified on macOS/Catalyst.

30 Phase 1 inspector + 8 Phase 1 loader + 10 Phase 2 integration test methods pass normally and with sanitizer builds of the host/runtime. ABI assertions include 40 load/state/destroy/unload cycles and failed-open checks. Final automated UI sequence was 0 → 1 → 0 → -1 → 0. Additional counter changes during development came from user clicks.

Reports: [Phase 2 report](docs/phase2-report.md), [findings](docs/phase2-findings.md), [evidence](docs/evidence/phase2/results.json), [UI observation](docs/evidence/phase2/ui-observation.json).

Prepared next step: [vphone-cli research](docs/phase2-vphone-research.md), [Phase 3 handoff](docs/phase3-preparation.md), and `phase2/ios/Phase2Host.xcodeproj`. No iOS execution is established. Full Xcode/iOS SDK is absent. The user intends to arrange the patched iOS 27 vphone environment separately. No security settings changed, no VM installed, no game touched.

Stopped before Phase 3. Luna's recurring checks remain off; the existing companion chat is available for questions.

## Phase 5.5 active — loader milestone

Official ARM64 Veloren preserved unchanged. First failure was 64 MiB image cap.
Added bounded host policy, tested TLS, legacy weak binds, tagged relocations and
signed addends. Official binary now loads (146,786 rebases / 1,517 binds) and runs
its own `--help` in the macOS harness. Existing Phase 1–5 tests pass; synthetic
TLS tests pass under host sanitizers (288 workers, 12 unload cycles). iOS package
built; next work is actual iOS admission/API failures and gameplay. No gameplay
or normal-signing success claimed. No valid development signing identity exists.
Full phase remains active; see docs/phase5.5-findings.md and phase5.5-report.md.

Phase 5.5 iOS progress: original hash verified after VM installation; signed
container now accommodates virtual BSS gaps without editing original bytes.
Veloren's real `list-wgpu-devices` executes in iOS and reports Apple Paravirtual
device GPU, exit zero. Original assets copied with every SHA-256 checked. Normal
startup finds them; actual build identifies itself as 6162d956 [2026-09-30].
Writable userdata now uses Documents. Current observed fatal boundary is winit's
NSApplication.sendEvent: expectation; class lookup bridge and event routing are
being expanded. Real audio initialization reports Unknown property; outstanding.
Still no gameplay/rendering/stress or ordinary-signing success claim.

Phase 5.5 continuation: Veloren now constructs its winit view/window and starts its own shader compilation on iOS. Independent GPU border sampling: 6/6 cases passed; UIKit adapter probe: 12/12 checks. Current boundary is fullscreen/display lifecycle. Legacy Mac feature profile remains explicitly experimental; no game frame or gameplay claimed. Mac/display kept awake with user-requested indefinite caffeinate.

Phase 5.5 current: real title/singleplayer UI renders; world generation reached
3D character creation. Pointer flipping fixed and 17 iOS adapter checks pass.
Carbon ANSI-US keyboard fallback matches 1,600 native layout cases under sanitizers.
Working through actual keyboard/audio API failures before entering gameplay.
Current custom-trust/legacy-Metal-profile limitations remain explicit. Caffeinate
has no timeout and remains active until the user returns. No game source read.

Phase 5.5 live update: the unchanged Veloren binary enters the actual 3D village.
Movement, camera rotation, attack animation and opening inventory observed in iOS
(evidence 66–71). Audio still fails at the desktop HAL buffer-size-range query.
Adding a collapsible generic keyboard and an independent RemoteIO probe. No full
phase completion or ordinary-signing claim.

Phase 5.5 latest: actual gameplay includes forest traversal, lantern, consuming
cheese through secondary click, collecting wood and opening crafting UI.
Item changes persist across relaunch. Fixed the Graphics settings crash with
a generic primary-display identity/current-mode adapter; 32 iOS probe checks
pass and the original game's panel opens. Logout returns to the game's title
with its own save-thread-finished log; same-process re-entry verified.
A later process exit/VM locked-screen event has no established cause or fresh
app crash report. Relaunched as PID 4909. Higher-load setting not yet verified.
Audio has no usable VM output route even in the independent iOS probe. Ordinary
signing remains unverified (zero valid identities). No phase completion claim;
original game hash unchanged. Indefinite caffeinate remains active.

Recovery: PID 4909 re-entered the saved world and rendered gameplay (evidence 95).
Display adapter and gameplay persistence milestone committed as e61aa10.

## Phase 6 active — SuperTuxKart 1.5, multi-library guests (agent work log)

Started 7 October 2026 by Claude (Opus 5.5) on the user's request. Goal: the
unchanged official SuperTuxKart 1.5 macOS release boots on the iOS VM and is
playable at >=30 fps. This needs the loader to support several guest images
(main executable + its bundled dylibs) instead of exactly one MH_EXECUTE.
Any agent continuing this work: read this section first, then
docs/phase6-findings.md. Keep entries short and dated; mark DONE/IN PROGRESS.

Target: `SuperTuxKart-1.5-mac-signed.zip` (715 MB, GitHub release 1.5,
2025-10-20), preserved under build/stk/original/. Treated as closed source.

Plan / task board:
1. DONE 7 Oct — inspected. Universal app; arm64 slices extracted to
   build/stk/thin (hashes in SHA256SUMS). 19 images: supertuxkart + 18 libs,
   all LC_DYLD_INFO_ONLY, install names @executable_path/../libs/<name>.
   MoltenVK is not linked: SDL dlopens it. ObjC in main, SDL2 (categories),
   MoltenVK (categories, protorefs). C++ unwind info everywhere.
2. DONE 7 Oct (macOS) — loader groups: runtime/group.c + image.c phases
   (map all, link all, metadata, init deps-first/main last), hashed exports,
   special bind ordinals, guest dlopen/dlsym/dladdr/dlerror, libunwind
   dynamic-section hook, MH_DYLIB admission (policy opt-in), Extended.c
   applies compiled categories. Two dyld-compat fixes: wrapped negative
   DO_BIND_ADD_ADDR_ULEB deltas; fixup streams may end without DONE.
   Phase 5.5 tests pass; Veloren --help unchanged (146,786/1,517).
   macOS harness: `make -C phase6 && SUPERTUXKART_DATADIR=<app>/Contents/Resources
   SUPERTUXKART_SAVEDIR=build/phase6/mac-save build/phase6/stk-load build/stk/thin --run`
   → 19 images, 99,395 rebases, 20,735 binds, 1,441 selectors, 390
   initializers; game reaches its GUI. With config render_driver="vulkan"
   (iOS has no GL): guest dlopen loads MoltenVK 1.3, VkDevice + swapchain in
   SDL's CAMetalLayer. Run STK from a scratch cwd: it creates ./icons ./tmp.
2. TODO — loader: admit MH_DYLIB guests (LC_ID_DYLIB, no LC_MAIN), resolve
   @rpath/@executable_path/@loader_path to other guest images, fast export
   lookup (hash table), cross-image binds and weak coalescing, dependency-
   ordered initializers. Files: runtime/image.c, fixups.c, services.c.
3. DONE 7 Oct — packaging: `python3 phase6/tools/build.py [--quick]` builds
   one signed container per image (+ rebased __unwind_info) and STKHost.ipa.
4. DONE 7 Oct — iOS host phase6/host/Main.m + phase6/runtime adapters.
   Drive with `python3 phase6/tools/vm.py install|launch|report|logs|probe|
   survey|probe-vertex|args ...|env K=V ...|screenshot` and phase6/tools/tap.py.
5. DONE 7 Oct — install route without UI. VM runs with the host API:
   `VPHONE_API_TOKEN=$(cat build/vm-api-token) nohup "<bundle>/MacOS/vphone-cli"
   vm launch iphone --library-root ~/.vphone/machines --api-listen
   127.0.0.1:18765` (token file chmod 600, port in build/vm-api-port; the
   launch log does not print the token, so we choose it via the env var).
   Install: `python3 tools/vphone_install.py X.ipa --bundle-id ID --launch`
   (PUT /v1/files/content + apps.install; 26 MiB in ~3 s). HTTP replies are
   {"result":...} or {"error":...}, no "ok" field. Fallback: drag the IPA onto
   the VM window, or Apps > Install App Package (computer use works for menus).
6. DONE 7 Oct — menus, races and keyboard driving at ~55-60 fps native
   resolution. Root causes (BC via legacy profile, MTLHeap, GPU baseVertex
   16-bit truncation) and everything else: docs/phase6-findings.md.
   Open: audio (no VM route), visible touch controls, ordinary signing.
7. DONE 7 Oct — data push without UI: `python3 tools/vphone_push_tree.py LOCAL GUEST
   [--bundle-id ID] [--workers N] [--prune]` (GUEST relative to the app data
   container with --bundle-id, e.g. Documents/stkdata/data). Resumable: one
   files.list per guest dir, skips same-size files, parallel PUTs (6 workers),
   verifies file count + bytes. STK data (5,585 files, 761 MiB): 8-10 s
   (~80-95 MiB/s, ~600 files/s); re-run skips all in 2.5 s. Workers: 2=20 s, 4=12 s, 6-8=8-10 s, 12=16 s.
   API quirks: PUT and files.mkdir create parents; files.list on a missing path is HTTP 400; files.find is exact-name only.

Side note carried over from Veloren (7 Oct): the game leaks ~38 KB per rendered
frame (memory growth stops when rendering stops); with a 4 GB VM this ends in a
jetsam kill (ReportSystemMemory crashed while writing CDJetsamReport on 1 Oct,
which is why no jetsam report exists). Instrumented build (wrapper/handler
counters in phase5_5/runtime/LegacyMetal.m) is built but not yet installed.
Performance settings profile: docs/evidence/phase5.5/perf/ (35-50 fps measured).

## Phase 7 — physical iPhone 18 Pro (9 Oct 2026)

DONE: unchanged SuperTuxKart 1.5 runs on the user's iPhone 18 Pro (iPhone19,2,
iOS 27.0.1) at 60 fps. Signing: free Personal Team <TEAM-ID>, ONE App ID
`research.machprobe.STKHost` for every build (free accounts: 10 App IDs/week —
never create another). Profile expires 2026-10-16; refresh with
phase7/signing/Provisioner.xcodeproj (same bundle ID). Workflow:
`python3 phase7/tools/device.py deploy|launch|report|logs|args ...` (USB via
devicectl; data was pushed once with `devicectl device copy to`).
Real-device findings: signed containers install and run; only macOS-only
MTLDevice queries needed answering (LegacyMetal.m); the VM baseVertex defect
is absent. Touch gamepad (GameControls.m) toggled with 🎮. Next: Cyberpunk 2077.
