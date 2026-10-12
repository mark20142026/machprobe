# Troubleshooting

Quick lookup. Start with `python3 phase8/tools/setup.py doctor`: it prints a
PASS/FAIL line for each prerequisite with the fix under every FAIL. For deeper
diagnostics (telemetry, memory traces, console runs) see
[../05-tools-and-diagnostics/](../05-tools-and-diagnostics/). The agent version
of the fixes below, worded for a non-technical user, is in
[AGENT-SETUP.md](../../AGENT-SETUP.md).

## A `setup.py` step fails

| Message | What it means and what to do |
|---------|------------------------------|
| `FAIL` lines from `doctor` | Fix them top to bottom using the `fix:` text under each (Xcode, Steam install, signing identity, Xcode account, phone paired, Developer Mode, profile), then run `doctor` again until `ALL GOOD`. |
| `machprobe.local.json is missing: run ... setup.py config` (or `lacks [...]`) | Your personal values are not recorded yet. Run `python3 phase8/tools/setup.py config`. Every script that talks to the phone reads this file, so they all stop with this message until it exists. |
| `config` prints `choose --udid:` / `--identity:` / `--team:` and a list | More than one candidate (or none) was found, so nothing was written. Pick one from the list and re-run, for example `setup.py config --udid <DEVICE-UDID>`; `--identity <SIGNING-IDENTITY-SHA1>` and `--team <TEAM-ID>` work the same way. If a list says `no iPhone found`, connect, unlock and trust the phone; if it says none for the identity or team, sign in to Xcode (Settings > Accounts) and add an Apple Development certificate under Manage Certificates. |
| `prepare-game`: `not found: <path>` | The macOS game is not at the default Steam location. Install it via Steam on this Mac, or run `setup.py prepare-game --steam "<path to the 'Cyberpunk 2077' folder>"`. |
| `prepare-game`: `missing in your install: <file>` | The install is incomplete. In Steam, verify the game's files and try again. |
| `prepare-game`: `these binaries differ from the supported build 20383525` | Your Steam copy is a **different game build** from the one machprobe supports (`doctor` shows your build number). The binaries are verified against `phase8/cyberpunk-macos-20383525.sha256` and nothing is written to `SHA256SUMS`. Do not try to patch or hand-copy files to force it: a plain copy of the universal `libsteam_api.dylib` will not match either (`prepare-game` extracts its arm64 slice itself). Porting a new build is development work, not setup. |
| `no provisioning profile for <bundle id>: run ... setup.py profile` | No Xcode profile exists for your Cyberpunk App ID yet (or the config's prefix changed). Run `python3 phase8/tools/setup.py profile`, then retry `install`. |
| `profile`: `no profile was created` | Xcode could not create the profile. Check that Xcode is signed in, the iPhone is connected, unlocked and registered, and that you have not hit the free-account limit of 10 App IDs per week; the `error` lines from `xcodebuild` are printed. See also [provisioning.md](provisioning.md). |
| `restore`: `cannot read the phone ... not copying anything` | The phone is not connected or is locked. Unlock it, reconnect, run `restore` again. Nothing was copied. |

## USB copy interrupted or very slow

Symptoms: the copy stops with a devicectl error, the phone locks, the Mac
sleeps, or a `retry N <file>` line repeats.

1. Re-run the resumable copy; it skips files whose size already matches:

   ```sh
   python3 phase8/tools/setup.py copy-data
   ```

   It retries each file 4 times, then exits with `FAILED <file>`; just run it
   again. A final `verify OK` per folder and `ALL DATA ON PHONE` means done.
   On a fresh phone the first thing it does per folder is create the folder
   tree (`new on the phone, creating folders ...`); that is normal.
2. Keep the phone unlocked; use a direct cable and port, no hub.
3. Keep the Mac awake (`caffeinate -dims`).
4. Do not run other `devicectl` commands during the copy (the script says so).
5. `MISMATCH [...]` after a folder: re-run once; if the same file keeps
   failing, check phone free space (about 65 GB needed) and that the file on
   the Mac is intact (verify the game in Steam).
6. Plain `phone.py push-data` cannot resume; use `setup.py copy-data`
   (`push_resume.py`) instead.

## Profile expired (app will not open)

Symptom: the app is installed but fails to open or iOS says the developer
profile is no longer valid; free profiles last 7 days. The app and data are
still on the phone.

1. Regenerate the profile (see [provisioning.md](provisioning.md)):

   ```sh
   python3 phase8/tools/setup.py profile
   ```
2. `python3 phase8/tools/setup.py install` (installs over the same App ID).
3. **Do not delete the app**; that wipes the ~60 GB of data and the saves.

`setup.py doctor` shows how many days the profile has left. If `install` stops
with `no provisioning profile for <bundle id>`, no profile in
`~/Library/Developer/Xcode/UserData/Provisioning Profiles/` matches your
Cyberpunk App ID exactly; `setup.py profile` creates one. If it cannot, you
may have hit the free-account limit of 10 App IDs per week; wait, or keep the
prefix you already used (`setup.py config --bundle-prefix <your-bundle-prefix>`)
rather than creating a new App ID.

## Killed for memory (jetsam)

Symptoms: the game disappears back to the home screen, usually during heavy
scenes such as a car crash, fast driving, or right after a world load.
`phone.py report` shows `memory_available_bytes` very low (a kill was
recorded at roughly 265 MB free), and `error`/`stage` may be missing because
the process was killed externally.

- Confirm the profile includes the increased-memory-limit entitlement
  (it should: see [requirements.md](requirements.md); `setup.py doctor`
  checks it). Without it the limit is only ~3.44 GB. `install` signs with
  whatever entitlements the profile holds, so a profile made without the
  Provisioner's entitlements file will not raise it; re-run
  `setup.py profile`.
- Lower memory pressure: use the recommended settings (Low textures, low
  resolution 1564x720), close other apps, restart the phone, relaunch.
- Known limits: even with 6 GB the city reaches ~2.6 GB GPU plus ~3.1 GB CPU
  with only ~450 MB free, and a slow memory creep was observed. A dynamic memory
  governor is on the roadmap
  ([../06-policies-and-roadmap/](../06-policies-and-roadmap/)).
- Tuning knobs (advanced) can be placed in `Documents/env.json` as
  `{"MP_NAME":"value"}`; the host applies it before startup (for example
  `MP_MEMSIZE_GB`, `MP_SPILL_CAP_MB`). See
  [../04-cyberpunk/](../04-cyberpunk/) before changing them.

## Stuck at 30 fps (the VSync trap)

The VSync option is a dynamic list ("120", "30", ...). `"60"` is not a valid
entry, and writing it into `UserSettings.json` silently caps the game at 30.
Fix: set **VSync = 120** in the in-game video menu (or in the JSON) and use
**Maximum FPS** (on, 60) for the cap. Details in
[first-launch.md](first-launch.md). Related: an uncapped phone throttles
from heat within minutes; a 40 or 60 cap helps.

## `xcode-select`, `devicectl` or `xcrun` not found / wrong

- `xcrun: error: unable to find utility "devicectl"` or `xcodebuild`
  complaining that it requires Xcode: `xcode-select -p` points at
  CommandLineTools. In each shell:

  ```sh
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  xcrun devicectl --version
  ```

  (or `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`).
  The Python tools already pass this variable to their `devicectl` calls, but
  it must also be correct for your own `xcodebuild`/`xcrun` commands, and
  Xcode must really be at that path.
- Device not found: check the cable, unlock the phone, tap Trust, confirm
  Developer Mode. `setup.py doctor` says whether the phone configured in
  `machprobe.local.json` is visible; if you changed phones, re-run
  `setup.py config` (add `--udid <DEVICE-UDID>` if it asks you to choose).
  `python3 phase8/tools/phone.py check` is a quick test.
- `codesign` or `security` errors: `doctor` reports `the configured signing
  identity is in the keychain`; if it fails (for example after a certificate
  was renewed), re-run `setup.py config` so `machprobe.local.json` holds the
  current `<SIGNING-IDENTITY-SHA1>`. You can compare with
  `security find-identity -v -p codesigning`.

## App replaced by another install with the same App ID

Symptom: the icon or name changed, the game data is gone, and
`phone.py report` shows `data_present` false for all folders.

Cause: something else was installed with the same bundle identifier;
iOS treats it as an update and wipes the container. This happened in the
author's setup when another project was installed over the SuperTuxKart host's
App ID.

Prevention and recovery:

1. Cyberpunk must have its own App ID (`<your-bundle-prefix>.CP2077`, which
   `setup.py config` sets up); never install another project under it.
2. Recover by re-running `setup.py install`, then `setup.py copy-data` for the
   data (the Steam install on the Mac is the source of truth), then
   `setup.py restore` for the saves and settings, or copy them back from your
   backups ([copying-game-data.md](copying-game-data.md)).
3. Ask collaborators to use their own bundle prefix (the default
   `machprobe.t<team id>` is already unique per team); free accounts allow
   only 10 new App IDs per week, so choose IDs once.

## Other quick checks

- Game files rejected: `guest hash mismatch` in `report` means the files are
  not the build the project was prepared for (Steam build 20383525). The
  host verifies hashes at launch and the game bytes are never patched. If
  `setup.py prepare-game` passed, this should not happen; if it did not, see
  the table at the top.
- Logs: `python3 phase8/tools/phone.py logs 60` prints the tail of
  `runtime-stderr.log` and `runtime-stdout.log`.
- Do not run the game on the Mac. Only load-only checks are supported there.
