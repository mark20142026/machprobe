# AGENT-SETUP.md — instructions for an AI agent setting this up for a user

You are helping a person put **their own copy** of Cyberpunk 2077 (macOS, Steam) on **their own
iPhone** with machprobe. Read [AGENTS.md](AGENTS.md) for what the project is and its limits. This
file is your script: what to run, what to tell the user, what to ask, and what never to do.

The user may not be technical. Talk in short, plain sentences. Give one physical instruction at a
time ("Unlock your iPhone and tap Trust") and wait for them to say it's done.

---

## Rules (read first)

1. **Never ask for, type or handle passwords.** The user signs in to Xcode and Steam themselves.
   You never see their Apple ID password, Steam password or 2FA codes.
2. **Ask before** `setup.py install`, `setup.py launch`, and any `--force`. Installing or launching
   interrupts whatever the phone is doing; `--force` overwrites saves/settings.
3. **Never delete the app** from the phone. That erases the 61 GB of game data and the saves.
4. **Never commit** `machprobe.local.json`, anything in `build/`, provisioning profiles, or game files.
   Never print the user's UDID, team ID or signing identity in shared places.
5. **Extra-memory entitlement:** every profile and install must carry
   `com.apple.developer.kernel.increased-memory-limit` (see Stage 4); without it the game is killed
   by iOS within seconds.
6. **Ownership:** confirm the user owns Cyberpunk 2077 and it is installed from *their* Steam
   account on *this* Mac. Never fetch the game from anywhere else. Never use leaked code.
7. **Don't modify game files** and don't try to make a different game build work by patching it.
8. All commands run from the repository root. Use `python3`. Long steps: run in the background if
   your harness supports it, and keep the user informed.

---

## The script, stage by stage

### Stage 0 — Explain and confirm (no commands)

