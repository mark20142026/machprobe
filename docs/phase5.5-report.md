# Phase 5.5 report — in progress

Phase 5.5 is not complete. Initial real gameplay now works in the iOS research installation; audio, stress testing and ordinary signing remain incomplete.
See [findings](phase5.5-findings.md) and numbered evidence in `evidence/phase5.5/`.

## Build and verification

```
make -f phase5_5/Makefile test
build/phase5.5/load-cli build/phase5.5/original/extracted/veloren-voxygen --run --help
python3 phase5_5/tools/build.py
```

`phase5_5/host/LoadCLI.m` is a macOS loader harness; it is not an iOS result.
`phase5_5/host/Main.m` and `tools/build.py` prepare the actual iOS research host.
`phase5_5/guests/` contains only our synthetic regression fixture, never rebuilt
third-party game code. Original Veloren bytes remain in the signed iOS container.

VERIFIED: existing Phase 1–5 suites pass after the loader changes, including
Phase 2 sanitizer integration and Phase 3 fixup parser sanitizer tests.
Focused TLS tests pass with 288 workers and 12 unloads.
Evidence: `regressions-after-loader.txt`, `loader-tests.txt`.

## Current result

VERIFIED in the existing iOS 27 vphone research installation: the unchanged
official executable loads its assets, renders menus, generates/loads a world,
creates and reloads a character, and enters actual gameplay. Movement reaches
forest terrain beyond the village; camera rotation, weapon animation, lantern,
inventory, consuming cheese, collecting wood and opening crafting UI work.
The gameplay/state changes belong to the original game executable.

The new generic secondary-click adapter passes an iOS responder test and works
in the actual inventory. On-screen keys can be hidden; physical keys remain
available. Initial world sessions lasted several minutes across multiple
relaunches. Evidence 66–85 records observations and memory/GPU samples.

The Graphics settings display-mode query failure is fixed and the actual panel
now opens (evidence 89). The adapter exposes only the current UIKit display
mode; it does not implement arbitrary desktop resolution changes. Collected
wood and the consumed-item state survived a crash/relaunch (evidence 90).
Same-process logout/re-entry also works, with footprint dropping about
2.48 → 0.99 GB at the title screen. A later session ended with the VM locked
and no fresh app crash report; the cause is unresolved (evidence 91–94).
This report is not a completed phase claim.

**Audio remains blocked:** an independent iOS RemoteIO probe, with no guest
loaded, reports no route, zero sample rate/channels, and initialization error
-10851. The desktop HAL/audio compatibility work must still be completed and
verified once the VM supplies usable output. Audio is not being faked.

**Ordinary signing remains unverified:** this Mac still has zero valid signing
identities. vphone's custom-trust installation and effectively unlimited jetsam
allowance are research dependencies. Process uid 501 alone does not prove normal
sandbox/signing independence.

The experimental legacy Metal feature profile is not full Mac feature-set
conformance. No source, shaders or original assets have been altered. Caffeinate
remains active as requested; no security setting or VM firmware was changed.

## Measurements and tests

VERIFIED: Phase 1 inspector 30 + Hello loader 8 tests, Phase 2 sanitizer
integration 10, Phase 3 package/fixup 8, Phase 4 binary/metadata 8, Phase 4.5
package/GPU 6, Phase 5 integrity/GPU 2, and Phase 5.5 loader/TLS/keyboard 4 pass.
The expanded iOS UIKit/display/input probe passes 32 checks (evidence 87).
Historical-evidence/package assertions are not presented as fresh execution of
all earlier games on iOS. Strataris was not launched during this continuation.

A 20-snapshot mixed traversal/UI interval completed 5,157 presentation-requesting
GPU buffers over 201.98 seconds, with no completion errors. The 25.53/s rate is
not display FPS; drawable presentedTime is zero in this VM. Footprint ranged
2.292–2.466 GB. These observations do not establish physical-iPhone performance
or a leak-free memory ceiling. The per-frame cursor-association report rewrite
was removed; the regular two-second sampler remains. No controlled speedup
claim is made between different scenes.

## What Veloren exposed that Strataris did not

Image/fixup scaling, TLS, weak definitions, legacy tagged pointers, signed
relocation addends and process argument acquisition. The findings document lists
exact failures and changes.

## What remains between this runtime and Cyberpunk 2077

This is an interim evidence-based audit; Phase 5.5 is not yet complete and no
Cyberpunk executable has been downloaded or inspected.

| Area | Verified surface | Remaining gap |
| --- | --- | --- |
| Loading | Large ARM64 executable, legacy/earlier chained fixups, signed embedded container, BSS gaps | General multi-image dyld behavior, arbitrary executable code generation, broader chained/PAC formats |
| Threads | Real Rust worker workload; synthetic TLS isolation/destructor/unload tests | Comprehensive unwind/exception registration, general guest unload while callbacks or threads remain |
| Graphics | Actual wgpu/Metal world rendering, original shaders/assets, tested border sampling | Full legacy Mac feature conformance, feature combinations not exercised by this target, physical-device GPU validation |
| Memory | Measured process footprint/residency during traversal | Attribution of guest/driver/runtime allocations, ordinary jetsam limits and pressure recovery, long-term growth |
| Input/lifecycle | UIKit-to-winit keyboard/pointer, secondary click, menus, world entry/relaunch | Controllers, international layouts/IME, robust background/resume and more general window behavior |
| Audio | Independent iOS failure isolated from game; desktop HAL boundary identified | Usable VM output route, actual guest audio, concurrent audio stress |
| Assets/files | Original asset tree, world traversal, writable userdata/configuration | Broader streaming workloads, case-sensitive/path assumptions in other applications |
| Security | Hash-verified guest, user-process research execution | Ordinary development signature/provisioning and independence from custom trust/private entitlement |

HYPOTHESIS: a substantially larger Mac game may exercise any of these untested
areas. Veloren results establish no guarantee about another game's APIs or
performance. No additional intermediate phase or game has been introduced.
