# machprobe

`machprobe` is a small macOS-only ARM64 research tool for inspecting Mach-O executables and their dependency metadata. Phase 1 is intended for learning and analysis; it is not an emulator and does not execute Mach-O code itself.

The project builds four small native sample programs and a C++17 command-line inspector. `machprobe inspect` reports basic Mach-O structure, while `machprobe deps` explores the dependency information available in the file.

## Build and run

Requirements: macOS on Apple Silicon, Xcode Command Line Tools (including `xcrun`, Clang, and the macOS SDK), and Python 3 for tests/evidence.

```sh
make all
make run-samples
make test
make test-sanitize
make evidence
```

`make evidence` builds the project and writes a machine-readable baseline to `docs/evidence/baseline.json`. The evidence script runs the `file_io` sample in a temporary directory and records tool output and exit codes for the samples and inspector.

## CLI

```text
build/machprobe inspect FILE [--arch arm64|arm64e] [--json]
build/machprobe deps FILE [--arch arm64|arm64e] [--json] [--max-depth N]
```

The optional architecture selects a slice from universal binaries. JSON output is intended for scripts and evidence capture. `--max-depth` limits dependency traversal.

## Current scope and limits

The parser handles little-endian 64-bit ARM64 Mach-O, including FAT/FAT64 architecture selection. It reads defined and undefined external symbols from the symbol table and exports from the export trie. It does not fully decode bind opcodes or chained fixups, and it does not extract dyld shared-cache contents. Cache-only dependencies are reported at the boundary of what the input file provides; this phase does not resolve them by extracting or analyzing a shared cache.

## Directory layout

- `src/` — command-line entry point, Mach-O parsing, and dependency analysis.
- `include/` — shared C++ interface.
- `tests/` — Python unit and integration tests.
- `samples/` — source for the four native sample programs.
- `build/` — generated executables (ignored by Git).
- `scripts/evidence.py` — reproducible environment and sample evidence capture.
- `docs/evidence/` — generated baseline JSON.

## Research results

See [Phase 1 findings](phase1-findings.md), [Phase 1 report](phase1-report.md), and [current progress](../progress.md). `python3 scripts/research.py` captures the focused header/ABI/modern-linker experiments. The separately requested [tiny iOS-on-Mac experiment](../experiments/ios-on-mac/README.md) preserves an original IPA and tests a converted copy; it is not part of the four baseline samples.

The default `--arch arm64` prefers a plain ARM64 slice, falling back to an ARM64 subtype when no plain slice exists; `--arch arm64e` requires that subtype. FAT/FAT64 headers use standard big-endian container encoding. Individual slices must be little-endian 64-bit ARM64. `--max-depth` accepts 0–128 (default 16), with a 1,024-node traversal ceiling. Unknown commands are retained; a successful parse is not proof of loadability. A readable graph may legitimately report cache boundaries.

## Phase 2 runtime

The separate `runtime/` and `phase2/` directories extend the original research into a controlled in-process runtime with a guest-owned interactive counter, framework forwarding and verified Metal compute. Phase 1 commands and fixtures remain unchanged. Read [Phase 2 results](phase2-report.md), [the detailed findings](phase2-findings.md) and [the prepared Phase 3 handoff](phase3-preparation.md). All execution evidence remains macOS/Catalyst-only.

```sh
make all
make -f phase2/Makefile all test sanitize
python3 phase2/host/build.py --launch
```
