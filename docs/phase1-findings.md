# Phase 1 findings

Investigation date: 1 October 2026 (Asia/Nicosia). These findings concern the four controlled macOS samples, not any game. No macOS executable was run on iOS.

## Evidence and interpretation

- **Verified** means observed locally in the recorded environment or checked by automated tests.
- **Documented** means supported by installed Apple headers or a linked primary source; it is not an iOS execution result.
- **Hypothesis** means a proposed compatibility implication requiring an experiment.
- **Untested** means no evidence yet establishes the behavior.

[evidence/baseline.json](evidence/baseline.json) records binary SHA-256 hashes, commands, stdout, stderr, exit codes, Apple-tool reference output, and our JSON reports. [evidence/research.json](evidence/research.json) records header versions/hashes, ABI macros, Objective-C selectors/disassembly, entitlement inspection, and a separate modern-linker experiment. [evidence/validation.json](evidence/validation.json) records the automated verification run. Synthetic fixtures are parser tests, not evidence that an operating system accepts those files.

## What each unmodified executable asks for

**Verified:** all four baseline files are thin ARM64 `MH_EXECUTE` images, CPU subtype 0, with `LC_BUILD_VERSION` platform 1 (macOS), minimum OS 11.0, SDK 27.0, `LC_LOAD_DYLINKER` `/usr/lib/dyld`, `LC_MAIN`, UUID, and `LC_CODE_SIGNATURE`. None has an `LC_RPATH` or encryption command. Each uses `LC_DYLD_INFO_ONLY`, `LC_SYMTAB`, and legacy dyld export-trie data. Each exports `_main` and `__mh_execute_header` in the trie.

| Sample | Verified runtime and direct dependencies | Additional obstacles for these exact bytes on iOS |
|---|---|---|
| `hello` | Prints `Hello from macOS ARM64`; loads `/usr/lib/libSystem.B.dylib`; undefined `_puts` and `dyld_stub_binder` | Platform and signing admission, dyld initialization/binding, C runtime, and a destination for stdout. A shared ISA does not supply these services. |
| `file_io` | Creates, writes, rereads and deletes a temporary file; loads libSystem; imports stdio, `mkstemp`, `unlink`, `___stderrp`, stack-protector and checked-formatting helpers | The runtime must preserve libc semantics, globals, errno/error handling and a writable path inside the allowed container. The sample accepts its directory as an argument; it does not require arbitrary disk access. |
| `framework` | Reports CoreFoundation string length 11; loads CoreFoundation and libSystem; imports `CFStringCreateWithCString`, `CFStringGetLength`, `CFRelease`, and `printf` | Resolve the macOS framework install name and compatible function/data ABI. Similar source APIs alone do not prove the iOS framework satisfies the binary's contract. |
| `metal_info` | Creates the Apple M2 device; reports registry ID 4294968552 and unified memory `yes`; loads Foundation, Metal, libobjc and libSystem | In addition to admission/linking: Objective-C object and selector registration, ownership/runtime helpers, framework behavior, and GPU feature support. No rendering, shaders, presentation, or game workload was tested. |

The obstacle column is a **hypothesis/checklist**, not an observed iOS failure trace. Shared admission restrictions below apply to every sample. Registry IDs are host observations, not stable identifiers for tests.

## Mach-O metadata and load commands

**Verified:** Apple `file`, `lipo`, `otool`, `vtool`, `nm`, and `codesign` agree with the tested parsed fields. Minimum deployment OS and SDK are different values: explicitly choosing macOS 11.0 does not mean the compiler used the macOS 11 SDK.

**Documented in the installed `mach-o/loader.h`:** modern builds describe the target with `LC_BUILD_VERSION`; macOS, iOS, Mac Catalyst and iOS Simulator have distinct platform IDs (1, 2, 6, 7). Legacy `LC_VERSION_MIN_MACOSX` and `LC_VERSION_MIN_IPHONEOS` also differ. Segment, symbol, UUID, entry and signing structures belong to the shared Mach-O format; it is incorrect to treat every macOS command as inherently absent on iOS.

**Verified separate experiment:** compiling `hello.c` for macOS 13.0 with `-Wl,-fixup_chains` produces `LC_DYLD_CHAINED_FIXUPS` and `LC_DYLD_EXPORTS_TRIE`. That variant runs on this Mac, and our inspector finds its exports/imported symbols. It is stored under `build/variants`, leaving the macOS 11 baselines unchanged. Thus a parser limited to the four baseline command layouts would miss a relevant modern case.

