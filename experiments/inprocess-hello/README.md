# In-process macOS hello inside the UIKit test app

This is an additional experiment explicitly requested after the Phase 1 baseline. The target is the repository's original `build/hello`: an ARM64 macOS `MH_EXECUTE`. Its bytes are copied unchanged into the test app as `hello-macos`.

The host is built as an experimental iOS-target IPA using the minimal-declaration route described in `../ios-on-mac/README.md`. A separate copy of the **host** is classified as Mac Catalyst and re-signed so it can run on this Mac. The **guest** remains the repository's original, unchanged macOS `build/hello` binary. This demonstrates one controlled macOS guest running inside this Catalyst-adapted UIKit host on this Mac; it is not iPhone/iPad execution or an unchanged iOS-platform host.

## What the loader does

1. Reads the guest's Mach-O header, segments, macOS platform, `LC_MAIN`, legacy dyld streams and embedded signature. It accepts only the deliberately narrow hello fixture contract.
2. Registers the existing signature using `F_ADDFILESIGS_RETURN`, checks its covered range, and honors `F_CHECK_LV`. Failure stops loading. It does not replace a signature, suppress validation or change a security setting.
3. Reserves an address range excluding `__PAGEZERO`. Maps signed executable pages directly from the file as read/execute, and data as private writable mappings. No RWX allocation, JIT entitlement, or anonymous executable code copy is used.
4. Applies the one pointer rebase and binds the two import slots. `_puts` resolves to a host C shim that captures the guest's string for UIKit. The unused lazy binder resolves to a fail-fast trap, because lazy imports are bound eagerly.
5. Protects constant data, calls the mapped `LC_MAIN` address as this sample's `int main(void)`, captures the return value and releases mappings after it returns.

There is no `exec`, `posix_spawn`, `fork`, or subprocess in the runtime path. The outer window is the UIKit host. Its inner macOS-style “macOS hello” panel displays only the actual string captured from the guest's `_puts` call, or a concise loader error on failure. The panel is rendered by UIKit; hello has no AppKit window or graphics of its own. The UI shows no source listing, logs, or loader counters.

## Commands

```sh
make test-loader
make test-loader-sanitize
python3 experiments/ios-on-mac/build_experiment.py --with-macos-hello --launch
```

Outputs are under `build/inprocess-hello`. The builder asserts that the bundled guest hash equals `build/hello` before and after host adaptation. `docs/evidence/inprocess-hello.json` records the build, host metadata and guest hash. The separate UI observation and loader validation records distinguish launch requests from actual execution/rendering.

The default Phase 1 `make test` remains the inspector's 30-test suite. The optional loader suite adds eight test methods, including execution of a fresh signed copy, unchanged hashes, and rejection of malformed headers, wrong platforms, bad entry points, unknown imports, unsupported rebase types and non-hello samples. The latest normal and sanitizer runs pass all 30 Phase 1 tests and all eight loader tests; see [Phase 1 validation](../../docs/evidence/validation.json) and [loader validation](../../docs/evidence/loader-validation.json). The actual UI observation is recorded in [inprocess-ui-observation.json](../../docs/evidence/inprocess-ui-observation.json).

## Important discovery during this experiment

The first version ran `build/hello` in the CLI but got `EPERM` mapping `__TEXT` from a freshly copied signed guest. The copied file had the same SHA-256 and passed `codesign --verify`. The same failure reproduced in the ordinary macOS CLI, so it did not establish a Catalyst-specific policy restriction.

Registering the already embedded signature with `F_ADDFILESIGS_RETURN`, checking its covered range, and honoring `F_CHECK_LV` resolved the fresh-copy case in both the native macOS CLI and Catalyst/UIKit host. The loader does not alter the signature bytes, skip library validation, or change system security settings. This follows the signature registration and library-validation sequence visible in Apple's [dyld Loader.cpp](https://github.com/apple-oss-distributions/dyld/blob/main/dyld/Loader.cpp) and installed `sys/fcntl.h`. This result is specific to the controlled signed hello image and host environment.

## Deliberate limits

Only thin little-endian ordinary arm64, macOS, libSystem-only hello with the measured legacy pointer rebase/bind streams is supported. Unknown imports are errors. There is no general dyld replacement, runtime symbol search, chained fixup support, TLS, initializers, Objective-C registration, exception/unwind registration, AppKit rendering, process isolation, or guest application lifecycle. The loader is synchronous and non-reentrant; the guest returns normally. It is not a security boundary for arbitrary code. Any extension needs a new controlled fixture and tests.

The SDK-declared fcntl interfaces are used here as macOS research mechanisms. Their presence in headers is not evidence that third-party iOS applications may use this loading strategy or that App Store policy permits it.
