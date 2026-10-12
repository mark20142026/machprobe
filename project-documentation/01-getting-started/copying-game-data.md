# Copying game data to the phone

The app does not contain the game's data. You copy three folders from your
Steam install into the app's data container over USB. Total ~61 GB, so this
is the slowest step (about 40 minutes over USB); plan for it to be
interrupted. Two `setup.py` commands cover this page:

```sh
python3 phase8/tools/setup.py copy-data    # the ~61 GB game data; resumable, verified
python3 phase8/tools/setup.py restore      # your Mac saves + recommended settings; never overwrites
```

Keep the phone plugged in, unlocked and awake while `copy-data` runs (set
Auto-Lock to Never for the duration), keep the Mac awake (`caffeinate -dims`
in another terminal works), and do not open the game yet. The agent version of
these steps is Stages 7 and 8 of [AGENT-SETUP.md](../../AGENT-SETUP.md); the
manual version is Part 2, step 4 of the [top-level README](../../README.md).

## Where things go (inside the app container)

| Content | Source on the Mac | Destination in the container |
|---------|-------------------|------------------------------|
| Game data | `~/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077/{archive,engine,r6}` | `Documents/Cyberpunk 2077/archive`, `.../engine`, `.../r6` |
| Settings | `phase8/config-recommended-UserSettings.json` (optional) | `Library/Application Support/CD Projekt Red/Cyberpunk 2077/UserSettings.json` |
| Saves | `~/Library/Application Support/CD Projekt Red/Cyberpunk 2077/saves` (Steam Cloud copy) | `Library/Application Support/CD Projekt Red/Cyberpunk 2077/saves` |

How the game finds its data: it walks up from its executable path. The layer
returns a virtual path,
`Documents/Cyberpunk 2077/Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077`,
so `archive/`, `engine/` and `r6/` must sit next to a (virtual)
`Cyberpunk2077.app` in `Documents/Cyberpunk 2077/`. The `.app` itself is not
copied; the host provides it. Path lookups are case-insensitive in our layer
(the game asks for `archive/mac`, the install has `archive/Mac`).

The game's Mac-style per-user paths (`~/Library/...`) are mapped to the app's
home directory, which is why saves and settings live under the container's
`Library/Application Support/CD Projekt Red/Cyberpunk 2077/`.

## `setup.py copy-data` (recommended)

```sh
python3 phase8/tools/setup.py copy-data
```

This runs `phase8/tools/push_resume.py archive engine r6`. It needs the app
installed (`setup.py install`) so the data container exists, and it reads the
game from the default Steam location. Your device and App ID come from
`machprobe.local.json`; there is nothing to edit in the script. It prints
progress per file (GiB done, MB/s, file name) and ends with
`ALL DATA ON PHONE`. **If it is interrupted for any reason, run it again**: it
skips files that are already complete.

Behavior (from the script), per folder (`archive`, `engine`, `r6`, in that
order):

1. Lists local files and asks the phone for the files already present under
   `Documents/Cyberpunk 2077/<folder>` (`devicectl device info files`).
2. **Fresh phone:** if the phone has no files for the folder, it prints `<folder>:
   new on the phone, creating folders ...` and first copies a skeleton of the
   folder tree: the smallest file of every subfolder, hard-linked into
   `build/phase8-runtime/seed/<folder>` (no extra disk space; a normal copy if
   linking fails). Copying a folder creates its whole tree on the phone,
   while a single-file copy into a missing folder may not. It then lists the
   phone again. (A listing that fails, for example because the phone is locked,
   looks the same as an empty folder; keep the phone unlocked.)
3. A file is skipped when the phone's file has the **same size**; only
   missing or different-size files are copied.
4. Copies **one file at a time**, smallest first, with up to 4 attempts per
   file (5 s pause between). It prints GiB done, MB/s and the file name.
5. After each folder it lists the phone again and **verifies sizes**; any
   mismatch prints `MISMATCH [...]` and exits with status 1. Success ends with
   `ALL DATA ON PHONE`.

