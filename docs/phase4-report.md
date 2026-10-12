# Phase 4 report

1 October 2026 — **functional milestone achieved in the iOS research VM**.

The official DashboardCalculator macOS ARM64 executable renders its own SwiftUI
interface through machprobe and correctly performs **2 + 2 = 4** and **7 × 8 = 56**.
The target was treated as closed source: no implementation source was read,
changed or compiled; no calculator UI or logic was recreated or remotely rendered.

The normal-signing/sandbox independence requirement remains **unverified** because
vphone's installer adds private trust/container entitlements. This is an actual
iOS VM execution result, not proof of ordinary-device deployment. Phase 4 stops
here at the user's request; no Phase 4.5 work has begun.

## Target and integrity

Official release: **v2.0-2203A1347**, version 2.0, published 20 January 2022.
[Author download](https://github.com/elunico/DashboardCalculator/releases/download/v2.0-2203A1347/DashboardCalculator.app.zip).
The preserved universal executable includes x86_64 and ARM64. Its ARM64 slice is
macOS MH_EXECUTE, minimum macOS 11.0, SDK 12.1, with original Developer ID signature
and a validated notarization ticket on the app.

Original app and ZIP remain in `build/phase4/original/`. All eight files retain their
recorded hashes. Selected ARM64 SHA-256:
`87986a2aaa6a000c6d72ad0ea46ae67683d7ce8d724a79e2ed1655077065299b`.
The same bytes are preserved inside a separately signed iOS container and verified
by the runtime before relocations. The target was not re-signed. The original
asset catalog was converted into an iOS catalog; **the package resources were
adapted, while executable bytes and original preserved resources were unchanged**.

## Implementation

| Area | Added behavior |
|---|---|
| Loader | Opt-in weak imports, extended library policy, additional bounded legacy fixups, section access and process-lifetime pinning |
| Swift/Objective-C | Compiled class and Swift metadata registration using host runtime SPIs |
| SwiftUI | Forward common imports; native Swift ABI adapter for Image(nsImage:) |
| AppKit gaps | Small NSImage and NSSound compatibility objects |
| Foundation gap | Legacy NSNumberFormatter thousand-separator selector adapter |
| Resources | Generic original asset extraction/catalog conversion and original font registration |
| Lifecycle | Original guest SwiftUI App.main owns iOS application startup |
| Input/display | iOS SwiftUI gestures invoke guest closures/state, which redraw through host SwiftUI |

`runtime/` holds the shared loader. `phase4/runtime/` contains the opt-in policy,
metadata integration and adapters. `phase4/host/RuntimeMain.m` is the minimal host;
`build_runtime.py` packages the unchanged slice. `phase4/tools/` contains preparation,
resource conversion and VM control. `phase4/tests/` contains integrity, metadata-load
and evidence checks. Early diagnostic hosts and failure records remain available.

The first concrete failure was compiled class registration. Later failures exposed
missing imports, unavailable image assets, and a legacy formatter selector. Each
was addressed in runtime or generic packaging code. The guest UI and arithmetic
were never changed. Full chronology, architecture diagram, dependencies and
labeled limitations: [phase4-findings.md](phase4-findings.md).

## Verified results

| Requirement | Result |
|---|---|
| Official native ARM64 guest, original bytes | VERIFIED |
| Loads / entry / SwiftUI lifecycle | VERIFIED in iOS VM |
| Original recognizable UI and buttons | VERIFIED |
| Input invokes original application logic | VERIFIED |
| Calculations and redraw | VERIFIED: 4 and 56 |
| Source rebuild, manual UI replacement, remote rendering | None |
| Ordinary iOS signing / VM-independent sandbox guarantees | UNTESTED |
| Physical iPhone, general SwiftUI/AppKit coverage | UNTESTED |

The successful observed calculator run is PID 768, run
`BCBFFC6A-580F-49A4-AEFC-0B7748AF7D82`. It applied 223 rebases and 244 binds.
[Runtime evidence](evidence/phase4/runtime-success.json),
[interaction record](evidence/phase4/interactions.json),
[screen showing 4](evidence/phase4/calculation-2-plus-2.jpg),
[package hashes](evidence/phase4/runtime-packaging.json).
UI interaction was observed, not an automated accessibility assertion.

**Final regression checks:** 30 Phase 1 + 8 original-loader + 10 Phase 2 +
8 Phase 3 + 8 Phase 4 test methods passed: **64 total**. Phase 2's 10 methods
also passed with ASan/UBSan; the Phase 3 fixup harness runs with both sanitizers
and now covers the new opcodes and weak/strong missing-import behavior.

After rebuilding the controlled iOS host with the final shared runtime, all eight
controlled guests passed a fresh VM run: Hello, interactive input, file I/O,
CoreFoundation, Foundation, Metal device, Metal compute and AppKit GUI.
PID 816, run `B2B748CA-3434-4D97-A072-3CFE9CB26BED`:
[final iOS regression](evidence/phase4/final-controlled-ios-regression.json).
Local test logs are `docs/evidence/phase4/final-*-tests.txt`.

## Reproduce

From `/Users/<user>/machprobe`, with the original author app preserved:

```sh
make all
make -f phase2/Makefile all
python3 phase4/tools/prepare.py
python3 phase4/host/build_runtime.py
python3 phase4/tools/runtime_vm.py install
python3 phase4/tools/runtime_vm.py launch
python3 phase4/tools/runtime_vm.py report
make test test-loader
make -f phase2/Makefile test sanitize
python3 -m unittest discover -s phase3/tests -v
python3 -m unittest discover -s phase4/tests -v
```

The existing `iphone` VM must be running. Build scripts select the installed full
Xcode per command; no simulator installation is needed. The result is
`build/phase4-runtime/MacGuest.ipa`, also copied to the VM's
`/private/var/mobile/ipas/MacGuest.ipa`. Historical diagnostic-package tests also
require `python3 phase4/host/build.py` if starting with no previous build outputs.
Phase 3 package checks require `python3 phase3/host/build.py`.

Remaining limitations include process-lifetime metadata, runtime SPI dependence,
nonempty weak-coalescing streams, broader AppKit/window semantics, untested input
modes and ordinary-device admission. Sound equivalence and every calculator
operation were not exhaustively tested. No new game or next-phase test was started.
