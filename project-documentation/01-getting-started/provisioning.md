# Provisioning: config, profile, App ID, expiry

iOS only runs a sideloaded app if it is signed by your certificate **and**
embeds a provisioning profile for its App ID that lists your device. With a
free account Xcode creates this for you; machprobe uses a tiny throw-away
Xcode project, `phase7/signing/Provisioner.xcodeproj`, purely to make Xcode
generate the profile. Two `setup.py` commands cover this page:

```sh
python3 phase8/tools/setup.py config     # once: remember your phone, certificate, team
python3 phase8/tools/setup.py profile    # now, and again every 7 days
```

Both are safe to re-run. The same steps for a person doing it by hand are in
Part 2 of the [top-level README](../../README.md); the agent version
(including what to say when a prompt appears) is Stages 2 and 4 of
[AGENT-SETUP.md](../../AGENT-SETUP.md).

## Step 1: `setup.py config` (your personal values)

Prerequisites: Xcode signed in to your Apple ID, the iPhone connected,
unlocked and trusted (see [requirements.md](requirements.md); `setup.py
doctor` checks all of it).

```sh
python3 phase8/tools/setup.py config
```

Nothing personal is hard-coded in the scripts and nothing needs editing.
`config` detects four values and writes them to `machprobe.local.json` in the
repository root:

