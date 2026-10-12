# Tests

Two test suites are relevant to the runtime, plus the Phase 1 tests they sit beside. There
is no test directory in `phase8/`. The Phase 8 check is the Mac load-only run of
`cp-load` (see [debugging-playbook.md](debugging-playbook.md), section 10) and the device
telemetry.

| Location | Runner | What it tests | Needs |
|---|---|---|---|
| `tests/` | `make test` (root `Makefile`) | Phase 1 `machprobe` CLI: Mach-O parser, dependency graph, sample programs | root `build/machprobe` and `build/{hello,file_io,framework,metal_info}` |
| `phase5_5/tests/` | `make -C phase5_5 test` | Shared loader runtime: size policy, keyboard layout, TLS thread isolation and unloads | `phase5_5/Makefile` builds its own binaries; one test also needs root `build/machprobe` |
| `experiments/inprocess-hello/tests/` | `make test-loader` | Optional in-process loader experiment | outside Phase 8 (not described here) |

All tests run from the repository root. Python tests use `python3 -m unittest discover`.
Set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if `xcrun` picks the
Command Line Tools (the Makefiles set it for their own compiles).

---

## 1. `tests/` (root Makefile)

**Make targets (root `Makefile`).**

- `make test`: depends on `all`, which builds the four samples (`build/hello`, `build/file_io`,
  `build/framework`, `build/metal_info`) and `build/machprobe` from `src/`. Then runs
  `python3 -m unittest discover -s tests -v`.
- `make test-sanitize`: builds `build/machprobe-sanitize` with `-fsanitize=address,undefined`,
  then runs the same tests with `MACHPROBE=build/machprobe-sanitize`.
- `make run-samples`: runs the samples directly.

**Files.**

| File | Test class | Methods | What it checks |
|---|---|---|---|
| `tests/test_parser.py` | `ParserTests` | 17 | Load commands, dylib and rpath variants, signing and encryption ranges, thread entries, symbol tables, export trie, re-exports, malformed and truncated commands, universal (fat) containers, JSON escaping, a mutation smoke test, real modern LINKEDIT, usage errors. Uses fixtures encoded in the test plus a seed from `build/hello`. |
| `tests/test_dependencies.py` | `DependencyTests` | 8 | Dependency graph: a native chain resolves, depth and node limits, cycles, missing libraries, identity, inherited rpath and precedence, same library under different runpath contexts, malformed or unsupported entries, relative paths (stated as unmodelled). Uses `tests/fixtures/` (`dep_a.c`, `dep_b.c`, `dep_main.c`). |
| `tests/test_samples.py` | `SampleIntegrationTests` | 5 | Runs the samples; `file_io` cleans up; the Metal sample reports device properties; inspection matches system tools; expected external symbols; the dependency report classifies system and Metal libraries. Honors `MACHPROBE` for the tool path. |

These tests cover the Phase 1 CLI (the parser that the later phases' loader started from).
They do not exercise `phase8/`.

---

## 2. `phase5_5/tests/` (`make -C phase5_5 test`)

**Make target (`phase5_5/Makefile`).** `make -C phase5_5 all` builds three products into
`build/phase5.5/`:

- `load-cli`: `runtime/` core plus `phase4/runtime/Extended.c`, both `Policy.c` files, and
  `phase5_5/host/LoadCLI.m`.
- `tls-guest`: `phase5_5/guests/tls.c` with `-Wl,-export_dynamic`.
- `tls-test`: the core runtime plus `phase5_5/tests/tls_host.c`, built with
  `-fsanitize=address,undefined -fno-sanitize-recover=all`.

`make -C phase5_5 test` then runs `python3 -m unittest discover -s phase5_5/tests -v` from the
root. The root `Makefile` must have been run first (`make`), because one test needs
`build/machprobe`.

**Test file: `phase5_5/tests/test_runtime.py`.** Four tests:

| Test | What it does | Expected output |
|---|---|---|
| `test_keyboard_matches_native_us_layout` | Builds `phase5_5/runtime/Keyboard.m` and `phase5_5/tests/keyboard.m` with ASan and UBSan and the Carbon framework, runs it. | `1600 native US layout comparisons, 0 failures` (the string `keyboard.m` prints). |
| `test_size_policy` | Creates a sparse file of 64 MiB + 1 byte and runs `load-cli` with `MP_IMAGE_LIMIT` set to 0, 128 MiB, and 513 MiB. | stderr contains `oversized`, `requires thin ordinary ARM64`, `512 MiB ceiling`. These messages come from the shared loader, `runtime/image.c`; `MP_IMAGE_LIMIT` is read by `phase5_5/host/LoadCLI.m`. |
| `test_tls_thread_isolation_and_teardown` | Runs `tls-test` against `tls-guest`. | `288 workers` |
| `test_embedded_bss_gap_and_restore` | Splits the `tls-guest` binary into text and data, builds a container dylib with `xcrun ld -sectcreate __TEXT __guest` and `__DATA __guest` and an ad-hoc `codesign`, and runs `tls-test` with `MP_CONTAINER` set. Uses `build/machprobe inspect --json` to find the segment layout. | `12 unloads` |

**`tls_host.c` (what the thread test checks).** Source: `phase5_5/tests/tls_host.c`.

- The outer loop runs 12 times. Each run opens the guest (by path, or as an embedded image from
  the container), checks `_tls_startup_check`, and gets `_tls_step`.
- Each run starts 24 threads. Each thread calls `tls_step` twice and checks the return values
  (`9 + id`, then `11 + 2*id`).
- The callback `report` is passed to `tls_step` and counts each call. After 12 runs the test
  requires exactly 288 calls (`12 × 24`, the destructor count named in the test's final message),
  and a sum of reported values that matches the expected total.
- After each run the image is closed, and `mp_live_images()` must be 0. That is the "12 unloads".
- In the embedded variant, the resident `__TEXT,__guest` bytes are compared with the file before
  and after every run. That checks that the loader restores the bytes it may have changed.

The count `288 workers` is 12 runs times 24 threads. It is a fixed number in the source, not a
measurement.

---

## 3. Running the suites

```sh
# Phase 1 CLI tests
make test                           # root Makefile
make test-sanitize                  # same tests, ASan/UBSan build of build/machprobe

# Shared runtime tests (needs root `make` first for the embedded-container test)
make                                # root build: build/machprobe
make -C phase5_5 test               # builds load-cli, tls-guest, tls-test; runs test_runtime.py
```

Phase 8 has no unit tests. Before a device install, the checks in the repo are:

- `python3 phase8/tools/build.py --quick` (asserts each image's SHA-256 against `SHA256SUMS`).
- The Mac load-only check (`make -C phase8` and `build/phase8/cp-load build/cyberpunk/thin Cyberpunk2077`,
  with no `--run`). Expected figures are in `CONTEXT.md`.

## 4. Gaps

- Nothing in `tests/` or `phase5_5/tests/` covers `phase8/runtime/` (Metal stubs, AppKit stand-ins,
  curl, controls) or `phase8/host/Main.m`. Their behaviour is checked on the device through telemetry.
- `phase8/tools/*.py` have no tests. Their output is the only check: the gap table from `import_gaps.py`,
  and the `verify OK` line from `push_resume.py`.
- The `test_embedded_bss_gap_and_restore` test shells out to `xcrun ld` and `codesign`, so it is not
  portable to a machine without Xcode.
