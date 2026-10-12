# Build, deploy and data tools

Scripts that package, sign, install and inspect the Cyberpunk 2077 iOS app. Source
files: `phase8/tools/`, plus `phase7/tools/device.py` and `phase7/tools/localconfig.py`,
which `phone.py` imports.

**Start with `setup.py`.** `phase8/tools/setup.py` is the one entry point for setting
up: it runs the other scripts in order, and the sections below describe what each of
them does internally. Step-by-step usage is in
[../01-getting-started/](../01-getting-started/); the same steps for a person are in
Part 2 of the top-level [README](../../README.md), and for an AI agent in
[AGENT-SETUP.md](../../AGENT-SETUP.md).

Common setup: the scripts resolve the repository root from their own location
(`parents[2]`), so the current directory does not matter. Device calls go through
`xcrun devicectl` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (set by
the scripts). Per-user values (device UDID, signing identity, Apple team, App ID prefix)
are not in any script: they come from the git-ignored `machprobe.local.json` at the
repository root, read through `localconfig.py` (section 2). The docs write them as
`<DEVICE-UDID>`, `<SIGNING-IDENTITY-SHA1>`, `<TEAM-ID>` and `<your-bundle-prefix>`.

---

## 1. `phase8/tools/setup.py`

**Purpose.** One command-line entry point for the whole setup. Every subcommand is safe to
re-run. `python3 phase8/tools/setup.py help` (or no argument) prints the usage text.

| Subcommand | What it does |
|------------|--------------|
| `doctor [--steam <folder>]` | Prints a PASS/FAIL checklist with a `fix:` line under each FAIL; ends `ALL GOOD` or asks you to fix the FAILs top to bottom and re-run. Exit status 0 only if everything passed. |
| `config [--udid U] [--identity SHA1] [--team ID] [--bundle-prefix P]` | Detects the iPhone, signing identity and Apple team, and writes `machprobe.local.json`. |
| `prepare-game [--steam <folder>]` | Builds `build/cyberpunk/thin` from your Steam install and verifies it. |
| `profile` | Registers the Cyberpunk App ID and creates the provisioning profile through Xcode. |
| `build [args]` | Runs `phase8/tools/build.py` with the arguments (for example `--quick`). |
| `install` | Runs `phase8/tools/phone.py deploy`. |
| `copy-data` | Runs `phase8/tools/push_resume.py archive engine r6`. |
| `restore [--saves] [--settings] [--force]` | Copies Mac saves and the recommended settings to the phone without overwriting. |
| `launch` | Runs `phase8/tools/phone.py launch`. |

`build`, `install`, `copy-data` and `launch` run the other script in a child Python process
with `DEVELOPER_DIR` set and exit with its status if it fails.

**`doctor` checks, in order.** Apple silicon; Xcode at `/Applications/Xcode.app`; the macOS game
installed (default `~/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077`, or
`--steam`); the Steam build (read from `appmanifest_1091500.acf`) equals 20383525;
`build/cyberpunk/thin/SHA256SUMS` exists; `machprobe.local.json` exists; at least one "Apple
Development" signing identity; Xcode is signed in to a team; an iPhone is paired. With a config
it adds: the configured iPhone is visible; Developer Mode is `enabled`; the configured
identity is in the keychain; the Cyberpunk profile exists, has not expired (shows days left),
lists the configured UDID, and has `com.apple.developer.kernel.increased-memory-limit`. It
finally prints a reminder to check for 65 GB of free space on the phone (it does not measure it).

**`config` detection.** The phone list comes from `devicectl list devices` (physical iOS
devices only); identities from `security find-identity -v -p codesigning` (names containing
"Apple Development"); teams from Xcode's `IDEProvisioningTeamByIdentifier` preference
(`defaults export com.apple.dt.Xcode`). A value is chosen automatically only when exactly one
candidate exists or the flag is given; otherwise it prints `choose --udid:` (or `--identity`,
`--team`) with the candidates, writes nothing and returns 1. The bundle prefix is the
`--bundle-prefix` value, else the prefix already in the existing config file, else
`machprobe.t<team id lowercased>`. It prints `App ID will be <prefix>.CP2077`.

