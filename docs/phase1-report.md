# Phase 1 report

1 October 2026 · Repository: `/Users/<user>/machprobe`

## Result

Phase 1 produced four working ARM64 macOS test executables, a native C++17 Mach-O/dependency inspector, automated parser and integration tests, and recorded evidence. No macOS executable was run on device iOS, and no game or general compatibility runtime was built. The separately requested narrow UIKit-host loader experiment is described below.

The environment is macOS 27.0 (26A428), Apple M2, Apple Clang 21, and macOS SDK 27.0. Builds explicitly target ordinary ARM64 and macOS 11.0. The installed Command Line Tools are sufficient for these macOS experiments; an iOS SDK is absent.

## What was built

The C and Objective-C samples isolate console output, libc file operations, CoreFoundation and Metal device creation. The inspector parses Mach-O structures itself using Apple headers. It does not invoke `otool` or `nm` internally. Those tools serve as independent references in tests and evidence collection.

`inspect` reports architecture/subtype, file type, platform and OS/SDK versions, every command's identifier/size/offset, dylib load kinds and versions, RPATHs, entry points, UUIDs, segments/sections, signing/encryption command ranges, symbol-table externals and export tries. Unknown commands remain visible. `deps` reports categorized graph edges, resolution candidates and reasons for unresolved or bounded traversal.

| Directory | Purpose |
|---|---|
| `src/`, `include/` | Inspector, bounded binary reads, reporting and dependency traversal |
| `samples/` | Four small baseline programs |
| `tests/` | Real-binary integration tests, synthetic parser fixtures and native dependency fixture sources |
| `scripts/` | Baseline and focused research evidence collection |
| `docs/` | Findings, this report, machine-readable evidence and validation results |
| `build/` | Ignored binaries, modern-target variant and test artifacts |
| `experiments/inprocess-hello/` | Narrow unchanged-hello loader, UIKit guest display and eight focused tests |
| `experiments/ios-on-mac/` | Separately requested tiny IPA and measured iOS-to-Catalyst adaptation experiment |
| `progress.md` | Luna-maintained project status and next actions |

## Reproduce

From the repository:

```sh
make all
make run-samples
make test
make test-sanitize
make evidence
python3 scripts/research.py

build/machprobe inspect build/hello
build/machprobe inspect build/metal_info --json
build/machprobe deps build/metal_info
build/machprobe deps build/metal_info --max-depth 2 --json
```

No dependencies need downloading. Git milestones record the samples, implementation and verification. The local Git installation supplied its existing automatic committer identity; no global Git settings were changed.

`make clean` removes generated build artifacts. Rebuilding can change hashes, UUIDs and signatures, so regenerate evidence after an intentional rebuild. Reports contain schema version 1. A malformed/unsupported root input exits 1; valid inspection or an explicitly incomplete dependency graph exits 0. Empty metadata arrays mean absent information, not a compatibility verdict.

## Sample results

| Program | Actual stdout/result | Direct libraries |
|---|---|---|
| `hello` | `Hello from macOS ARM64` | libSystem |
| `file_io` | `File I/O round trip OK`; temporary file removed; invalid directory fails | libSystem |
| `framework` | `CoreFoundation string length: 11` | CoreFoundation, libSystem |
| `metal_info` | `Metal device: Apple M2`; `Registry ID: 4294968552`; `Unified memory: yes` | Foundation, Metal, libobjc, libSystem |

All four exited successfully, were confirmed ARM64 by Apple tools and passed strict signature verification. Their signatures are ad-hoc/linker-generated, not iOS development signatures. All encode macOS platform 1, minimum 11.0 and SDK 27.0. No RPATH or encryption command is present in these particular samples.

All direct system dependencies in the baseline reports are confirmed host-cache entries without inspectable ordinary dylib files. Recursive traversal is demonstrated independently by the native local executable → dylib A → dylib B chain, which prints `dependency chain: 42`.

The separate macOS 13 variant of hello runs with chained fixups and a modern export-trie command. The baseline files retain their original macOS 11 format.

## Verification and limits

The suite covers 30 test methods, with additional subcases and 40 deterministic malformed-input mutations. It checks exact sample behavior, architecture and build metadata, UUID/entry/dylib/symbol agreement with Apple tools, real modern linkedit commands, FAT/FAT64 selection, legacy version metadata, signatures/encryption fields, trie exports/re-exports, truncation and overflow handling, graph cycles and runpaths, and depth/node limits. Normal and sanitizer results are recorded in [evidence/validation.json](evidence/validation.json).

This is a bounded research parser, not a complete dyld validator or hardened general-purpose binary service. Input size is limited to 512 MiB, export traversal has depth/visit/name limits, and dependency traversal defaults to depth 16 and at most 1,024 nodes. Big-endian/32-bit slices and non-ARM64 execution are unsupported. Binding opcodes, chained-import tables, signature payload validation, decryption and cache extraction are outside the implementation. `LC_SYMTAB` undefined symbols are useful evidence, not a complete list of dynamic runtime lookups.

