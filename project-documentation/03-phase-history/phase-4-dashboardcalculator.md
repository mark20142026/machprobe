# Phase 4: unchanged SwiftUI calculator in the iOS VM (DashboardCalculator)

Dates: 2026-10-01. Commits `0073476` (black-box attempt and measured blockers)
and `aaa8b5f` (the guest's UI and input run in the iOS runtime). Phase sources:
`docs/phase4-report.md`, `docs/phase4-findings.md`, `docs/evidence/phase4/`.

## Goal

Run the official DashboardCalculator macOS ARM64 release (a SwiftUI app) in the
iOS VM, with its original bytes, and make its own buttons and logic work. The
target was treated as closed source. No implementation source was read,
recompiled or replaced, and no calculator UI was recreated or rendered remotely.

## What was built

| Path | Contents |
|---|---|
| `phase4/runtime/Extended.c`, `Extended.h` | Opt-in extended import policy: weak missing imports become null, extra bounded legacy fixup opcodes, and compiled class and Swift metadata registration through host SPIs. |
| `phase4/runtime/ImageShim.m`, `ImageShim.h`, `ImageShim.swift` | Compatibility objects for `NSImage` (wrapping `UIImage`) and `NSSound` (mapped to a system sound). A Swift ABI adapter provides the `Image(nsImage:)` constructor. |
| `phase4/host/RuntimeMain.m`, `build_runtime.py` | Minimal iOS host and packaging. The packaging selects the exact ARM64 slice and embeds it in a separately signed iOS dylib. |
| `phase4/host/Probe.m/.h`, `Main.m`, `CLI.m`, `LoadCLI.m`, `build.py` | Diagnostic hosts and the earlier black-box probe. Kept for the record. |
| `phase4/tools/prepare.py` | Extracts the release, hashes the original files, and records the slice boundaries. |
| `phase4/tools/convert_assets.py`, `export_assets.m` | Reads the original compiled `Assets.car` with macOS resource APIs and writes an iOS asset catalog through Apple's `actool`. |
| `phase4/tools/runtime_vm.py`, `vm.py` | Install, launch and report against the VM. |
| `phase4/tests/test_blackbox.py` | Eight tests: slice exactness, original bundle unchanged, both inputs preserved in the diagnostic IPA, runtime container preserves the original slice, extended metadata load, measured platform gap, recorded loader failure is not reported as success, and asset conversion preserves the source catalog. |

## How it was done

1. Downloaded the author's release, recorded hashes for all eight bundle files,
   and kept the original app under `build/phase4/original/`.
2. Ran a black-box attempt first (`0073476`). It measured the iOS SwiftUI
   blockers without changing the guest.
3. Selected the exact ARM64 byte range of the universal executable, `147456`
   through `267615` inclusive, and embedded that slice unchanged in a signed
   iOS container. The rest of the universal file was not used.
4. Enabled the extended loader policy and fixed each failure in turn (table
   below). Failures were recorded as they happened. No calculator button or
   arithmetic branch was added to the runtime.
5. Ran the original `main` (SwiftUI `App.main`). The guest creates its own view
   tree; the iOS SwiftUI, UIKit and graphics stack renders it.
6. Interacted through the VM and recorded the screen after each step.

## Problems and bugs

| Symptom | How it was found | Root cause | Fix | Commit |
|---|---|---|---|---|
| The universal file header was rejected | Loader error on the full file | The loader accepts thin ARM64 slices only. | Select the exact ARM64 slice range. The original file bytes were not changed. | `aaa8b5f` |
| Compiled Objective-C class metadata was rejected | Loader error on class registration | The default loader policy rejects compiled class metadata. | Opt-in class admission and explicit registration with `objc_readClassPair`, plus Swift protocol, conformance and type-record registration through the platform's runtime hooks. | `aaa8b5f` |
| Extra dylibs, weak loads and legacy fixups failed | Loader errors on the other dylib install names (22 libraries are declared) and on fixup opcodes | Policy and opcode coverage were too narrow for this binary. | Bounded extended import policy. Weak missing imports resolve to null, and strong missing imports still fail. Added `REBASE_ADD_ADDR_ULEB`, dylib ordinal ULEBs and scaled bind increments. | `aaa8b5f` |
| `NSImage`, `NSSound` and Swift overlay exports were missing | Link-time import report | The iOS host lacks the macOS AppKit classes. | Small `NSImage` and `NSSound` compatibility objects. `Image(nsImage:)` implemented as a real Swift-ABI constructor adapter, not a class-pointer alias. | `aaa8b5f` |
| The guest asserted that a required image was absent | Runtime UI failure | The original `Assets.car` is in macOS form. | The converter reads the original compiled assets and writes an iOS catalog. Pixels and names are kept. The executable bytes are unchanged. | `aaa8b5f` |
| The first button press raised a missing `NSNumberFormatter` selector | Input test (first key) | The guest uses the legacy `setHasThousandSeparators:` selector. | Map it to `usesGroupingSeparator` on a subclass. | `aaa8b5f` |

Known open items from the report: a non-empty weak-coalescing stream remains
unsupported. RPATH records are validated, but generic `@rpath` search is not
implemented. Process-lifetime pinning of metadata means one guest per process.

## Results / evidence

- VERIFIED in the iOS VM (firmware 24A435, iOS 27): the unchanged guest renders
  its SwiftUI interface and performs **2 + 2 = 4** and **7 x 8 = 56**. The
  calculation screens and the interaction record are in
  `docs/evidence/phase4/`.
- The successful run applied 223 rebases and 244 binds. It is recorded in
  `docs/evidence/phase4/runtime-success.json`.
- Final regression: 64 test methods pass in total (30 Phase 1, 8 original
  loader, 10 Phase 2, 8 Phase 3 and 8 Phase 4). Phase 2 tests also pass under
  ASan/UBSan.
- A fresh VM run of all eight controlled guests (hello, interactive, file I/O,
  CoreFoundation, Foundation, Metal device, Metal compute and AppKit GUI) passed
  with the final shared runtime (`docs/evidence/phase4/final-controlled-ios-regression.json`).
- The UI interaction was observed by a person and recorded, not checked by an
  automated accessibility assertion.

Not verified: ordinary (non-VM) iOS signing, the sandbox without the VM's
custom-trust entitlement, a physical iPhone, pointer and keyboard input, all
memory and decimal operations, window management, and general AppKit coverage.
The installed app carries the installer's `jb.pmap_cs_custom_trust` entitlement.

## What it unlocked next

- A working path from an unchanged, Swift-based, third-party application to a
  visible and interactive result in the VM. Earlier results used the project's
  own controlled guests.
- Reusable adapters for NSImage and NSSound, the extended loader policy, and
  the metadata registration. Phases 5 and 5.5 used these directly.
- Objective-C and Swift metadata registration on the loader, which later phases
  reused for other binaries.
- The report says Phase 4 stopped at the user's request, and no Phase 4.5 work
  had begun. Ordinary signing stayed open. The next recorded commit (`fd1ccdc`)
  is Phase 4.5, a native Metal test. Phase 5 followed it.