**`prepare-game` internals.** Reads the expected hashes from `phase8/cyberpunk-macos-20383525.sha256`
(Steam build 20383525; five entries: `Cyberpunk2077` and four `Frameworks/*.dylib`). Deletes and recreates
`build/cyberpunk/thin`, copies each file from `Cyberpunk2077.app/Contents` (the executable from
`MacOS/`), but for a universal binary (`lipo -archs` lists more than one architecture; in
practice `libsteam_api.dylib`) runs `lipo -thin arm64` instead of copying, because a plain copy
would not match the hash. It then compares SHA-256 values; on any difference it prints the
differing names and returns 1 (a different game build). On success it copies the hash file to
`thin/SHA256SUMS` (the format `build.py` reads).

**`profile` internals.** Runs `xcodebuild` on `phase7/signing/Provisioner.xcodeproj`
(`-configuration Debug -sdk iphoneos -allowProvisioningUpdates`, `SYMROOT`/`OBJROOT` under
`build/setup/`) with `PRODUCT_BUNDLE_IDENTIFIER=<prefix>.CP2077` and `DEVELOPMENT_TEAM=<TEAM-ID>`
from the config. The pbxproj itself carries no team. The exit status of `xcodebuild` is ignored
(the stub may fail to link); success is whether `localconfig.profile()` then finds a profile
for that exact App ID, in which case it prints `OK: profile <file>, expires <date>`. Otherwise
it prints the `error` lines from `xcodebuild` and the usual causes, and returns 1.

**`restore` internals.** Saves come from `~/Library/Application Support/CD Projekt Red/Cyberpunk 2077/saves`
(copied to `build/setup/saves` first, with `user.gls` removed because the EULA acceptance is per
device); settings come from `phase8/config-recommended-UserSettings.json`. Both go into the app
container under `Library/Application Support/CD Projekt Red/Cyberpunk 2077/` with
`devicectl device copy to`. Before each, `remote_has()` lists the *parent* folder on the phone
(`devicectl device info files`) and looks for the name; existing saves/settings are skipped
unless `--force`. If the listing fails and the container's `Library` folder also cannot be
listed, it prints `cannot read the phone ... not copying anything` and exits 1; if only the
parent is missing (fresh install) the item counts as absent and is copied.

---

## 2. `phase7/tools/localconfig.py`

**Purpose.** The single place that knows the per-user values. Imported by `device.py`,
`phone.py`, `push_resume.py`, `build.py` and `setup.py`.

| Name | What it does |
|------|--------------|
| `PATH` | `machprobe.local.json` in the repository root (git-ignored). |
| `load()` | Reads it and requires the keys `device_udid`, `signing_identity`, `team_id`, `bundle_prefix`. If the file or a key is missing it exits with `... run python3 phase8/tools/setup.py config`. |
| `bundle(app)` | `bundle_prefix + '.' + app`: `<prefix>.CP2077` for Cyberpunk, `<prefix>.STKHost` for the SuperTuxKart host. |
| `profile_info(f)` | Decodes a `.mobileprovision` with `security cms -D` and returns its plist as a dict. |
| `profile(bundle_id)` | The newest profile in `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` whose `application-identifier` (without the team prefix) equals `bundle_id` exactly; never just the newest overall. If none matches it exits with `no provisioning profile for <bundle id>: run python3 phase8/tools/setup.py profile`. |

Because `device.py` loads the config when it is imported, every `phone.py` and
`device.py` subcommand exits with the `... run setup.py config` message when
`machprobe.local.json` is missing or incomplete.

---

## 3. `phase8/tools/build.py`

**Purpose.** Packages the unchanged Cyberpunk 2077 images (Steam macOS build 20383525,
thin arm64 copies in `build/cyberpunk/thin/`, made by `setup.py prepare-game`) into an iOS app. It builds one container
dylib per guest image, compiles the Phase 8 host and runtime with `-O3 -flto=thin`,
writes `Info.plist`, and zips an ad-hoc-signed `.app` into an `.ipa`.

**Usage.** Normally through `setup.py`; both forms are equivalent:

```sh
python3 phase8/tools/setup.py build            # full build (containers + host)
python3 phase8/tools/setup.py build --quick    # reuse containers whose SHA-256 is unchanged
python3 phase8/tools/build.py [--quick]        # what setup.py runs
```

