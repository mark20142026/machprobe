# Phase 2 findings

1 October 2026. **VERIFIED** means observed in this repository on this Mac. **DOCUMENTED** means supported by headers or primary sources. **HYPOTHESIS** means a proposed implication. **UNTESTED** means no execution evidence. All successes below are macOS/Catalyst results, not iOS compatibility claims.

## Evidence boundary

**VERIFIED:** Phase 1 started at commit `c2333fe`. All 30 inspector and eight original loader tests passed normally and under ASan/UBSan before implementation. The four original guest hashes and every existing Phase 1 evidence JSON were recorded in [the Phase 2 baseline](evidence/phase2/baseline.json). Final checks preserve them. Phase 1 source, tests, inspector and its separate loader were not rewritten. The new runtime derives its initial mapping/fixup code from that loader and lives separately in `runtime/`.

[results.json](evidence/phase2/results.json) records native and loaded executions, parsed metadata, signatures, ABI results, test transcripts and source hashes. [ui-build.json](evidence/phase2/ui-build.json) records packaging and guest hash preservation. [ui-observation.json](evidence/phase2/ui-observation.json) distinguishes observed UIKit behavior from an `open` command succeeding.

The new interactive, Foundation and compute binaries are newly compiled **macOS-targeted** guests. After building them, loading and packaging leave their bytes unchanged. Deliberately damaged test copies are individually marked and re-signed where necessary; they are not the baseline guests. Only the experimental **host copy** has its platform metadata changed from iOS 2 to Catalyst 6 and is re-signed. The preserved iOS-platform host IPA uses minimal declarations/link stubs and SDK field 0; it is not a validated full-SDK iOS development build. No recompiled iOS guest counterpart was executed.

## Runtime, entry and memory

**VERIFIED:** the runtime opens thin ordinary arm64 macOS `MH_EXECUTE` files, bounds segments/sections, validates the entry, registers the existing embedded signature, honors library validation, maps file-backed RX code and private writable data, applies supported legacy fixups, registers selector names, protects constant data and runs supported C initializers. It can keep an image loaded while the host invokes an exported interface. Symbol lookup uses bounded `LC_SYMTAB` entries. It never launches the guest as another process.

**VERIFIED:** `F_ADDFILESIGS_RETURN` and `F_CHECK_LV` succeed on the tested host. No code pages are rewritten and no RWX mapping is requested. The permission check rejects `initprot` exceeding `maxprot`. Tests query actual VM permissions for guest code and verify its address is no longer mapped after close. They also check file-descriptor counts and live image counts across 40 cycles, including failed import resolution. These checks do not prove absence of every possible framework allocation or cache leak.

**VERIFIED:** the additional fixtures require `DO_REBASE_ULEB_TIMES` and `BIND_OPCODE_ADD_ADDR_ULEB`. Apple's linker emits modulo-2^64 negative address deltas in the latter stream. The implementation accepts that encoding, then validates each final writable pointer slot. It does not interpret it as permission to write anywhere in memory.

**UNTESTED/unsupported:** chained fixups, general dependency loading, weak binding, guest-defined TLS descriptors, guest Objective-C class/category registration, C++/Objective-C exception unwinding, termination routines and asynchronous guest threads. Explicitly encountered unsupported imports/commands are rejected. Unknown optional metadata is not a claim of runtime support. The runtime is for trusted fixtures, not an isolation boundary or complete malformed-code validator. Guest code can call supported host APIs and can crash the process.

## Interaction and ABI

**VERIFIED:** UIKit controls construct an `MPEvent` and invoke a function pointer returned by loaded macOS code. The guest allocates its own `Counter` context, changes its counter and sequence, formats its result and invokes the host callback. UIKit displays that callback text; it contains no counter arithmetic. Two contexts have independent state. Invalid event types/sizes and ABI versions are rejected without a state callback. The versioned interface uses fixed-width integer fields, opaque context pointers and explicit ownership. Calls are synchronous; destroy guest contexts and finish callbacks before unloading.

| Boundary | VERIFIED on this Mac | Retest in iOS |
|---|---|---|
| Integer arguments/return | Signed values and values above 32 bits | Yes |
| Pointers and buffers | Guest reverses a host string into caller storage; short/null buffers return errors | Yes |
| Struct by value/return | Two-field 16-byte state transforms correctly | Yes |
| Callbacks/context | Guest invokes host function with transformed arguments; host receives guest state/string | Yes |
| Errors | Negative status values and rejected protocol inputs | Yes |
| Variadics | Typed variadic integer sum; real guest `printf`/`snprintf` paths | Yes; not every vararg class tested |
| Error state | Guest `__error` resolves to the current host thread's errno; two worker threads preserve the main thread value | Yes; this is host TLS forwarding |
| Initialization | C constructor sets 73 before exported functions execute | Yes; not Objective-C `+load` |

**DOCUMENTED:** Apple's [ARM64 ABI guidance](https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms) defines Apple-specific calling convention details, including variadics. **HYPOTHESIS:** the tested ordinary arm64 C boundary is a useful iOS candidate. Same-ISA success on this host does not establish iOS library layouts, all aggregate/variadic cases, arm64e/PAC or syscall compatibility.