Tell the user, briefly:
- This runs their own Steam copy on their iPhone; nothing is downloaded from elsewhere.
- Expect ~30–40 fps, heat, occasional memory kills, and about an hour of setup (mostly copying 61 GB).
- Free Apple accounts must re-sign every 7 days (2 commands; data is kept).
- **Warn clearly about hardware and heat** (don't skip this):
  - "A recent, high-end iPhone is recommended. It's fully verified on the iPhone 18 Pro; other
    models are untested. Phones older than the iPhone 15 Pro are not recommended (low memory limits)."
  - "Your phone can get **seriously hot** within minutes. Don't play while charging or in hot
    places, keep the 60 (or 40) fps cap, take breaks, and stop if it's uncomfortable to hold.
    It's experimental and at your own risk."
  Make sure the user acknowledges this before continuing.

Ask:
- "Do you own Cyberpunk 2077 on Steam, and is the **macOS** version installed on this Mac?"
  → If not installed: tell them to install it in Steam on this Mac (Library → Cyberpunk 2077 →
  Install; ~65 GB). Wait.
- "Which iPhone do you have?"
  - iPhone 18 Pro → fully verified.
  - iPhone 17 Pro / Pro Max, iPad Pro (M-series) → "will probably work, but it's untested".
  - iPhone 15 Pro / 16 series / 17 (8 GB RAM) → "untested with Cyberpunk, but it may work: a user
    measured ~6 GB allowed per app on an 8 GB iPhone 15 Pro Max with the extra-memory entitlement,
    about the same as the verified 18 Pro. Expect more memory crashes than on 12 GB phones."
  - Best experience: 12 GB iPhones (17 Pro / 18 Pro) or 16 GB iPad Pros.
  - Older than the iPhone 15 Pro (6 GB RAM or less) → "this phone is not recommended due to low
    memory limits: iOS lets one app use only part of the RAM, and the game needs more." Let the user decide, but
    be clear it will very likely not work.
- "Does your iPhone have about 65 GB free?" (Settings → General → iPhone Storage)

### Stage 1 — Doctor

```bash
python3 phase8/tools/setup.py doctor
```

Fix FAILs **top to bottom**. Translate each into one instruction for the user:

| FAIL line | Tell the user |
|---|---|
| Mac has Apple silicon | "This needs an M-series Mac; it won't work on an Intel Mac." Stop. |
| Xcode is installed | "Install Xcode from the Mac App Store (large download), open it once and accept the licence." |
| Cyberpunk 2077 (macOS) is installed | See Stage 0. If installed elsewhere, ask for the folder and pass `--steam "<folder>"`. |
| Steam build is 20383525 | Explain other versions are untested; continue — `prepare-game` decides. |
| game binaries prepared | You fix it in Stage 3. |
| machprobe.local.json exists | You fix it in Stage 2. |
| signing identity / Xcode signed in | "Open Xcode → Settings → Accounts → **+** → Apple ID → sign in. Then select your account → Manage Certificates → **+** → Apple Development." |
| an iPhone is paired | "Plug your iPhone in with a USB cable, unlock it, and tap **Trust This Computer** (enter your phone passcode)." |
| Developer Mode is on | "On the iPhone: Settings → Privacy & Security → Developer Mode → On. It restarts; after restart tap **Turn On** and enter your passcode." (The option appears only after the phone has been connected to Xcode once; if missing, open Xcode → Window → Devices and Simulators with the phone plugged in.) |
| provisioning profile … | You fix it in Stage 4. |

Re-run `doctor` after each fix.

### Stage 2 — Config

```bash
python3 phase8/tools/setup.py config
```
- It auto-detects the iPhone, signing identity and Apple team and writes `machprobe.local.json`.
- If it prints `choose --udid` / `--identity` / `--team`, show the user the choices in plain words
  ("I see two phones: iPhone 18 Pro and iPad — which one?") and re-run with the flag.
- The App ID defaults to `machprobe.t<team>.CP2077` (App IDs are unique across all of Apple).

### Stage 3 — Prepare the game binaries

```bash
python3 phase8/tools/setup.py prepare-game
```
- Copies the game's 5 binaries from the user's Steam install and verifies them against known hashes.
- **If it says the binaries differ:** the user has a different game version. Tell them plainly:
  "Your Cyberpunk version is newer/older than the one machprobe was built for (Steam build
  20383525). It may not work, and I can't change the game to fit." Stop here unless the user is a
  developer who wants to attempt a port of that build (that's engineering work, not setup).

### Stage 4 — Provisioning profile

```bash
python3 phase8/tools/setup.py profile
```
- Uses the user's Xcode account to register the App ID and make a 7-day profile for their phone,
  including the `increased-memory-limit` entitlement.
- The phone must be connected. The link error from the stub project is expected; the script
  checks that the profile exists.
- If it fails: Xcode not signed in → Stage 1. "10 App IDs per 7 days" → tell the user to wait or
  reuse their existing prefix (`config --bundle-prefix <old prefix>`).

> **⚠️ Remember the extra-memory entitlement.** The profile MUST include
> `com.apple.developer.kernel.increased-memory-limit`. It raises the app's memory limit from about
> **~3.4 GB to ~6 GB** (measured on the 12 GB iPhone 18 Pro; a user measured the same ~6 GB on
> an 8 GB iPhone 15 Pro Max). Without it, Cyberpunk (~4.8 GB in the city) is killed
> by iOS within seconds of loading, with no error message, which looks like a random crash.
> - It works on **free** Apple accounts; nothing to buy. It is requested automatically by
>   `phase7/signing/Provisioner/Provisioner.entitlements`, which `setup.py profile` uses.
> - **Check it:** `setup.py doctor` must show `PASS  profile has the increased-memory-limit entitlement`.
>   Run doctor again after every `profile` and before every `install`.
> - If it is missing: re-run `setup.py profile` (don't make profiles with other tools or Xcode
>   projects; they won't request it), then `setup.py install` (ask first).
> - Don't add `increased-debugging-memory-limit` or `extended-virtual-addressing`: free accounts
>   can't use them and profile creation fails.

### Stage 5 — Build

```bash
python3 phase8/tools/setup.py build
```
Takes a few minutes. Ends by printing the path of `CP2077Host.ipa`. **Never share or upload that
file** — it contains the user's copy of the game.

### Stage 6 — Install (ASK FIRST)

Ask: "Ready to install the app on your iPhone? Keep it unlocked."
```bash
python3 phase8/tools/setup.py install
```
Then tell the user: "On the iPhone: Settings → General → VPN & Device Management → tap your Apple
ID under Developer App → **Trust**." (Only needed the first time per Apple ID.)

### Stage 7 — Copy the game data (long)

Tell the user first: "Now I copy about 61 GB to your phone. It takes roughly 40 minutes over USB.
Keep the phone plugged in and unlocked — set Settings → Display & Brightness → Auto-Lock → Never
for now. Don't open the game yet."
```bash
python3 phase8/tools/setup.py copy-data
```
- Copies file by file, retries, and verifies every size at the end (`ALL DATA ON PHONE`).
- If the connection drops, **just run it again**: it skips finished files.
- When done, remind the user to set Auto-Lock back.

### Stage 8 — Saves and settings

Ask: "Do you want your Mac saves on the phone?" Saves come from
`~/Library/Application Support/CD Projekt Red/Cyberpunk 2077/saves` (they exist if the game
was played on this Mac or Steam Cloud synced them).
```bash
python3 phase8/tools/setup.py restore
```
- Copies saves + the recommended settings (1564×720, VSync 120 + 60 fps cap, Motion Blur Off). It never overwrites files
  already on the phone; `--force` does (ask first).
- The licence (EULA) screen appears once on the phone; the user accepts it themselves.

### Stage 9 — Play

Tell the user: "Tap **Cyberpunk 2077** on your home screen. First load takes a while. Accept the
licence screen." Or, if they ask you to, (ASK FIRST) `python3 phase8/tools/setup.py launch`.

Tips to pass on:
- A controller works best (Xbox tested; other Bluetooth game controllers should work): pair it in iPhone Settings → Bluetooth.
- **In the game's settings, keep VSync at 120** (not 60/30) and use the frame-rate cap — a
  wrong VSync value silently caps the game at 30 fps.
- If the phone gets hot, cap at 40 fps.
- **Keep Motion Blur Off** (the recommended settings already do). With motion blur on, a black
  blob can appear near the sun while the camera moves (known bug #30).

### Stage 10 — Aftercare

- **Every 7 days** (free accounts) the app stops opening. Fix: `setup.py profile` then
  `setup.py install` (ask first). Data and saves stay.
- If the game closes by itself **within seconds of loading**: check `setup.py doctor` for the
  increased-memory-limit entitlement first (Stage 4).
- If the game closes by itself later: usually iOS memory limits. Lower settings; report with
  `python3 phase8/tools/phone.py report` and `python3 phase8/tools/phone.py logs 80`.
- More fixes: [project-documentation/01-getting-started/troubleshooting.md](project-documentation/01-getting-started/troubleshooting.md).

---

## Quick reference

| Step | Command | Needs the user? |
|---|---|---|
| Check | `setup.py doctor` | to fix FAILs |
| Config | `setup.py config` | only if several devices/identities |
| Binaries | `setup.py prepare-game` | no |
| Profile | `setup.py profile` | phone connected; doctor must PASS the increased-memory-limit check |
| Build | `setup.py build` | no |
| Install | `setup.py install` | **ask first**; trust developer once |
| Data | `setup.py copy-data` | phone plugged in + unlocked |
| Saves/settings | `setup.py restore` | ask about saves |
| Launch | `setup.py launch` or tap the icon | **ask first** |