It needs `machprobe.local.json` (for the bundle ID) and `build/cyberpunk/thin/` with its
`SHA256SUMS` (from `prepare-game`).

**Output.** `build/phase8-runtime/Payload/CP2077Host.app` (the app bundle) and
`build/phase8-runtime/CP2077Host.ipa`. Containers are under
`build/phase8-runtime/containers/` (`WORK`).

**What it does, step by step.**

1. Imports `phase6/tools/build.py` as module `p6` and overrides its output globals
   (`OUT`, `APP`, `WORK`) so `p6.container()` writes into the Phase 8 folders.
2. Creates `Frameworks/`, writes a one-line `empty.s`, and assembles `empty.o`. The
   script never links `empty.o` afterwards, so this step is unused in the current code.
3. Builds the image list: `Cyberpunk2077` plus every `Frameworks/*.dylib` in the thin
   copy, in sorted order.
4. For each image, computes SHA-256 and checks it against `build/cyberpunk/thin/SHA256SUMS`.
   The `assert` is the guarantee that only the preserved release bytes are packaged.
5. With `--quick`, loads the previous `target.json` and keeps an image's container when
   its hash matches and the container file still exists. Otherwise calls
   `p6.container(i, name, data)` to build a new one.
6. Writes `target.json` into the app bundle: release name plus one manifest entry per
   image (name, container, sha256, slice size, unwind info). The host checks these
   hashes at launch (see [host-app.md](host-app.md)).
7. Compiles about 40 translation units with `xcrun clang -O3 -flto=thin -g`, using
   `-fobjc-arc` for `.m` files. Sources come from `runtime/`, `phase4/`, `phase4_5/`,
   `phase5/`, `phase5_5/`, `phase6/runtime/`, and `phase8/`. The host list includes the
   Phase 5.5 probe sources `MetalProbe.m`, `UIKitProbe.m`, and `AudioProbe.m` from
   `phase5_5/tests/`.
8. Compiles `phase4/runtime/ImageShim.swift` with `swiftc` into `SwiftShim.o`.
9. Links everything with `swiftc` against Foundation, UIKit, Metal, MetalKit, QuartzCore,
   CoreGraphics, CoreText, CoreFoundation, AudioToolbox, AVFAudio, IOSurface,
   GameController and MetalFX. Link flags: `-export_dynamic`, rpath
   `@executable_path/Frameworks`. Output: `CP2077Host`.
10. Writes `Info.plist`: bundle ID `localconfig.bundle('CP2077')` (`<your-bundle-prefix>.CP2077`), display name
    "Cyberpunk 2077", `MinimumOSVersion` 15.0, landscape orientations, full screen, GameController
    support, file sharing enabled (so Finder can copy game data into Documents), and
    `CADisableMinimumFrameDurationOnPhone` true (ProMotion, 120 Hz allowed).
11. If the user's Steam install has `Cyberpunk2077.app/Contents/Resources/AppIcon.icns`,
    runs `make_icon.swift` to create the icon PNGs and adds the icon keys. The icon is read
    at build time from the user's copy and is never stored in the repo.
12. Copies `phase8/host/selectors.txt` into the bundle (input for `MP_SEL_SURVEY`).
13. Signs the bundle ad hoc (`codesign --sign -`) and zips it to `CP2077Host.ipa`.

**Key functions.**

| Name | What it does |
|------|--------------|
| `main()` | Runs steps 1-13 in order. |
| (module import of `p6`) | Reuses `run`, `sdk`, `target` and `container()` from `phase6/tools/build.py`. |

Note: `build.py` does not run `phone.py deploy`. Signing with the developer identity
happens in `phone.py deploy` (`setup.py install`), not here.

---

## 4. `phase8/tools/phone.py`

**Purpose.** Drives the Cyberpunk app on the physical iPhone over USB with `devicectl`.
App ID `<your-bundle-prefix>.CP2077`, which is separate from the STKHost App ID.
`setup.py install` runs `phone.py deploy` and `setup.py launch` runs `phone.py launch`; the
other subcommands are run directly.

**Usage.** `python3 phase8/tools/phone.py <subcommand> [args]`

Subcommands: `check`, `deploy`, `push-data`, `launch`, `report`, `logs [N]`, `args ...`,
`debug on|off`.

