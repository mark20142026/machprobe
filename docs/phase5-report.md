# Phase 5 report — gameplay milestone, stopped by user

The official Strataris v1.0.1 ARM64 macOS game rendered its title screen and actual
cockpit on the iOS 27 vphone guest. Host virtual keys reached its original game
logic: briefing/start, movement and firing were observed. The user confirmed
playability and requested stopping this phase rather than completing optional
keyboard-configuration UI.

No game source was inspected, altered or rebuilt. The original .app is preserved;
its selected executable slice is unchanged inside the separately generated iOS
container. All compatibility changes are in our runtime/host.

## Built

- Opt-in modern chained fixup support in `runtime/`, including high8 tags.
- `phase5/runtime/`: AppKit lifecycle, window, menu and keyboard adapters;
  explicit unavailable desktop-updater capability; Managed→Shared Metal texture
  mapping; preliminary desktop control adapters; frame/audio observations.
- `phase5/host/Main.m`: checked guest loading, metadata registration, diagnostics.
- `phase5/tools/build.py`, `vm.py`: package our runtime around original guest bytes
  and install/control it in the existing VM.
- `phase5/tests/`: executable integrity and GPU readback tests.
- `docs/evidence/phase5/`: original metadata, hashes, first failures, subsequent
  failures, test outputs, screenshots and runtime reports.

## Commands

```sh
cd /Users/<user>/machprobe
python3 phase5/tools/build.py
python3 -m unittest discover -s phase5/tests -v
python3 -m unittest discover -s phase3/tests -v
python3 phase5/tools/vm.py install
python3 phase5/tools/vm.py launch
python3 phase5/tools/vm.py report
python3 phase5/tools/vm.py logs
```

Build inputs must already be present in `build/phase5/`. The build compiles only
our host/adapters, never the third-party game. The final host omits its K shortcut;
this does not remove keyboard configuration from the original game itself.

## Handoff

This is verified gameplay in the research VM, **not** full satisfaction of every
original Phase 5 criterion. Audio startup currently fails; normal sandbox/signing
independence, persistence, long gameplay profiling and full final regression are
unverified. K/keyboard sheets and some optional desktop dialogs remain unsupported.
A menu or physical-key route can still reach them. The installed host's callbacks
remain version-sensitive through Objective-C/Swift metadata registration SPIs.

Before any harder target, preserve this known working gameplay evidence and make
an explicit decision about those remaining gaps. No Phase 5.5, new game, Steam or
Cyberpunk work has started. Detailed chronology and limitations are in
[phase5-findings.md](phase5-findings.md).
