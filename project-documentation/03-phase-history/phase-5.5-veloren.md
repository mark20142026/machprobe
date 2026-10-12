# Phase 5.5: Veloren (large Rust/wgpu guest) in the iOS VM

Dates: 2026-10-01 (commits `9df8ec4`, `171944f`, `c350519`, `35e2770`,
`7408629`, `e61aa10`, `ba9e9b8`), with a memory diagnosis dated 7 October in the
findings. Sources: `docs/phase5.5-report.md`, `docs/phase5.5-findings.md`
(numbered evidence `01` to `95` under `docs/evidence/phase5.5/`), `progress.md`.

**Status: not complete.** The report and findings say so. Gameplay was observed
in the VM. Audio, ordinary signing, stability and memory are open.

## Goal

Run the unchanged official Veloren weekly build (a Rust game using wgpu, with
its own winit windowing) in the iOS VM, and reach real gameplay. Veloren was
much larger than Strataris, and it used desktop frameworks Strataris did not
(IOKit, CoreAudio, Carbon, legacy Metal feature sets).

## Target

- Official rolling weekly archive `weekly-macos-aarch64-2026-09-30T23_33.zip`,
  created 2026-10-01 08:01:45 UTC. The archive SHA-256 is recorded in
  `docs/phase5.5-findings.md`.
- Main executable `veloren-voxygen`: 75,697,760 bytes, thin ARM64, `MH_EXECUTE`,
  minimum macOS 11.0, SDK 15.5, ad hoc signature. No Team ID.
- Distributed as loose files, not an `.app`: the executable, `veloren-server-cli`
  and assets (10,654 files, 435 MB in the iOS package). Every copied asset was
  checked by SHA-256.

## What was built

| Path | Contents |
|---|---|
| `runtime/tls.c` (shared) | Register-preserving TLV thunk, per-thread storage, guest destructor registration, host teardown. |
| `phase5_5/runtime/Policy.c` | Per-host policy: 128 MiB image size opt-in (512 MiB ceiling), explicit fixup budget of 1,048,576 per kind, admitted IOKit and other dylib paths. |
| `phase5_5/runtime/LazyImports.c` | Unresolved function imports can opt in to abort stubs that name the import on first use. Data imports must still resolve. |
| `phase5_5/runtime/Constants.m` | Desktop data constants, measured on the Mac, including `NSAppKitVersionNumber` and `NSAppearanceNameAqua`. |
| `phase5_5/runtime/ObjCRuntime.m` | Dynamic class and image resolution for `objc_getClass`, including the NSImage shim. |
| `phase5_5/runtime/Display.m` | Primary display identity and current UIKit display mode only. Does not change display modes. |
| `phase5_5/runtime/Keyboard.m` | Carbon TIS and `UCKeyTranslate` fallback for ANSI-US. |
| `phase5_5/runtime/LegacyMetal.m` | Experimental legacy Mac Metal feature-set profile (sets 10000 and 10001), gated by a native border-colour probe. |
| `phase5_5/runtime/AudioDiagnostics.m` | RemoteIO and AVAudioSession diagnostics, separate from the game. |
| `phase5_5/host/Main.m`, `LoadCLI.m`, `tools/build.py`, `vm.py`, `sample_session.py`, `vsock.py` | iOS host, macOS loader harness, packaging, VM control and session sampling. |
| `phase5_5/tests/` | `test_runtime.py`, `keyboard.m`, `AudioProbe.m`, `UIKitProbe.m`, `MetalProbe.m`, `tls_host.c`. |
| `phase5_5/guests/tls.c` | A synthetic TLS fixture (not Veloren code). |

## How it was done

The first attempt used the Phase 5 policy and failed on its 64 MiB limit. Each
later failure was recorded as a numbered evidence file, and the next change was
made against that exact boundary. The sequence is in the findings; the steps
below group it.

1. Loader scale (`9df8ec4`): size policy, TLS, weak definitions, fixup budget,
   tagged and signed relocations, and guest command-line arguments. The
   unchanged executable then loaded (146,786 rebases and 1,517 binds), and its
   own `--help` ran in the macOS harness.
