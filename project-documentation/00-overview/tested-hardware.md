# Tested hardware and software

machprobe has been tested on exactly one phone and one Mac. Anything else is **untested**.

## ✅ Fully verified device: iPhone 18 Pro

The **iPhone 18 Pro** (`iPhone19,2`, A20 Pro, 12 GB RAM, iOS 27.0.1) is a **fully verified working
device** for Cyberpunk 2077 (Steam macOS build 20383525). Verified on it, end to end:

| Area | Verified |
|---|---|
| Setup | Build, signing with a free Apple account, install, 61 GB data copy, saves and settings restore |
| Boot | Home screen → loading → main menu, licence screen, settings |
| Gameplay | Loading a level-50 save, open world, driving, on-foot play, combat, audio |
| Input | Xbox controller, touch menus (tap/scroll), on-screen touch controls |
| Performance | 30–40 fps in the city at 1564×720; built-in benchmark **39.44 fps** average |
| Stability | Long play sessions with the recommended settings |

Known limitations on this device (not blockers): heat within minutes (use a 60/40 fps cap),
occasional memory kills during heavy moments, and the black blob near the sun unless Motion Blur is
Off (the recommended settings turn it off). See [../04-cyberpunk/known-issues.md](../04-cyberpunk/known-issues.md).

## Full tested setup

| Role | Device | Software |
|---|---|---|
| **Phone (runs the game)** | iPhone 18 Pro (`iPhone19,2`), A20 Pro, 12 GB RAM — ✅ **fully verified** | iOS 27.0.1 (24A446) |
| **Mac (builds, signs, stores the game files)** | MacBook Air M2 (`Mac14,2`), 8 GB RAM | macOS 27.0.1, Xcode 27.0 |
| **Game** | Cyberpunk 2077, Steam macOS build 20383525 (arm64) | In-game benchmark 39.44 fps at 1564×720 |
| **Controller** | Xbox wireless controller (Bluetooth) | via Apple's GameController framework |
| **Signing** | Free (personal team) Apple developer account | 7-day profiles |
| **Earlier test target** | iOS virtual machine ("vphone") on the Mac | Phases 2–6 (SuperTuxKart at 60 fps) |

The Mac never runs Cyberpunk; it only builds the host app and holds the Steam install the data is
copied from. That's why an 8 GB MacBook Air is enough.

## Probably works (untested)

- **iPhone 17 Pro / 17 Pro Max** (12 GB RAM, same as the 18 Pro): will probably work, with the
  same `increased-memory-limit` entitlement.
- **iPhone 18 Pro Max:** will probably work, with less thermal throttling (bigger body).
- **iPad Pro (M-series):** will probably work, and likely better (more cooling). Models with
  more RAM (16 GB configurations) have the most headroom; 8 GB configurations are untested.
- **Any Apple-silicon Mac** for building.

## Which iPhone? (by RAM)

Why RAM matters: iOS only lets one app use part of the phone's memory. With the extra-memory
entitlement, that limit is about **6 GB** on both the 12 GB iPhone 18 Pro (measured, ~6.1 GB) and an
8 GB iPhone 15 Pro Max (user report, ~6 GB, [SideStore issue #1616](https://github.com/SideStore/SideStore/issues/1616)); without it, about 3.3–3.4 GB. Cyberpunk uses
about 4.8 GB in the city. Phones with 6 GB RAM or less get a lower limit.

| Devices | RAM | Recommendation |
|---|---|---|
| **Older than the iPhone 15 Pro** (iPhone 14 Pro and earlier, iPhone 15 / 15 Plus) | 6 GB or less | **Not recommended due to low memory limits.** iOS gives the app too little memory; expect crashes or no start. |
| iPhone 15 Pro / Pro Max, iPhone 16 series, iPhone 17 (non-Pro) | 8 GB | **Untested with Cyberpunk, may work.** A user measured **~6 GB** available with the extra-memory entitlement on an iPhone 15 Pro Max (iOS 27.0, free account; ~3.3 GB without it) — about the same as the 18 Pro's ~6.1 GB ([SideStore issue #1616](https://github.com/SideStore/SideStore/issues/1616)). With less spare RAM overall, expect more memory kills than on 12 GB devices. Reports welcome. |
| iPhone 17 Pro / Pro Max, iPhone 18 Pro / Pro Max (12 GB), iPad Pro with 16 GB | 12 GB+ | **Best experience: fewest crashes** (18 Pro fully verified; ~6.1 GB allowed per app, game uses ~4.8 GB). |

## Not expected to work

- Phones with 6 GB RAM or less (anything older than the iPhone 15 Pro): not recommended due to low
  memory limits; the game is unlikely to fit in the per-app limit.
- Intel Macs as the build machine (untested; the Steam build is still arm64, but tooling assumptions may differ).
- Other game builds than the one listed. A different Steam build may need small changes
  (the build script records the build number it packages).

## Reporting a new device

If you try another device, record: model, iOS version, RAM, settings file, fps from the in-game
benchmark, and whether/when iOS killed the app (the `[budget]` telemetry line just before a kill
is the most useful data). See [../05-tools-and-diagnostics/telemetry.md](../05-tools-and-diagnostics/telemetry.md).