| Key | Value | Detected from |
|-----|-------|---------------|
| `device_udid` | `<DEVICE-UDID>` | the physical iPhone/iPad paired with the Mac (`xcrun devicectl list devices`) |
| `signing_identity` | `<SIGNING-IDENTITY-SHA1>` (40 hex characters) | the "Apple Development" identity in your keychain (`security find-identity -v -p codesigning`) |
| `team_id` | `<TEAM-ID>` | the teams your Xcode is signed in to (Xcode's `IDEProvisioningTeamByIdentifier` preference) |
| `bundle_prefix` | `<your-bundle-prefix>` | default `machprobe.t<team id, lowercased>` |

The file is git-ignored. Do not commit it or paste its contents into shared
places. Every script reads it through `phase7/tools/localconfig.py`; if it is
missing or incomplete they stop with a message telling you to run `config`.

If there is more than one candidate for a value (two phones, two certificates,
two teams), `config` writes nothing. It prints `choose --udid:` (or
`--identity`, `--team`) followed by the candidates, and you re-run it with the
flag, for example:

```sh
python3 phase8/tools/setup.py config --udid <DEVICE-UDID>
```

`--udid`, `--identity`, `--team` and `--bundle-prefix` are the overrides. If
nothing was found at all, the list says what to do (connect and trust the
phone; add the Apple ID in Xcode > Settings > Accounts; add an Apple
Development certificate under Manage Certificates). When the config file
already exists, re-running `config` keeps its `bundle_prefix` unless you pass
`--bundle-prefix`, so the App ID does not change by accident.

## Why each game gets its own App ID

An App ID is the bundle identifier. For Cyberpunk it is always
`<your-bundle-prefix>.CP2077` (`localconfig.bundle('CP2077')`); the default
prefix is built from your team ID because App IDs are unique across all Apple
accounts, so a prefix that is unique to your team avoids clashes. iOS keys the installed app and its data container to the App ID. If
two projects install under the same ID, the second install **replaces the first
and wipes its data container**.

That happened once in the author's setup: another project was installed over
the SuperTuxKart host, which erased the Cyberpunk game data and saves stored
under that ID. Since then Cyberpunk has its own ID, and the SuperTuxKart host
(`phase7/tools/device.py`) uses a different one, `<your-bundle-prefix>.STKHost`.

Rules of thumb:

- One game = one App ID. Never install a different project under it.
- A free account can create **10 App IDs per week**. `setup.py profile`
  registers the Cyberpunk App ID the first time and reuses it afterwards; do
  not change the prefix without a reason, because a new prefix is a new App ID
  (and a new, empty data container).
- To use your own prefix, pass `--bundle-prefix <your-bundle-prefix>` to
  `config`. There is no other place to change it.

## Step 2: `setup.py profile` (make or refresh the profile)

```sh
python3 phase8/tools/setup.py profile
```

Keep the phone connected and unlocked. It prints `registering App ID ... for
team ...`, runs Xcode's build with automatic provisioning, and ends with `OK:
profile <file>, expires <date>`. The profile it creates includes the
`com.apple.developer.kernel.increased-memory-limit` entitlement, because the
Provisioner target's entitlements file (`Provisioner/Provisioner.entitlements`)
asks for it. The stub app may fail at the link step; that is expected, and the
script only checks that a profile for the Cyberpunk App ID exists afterwards.

If it prints `no profile was created`, it shows the `error` lines from
`xcodebuild` and the usual causes: Xcode not signed in, the phone not
connected or not registered, or the 10-App-IDs-per-week limit on free
accounts. See [troubleshooting.md](troubleshooting.md).

### What `setup.py profile` runs

For reference (you do not need to type this), it is this `xcodebuild` call,
with `DEVELOPER_DIR` set to Xcode, your `team_id` and the Cyberpunk App ID
filled in from `machprobe.local.json`:

```sh
xcodebuild -project phase7/signing/Provisioner.xcodeproj -configuration Debug -sdk iphoneos \
  -allowProvisioningUpdates SYMROOT=build/setup/prov-build OBJROOT=build/setup/prov-obj \
  PRODUCT_BUNDLE_IDENTIFIER=<your-bundle-prefix>.CP2077 DEVELOPMENT_TEAM=<TEAM-ID> build
```

- `-allowProvisioningUpdates` lets `xcodebuild` register the App ID and
  download/create the profile using the account Xcode is signed in to.
- `PRODUCT_BUNDLE_IDENTIFIER=` gives the profile its App ID and
  `DEVELOPMENT_TEAM=` its team. The committed `project.pbxproj` carries no team,
  so there is nothing to edit in the Xcode project.
- The target is a stub (`Provisioner/main.m`); only the profile matters.

To look at the result yourself:

```sh
ls -t ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/ | head
security cms -D -i ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/<UUID>.mobileprovision
```

Look for `application-identifier` = `<TEAM-ID>.<your-bundle-prefix>.CP2077`, an
`ExpirationDate` about 7 days out, and the memory entitlement. `setup.py
doctor` runs the equivalent checks (profile valid with N days left, includes
this iPhone, has the memory entitlement).

## How the tools pick the profile

`phase7/tools/localconfig.py` `profile(bundle_id)` searches
`~/Library/Developer/Xcode/UserData/Provisioning Profiles/*.mobileprovision`,
decodes each with `security cms -D`, keeps those whose `application-identifier`
(minus the team prefix) equals the **exact** App ID, and takes the newest by
modification time. It is not "newest profile overall", so profiles for other
apps do not interfere. If none matches it stops with `no provisioning profile
for <bundle id>: run python3 phase8/tools/setup.py profile`. The profile is
looked up when `phone.py deploy` runs (and by `doctor`), not when `phone.py`
starts.

`deploy` (that is, `setup.py install`) embeds that profile as
`embedded.mobileprovision`, writes the profile's entitlements to a plist, and
signs with them using the `signing_identity` from the config (see
[build-and-install.md](build-and-install.md)).

## Expiry and re-signing

- Free-team profiles last **7 days**. `setup.py install` prints
  `signed (profile expires ...)` so you can see the date, and `setup.py doctor`
  shows the days left.
- After expiry the app **stays installed and its data stays on the phone**,
  but it will no longer launch.
- To renew, run `python3 phase8/tools/setup.py profile`, then
  `python3 phase8/tools/setup.py install`. `profile` refreshes the profile for
  the same App ID, so you do not need to rebuild.
- Installing over the same App ID **keeps the container**: the ~60 GB of
  game data, saves and settings survive.
- **Never delete the app** from the home screen to "fix" signing: deleting
  removes the data container (game data, saves, settings, EULA file).
- Back up what is not reproducible before any risky step: the game data is
  your Steam install on the Mac; saves can be pulled with
  `devicectl device copy from` (see [copying-game-data.md](copying-game-data.md)).
