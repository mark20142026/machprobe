# What is machprobe?

machprobe is a **macOS → iOS translation layer** for Apple-silicon games. It takes the
*unmodified* arm64 binary of a Mac game — the exact bytes you get from Steam — and runs it
inside a normal signed iOS app on a real iPhone.

Its headline result: **Cyberpunk 2077 (Steam macOS build) running and playable on an
iPhone 18 Pro**: a level-50 save loaded, driving through Night City, Xbox controller and touch
input, roughly 30–40 fps at 1564×720.

## The idea in one paragraph

A Mac game built for Apple silicon is already arm64 machine code, and an iPhone also runs
arm64. The CPU instructions are the same, so nothing has to be emulated or recompiled. What differs is
everything *around* the code: how the program is loaded (macOS's dyld vs. our own loader),
which system libraries exist (AppKit exists on Mac, UIKit on iPhone), how much memory and
address space the OS allows, and which Metal features are present. machprobe fills those gaps.

## What it does

- **Loads Mach-O images itself.** A custom loader maps the game's executable and its
  bundled dylibs into memory, applies fixups and binds symbols, sets up thread-local storage,
  registers Objective-C classes and runs initializers. See [../02-architecture/loader.md](../02-architecture/loader.md).
- **Provides the Mac APIs the game expects.** `NSApplication`, `NSWindow`, `NSEvent`,
  `NSScreen`, display modes, cursor and focus are implemented on top of UIKit.
- **Passes Metal straight through** to the iPhone GPU, adding only the handful of Mac-only
  methods and storage modes the game uses. That's why the overhead is small (~1–5%).
- **Adapts the environment:** case-insensitive file paths, home directory remapping,
  `sysctl` answers, an offline replacement for network libraries, address-space rationing.
- **Adds a phone UX:** touch controls, controller support, telemetry, crash reports.

## What it does NOT do

- It does **not** modify the game. The game bytes are never patched (they are hash-verified at
  launch); behaviour is changed only from the outside (interposed functions, added methods).
- It does **not** ship any game. Users copy *their own* purchased copy from their own Mac.
  No game files, icons or assets are stored in this repository.
- It is **not** an x86 emulator. Windows games or Intel-only Mac games are out of scope.
- It is **not** App Store software. It is sideloaded with a developer profile.

## Why is it called "machprobe"?

Phase 1 was a small command-line tool that *probed* Mach-O files (`machprobe inspect`,
`machprobe deps`). The project grew from that inspector into a loader and then into a full
runtime, but the name stayed. See [../03-phase-history/](../03-phase-history/).

## Games run so far

| Game | Platform | Result |
|---|---|---|
| DashboardCalculator (SwiftUI app) | iOS VM | Renders its own UI (phase 4) |
| Strataris v1.0.1 | iOS VM | Runs unchanged (phase 5) |
| Veloren (Rust, wgpu) | iOS VM | Reaches the 3D village (phase 5.5) |
| SuperTuxKart 1.5 | iOS VM, then physical iPhone | 60 fps (phases 6–7) |
| Cyberpunk 2077 (Steam macOS) | Physical iPhone 18 Pro | Playable, ~30–40 fps (phase 8) |