Verification is by size only, not checksum. Practical notes:

- The script runs `devicectl` itself; **do not use other `devicectl` commands
  at the same time** (its docstring says so).
- Use a good cable and a direct port. If the folder list is larger than
  expected, check phone free space (~65 GB needed).
- `setup.py copy-data` always copies all three folders. To copy only some,
  run the script directly: `python3 phase8/tools/push_resume.py r6 engine`.

### Older alternative: `phone.py push-data` (simple, not resumable)

```sh
python3 phase8/tools/phone.py push-data
```

Copies `r6`, `engine`, then `archive` (small folders first) with one
`devicectl device copy to` per folder and prints the time for each. It does not
skip existing files or verify. If the cable drops or the Mac sleeps
mid-folder, you must start that folder over. Fine for `r6` and `engine`;
risky for the ~60 GB `archive`. Use `setup.py copy-data` instead.

## `setup.py restore` (saves and settings)

```sh
python3 phase8/tools/setup.py restore                 # saves + recommended settings
python3 phase8/tools/setup.py restore --saves         # only saves
python3 phase8/tools/setup.py restore --settings      # only settings
python3 phase8/tools/setup.py restore --force         # overwrite what is already on the phone (ask yourself first)
```

What it copies, into `Library/Application Support/CD Projekt Red/Cyberpunk 2077/`
in the app container:

- **Saves:** your Mac's `~/Library/Application Support/CD Projekt Red/Cyberpunk 2077/saves`
  (they exist if you played on this Mac or Steam Cloud synced them), staged in
  `build/setup/saves` **without `user.gls`**. The EULA acceptance is per device:
  the game shows the licence screen once on the phone and you accept it there.
  If there is no Mac saves folder it says so and continues (start the game once
  on the Mac via Steam so Steam Cloud downloads them, if you want them).
- **Settings:** `phase8/config-recommended-UserSettings.json` as
  `UserSettings.json` (1564x720, VSync 120, MaximumFPS on at 60, many options
  Low/Off; details in [first-launch.md](first-launch.md)).

Safety rules built in:

- It **never overwrites** saves or `UserSettings.json` that are already on the
  phone; it says `phone already has ...: not touching it` and skips. Only
  `--force` overwrites. The game rewrites `UserSettings.json` whenever you
  change options in-game, so do not force unless you mean to replace what the
  phone has.
- To decide whether something exists it lists the parent folder on the phone.
  If the phone cannot be read (not connected, not unlocked) it prints `cannot
  read the phone (connected and unlocked?): not copying anything` and exits
  with status 1, so a flaky connection cannot cause an overwrite.
- A fresh install (no folder yet) counts as "nothing there" and is copied.

Never write `"60"` as a VSync value; see [troubleshooting.md](troubleshooting.md).

### Manual copies and backups (`devicectl`)

`restore` is a thin wrapper over this `devicectl` pattern, which you can use
for anything else (replace the placeholders):

```sh
xcrun devicectl device copy to --device <DEVICE-UDID> \
  --domain-type appDataContainer --domain-identifier <your-bundle-prefix>.CP2077 \
  --source <local file or folder> \
  --destination "Library/Application Support/CD Projekt Red/Cyberpunk 2077/<name>"
```

To back up from the phone:

```sh
xcrun devicectl device copy from --device <DEVICE-UDID> --domain-type appDataContainer \
  --domain-identifier <your-bundle-prefix>.CP2077 \
  --source "Library/Application Support/CD Projekt Red/Cyberpunk 2077" --destination ./phone-backup
```

Rules learned the hard way: do not overwrite saves already on the phone
without a backup, and never overwrite the phone's EULA acceptance file
`saves/user.gls` with one from elsewhere (if it is missing, the game simply
shows the licence screen once).

## Check the result

```sh
python3 phase8/tools/setup.py launch
python3 phase8/tools/phone.py report     # data_present should list archive/engine/r6 as true
```

Then continue with [first-launch.md](first-launch.md).
