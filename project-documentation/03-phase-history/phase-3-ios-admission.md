# Phase 3: first iOS VM run and the admission gate

Dates: 2026-10-01. Commits `345af7f` (admission host and blocker record) and
`989e3d9` (guests running inside signed containers, verified evidence). Phase
sources: `docs/phase3-ios-admission.md`, `docs/phase3-preparation.md` (the
pre-phase handoff), `docs/evidence/phase3/`.

## Goal

Run the unchanged Phase 2 macOS guests inside the iOS 27 research VM. The phase
was meant to answer one question first: can an unmodified macOS Mach-O image be
admitted and mapped on iOS at all? Only after that could framework forwarding,
the CPU ABI, Metal and input be tested on iOS.

## What was built

| Path | Contents |
|---|---|
| `phase3/host/` | Official-SDK UIKit host. `Main.m` (scene-based app, staged probe writer), `build.py` (packaging; embeds the original guests as base64 resources), `signature_probe.m/.h` (`fcntl` signature-registration probe), `Audit.m/.h`, `AppKitBridge.m/.h`, `MetalGuestView.m/.h`. Bundle ID `research.machprobe.Admission`. Output `build/phase3-ios/MachProbe.ipa`. |
| `phase3/guests/appkit_gui.m` | A macOS AppKit guest used for the GUI check. |
| `phase3/tests/` | `test_package.py` (IPA contents, hashes, embedded signatures, scene manifest, saved-evidence consistency) and `test_fixups.py` with `fixups.c` (fixup parser under sanitizers). |
| `phase3/tools/vm.py` | Installs and launches the IPA through the vphone host API, and reads back `Documents/probe.json`. |
| `runtime/image.c`, `runtime/fixups.c` | Changed for the signed-container path and for new fixup cases. |

Environment as recorded in the phase document: Xcode 27.0 (build 27A266a) and
iPhoneOS 27.0 SDK, selected per build with `DEVELOPER_DIR`. The VM `iphone` ran
iOS 27.0, firmware 24A435, kernel 25.4.0, four CPUs and about 4 GiB RAM, under
vphone Launchpad/Bundle 2.2.5. The VM's `device.info` reported no jailbreak
layout ("not detected"), and the user reported the VM as not jailbroken. Zero
valid code-signing identities were present on the Mac.

## How it was done

1. Built a UIKit host with the real iPhoneOS SDK (`345af7f`). The first build,
   without a scene lifecycle, never reached the foreground. Adding a
   `SceneDelegate` and a scene manifest fixed it.
2. Embedded the original guests as base64 resources. This keeps the installer's
   recursive executable signing from touching the guests. The host records the
   original SHA-256 hashes, writes each guest into its own Documents directory,
   and verifies the bytes before and after writing.
3. Made the host write `Documents/probe.json` before each load and entry stage,
   so each failure is recorded with its numeric errno.
4. Ran the admission matrix: installed host, a byte-identical Documents copy,
   a recompiled iOS hello control (ad hoc signed), and every unchanged macOS
   guest.
5. Compared the installed `interactive` guest with its local copy using
   `codesign` and the Phase 1 inspector.
6. Re-packaged the guests inside a separately signed iOS container (a dylib with
   `__TEXT,__guest` and `__DATA,__guest` sections) and ran the verified run
   (`989e3d9`).

## Problems and bugs

| Symptom | How it was found | Root cause | Fix | Commit |
|---|---|---|---|---|
| Every unchanged macOS guest failed at `fcntl(F_ADDFILESIGS_RETURN)` with `EBADEXEC` (errno 85) before any entry point ran | `probe.json` written per stage by the host | Exact branch unknown. The VM kernel's signature validation rejected the file. Source inspection of the public XNU code does not identify which branch this VM used. | Standalone guests were not fixed. Guests were moved into a separately signed iOS container, which passed registration (`989e3d9`). | `345af7f`, `989e3d9` |
| The installed host registered successfully, but a byte-identical copy in Documents failed | Admission matrix: the same bytes, different location and install state | Hypothesis: installation sets trust state for the installed file that an in-app copy does not get. Not proven. | Shipping guests inside a signed container avoids depending on that state. | `345af7f` |
| The installed `interactive` guest was not the same file that was packaged: `LC_CODE_SIGNATURE` grew from 536 to 1,152 bytes at offset 51,408 | Local versus installed comparison with `codesign --verify` and the inspector | The VM installer re-signs executables inside the app bundle. The unchanged copies also fail registration, so this explains only part of the failure. | Guests are embedded as base64 resources, so the installer does not sign them. The host checks hashes around each write. | `345af7f` |
| The host UI stayed on "Running framework checks..." after an early return | Visual check of the app | The UI did not show the real per-guest result. | UI now records each guest's real failure and its errno. | `345af7f` |
| A recompiled iOS hello control also failed registration | Admission matrix control row | Platform metadata alone did not explain the failure. | Recorded. It shows the problem is not specific to macOS platform fields. | `345af7f` |

## Results / evidence

Admission matrix at the end of the first step (`docs/phase3-ios-admission.md`):

| File | Signature registration | Guest execution |
|---|---|---|
| Installed UIKit host | Pass | Native host already running |
| Byte-identical Documents copy of host | errno 85 | Not attempted |
| iOS hello control (ad hoc) | errno 85 | Not attempted |
| All seven unchanged macOS guests | errno 85 | Not reached |

Verified run after packaging inside signed iOS containers (`989e3d9`,
`docs/evidence/phase3/verified-run.json`, iOS 27.0): each guest's admission mode
is recorded as "prepackaged guest inside signed iOS dylib", and each embedded
hash matches the original.

| Guest | Recorded result |
|---|---|
| hello | `Hello from macOS ARM64` |
| file I/O | `File I/O round trip OK` |
| CoreFoundation | `CoreFoundation string length: 11` |
| Foundation | weak reference cleared; class `NSString`; length 17 |
| Metal device | `Apple Paravirtual device GPU` |
| Metal compute | 16 values `7,10,...,52`, checksum 472 |
| Interactive | counter 0, sequence 4 |
| AppKit GUI | Recorded in the same file; its check value is not summarised here |

Stress checks in the same run: a duplicate resident guest was refused, a
wrong-size embedded section was rejected, and a truncated file was refused.

Tests: 48 existing normal tests, 5 new package and evidence tests, and 10 Phase
2 sanitizer tests passed (`docs/evidence/phase3/run-metadata.json`). The Phase 4
report counts 8 Phase 3 test methods.

Not established: ordinary development or App Store signing, a debugger
breakpoint on the errno 85 branch, and any stock iOS device behaviour. The
research VM's custom-trust entitlement (`jb.pmap_cs_custom_trust`) is added by
the installer and is recorded as an install-time dependency.

## What it unlocked next

- The signed-container route. Phases 4, 4.5, 5, 5.5 and 6 all package the
  original executable bytes inside a separately signed iOS dylib, with the
  loader mapping them at run time.
- A set of rules for later phases: record hashes before and after packaging,
  never change the guest bytes, and label every result with its environment.
- The next question moved from "can the bytes be admitted" to "what does the
  loader and the adapter layer need so a real application runs". Phase 4 was
  the first real application.
- Ordinary signing stayed open. Phase 4.5 prepared a development-signing script
  that refuses to run without a profile and identity. Phase 7 was the first
  real device signing.