**Module setup (runs at import).**

- Imports `phase7/tools/device.py` as `d` (which loads `machprobe.local.json`; if it is
  missing, **every subcommand** exits with `... run setup.py config`) and sets
  `d.BUNDLE = localconfig.bundle('CP2077')`. `device.py`'s helpers read `BUNDLE` and `UDID`
  at call time, so this reassignment redirects them to the Cyberpunk app.
- `IDENTITY` is `signing_identity` from the config (`<SIGNING-IDENTITY-SHA1>`).
- `GAME` is `~/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077`.
- The provisioning profile is **not** chosen at import any more: `deploy()` calls
  `localconfig.profile(BUNDLE)`, the newest profile whose App ID is exactly the Cyberpunk
  one. If none exists, `deploy` exits with `no provisioning profile for <bundle id>: run
  ... setup.py profile`; the other subcommands do not need a profile.

### `check`

1. `info()` runs `devicectl device info details --json-output build/phase8-runtime/device.json`.
2. Prints the marketing name, iOS version and `developerModeStatus`.
3. Runs `devicectl device info lockState` and prints the last 200 characters.

### `deploy`

Signs the built app and installs it (`setup.py install`). Expects
`build/phase8-runtime/Payload/CP2077Host.app` to already exist (run `setup.py build` first).

1. Finds the profile with `localconfig.profile(BUNDLE)`, decodes it, and removes
   `build/phase8-signed/CP2077Host.app`.
2. `ditto`s the built app to `build/phase8-signed/CP2077Host.app`.
3. Copies the profile in as `embedded.mobileprovision`.
4. Writes the profile's `Entitlements` dictionary to `build/phase8-signed/entitlements.plist`.
5. Re-signs every `Frameworks/*.dylib` with `IDENTITY`, `--timestamp=none`.
6. Re-signs the app with `IDENTITY` and the entitlements file.
7. Prints the profile expiry date and runs `devicectl device install app`.

The profile expiry is printed on each deploy. The profile is refreshed with
`setup.py profile` (which runs the phase7 Provisioner project through `xcodebuild`); then
run `deploy` again.

### `push-data`

Copies `r6`, `engine`, `archive` (in that order, small first) from `GAME` into
`Documents/Cyberpunk 2077/<folder>` on the phone, one `devicectl device copy to` per
folder. It does not skip existing files and does not verify. For a resumable,
verified copy, use `push_resume.py` (`setup.py copy-data`).

### `launch`

`devicectl device process launch --terminate-existing <bundle>`. No environment is passed,
so `MP_CONSOLE` is not set and the app redirects its stdout and stderr to files.

### `report`

Pulls `runtime.json` (through `d.report()`, which writes `build/phase7/runtime.json`) and
prints these keys as JSON: `pid`, `stage`, `error`, `exception`, `load`, `gpu`,
`data_present`, `memory_available_bytes`, `frame_window`. Then the last 15 `events`, and,
if present, the first 25 lines of `stack` (set only for uncaught Objective-C exceptions).
The watchdog's `main_stack_stalled` and `main_stack_sample` are not printed here; read
the file directly.

### `logs [N]`

Pulls `runtime-stderr.log` and `runtime-stdout.log` (into `build/phase7/`) and prints the
last N lines of each (default 30).

### `args ...`

Writes every argument after `args` as a JSON array to `build/phase8-runtime/arguments.json`
and pushes it to `Documents/arguments.json`. The app reads this at launch (up to 33
entries) and passes them to the guest after `argv[0]` (`Cyberpunk2077`). The file is read
only at launch, so relaunch after changing it.

### `debug on|off`

`on` writes `build/phase8-runtime/debug` containing `1` and pushes it to
`Documents/debug`. The app then starts the watchdog (see [telemetry.md](telemetry.md)).

`off` copies `build/phase8-runtime/empty` to `Documents/debug` with `check=False`. Nothing
in the repo creates `build/phase8-runtime/empty`, and the failure is silent. **Unknown
whether `debug off` removes `Documents/debug`.** Verify the file on the device before
relying on it.

**Key functions.**

