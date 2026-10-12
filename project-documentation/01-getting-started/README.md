# 01 - Getting started

> Not piracy: no game files are included; you need your own copy. MIT-licensed. See [../NOTICE.md](../NOTICE.md).


Everything needed to take your own Steam copy of Cyberpunk 2077 (macOS build)
from "nothing installed" to "running on an iPhone". Read the files in this
order; each one assumes the previous one is done.

One script drives the whole setup: `phase8/tools/setup.py`. Each page below
leads with the `setup.py` command for its step and keeps what the lower-level
scripts do internally as secondary detail. The same steps, written for a
person without an agent, are in
[Part 2 of the top-level README](../../README.md); an AI coding agent can follow
[AGENT-SETUP.md](../../AGENT-SETUP.md) and do them with you.

| # | File | What it covers |
|---|------|----------------|
| 1 | [requirements.md](requirements.md) | Hardware, Xcode, Apple account limits, storage, owning the game, `setup.py doctor` |
| 2 | [provisioning.md](provisioning.md) | `setup.py config` and `setup.py profile`: your local config, the provisioning profile, why each game has its own App ID, expiry and re-signing |
| 3 | [build-and-install.md](build-and-install.md) | `setup.py prepare-game`, `setup.py build`, `setup.py install` |
| 4 | [copying-game-data.md](copying-game-data.md) | `setup.py copy-data` (~61 GB, resumable) and `setup.py restore` (saves and settings) |
| 5 | [first-launch.md](first-launch.md) | `setup.py launch`, the EULA screen, what loading looks like, recommended in-game settings |
| 6 | [troubleshooting.md](troubleshooting.md) | Failed `doctor`/`config`/`prepare-game`/`profile` steps, interrupted copies, expired profile, memory kills, the VSync trap, replaced app |

## Short version

Do these by hand once (details in [requirements.md](requirements.md)): install
Xcode and open it once, sign in to Xcode with your Apple ID (Settings >
Accounts), install Cyberpunk 2077 (macOS) in Steam on this Mac, plug in the
iPhone and tap Trust, and turn on Developer Mode on the phone. Then, from the
repository root (every step is safe to re-run):

```sh
cd ~/machprobe                                      # wherever you cloned it
python3 phase8/tools/setup.py doctor                # PASS/FAIL checklist, prints the fix for each FAIL
python3 phase8/tools/setup.py config                # detect iPhone, signing identity, team -> machprobe.local.json
python3 phase8/tools/setup.py prepare-game          # copy + verify the 5 game binaries from your Steam install
python3 phase8/tools/setup.py profile               # register the App ID, create the 7-day provisioning profile
python3 phase8/tools/setup.py build                 # build the iOS app
python3 phase8/tools/setup.py install               # sign + install on the iPhone
python3 phase8/tools/setup.py copy-data             # ~61 GB of game data; run again if interrupted
python3 phase8/tools/setup.py restore               # your Mac saves + recommended settings (never overwrites)
python3 phase8/tools/setup.py launch                # or tap the icon on the phone
```

`python3 phase8/tools/setup.py help` prints this list. Every 7 days (free
Apple account) run `profile` and then `install`; your data and saves stay.

Your device UDID, signing identity, Apple team ID and App ID prefix are not in
any script. `config` writes them to `machprobe.local.json` in the repository
root, which is git-ignored and must not be committed or shared. The docs use
these placeholders: `<DEVICE-UDID>`, `<TEAM-ID>`, `<SIGNING-IDENTITY-SHA1>`,
`<your-bundle-prefix>`, and `~` for your home directory. The scripts set
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` themselves.

Related sections: [architecture](../02-architecture/),
[Cyberpunk specifics](../04-cyberpunk/),
[tools and diagnostics](../05-tools-and-diagnostics/).

No game data is stored in this repository. You must own the game, and
machprobe only ever runs your own retail copy.