**Untested:** the exact kernel/dyld failure stage for any baseline on an iOS release. Editing a platform field is not an established solution and would also change signed bytes. No platform fields were patched in baseline executables.

## Dylib paths, dyld and entry points

**Verified:** framework install names include macOS version directories:

```text
/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation
/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
/System/Library/Frameworks/Metal.framework/Versions/A/Metal
/usr/lib/libobjc.A.dylib
/usr/lib/libSystem.B.dylib
```

The selected paths are confirmed by `otool -L`. The system images above are cache-only boundaries in our reports: ordinary files are unavailable, while the SDK-declared `_dyld_shared_cache_contains_path` API confirms membership in the **host** dyld cache. Missing a filesystem file therefore does not imply a missing runtime library. Apple's [dyld cache layout notes](https://github.com/apple-oss-distributions/dyld/blob/main/doc/CacheLayout.md) provide background; they do not identify this host's exact dyld source revision.

**Verified:** an additional native executable → dylib A → dylib B fixture runs and returns 42. Its `@executable_path`, `@loader_path`, and `@rpath` dependencies resolve to the local files expected by our graph. Synthetic tests cover cycles, inherited search paths, search order, and different loading contexts.

**Limits:** this is static analysis of declared dependencies, not a dyld implementation. It omits runtime `dlopen`, environment overrides, fallback search policy, cache internals, symbol interposition and complete platform admission. A graph marked incomplete can still describe a runnable program. Host-cache membership says nothing about an iOS cache. SDK `.tbd` files are link-time stubs, not runtime dylibs.

**Verified:** `LC_MAIN.entryoff` maps into each executable's file-backed `__TEXT` segment and matches `otool`. The derived address is unslid. ASLR, rebasing, binding and initialization occur before normal application code; jumping to that number is not a demonstrated loading strategy. Binding/fixup command ranges are reported, but their full contents are not decoded.

## ABI and Objective-C

**Verified:** the selected compiler reports little-endian ARM64, 8-byte pointers, 8-byte `long`, and 8-byte `long double`. All samples use ordinary arm64, not arm64e. These facts are for this macOS compiler target only.

**Documented:** Apple's [ARM64 ABI guidance](https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms) is the reference for calling convention requirements. **Untested:** cross-platform calls involving variadics, structures, TLS, exceptions/unwinding, runtime globals, and arm64e pointer authentication. An instruction-set match does not establish those contracts or compatibility of operating-system services. These samples call public libraries; they do not establish a direct syscall ABI bridge.

**Verified:** the Metal program imports `_objc_msgSend`, autorelease-pool functions, release/retain helpers and `_objc_storeStrong`. `otool` shows `UTF8String`, `name`, `registryID`, and `hasUnifiedMemory` selector strings. The C CoreFoundation sample introduces framework functions without adding direct Objective-C runtime calls to its own symbol table; this does not imply CoreFoundation has no internal Objective-C dependencies.

**Hypothesis:** forwarding only Metal C entry points will be insufficient once returned objects receive Objective-C messages. Class/selector registration, runtime ownership conventions and framework method behavior need controlled tests. No private Objective-C layouts or runtime metadata rewriting were implemented.

## Signing, sandbox and executable loading

**Verified:** Apple `codesign --verify --strict` succeeds for all four baseline executables. Signature details show ad-hoc, linker-signed signatures and no TeamIdentifier. Entitlement inspection emits no entitlement payload. This demonstrates local integrity verification, not distribution approval or iOS authorization.

**Documented:** Apple's [iOS app code-signing description](https://support.apple.com/guide/security/app-code-signing-process-sec7c917bf14/web) describes certificate-based executable authorization and launch-time validation of linked libraries. Our macOS ad-hoc signatures do not establish eligibility for those paths. Re-signing would modify the binary; preserve that distinction when saying “unmodified.”

**Documented:** Apple's [runtime security description](https://support.apple.com/guide/security/security-of-runtime-process-sec15bfe098e/web) describes mandatory app sandboxing, containers, entitlements, ASLR and restricted executable memory on iOS/iPadOS. A shell-launched macOS file-I/O test is not an iOS sandbox test. Reading instructions into an ordinary buffer does not itself make them authorized executable code.

**Hypothesis:** executable admission and initialization may be a feasibility gate before API mapping. There is no result here showing that an ordinary iOS host app may load these signed macOS images as executable code. Code signatures, app packaging/lifecycle and executable-memory policy need separate experiments using supported development mechanisms. No SIP, Gatekeeper, AMFI or other security setting was disabled.

## Metal: concrete overlap and difference