2. Container layout (`171944f`): Veloren's `__DATA` has a zero-fill tail, so the
   guest needed more virtual memory than the file. The container gained signed
   RW capacity. Executable pages were untouched, and BSS was zeroed and restored
   on unload.
3. Device enumeration (`171944f`): the unchanged `list-wgpu-devices` ran on iOS
   and printed `Apple Paravirtual device GPU`.
4. Assets and dynamic classes (`171944f`, `c350519`): userdata and asset paths
   were configured through launch environment variables, and dynamic class
   lookup was extended. The title screen rendered.
5. Window, input and GPU adapters (`c350519`, `35e2770`): pointer flipping,
   keyboard, cursor and image shims. A native probe checked the border-colour
   sampling the game needed.
6. Gameplay (`7408629`, `e61aa10`, `ba9e9b8`): singleplayer world entry, a
   character, traversal, inventory and crafting. Graphics settings opened after
   the display adapter was added. Items persisted across relaunch.

## Problems and bugs

| Symptom | How it was found | Root cause | Fix | Commit |
|---|---|---|---|---|
| Image rejected at 64 MiB | First loader run on the real file | Default host size limit. | Per-host policy: 128 MiB opt-in, 512 MiB ceiling. | `9df8ec4` |
| TLS descriptors rejected (45 in the binary, plus `_tlv_bootstrap` and `_tlv_atexit`) | Loader log | No TLS support in the loader. | TLS runtime with thunk, per-thread storage and destructor ordering. Tested with 288 workers and 12 load and unload cycles under sanitizers. | `9df8ec4` |
| Non-empty legacy weak-bind stream rejected | Loader log | Weak definitions were not handled. | Weak definition lookup in the guest, then declared host libraries. Not general dylib coalescing. | `9df8ec4` |
| 8,192-rebase limit exceeded (146,786 needed) | Loader log | Default fixup bound. | Explicit opt-in bound of 1,048,576 per kind. | `9df8ec4` |
| Rebase with high-byte tag `0x80000001033d94ee` | Loader validation | Legacy tagged pointers. | Preserve the tag while rebasing the address. | `9df8ec4` |
| Bind opcode 0x60 with signed addends | Loader decoding | Addends are signed SLEB128. | Bounded SLEB128 decoding with overflow rejection. | `9df8ec4` |
| Rust startup got no argv | Guest log | `_NSGetArgc` and `_NSGetArgv` need host arguments. | Optional guest arguments supplied at entry. `--help` then worked. | `9df8ec4` |
| `invalid resident guest range` on iOS | First iOS attempt | `__DATA` zero-fill tail beyond the file. | Signed RW capacity; BSS zeroed at load. | `171944f` |
| `NSAppKitVersionNumber`, `NSAppearanceNameAqua` missing | Data import failure | Not in the iOS SDK. | Constants measured on the Mac. | `171944f` |
| 38 unresolved desktop functions | Import report | No iOS equivalents. | Abort-on-use stubs for the lazy imports only. Eager data imports still must resolve. | `171944f` |
| Userdata write permission denied beside the executable | Guest log at first normal run | The default userdata location beside the executable is not writable on iOS. | Launch environment `VELOREN_USERDATA` to Documents. Launch configuration, not a game change. | `171944f` |
| Asset directory not found under another name | Guest log | The guest looks for the basename `assets`. | Assets placed under `Documents/assets`. | `171944f` |
| `class NSApplication could not be found` | Guest log | Dynamic class lookup did not know AppKit classes. | Class adapters in dynamic resolution. | `c350519` |
| `NSApplication must have sendEvent:` | Winit method check | Event routing did not go through `sendEvent:`. | Physical and on-screen keys routed through `NSApplication.sendEvent:` before monitors. | `c350519` |
| Border-colour sampler rejected by the device path | Guest error on missing `ADDRESS_MODE_CLAMP_TO_BORDER` | The driver reported no legacy Mac feature set, although the border operation itself worked in a native probe. | Native probe (6 of 6 cases) gates a legacy Mac1 profile (sets 10000 and 10001). Experimental. Later found to cause BC problems in Phase 6. | `c350519` |
| Carbon keyboard imports (TIS, `UCKeyTranslate`, `LMGetKbdType`) | Typing in character creation | Keyboard layout APIs are absent on iOS. | ANSI-US fallback; checked against 1,600 native cases with zero differences. Not all layouts or IME. | `35e2770` |
| Relative cursor request trapped | Pointer test | Pointer lock needs a UIKit-supported route. | Virtual guest cursor and UIKit pointer lock through the public view controller API. | `35e2770` |
| Invisible cursor image failed lookup | Guest log | `NSImage` missing from dynamic lookup. | Existing image shim added to dynamic resolution. | `35e2770` |
| Graphics settings aborted in `CGDisplayGetDisplayIDFromUUID` | Guest log (evidence 86) | Desktop display identity. | Display adapter for the primary display identity and current mode only. No mode switching. | `e61aa10` |
| Audio: no output route; RemoteIO -10851 | Independent iOS RemoteIO probe with no guest loaded | The VM has no usable output route (sample rate 0, zero channels). | **Open.** Diagnosed and recorded. No audio faked. | `7408629` |
| Session ended with the VM locked; no crash report | Observation during a slider change | Unknown. | **Open.** Relaunched. | `ba9e9b8` |
| Process footprint grows about 33 KB per frame (about 1.8 MB/s at 54 fps) | 300 s idle sampling on 7 Oct (`docs/evidence/phase5.5/perf/leak-counters.json`) | Wrapper and presented-handler hypotheses were tested and rejected. Cause is outside them. | **Open.** Next candidates listed in the findings. | (no commit) |
| Repeated cursor association requests rewrote the report each frame | Sampling overhead | Report code ran per frame. | Returns early when unchanged. | (no commit recorded) |