## Framework and Objective-C results

**VERIFIED:** the unchanged CoreFoundation guest creates/releases a CFString and reports length 11 through the runtime. The new Foundation guest uses host class lookup and object creation, registered selectors, `objc_msgSend`, a mutable array, string transformations, ARC helpers and an autorelease pool. A weak reference becomes nil after the temporary object's lifetime/pool ends. Its exact result is checked independently in CLI tests and UIKit.

| Mechanism | Current implementation/status |
|---|---|
| CoreFoundation operations | Direct forwarding to host framework functions |
| Framework install names | macOS versioned names translated to unversioned host framework paths |
| Selector references | Runtime rewrites private data mappings with `sel_registerName` results before calls |
| Classes | Imports resolve to existing host classes; explicit `objc_getClass` forwarded |
| Dispatch/ARC/pools/weak references | Host libobjc implements behavior; required compiler helpers explicitly whitelisted |
| Guest-defined classes/categories | Unsupported; fixture rejected before execution |
| Initialization | Supported C initializer pointers; Objective-C load/initialize ordering not generalized |
| Exceptions | Unsupported; new Objective-C fixtures compile with exceptions disabled |

**VERIFIED engineering limitation:** the weak-reference probe initially introduced `__objc_personality_v0`. Rather than suggest forwarding that symbol would make unwinding work, the controlled Foundation/compute builds explicitly disable exceptions. Existing Phase 1 binaries are untouched. Some forwarded optimizer helpers (`objc_opt_*`, `objc_alloc_init`) are compiler/runtime dependencies, not a portable public API guarantee.

## Metal

**VERIFIED:** the unchanged Phase 1 Metal executable obtains the host's Apple M2 device through our loader and returns its name, registry ID and unified-memory value into UIKit. Its Objective-C selector references need canonicalization; forwarding only `MTLCreateSystemDefaultDevice` is insufficient.

**VERIFIED:** a separate macOS guest creates shared input/output buffers, compiles a small Metal kernel, submits a compute command, waits for completion and reads back 16 values. For inputs 0 through 15, results are `7,10,13,16,19,22,25,28,31,34,37,40,43,46,49,52`, checksum 472. Guest code checks every value and completion status. Python tests and the UIKit host independently verify the returned values. Host validation also rejects damaged/partial output rather than trusting a success label.

**Catalyst supplies:** Metal objects, shader compilation service, command submission, memory/resource management, driver and GPU. Our runtime binds imports and prepares Objective-C metadata; it does not implement Metal or translate GPU commands. The computation runs on this Mac's GPU. **UNTESTED:** iOS/vphone GPU behavior, precompiled macOS metallibs, graphics presentation, render targets, triangle rendering, real game workloads and performance equivalence.

## Compatibility matrix

“Yes” means observed execution through our runtime, in both the macOS CLI and Catalyst UI unless qualified. N/A is not a pass. The dependency column describes the current proof environment, not a claim every named API is inherently macOS-only.

| Guest | Loads | Executes | Input | Output | Framework forwarding | Current Mac/Catalyst dependencies | Actual iOS environment tested |
|---|---|---|---|---|---|---|---|
| Original Hello | Yes | Yes | N/A | Exact greeting | N/A | Signed-file mapping; libc/capture shim | No |
| Interactive | Yes | Yes | Buttons and automated event sequences | Guest counter/sequence/callback | N/A | Mapping, host allocator/formatting/errno | No |
| Original File I/O | Yes | Yes | Directory via argc/argv | Round trip; file removed | N/A | Host libc/filesystem and host temp directory | No |
| Original CoreFoundation | Yes | Yes | N/A | Length 11 | Yes | Host CoreFoundation and loader policy | No |
| Objective-C/Foundation | Yes | Yes | N/A | Verified content and weak lifetime | Yes | Host libobjc/classes/Foundation/compiler helpers | No |
| Original Metal device | Yes | Yes | N/A | M2 information | Yes | Host libobjc/Metal and GPU | No |
| Metal compute | Yes | Yes | Guest-generated 16-element buffer | Independently verified result | Yes | Host shader compiler/Metal driver/GPU | No |

## Remaining assumptions

**UNTESTED:** every row on device iOS, Simulator or vphone-cli. In particular, retest signature registration, library validation, file-backed execute permission, platform admission, dependency paths, optimizer helpers, selector behavior, ownership, sandbox file access and Metal compute. Catalyst is an Apple compatibility environment inside macOS, and its success cannot erase these gates. Kernel admission of a whole macOS executable and manually mapping its permitted signed pages are different experiments.

**DOCUMENTED:** Simulator can run Metal through Mac hardware, with environment differences; it is useful for SDK/UI checks but not equivalent to an iOS kernel/device security test. [Apple Metal Simulator documentation](https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator), [Apple Simulator architecture discussion](https://developer.apple.com/videos/play/wwdc2019/418/).

The user's selected Phase 3 direction is patched/jailbroken iOS 27 in vphone-cli with debugging. [The researched environment and source references](phase2-vphone-research.md) distinguish upstream reports from local tests. The [Phase 3 handoff](phase3-preparation.md) defines what to measure without starting that phase. No host security settings were changed in Phase 2.
