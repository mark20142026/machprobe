# Build and install

Prerequisites: [requirements](requirements.md) (`setup.py doctor` is happy up
to this point), `setup.py config` done, and a valid
[profile](provisioning.md) (`setup.py profile`). All commands run from the
repository root; the scripts set `DEVELOPER_DIR` themselves:

```sh
cd ~/machprobe
python3 phase8/tools/setup.py prepare-game   # 1. your 5 game binaries, verified
python3 phase8/tools/setup.py build          # 2. build the iOS app
python3 phase8/tools/setup.py install        # 3. sign + install on the iPhone
```

Each step is safe to re-run. Part 2 of the [top-level README](../../README.md)
shows the same sequence; [AGENT-SETUP.md](../../AGENT-SETUP.md) (Stages 3, 5 and
6) is the agent version, including that an agent asks you before `install`.

## 1. `setup.py prepare-game` (one-time, and after a game update)

```sh
python3 phase8/tools/setup.py prepare-game
python3 phase8/tools/setup.py prepare-game --steam "<path to the 'Cyberpunk 2077' folder>"   # only if not in the default Steam location
```

`build.py` does not read the Steam install directly. It needs the five game
images in `build/cyberpunk/thin/` plus a `SHA256SUMS` file. `prepare-game`
creates exactly that from your own Steam install and checks it against the
hashes committed in `phase8/cyberpunk-macos-20383525.sha256` (Steam build
20383525):

```
build/cyberpunk/thin/Cyberpunk2077
build/cyberpunk/thin/Frameworks/libBink2MacArm64.dylib
build/cyberpunk/thin/Frameworks/libGameServicesSteam.dylib
build/cyberpunk/thin/Frameworks/libREDGalaxy64.dylib
build/cyberpunk/thin/Frameworks/libsteam_api.dylib
build/cyberpunk/thin/SHA256SUMS
```

On success it prints `OK: 5 binaries copied from your install and verified
(build 20383525)`. `build/` is git-ignored; these copies are yours and are never
committed.

What it does, so you can read its messages:

1. Deletes and recreates `build/cyberpunk/thin/`.
2. Copies `Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077` and the four
   `Contents/Frameworks/*.dylib` files listed in the hash file. A file that is
   not a universal binary is copied as it is.
3. `libsteam_api.dylib` ships **universal** (x86_64 + arm64) and machprobe loads
   only the arm64 slice, so `prepare-game` extracts it with
   `lipo -thin arm64`. A plain `cp` of that file does **not** match the
   committed hash; do not copy the files by hand.
4. Compares the SHA-256 of every file in `thin/` with the committed list. If
   all five match it writes the list into `thin/SHA256SUMS`.

If a hash differs, it prints `these binaries differ from the supported build
20383525` and the names, and exits with status 1 without writing
`SHA256SUMS`. That means your Steam copy is a different game build; machprobe
cannot be made to work with it by copying files differently (see
[troubleshooting.md](troubleshooting.md)). `not found: <path>` means the game
is not installed in the default location (install it via Steam, or use
`--steam`); `missing in your install: <file>` means the install is incomplete
(verify the game files in Steam).

Optionally check that the loader accepts the images on the Mac (load only;
never add `--run`):

```sh
make -C phase8
build/phase8/cp-load build/cyberpunk/thin Cyberpunk2077
```

## 2. `setup.py build`

```sh
python3 phase8/tools/setup.py build            # full
python3 phase8/tools/setup.py build --quick    # reuse unchanged guest containers
```

`setup.py build` runs `phase8/tools/build.py` (extra arguments such as
`--quick` are passed through) and takes a few minutes. It ends by printing the
path of `build/phase8-runtime/CP2077Host.ipa`. Do not share or upload that file:
it contains your copy of the game. `build.py` needs `build/cyberpunk/thin/`
from step 1; without it, run `prepare-game` first.

What `build.py` does (read from the script):

1. Re-hashes each image and asserts it equals the `SHA256SUMS` entry, so only
   the preserved release bytes are packaged.
2. Wraps each guest image in its own signed iOS container dylib
   (`__TEXT,__guest` + `__DATA,__guest`, with a rebased `__unwind_info`),
   reusing Phase 6's `container()`. `--quick` skips containers whose hash
   is unchanged.
3. Writes `target.json` (release name + image manifest) into the app.
4. Compiles the runtime and the lean Phase 8 host (`phase8/host/Main.m`,
   `phase8/runtime/*`, shared AppKit/Metal adapters from earlier phases) for
   `arm64-apple-ios14.0` with `-O3 -flto=thin`, and links `CP2077Host`
   against Foundation, UIKit, Metal, QuartzCore, GameController, etc.
5. Writes `Info.plist`: bundle id `<your-bundle-prefix>.CP2077` (from
   `machprobe.local.json`), display name "Cyberpunk 2077", landscape only,
   `UIFileSharingEnabled`, game-controller support,
   `CADisableMinimumFrameDurationOnPhone` (allow 120 Hz).
6. If your Steam install has `Cyberpunk2077.app/Contents/Resources/AppIcon.icns`,
   builds the app icon from it with `phase8/tools/make_icon.swift`. The icon is
   generated from your copy and never stored in the repo.
7. Ad-hoc signs the bundle and zips `build/phase8-runtime/CP2077Host.ipa`.

Outputs: `build/phase8-runtime/Payload/CP2077Host.app` (used by install) and
`build/phase8-runtime/CP2077Host.ipa`.

## 3. `setup.py install`

Keep the phone connected, unlocked and plugged in.

```sh
python3 phase8/tools/setup.py install
```

`setup.py install` runs `python3 phase8/tools/phone.py deploy`. It needs the
built app from step 2 and the profile from `setup.py profile`; your device,
signing identity and App ID come from `machprobe.local.json`, so there is
nothing to edit in `phone.py` or `device.py`. It prints `signed (profile
expires <date>)` and installs the app. If no profile matches, it stops with `no
provisioning profile for <bundle id>: run python3 phase8/tools/setup.py
profile` (see [troubleshooting.md](troubleshooting.md)).

The first time, iOS asks you to trust your developer certificate: on the
iPhone, Settings > General > VPN & Device Management > your Apple ID under
Developer App > Trust.

What `phone.py deploy` does internally:

1. Finds the newest profile for `<your-bundle-prefix>.CP2077` and reads its
   entitlements and expiry.
2. Copies `build/phase8-runtime/Payload/CP2077Host.app` to
   `build/phase8-signed/CP2077Host.app` (`ditto`) and embeds the profile as
   `embedded.mobileprovision`.
3. Writes the profile's `Entitlements` to
   `build/phase8-signed/entitlements.plist`.
4. Signs every `Frameworks/*.dylib`, then the app itself with
   `--entitlements`, using your `<SIGNING-IDENTITY-SHA1>`
   (`codesign --force --timestamp=none`).
5. Prints `signed (profile expires <date>)` and runs
   `xcrun devicectl device install app --device <DEVICE-UDID> ...`.

Installing over an existing copy keeps the data container. The phone must be
connected and unlocked.

Other `phone.py` subcommands (used later): `push-data`, `launch`, `report`,
`logs [N]`, `args ...`, `debug on|off`. See
[../05-tools-and-diagnostics/](../05-tools-and-diagnostics/).

## Quick sanity check after install

The app icon "Cyberpunk 2077" should appear on the home screen. If iOS says
the developer is not trusted, trust the certificate in Settings (see
[requirements.md](requirements.md)). Next: [copying-game-data.md](copying-game-data.md).