Commit column: the commit whose message or changed files cover the fix. Several
fixes landed in one commit, so the attribution is by theme and is approximate.

## Results / evidence

Observed in the VM (findings, evidence `66` to `95`):

- Title screen, singleplayer world selection, world generation, and 3D character
  creation.
- Movement from the village into forest terrain, camera rotation, weapon swing,
  lantern use, inventory, consuming cheese, collecting wood and opening the
  crafting UI.
- Item changes persisted across a crash and relaunch. Logout returned to the
  title, and re-entry in the same process resumed rendering. Footprint fell from
  about 2.48 GB to about 0.99 GB around logout.
- Graphics settings opened without an exception. The adapter exposes only the
  current display mode.

Measured, with caveats in the findings: about 202 s of mixed traversal produced
5,157 completed presentation-requesting GPU buffers and no GPU completion errors.
This is not display FPS, because drawable `presentedTime` is zero in this VM.
Footprint ranged from 2.29 to 2.47 GB. Later sessions reached 2.57 GB peak.

Regression evidence: Strataris was reinstalled after the shared event-path
change. A physical Return key reached its `keyDown:`, and the run recorded 506
draw callbacks in 8.84 s. The report calls this a regression check, not a
benchmark.

Tests (report): Phase 1 inspector 30, Phase 1 loader 8, Phase 2 sanitizer 10,
Phase 3 8, Phase 4 8, Phase 4.5 6, Phase 5 2 and Phase 5.5 loader, TLS and
keyboard 4 all passed. The iOS UIKit probe passed 32 checks, the iOS input and
cursor probe passed 24 checks, and the native border probe passed 6 of 6 cases.

Not established: working audio, controller input, ordinary development signing
(zero valid identities on the Mac), the sustained memory ceiling, the VM's
unlimited jetsam allowance versus a real phone, and performance on a physical
iPhone.

## What it unlocked next

- Phase 6 started from the loader scale work (guest images and fixup budgets).
  Its multi-image guest groups were needed because SuperTuxKart links 19 images.
- The legacy Metal profile added here was later identified as the cause of a
  wrong BC texture path in SuperTuxKart. Phase 6 disabled it for that game.
- The report's gap table names what was still missing for a larger game:
  general multi-image dyld behaviour, exceptions and unwinding, real shader and
  pipeline workloads, streaming, audio, controller input and normal signing.
  Phase 6 and later phases tackled several of these in turn.
- The memory-growth finding was carried forward. Later phases (Cyberpunk in
  Phase 8) report memory and heat telemetry again.
