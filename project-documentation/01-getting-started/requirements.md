# Requirements

## Checklist

| Item | Requirement |
|------|-------------|
| Mac | Apple silicon (the project was developed on an M2). The scripts use `xcrun`, `xcodebuild`, `codesign`, `security`, `lipo`, `ditto` and Python 3. |
| Xcode | A full Xcode install (project developed with Xcode 27), not only Command Line Tools. `devicectl` ships with Xcode. |
| iPhone | A physical iPhone with **Developer Mode** enabled. The headline result is on an iPhone 18 Pro (iOS 27.0.1). |
| Cable | A USB cable. All scripts talk to the phone over USB through `xcrun devicectl`. |
| Apple account | A free Apple ID / Personal Team is enough. Paid membership is not required. |
| Phone storage | About **65 GB free** for Cyberpunk (the game folders are ~61 GB) plus room for the app itself. |
| Game | Your own copy of Cyberpunk 2077 on Steam, **macOS build**, installed on the Mac. |

## Check everything with `setup.py doctor`

```sh
python3 phase8/tools/setup.py doctor
```

`doctor` prints a PASS or FAIL line per check, with the fix under each FAIL.
Fix the FAILs from the top down and run it again until it prints `ALL GOOD`.
It checks, in order: the Mac is Apple silicon; Xcode is at
`/Applications/Xcode.app`; the macOS game is installed under Steam; the Steam
build is 20383525; the game binaries are prepared (`prepare-game`);
`machprobe.local.json` exists (`config`); an "Apple Development" signing
identity is in the keychain; Xcode is signed in to a developer team; an iPhone
is paired. Once the config exists it also checks that the configured iPhone is
visible and has Developer Mode on, that the configured signing identity is
still in the keychain, and that the Cyberpunk provisioning profile is valid
(days left), lists your phone, and has the increased-memory-limit entitlement.
It cannot read the phone's free space; it only prints a reminder to check for
about 65 GB. The same checklist, with the exact words to tell a user, is in
[AGENT-SETUP.md](../../AGENT-SETUP.md) (Stage 1).

Doing the by-hand parts once (Xcode, Apple ID, Steam, Trust, Developer Mode)
is Part 2, step 1 of the [top-level README](../../README.md).

## Mac and Xcode

- The scripts set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
  for their `xcodebuild`, `devicectl` and `lipo` calls, so Xcode must live at
  that path (`doctor` checks it).
- If `xcode-select -p` prints `/Library/Developer/CommandLineTools`, commands
  you run by hand (`xcodebuild`, `xcrun --sdk iphoneos ...`) will fail or
  pick the wrong toolchain. Export this in every shell you use:

  ```sh
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  xcrun --sdk iphoneos --show-sdk-path   # should print an iPhoneOS SDK path
  ```

  (`setup.py` and the tools under `phase8/tools/` set it themselves; this
  only matters for commands you type by hand.)
- Open Xcode once, accept the license, and sign in with your Apple ID under
  Settings > Accounts so `setup.py profile` can create a provisioning profile
  (see [provisioning.md](provisioning.md)). You never give your Apple ID
  password to a script or an AI agent: you sign in to Xcode yourself.

## iPhone

1. Connect by USB, unlock, and tap Trust.
2. Settings > Privacy & Security > Developer Mode > on (the phone restarts).
3. After the first install, trust your developer certificate if iOS asks
   (Settings > General > VPN & Device Management).
4. `python3 phase8/tools/phone.py check` prints the device name, iOS version
   and `devmode:` status once `setup.py config` has been run.

You do not look up or paste your UDID: `python3 phase8/tools/setup.py config`
finds the paired iPhone with `devicectl` and stores its `<DEVICE-UDID>` in
`machprobe.local.json` (see [provisioning.md](provisioning.md)). If you want to
see it yourself, `xcrun devicectl list devices` or Xcode's Devices window
shows it.

## Free Apple developer account: what works

| Limit / entitlement | Free Personal Team |
|---------------------|--------------------|
| Provisioning profile lifetime | **7 days**, then the app stops launching until re-signed |
| New App IDs | **10 per week** (each game here gets its own, so do not waste them) |
| `com.apple.developer.kernel.increased-memory-limit` | **Works.** Raises the app limit from ~3.44 GB to roughly 6.0-6.4 GB available. Required for Cyberpunk. |
| `com.apple.developer.kernel.increased-debugging-memory-limit` | **Does not work** on the free team |
| `com.apple.developer.kernel.extended-virtual-addressing` | **Does not work** on the free team |

Entitlements that end up in the profile on the free team: application-identifier,
team-identifier, get-task-allow, keychain-access-groups, plus increased-memory-limit
when the Provisioner project requests it (it does:
`phase7/signing/Provisioner/Provisioner.entitlements`).

Without extended virtual addressing iOS gives the app about 66 GB of address
space; the Cyberpunk layer works around RED engine's huge reservations (see
[../04-cyberpunk/](../04-cyberpunk/)).

## The game

- Steam app 1091500, macOS build. The supported build is 20383525 (`doctor`
  reads the build number from Steam's `appmanifest_1091500.acf`). Other builds
  are not supported: `setup.py prepare-game` compares your binaries with the
  committed hash list `phase8/cyberpunk-macos-20383525.sha256` and stops if
  they differ (see [build-and-install.md](build-and-install.md) and
  [troubleshooting.md](troubleshooting.md)).
- Default install location expected by the scripts:
  `~/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077/`
  containing `Cyberpunk2077.app`, `archive/`, `engine/`, `r6/`. If yours is
  elsewhere, `doctor` and `prepare-game` accept `--steam <path to the
  'Cyberpunk 2077' folder>`; the data copy tools use the default location.
- Game bytes are never modified or redistributed; the host verifies hashes at
  launch.
- Do not run the game on the Mac through machprobe (`--run` on the Mac
  harness). Load-only checks are fine.

## Not required

- A paid developer account, a jailbreak, or JIT: the game code is already
  arm64 and is loaded as-is.
- A second device: the optional vphone VM is only used for earlier phases.
