# Phase 3 handoff — prepared, not started

Historical Phase 2 handoff. For the subsequent Xcode installation and actual
iOS VM admission experiment, see [current findings](phase3-ios-admission.md).
The proposed jailbroken configuration below was not the configuration later
observed; the VM reported no detected jailbreak bootstrap.

The user's chosen next environment is **vphone-cli with patched/jailbroken iOS 27 and a debugger**. Phase 2 does not install it, create a VM, modify security policy, jailbreak anything, or test any third-party IPA. The user plans to arrange the host environment separately. See [vphone research](phase2-vphone-research.md) for pinned upstream sources and the distinction between reported support and our measurements.

## Which environment answers which question?

| Environment | Mapping/signing/platform admission | Libraries/Objective-C | Metal | Status |
|---|---|---|---|---|
| Current Catalyst host | macOS policy only | Mac/Catalyst implementations | Mac driver/GPU | VERIFIED |
| Official ARM64 Simulator | Simulator platform and macOS kernel behavior; not stock-device authorization | Simulator frameworks/runtime | Simulator feature profile on Mac hardware | SDK absent; UNTESTED |
| Official signed iOS development app on hardware | Best supported test of real device admission, entitlements and memory policy | Actual device frameworks/runtime | Actual device GPU | SDK, signing and device absent; UNTESTED |
| vphone-cli iOS 27 research VM | Real guest OS behavior **under recorded patches**, not stock security guarantees | iOS guest userland with hybrid firmware/runtime integration | Paravirtual GPU/compiler route, not physical-iPhone equivalence | User-selected Phase 3 route; UNTESTED locally |

Simulator is an optional SDK/UI smoke test, not a replacement for the chosen VM experiment. Full Xcode would provide the official SDK/build/debugging path, but it is a large toolchain and was not installed merely for preparation. Device provisioning cannot be inferred from its availability.

## Prepared artifacts

`phase2/ios/Phase2Host.xcodeproj` and its shared scheme build the existing UIKit host plus runtime against real SDK interfaces when available. Guest resources are copied without CodeSignOnCopy. `phase2/ios/scripts/preflight.sh` is read-only and currently reports missing Xcode/SDKs. Project/plist syntax and scheme XML were checked; actual project compilation/execution is UNTESTED. Follow [the iOS project README](../phase2/ios/README.md) when the SDK exists.

The already-built `build/phase2-ui/HelloIOS.ipa` is an experimental minimal-declaration, ad-hoc iOS-platform package, **not** a validated official-SDK/device-signed build. `HelloIOS-Catalyst.app` is its separately modified host copy and must not be submitted as an iOS result. The original seven macOS guest files remain unchanged. Record hashes before and after copying/signing the host; a packaging tool may treat nested executable resources differently.

## First execution sequence

1. Identify the installed vphone version/commit and consult its own help. Record iPhone and PCC firmware builds/hashes, actual guest OS/kernel, resolved patch manifest, debugger version, host policy as found, and GPU driver/compiler versions. The upstream iOS 27 pairing is a candidate, not a substitute for these observations. Do not infer the configuration from a displayed device name.
2. Build and launch a minimal **iOS-native control app** first through the chosen supported/supplied development route. Verify UIKit, logging, a Metal device query and debugger attach. Record which signing/entitlements the control requires. A successful control is not a macOS-guest result.
3. Package only the unchanged original macOS hello as the first compatibility guest. Verify its platform remains macOS and its SHA-256 matches the Phase 1 baseline. Record host signing separately. Do not silently re-sign or patch the guest.
4. Stop at the first failing stage: file access, signature registration, library validation, RX mapping, rebase/bind, entry, or output callback. Preserve exact return codes/errno and a debugger backtrace. A refusal is a useful result. The runtime must not suppress the check or replace its failure with a success label.
5. Once hello actually executes, verify breakpoints/PC addresses lie in the mapped guest text and trace its `puts` into the host shim. For file-backed signed text, prefer debugger-supported breakpoints that preserve the tested code-signing conditions; record any debugger-induced policy change.
6. Repeat the counter input sequence and ABI cases before trying CoreFoundation/Foundation. Inspect the guest shared cache's actual available libraries/helpers, class identity and selectors; do not carry Catalyst path assumptions over silently.
7. Run Metal device then compute, verifying all 16 results in the host. Separate shader compilation, command completion and data correctness from merely finding a device. Report paravirtual-driver behavior explicitly.
8. Only after these controls pass consider additional small, authorized, unencrypted test IPAs. No Cyberpunk, Steam or unrelated compatibility stack is part of this handoff.

Use the compatibility matrix in `phase2-findings.md` as an empty iOS results template. Each observation needs the actual environment label: **Catalyst**, **Simulator**, **patched iOS VM**, or **stock signed device**. Success in one must never populate another's column.

## Blockers that remain real

No full iOS SDK, official device-signing configuration, running VM or debugger session was available for Phase 2. The SDK visibility/availability of the signature-registration interfaces must itself be checked in the real build; their presence in macOS headers is insufficient. If compilation or policy blocks this architecture, record the restriction before redesigning it. The current loader also deliberately rejects guest TLS, custom Objective-C classes/categories, chained fixups and unknown imports. These are runtime limitations regardless of which environment is used.