JSON encodes non-ASCII file-string bytes as U+00XX escapes rather than assuming valid UTF-8. Entry virtual addresses are unslid. Graph categories may overlap. A `cache-only` boundary or missing weak dependency is not by itself proof the program fails to launch. Static path resolution is a documented subset of dyld policy, not a substitute for it.

## Compatibility conclusions

The detailed, claim-labeled analysis is in [phase1-findings.md](phase1-findings.md).

- **Established locally:** architecture identity does not erase platform metadata; even hello has dyld/libSystem dependencies. macOS framework install names and shared-cache resolution are concrete parts of the binary contract.
- **Apparently manageable, still unproven across OSes:** enumerating imports, comparing public API availability, supplying an allowed file directory and validating simple C-call behavior. Source-level similarity is a starting point for testing.
- **Requires early feasibility experiments:** supported executable admission on iOS, signing/entitlements, app lifecycle, relocation/binding, runtime initialization and Objective-C object/method behavior. A Metal device query leaves nearly all graphics workload compatibility untested.
- **Not established:** that a normal iOS app can execute an unchanged macOS image, that rewriting a platform field would suffice, or that shared ARM64/Metal technology implies binary compatibility.

## Recommended Phase 2 experiments — not performed

1. Establish the allowed execution/signing model first. Record whether “unmodified” forbids any re-signing or permits a separate packaging change; preserve original hashes in either case. Stop if the desired model cannot be exercised through supported mechanisms.
2. With an available iOS SDK and an explicitly authorized test environment, compare matched tiny macOS/iOS builds and imports. Keep source-port success separate from executing unchanged macOS bytes.
3. Probe a few ABI boundaries at a time: C arguments/returns, variadics, structs, TLS and error globals; then Objective-C selector dispatch and ARC ownership.
4. Extend dynamic-linking coverage only in response to concrete fixture needs: modern chained imports, re-exports, weak binds and initialization order.
5. Add one minimal Metal buffer/command workload and validate its result before investigating rendering, shader libraries or presentation.

Do not start with a game, GUI, Steam integration or emulation stack. Phase 1 stops at this research environment and evidence map. The user's separate iOS-on-Mac request tests Apple's existing reverse-direction support and cannot establish macOS-to-iOS feasibility.

## Additional experiment requested during Phase 1

The user explicitly requested a tiny iOS IPA and pointed to PlayCover. We built our own iOS-target ARM64 image with a small declared UIKit surface and generated link stubs, without pretending to have a complete iOS SDK. The original has platform 2 and SDK 0 (unspecified), no encrypted content, and an ad-hoc signature. Direct `open` failed with “incorrect executable format.” A copied image was changed to platform 6 using Apple `vtool`, following the platform conversion observed in PlayCover source, and re-signed. It launched and visibly displayed the greeting through UIKit. The original hash was preserved and both images have identical `__TEXT,__text` bytes. Full command evidence and hashes are in [evidence/ios-on-mac.json](evidence/ios-on-mac.json), and the independent visible UI check is in [evidence/ui-observation.json](evidence/ui-observation.json).

PlayCover itself was not installed. This was a minimal reproduction of its platform-conversion idea on our own code, not a test of PlayCover’s complete installer. No device provisioning, official iOS SDK build, unchanged iOS launch, or macOS-to-iOS execution was demonstrated. The existing Xcode project remains available for a future conventional build. This extra experiment is complete; it does not authorize proceeding into the main project’s Phase 2.

## Additional user-requested experiment: macOS hello inside the UIKit host

This add-on preserves the Phase 1 baseline snapshot. The Mac Catalyst-adapted UIKit host synchronously loaded the repository's original, unchanged ARM64 macOS `build/hello` executable in the same process. Its `_puts` call supplied the actual `Hello from macOS ARM64` text shown by the inner host-rendered macOS-style panel. No subprocess or guest GUI was involved. This confirms one narrow macOS guest running inside this Catalyst host on this Mac; it is not iPhone/iPad execution, nor an iOS-device-host result.

Fresh-copy executable mapping first returned `EPERM` in both the Catalyst host and a native macOS CLI. Registering the embedded signature with `F_ADDFILESIGS_RETURN`, checking the signed range, and honoring `F_CHECK_LV` resolved the controlled hello case without modifying its signature or changing system security settings. The loader is deliberately limited to this fixture and is not a general Mach-O runtime.

Current verification passes 30 Phase 1 tests in normal and sanitizer builds, plus all eight loader tests in both modes. See [Phase 1 validation](evidence/validation.json), [loader validation](evidence/loader-validation.json), and [the UI observation](evidence/inprocess-ui-observation.json). The experiment's contract and limits are in [`experiments/inprocess-hello/README.md`](../experiments/inprocess-hello/README.md).
