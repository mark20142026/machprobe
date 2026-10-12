# Phase 2: controlled in-process runtime (Mac and Catalyst only)

Dates: 2026-10-01. Commits `6f6f606`, `e4a8351`, `56d849c`. Phase sources:
`docs/phase2-report.md`, `docs/phase2-findings.md`,
`docs/phase2-vphone-research.md`, `docs/phase3-preparation.md`.

The phase title in the original project is "Phase 2 runtime". The repository
calls this work the "controlled runtime". It was the first runtime that loaded
ARM64 macOS images in-process, rather than as standalone processes. The
measured environment was the Mac itself, through a Catalyst UIKit host. No iOS
result was recorded.

## Goal

Move from inspection to execution. Load unchanged ARM64 macOS `MH_EXECUTE`
images into a host process, map their signed pages, apply fixups, resolve
imports to host frameworks, and call their code through a versioned interface.
Verify the results independently. Do not claim iOS compatibility.

## What was built

| Path | Contents |
|---|---|
| `runtime/` | Shared runtime. `image.c` (admission, mapping, entry and symbol lookup, cleanup), `fixups.c` (legacy rebase and bind opcodes), `services.c` (explicit host import list, framework path mapping, selector canonicalization, C initializers), `runtime.h`, `guest_abi.h` (versioned C event/callback interface). |
| `phase2/guests/` | Three new macOS-targeted guests: `interactive.c` (guest-owned counter with callbacks), `foundation.m` (Objective-C, ARC, autorelease pools, weak references), `metal_compute.m` (a small Metal compute kernel). |
| `phase2/host/` | `cli.c` and `checks.c` (command-line host), `Main.m` and `UIKitHost.h` (UIKit host with Increment, Decrement and Reset buttons), `build.py` (bundle packaging). |
| `phase2/tests/` | `abi.c` (ABI checks) and `test_runtime.py`. |
| `phase2/capture.py` | Runs every suite and writes only Phase 2 evidence. |
| `phase2/ios/` | A conventional Xcode project prepared for an iOS SDK that was not installed. Preflight script reports the missing SDK. |
| `docs/phase2-vphone-research.md` | Read-only research of the vphone-cli upstream, pinned to a commit. |

The runtime does not implement dyld, Metal, Objective-C or libc. Host Apple
libraries provide those. The runtime's own work is admission, mapping, fixups,
import binding, selector registration and path translation. It explicitly
rejects guest-defined Objective-C classes, guest TLS, chained fixups and
exceptions.

## How it was done

1. Read Phase 1 state and confirmed the 30 inspector and 8 loader tests passed
   before implementation. Recorded the original guest hashes as the baseline
   (`docs/evidence/phase2/baseline.json`).
2. Built the runtime by extending the Phase 1 loader. The Phase 1 source and
   tests were left in place.
3. Added the three new guests as macOS builds. Each was loaded and packaged
   without changing its bytes. Negative-test copies were re-signed separately.
4. Built a UIKit host that sends `MPEvent` values to the guest and displays the
   callback text. Its buttons reach guest-owned state.
5. Ran the same cases in the CLI and in the Catalyst UI. Recorded results in the
   compatibility matrix (`docs/phase2-findings.md`).
6. Wrote the vphone research note and the Phase 3 handoff, then stopped before
   any VM work.

## Problems and bugs

| Symptom | How it was found | Root cause | Fix | Commit |
|---|---|---|---|---|
| The weak-reference probe required `__objc_personality_v0` | Link result of the Foundation guest | Exception-unwinding support in the guest's compiled code. The runtime does not implement unwinding. | Controlled Objective-C guests are built with exceptions disabled. The personality symbol was not forwarded, because forwarding it would have suggested that unwinding worked. | `e4a8351` |
| Guest Objective-C selector references were not usable as-is | Calls from the Foundation and Metal guests failed or misdispatched | Compiled selector references in the guest's data must be registered with the Objective-C runtime first. | The runtime rewrites those data slots using `sel_registerName` before calls (`services.c`). | `e4a8351` |
| Forwarding only `MTLCreateSystemDefaultDevice` was not enough | Metal device probe: the returned object then needs message sends | Objects returned by Metal are Objective-C objects. Their methods need dispatch and canonical selectors. | Added the host `libobjc` bridge and the selector canonicalization above. Explicit whitelist of compiler helpers (`objc_opt_*`, `objc_alloc_init`). | `e4a8351` |
| Not a defect: the weak-reference lifetime check had to show the reference cleared after its temporary object was released | Foundation guest run, checked in CLI and UIKit | Lifetime behaviour belongs to the host `libobjc`, not the runtime. | No change needed. The guest reports `weak=cleared`. | `56d849c` |

Verification notes: the ABI test found no runtime defect at the 40 load, state,
destroy and unload cycles. It did check RX permissions, unmapping after close,
live image counts and file-descriptor counts.

## Results / evidence

Observed on this Mac, through the runtime, in both the CLI and the Catalyst UI:

| Guest | Result |
|---|---|
| Original hello | Exact greeting through a captured `puts` |
| Interactive | Counter `0 -> 1 -> 2 -> 1 -> 0 -> -1`; contexts independent; invalid inputs rejected |
| Original file I/O | Round trip, file removed; invalid directory fails |
| Original CoreFoundation | Length 11 |
| Foundation | Class lookup, dispatch, ARC, pools, weak-reference clearing |
| Original Metal device | Apple M2, unified memory `yes` |
| Metal compute | All 16 results `7,10,...,52`, checksum 472, checked by guest and host |

Tests: 30 Phase 1 inspector tests, 8 Phase 1 loader tests and 10 Phase 2
integration tests pass, normally and under ASan/UBSan on the runtime and host
harness. The UIKit run recorded a sequence `0 -> 1 -> 0 -> -1 -> 0` through
automation. Extra counter changes came from user clicks, recorded as user input.

Limits recorded in the report: no iOS, Simulator or vphone result. Guest-defined
classes and categories, guest TLS, exceptions, modern chained fixups and async
guest threads are unsupported. Sanitizers do not instrument the guest code or
the Apple frameworks.

## What it unlocked next

- A proven in-process load path, which Phase 3 reused for the iOS guests.
- A labelled compatibility matrix with an empty "iOS" column. Phase 3 and later
  phases filled it, labelled by environment (Catalyst, Simulator, patched iOS
  VM, stock signed device).
- The vphone-cli research and a written Phase 3 handoff. The handoff set the
  order of checks: control app first, then the unchanged macOS hello, then
  stop at the first failing stage (file access, signature registration, library
  validation, RX mapping, fixups, entry, output).
- The user-selected route for Phase 3 was patched iOS 27 in vphone-cli with a
  debugger. The report says that route was not tested locally when Phase 2
  ended.