| Name | What it does |
|------|--------------|
| `info()` | Runs `devicectl device info details` and returns the parsed `result`. |
| `check()` | Prints device model, iOS version, Developer Mode, lock state. |
| `deploy()` | Looks up the profile, signs and installs the app (steps above). |
| `push_data()` | Copies the three game folders to the phone. |
| `__main__` block | Dispatches on `sys.argv[1]`. A missing argument raises `IndexError`; an unknown one does nothing; there is no usage message (use `setup.py help`). |

---

## 5. `phase8/tools/push_resume.py`

**Purpose.** Copies the game data to the phone in a resumable, verified way. Use this in
place of `phone.py push-data` for the ~60 GB archive. The script's docstring says to run
it with no other `devicectl` use at the same time.

**Usage.** `python3 phase8/tools/setup.py copy-data` runs
`python3 phase8/tools/push_resume.py archive engine r6`. Run the script directly to copy only
some folders: `python3 phase8/tools/push_resume.py [archive engine r6]` (default: all three,
in that order). Safe to re-run after an interruption.

**What it does, per subfolder.**

1. `remote(sub)` lists the phone's files under `Documents/Cyberpunk 2077/<sub>` with
   `devicectl device info files --json-output <TMP>`, and returns a map of relative path to
   size. Listing errors are swallowed; the result is then empty.
2. Lists local files under `GAME/<sub>` with their sizes.
3. If the remote listing is empty, prints `<sub>: new on the phone, creating folders ...` and
   calls `seed(sub, local)`: it stages the smallest file of every local subfolder under
   `build/phase8-runtime/seed/<sub>` (hard links via `os.link`, falling back to a copy),
   copies that staging folder to `Documents/Cyberpunk 2077/<sub>` (copying a folder creates
   the whole tree on a fresh phone, which a single-file copy may not), deletes the staging
   folder, and lists the phone again. A failed seed exits with `seeding <sub> failed: ...`.
4. `todo` is every local file whose remote size is missing or different. Size is the only
   comparison; there is no hash check.
5. Copies the todo files, smallest first. Each copy has up to four attempts with a 5 s
   pause between them. If all attempts fail, the script exits with `FAILED <file>`.
6. Prints progress: GiB done, MB/s, file name.
7. Re-lists the remote folder and reports `verify OK` or `MISMATCH` (first five paths).
   On mismatch it exits 1.
8. After all folders, prints `ALL DATA ON PHONE`.

**Notes.** `UDID` (`<DEVICE-UDID>`) and `BUNDLE` (`<your-bundle-prefix>.CP2077`) come from
`machprobe.local.json` through `localconfig`; the script exits with the `run setup.py config`
message if it is missing. `GAME` is the default Steam install path. `TMP`
(`build/phase8-runtime/remote.json`) is relative to the repository root, so the script works
from any checkout. `ENV` sets `DEVELOPER_DIR`.

**Key functions.**

| Name | What it does |
|------|--------------|
| `dc(*a)` | Runs `xcrun devicectl` with `capture_output=True` and returns the process. |
| `remote(sub)` | Returns `{relative path: size}` for files under one remote subfolder. |
| `seed(sub, local)` | Creates the folder tree on a phone that has none of `sub` yet (steps above). |
| (main loop) | Per-folder seed if needed, sync, progress, retry, verify (see steps above). |

---

## 6. `phase8/tools/make_icon.swift`

**Purpose.** Builds the iOS app icon from the user's own installed game, at build time.
Called by `build.py` as `xcrun swift make_icon.swift <AppIcon.icns> <output-dir>`.

**What it does.**

1. Opens the `.icns` with ImageIO and takes the largest image (by width).
2. Draws the image into an RGBA buffer and finds the bounding box of pixels with alpha
   above 200. That box is the macOS squircle without its transparent padding.
3. Crops to a square of that box's larger side.
4. Takes the fill colour from a pixel just inside the left edge at mid-height. This fills
   the corners so the icon has no transparent gaps.
5. Writes four opaque PNGs (opaque because iOS icons must be opaque):
   `AppIcon60x60@2x.png` (120 px), `AppIcon60x60@3x.png` (180 px),
   `AppIcon76x76@2x.png` (152 px), `AppIcon83.5x83.5@2x.png` (167 px).

**Key functions.** Top-level script; no named functions.

---

## 7. `phase8/tools/import_gaps.py`

