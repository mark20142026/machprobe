# Phase 1: Mach-O inspector and controlled macOS samples

Dates: 2026-10-01. Commits `0030ed5`, `f8517bb`, `8b49db1`, `ffd9ac9`,
`5adcbc5`, `92d6b44`, `c2333fe`. Phase sources: `docs/phase1-report.md`,
`docs/phase1-findings.md`, `README.md`.

## Goal

Create a small, honest starting point before any runtime work. The goal was to
inspect ARM64 macOS Mach-O executables and their dependencies with a native
tool, and to record what four controlled sample programs actually need. The
phase explicitly did not try to run macOS code on iOS.

## What was built

| Path | Contents |
|---|---|
| `samples/` | Four ARM64 macOS sample programs: `hello`, `file_io`, `framework` (CoreFoundation), `metal_info` (Metal device query). Built with `make all`. |
| `src/`, `include/` | The `machprobe` C++17 command-line inspector. Commands: `machprobe inspect FILE [--arch] [--json]` and `machprobe deps FILE [--max-depth N]`. It parses Mach-O itself and does not call `otool` or `nm`. |
| `tests/` | Python tests: `test_parser.py`, `test_dependencies.py`, `test_samples.py`. The Phase 1 suite has 30 test methods. Apple tools are used as independent references. |
| `scripts/evidence.py`, `scripts/research.py` | Evidence capture (`docs/evidence/baseline.json`, `validation.json`) and focused header, ABI and modern-linker experiments (`research.json`). |
| `experiments/inprocess-hello/` | A narrow loader that maps the unchanged `build/hello` binary inside a Mac Catalyst UIKit host. Eight loader tests. |
| `experiments/ios-on-mac/` | A tiny iOS-platform IPA and a converted Catalyst copy, requested separately by the user. Not one of the four baseline samples. |

Key inspector behaviour: unknown load commands are kept visible, dependency
traversal is bounded (default depth 16, 1,024-node ceiling), and FAT/FAT64
slices are selected by architecture. Binding opcodes and chained-import tables
are not decoded.

## How it was done

1. Built the four samples as ARM64 `MH_EXECUTE` files targeting macOS 11.0
   (`0030ed5`). Confirmed their stdout and exit codes.
2. Wrote the inspector and dependency walker (`f8517bb`). Parsing used only
   Apple headers, so it could be checked against Apple tools.
3. Added the validation layer: real-binary integration tests, synthetic parser
   fixtures, 40 deterministic malformed-input mutations, and sanitizer runs
   (`8b49db1`).
4. Built a tiny iOS-platform IPA and a Catalyst-converted copy as a separate
   experiment (`ffd9ac9`).
5. Recorded findings with claim labels (Verified / Documented / Hypothesis /
   Untested) in `docs/phase1-findings.md` (`5adcbc5`).
6. Ran the unchanged `hello` inside a UIKit host through a narrow loader
   (`92d6b44`) and closed the phase (`c2333fe`).

## Problems and bugs

| Symptom | How it was found | Root cause | Fix | Commit |
|---|---|---|---|---|
| Fresh signed copy of the guest failed with `EPERM` when mapping its executable pages, in the UIKit host and in a native macOS CLI | Running the copied hello in both hosts | The file's signature was not registered with the kernel for this mapping. Reproduced without any Catalyst involvement, so it was not Catalyst-specific. | Register the existing embedded signature with `F_ADDFILESIGS_RETURN`, check the covered range, honour `F_CHECK_LV`. No signature bytes were rewritten. | `92d6b44` |
| Direct `open` of the minimal iOS IPA failed with "incorrect executable format" | Launch attempt on the minimal IPA | The image was declared as platform 2 with SDK 0 by hand-written declarations and link stubs, so macOS would not run it as-is. | On a copy only, change the platform to Catalyst (6) with Apple `vtool` and re-sign. The original image was kept. | `ffd9ac9` |
| Static dependency report listed `UIKit.framework` as missing although the converted app ran | Comparing the static report with the running app | The inspector does not model Catalyst's `iOSSupport` path handling. | Not fixed. Recorded as a known limit of the static analysis. | `ffd9ac9` |
| A parser limited to the four baseline command layouts would miss a modern binary | Building a macOS 13 variant of `hello` with `-fixup_chains` | Baseline binaries use legacy `LC_DYLD_INFO_ONLY`. A modern build uses `LC_DYLD_CHAINED_FIXUPS` and `LC_DYLD_EXPORTS_TRIE`. | Inspector reads the modern commands. The variant was kept under `build/variants`, and the baseline binaries were not changed. | `f8517bb` |

Ordinary-sample problems were not recorded as bugs. The phase report's
"obstacles" column for each sample (dyld binding, C runtime, Objective-C
registration, GPU feature support) is a checklist, labelled Hypothesis, not an
observed iOS failure.

## Results / evidence

- All four samples ran on the Mac: `Hello from macOS ARM64`,
  `File I/O round trip OK`, `CoreFoundation string length: 11`, and
  `Metal device: Apple M2` with unified memory `yes`.
- All four are thin ARM64 `MH_EXECUTE` images with macOS platform 1, minimum
  OS 11.0 and SDK 27.0. Apple `file`, `lipo`, `otool`, `vtool`, `nm` and
  `codesign` agreed with the inspector's parsed fields.
- The suite passes 30 Phase 1 inspector tests, plus 8 loader tests, in normal
  and sanitizer builds (`docs/evidence/validation.json`,
  `docs/evidence/loader-validation.json`).
- The macOS 11 baselines were not modified. The modern-target variant lives in
  `build/`.

Evidence limits, stated in the report: no iPhone, iPad, Simulator or game was
used. No iOS SDK was installed, so `xcrun --sdk iphoneos` failed. The
iOS-platform experiment shows only a converted, Catalyst-classified copy
running on the Mac. It does not show macOS-to-iOS compatibility.

## What it unlocked next

- The inspector and the sample set became the reference for every later
  phase. Later loader code was derived from the Phase 1 loader.
- The findings set the questions Phase 2 had to answer: executable admission
  and signing, the iOS SDK's absence, Objective-C and ABI boundaries, and a
  minimal Metal workload.
- The report recommended five experiments (signing model first, then matched
  builds, then ABI probing, then dynamic-link coverage, then a Metal compute
  kernel). Phase 2 followed this order where it could, but ran on Catalyst
  instead of iOS because no iOS SDK was available.