**Documented in the installed Metal header:** `MTLCreateSystemDefaultDevice` is available on macOS and iOS; `registryID` and `hasUnifiedMemory` have availability on both. Conversely, `isLowPower` and `isRemovable` are marked unavailable on iOS in this SDK and deprecated for macOS 27 as inapplicable to Apple Silicon. The sample deliberately uses only the first group. Header hashes and exact declarations are captured in research evidence.

**Verified:** device creation and property queries work on this Mac. **Untested:** iOS behavior, shader/library compatibility, command encoding, resource/storage modes, synchronization, feature families, memory limits and presentation. API-name overlap and a common GPU vendor do not establish all of these. Creating a device is intentionally a small observation.

## Boundary of the evidence

The active toolchain is Command Line Tools, macOS SDK 27.0, Apple Clang 21; the host reports macOS 27.0 build 26A428. `xcrun --sdk iphoneos --show-sdk-path` fails because no iOS SDK is selected/available. No iPhone, iPad, iOS simulator, vphone-cli, Wine, Rosetta-based emulation, or game binary was used. A Mac Catalyst/UIKit host window was used for the separately requested in-process experiment below; this is not an iOS-device result. The additional tiny iOS-on-Mac app experiment is documented in `experiments/ios-on-mac`; it is not evidence of macOS-to-iOS compatibility.

Primary web references were consulted on 1 October 2026. Apple security pages identify their publication date as 19 December 2024. Installed headers and experiments have stronger version specificity than unpinned online implementation sources; future releases must be rechecked.

## Extra observation: user-requested iOS-to-macOS direction

**Verified:** our minimal IPA has ARM64/iOS platform 2 and no encryption. The normal Xcode route was unavailable; the experiment used explicit UIKit declarations and minimal iOS link stubs with the installed macOS headers, with SDK 0 recorded in the final image. A direct launch returned “incorrect executable format.” A copied, re-signed platform-6 image rendered the UIKit greeting on this Mac. Its `isiOSAppOnMac` result was NO. Both copies have identical `__TEXT,__text` bytes, and the original image hash remained unchanged. See [ios-on-mac evidence](evidence/ios-on-mac.json) and [UI observation](evidence/ui-observation.json).

**Source-verified:** PlayCover’s [conversion implementation at commit 8235158](https://github.com/PlayCover/PlayCover/blob/8235158caca3232dcf526ad6ae9881707bd08728/PlayCover/Utils/Macho.swift#L132) changes build metadata to Mac Catalyst; its installer re-signs binaries. Our experiment uses Apple `vtool` to reproduce that part, not PlayCover itself. Thus this result concerns a modified, Catalyst-classified copy. It demonstrates useful execution of the same instruction bytes on the host’s compatibility infrastructure, but does not establish bidirectional compatibility or unchanged iOS execution. The direct-launch failure does not isolate every admission check involved.

**Known analysis limit exposed by the experiment:** the static dependency command reports the converted app’s `/System/Library/Frameworks/UIKit.framework/UIKit` path as missing even though that app runs. It does not currently model Catalyst’s iOSSupport path handling. This is a concrete example of why its static report is not a dyld acceptance verdict, and a focused future resolver test rather than a claimed complete platform model.

## Additional user-requested experiment: macOS hello inside a UIKit host

This add-on does not change the four-sample Phase 1 snapshot. **Verified on this Mac:** a Mac Catalyst-adapted UIKit host synchronously loaded the repository's original, unchanged ARM64 macOS `build/hello` in the same process. The guest's `_puts` call was bridged into a host buffer, and the inner host-rendered panel displayed the actual text `Hello from macOS ARM64`. No child process was launched; the guest is not an AppKit window and the host is not an iOS-device app.

The initial `EPERM` while mapping executable pages from a freshly copied signed guest was reproduced in the native macOS CLI too, so it did not establish a Catalyst-specific restriction. Registering the existing signature with `F_ADDFILESIGS_RETURN`, checking its covered range, and honoring `F_CHECK_LV` let both hosts run this copy. The loader does not replace signature bytes or alter system security settings. This result is limited to the controlled hello fixture and current host; it does not show arbitrary macOS binaries can be loaded.

The UI contains only the outer “UIKit host” title and inner macOS-style “macOS hello” output panel; it shows actual guest output or a concise loader error. The latest Phase 1 suite passes all 30 tests in normal and sanitizer builds, and the loader suite passes all eight tests in both modes. See [validation](evidence/validation.json), [loader validation](evidence/loader-validation.json), and [UI observation](evidence/inprocess-ui-observation.json). Implementation and limits are in [`experiments/inprocess-hello/README.md`](../experiments/inprocess-hello/README.md).