**Purpose.** Offline check of which symbols the five Cyberpunk images import from system
libraries that do not export them on iOS. It reads the iOS SDK's `.tbd` export lists.

**Usage.** `python3 phase8/tools/import_gaps.py build/cyberpunk/thin Cyberpunk2077`
(directory holding the executable plus `Frameworks/*.dylib`). Writes
`build/phase8/import-gaps.json` and prints a per-library table: library, number of
imports, number missing. Libraries absent on iOS are marked.

**Output meaning.** `CONTEXT.md` reports about 75 real gaps. Its note says the
`<weak-def-coalesce>` and libbz2 entries are false positives.

**Steps.**

1. `image_imports(path)` runs `otool -L` to map install names to library file names, then
   `xcrun dyld_info -imports` to list `(symbol, library)` pairs. Imports from `@`-prefixed
   (guest-to-guest) libraries are skipped.
2. For each import, `exports(lib)` returns the symbol set for that library. If the symbol
   is missing, or the library has no `.tbd` (`exports` returns `None`), it is recorded as a gap.
3. `main()` writes the gaps per library to JSON and prints the summary table.

**Key functions.**

| Name | What it does |
|------|--------------|
| `tbd_path(install)` | Maps `/System/Library/Frameworks/X.framework/...` and `/usr/lib/...` install names to the iOS SDK `.tbd` path. |
| `exports(install, seen)` | Returns the exported symbol set, including ObjC class/metaclass/ivar/EH symbols, and follows `reexported-libraries`. Caches results. Returns `None` for libraries not on iOS. Handles versioned names like `libbz2.1.0`. |
| `image_imports(path)` | Returns `(symbol, library)` pairs from `dyld_info -imports`. |
| `main()` | Builds the gap map and prints the table. |

---

## 8. `phase7/tools/device.py` (Phase 7, STKHost)

**Purpose.** The Phase 7 driver for SuperTuxKart on the phone. `phone.py` reuses its
helpers. Its own `deploy` and `install` target `localconfig.bundle('STKHost')`
(`<your-bundle-prefix>.STKHost`); in the author's original setup that App ID (under the old
`research.machprobe` prefix) ended up belonging to another project, which is why Cyberpunk has
its own. Do not use `device.py deploy` or `install` for Cyberpunk.

**Usage.** `python3 phase7/tools/device.py launch | deploy [--no-build] | install | report | logs [N] | args ...`

**Module-level helpers (used by `phone.py`).**

| Name | What it does |
|------|--------------|
| `dc(*args, check=True)` | Runs `xcrun devicectl`; on failure raises `RuntimeError` with the last 800 characters of output (unless `check=False`). |
| `pull(name, dest=None)` | Copies `Documents/<name>` from the app container to `build/phase7/<basename>` and returns its text (or `''`). |
| `push(local, remote)` | Copies a local file to `Documents/<remote>` in the app container. |
| `report()` | `pull('runtime.json')` parsed as JSON, or `{}`. |

`UDID` (`<DEVICE-UDID>`) is loaded from `machprobe.local.json` when the module is imported, and
`BUNDLE` defaults to the STKHost App ID. Both are module globals read at call time, which is
why `phone.py` can change `BUNDLE`. The signing identity is also read from the config.

**`deploy` steps (differs from `phone.py deploy`).**

1. Runs `phase6/tools/build.py --quick` unless `--no-build` is given.
2. Picks the newest provisioning profile for the STKHost App ID with
   `localconfig.profile(BUNDLE)` (exact App ID match, as `phone.py` does for its own).
3. `ditto`s `build/phase6-runtime/Payload/STKHost.app` to `build/phase7/STKHost.app`,
   embeds the profile, signs dylibs and app, and installs.

**`report` keys.** `pid`, `stage`, `error`, `exception`, `sdl_error`, `rebases`, `binds`,
`initializers`, `frame_window`, `base_vertex`, `verified_images`, then the last 12 events
and up to 25 stack lines. `base_vertex` relates to the VM bug in `CONTEXT.md`.

**Other subcommands.** `launch` (`--terminate-existing`), `install` (reinstalls
`build/phase7/STKHost.app`), `logs` (same as `phone.py logs`), `args` (writes and pushes
`arguments.json`).
