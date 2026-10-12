# machprobe

**Run the Mac version of Cyberpunk 2077 — the one you already own on Steam — on your iPhone.**

machprobe is a translation layer that runs unmodified Apple-silicon Mac games on iOS. It loads
the game's own Mac binary inside a normal iPhone app and supplies the Mac pieces iOS lacks
(AppKit, display modes, file paths, memory rules), while Metal graphics go straight to the
iPhone's GPU.

> **Not piracy.** This repository contains **no game files**. You need your own copy of
> Cyberpunk 2077 for macOS on Steam. machprobe's own code is [MIT-licensed](LICENSE).
> Details: [NOTICE](project-documentation/NOTICE.md).


> [!WARNING]
> **Use a recent, high-end iPhone.** ✅ Fully verified on the **iPhone 18 Pro** (12 GB RAM). Older or
> lower-memory iPhones are likely to crash, run very slowly, or not start at all.
>
> **Serious overheating can happen.** A AAA PC game pushes the phone's chip to its limits. The
> phone can get **very hot within minutes**, slow itself down, dim the screen or close the game.
> Don't play while charging, under a blanket or in direct sun, use a 40–60 fps cap, take breaks,
> and **stop if the phone becomes uncomfortable to hold**. You use this at your own risk; the MIT
> licence comes with no warranty.

<!-- Videos: see project-documentation/videos.md for the shot list. Replace these lines with links once recorded. -->
🎬 **Videos:** *boot to main menu* · *driving in Night City* · *controller and touch* — coming soon.

---

## What to expect

| | |
|---|---|
| ✅ Works | The real game: your saves, the open world, driving, combat, audio, Xbox controller, touch menus |
| 📈 Performance | ~30–40 fps at 1564×720 on an iPhone 18 Pro (built-in benchmark: 39.44 fps) |
| 🔥 Heat | The phone gets hot within minutes; a 60 or 40 fps cap helps |
| ⚠️ Rough edges | Occasional memory kills, basic touch controls, weekly re-signing (free Apple account). Keep **Motion Blur Off**: with it on, a black blob can appear near the sun |
| ⏱ Setup | About an hour, mostly copying 61 GB to the phone |

✅ **Fully verified device: iPhone 18 Pro** (iOS 27.0.1). Built on a MacBook Air M2; Steam macOS build 20383525.
More: [what to expect](project-documentation/00-overview/what-to-expect.md) ·
[tested hardware](project-documentation/00-overview/tested-hardware.md).

## You need

- A **Mac with Apple silicon** (M1 or later) and **Xcode** (free, Mac App Store)
- An **iPhone with ~12 GB RAM** and **65 GB free space**: ✅ iPhone 18 Pro (verified); iPhone 17 Pro
  and iPad Pro (M-series) will probably work. **Models older than the iPhone 15 Pro are not recommended due to low memory limits**
  (6 GB RAM or less: iOS gives the app too little memory); 8 GB Pro models (15 Pro, 16 Pro) are **untested but may work**: users measured ~6 GB allowed with the extra-memory entitlement, like the 18 Pro. **Best experience: 12 GB iPhones (17 Pro / 18 Pro) or 16 GB iPad Pros.**
- A **USB cable** and a free **Apple ID** (used as a developer account in Xcode)
- **Cyberpunk 2077 for macOS** in your Steam library, installed on that Mac

---

## Part 1 — Set it up with an AI agent (easiest)

Open this folder in an AI coding agent (Claude Code, Codex, …) and say:

> **"Set up Cyberpunk on my iPhone using AGENT-SETUP.md."**

The agent follows [AGENT-SETUP.md](AGENT-SETUP.md): it runs the setup script step by step,
tells you exactly what to tap or click when something needs your hands (signing in to Xcode,
enabling Developer Mode, trusting the Mac), and asks before it installs or launches anything.
You never give the agent your Apple ID or Steam password.

## Part 2 — Set it up yourself

All steps use one script, `phase8/tools/setup.py`. Every step can be re-run safely.

**1. Prepare the Mac and the phone (by hand, once)**
- Install Xcode, open it once and accept the licence.
- Xcode → Settings → Accounts → **+** → sign in with your Apple ID.
- Install Cyberpunk 2077 (macOS) in Steam on this Mac.
- Plug in the iPhone, unlock it, tap **Trust This Computer**.
- iPhone: Settings → Privacy & Security → **Developer Mode** → On (the phone restarts; confirm).

**2. Check everything**
```bash
python3 phase8/tools/setup.py doctor
```
Fix any `FAIL` lines; each one prints its fix.

**3. Configure, prepare, sign, build**
```bash
python3 phase8/tools/setup.py config
```
```bash
python3 phase8/tools/setup.py prepare-game
```
```bash
python3 phase8/tools/setup.py profile
```
```bash
python3 phase8/tools/setup.py build
```

Run `doctor` again: it must show **`PASS  profile has the increased-memory-limit entitlement`**.
That extra-memory entitlement raises the app's memory limit from ~3.4 GB to ~6 GB; without it iOS
kills the game within seconds. `setup.py profile` requests it automatically (free accounts work).

**4. Install and copy the game (keep the phone unlocked and plugged in)**
```bash
python3 phase8/tools/setup.py install
```
The first time, the iPhone asks you to trust the developer: Settings → General →
VPN & Device Management → your Apple ID → **Trust**.
```bash
python3 phase8/tools/setup.py copy-data
```
This copies ~61 GB (about 40 minutes over USB). If it stops, run it again; it resumes.
```bash
python3 phase8/tools/setup.py restore
```
(Copies your Mac saves, if any, plus the recommended settings. It never overwrites files already on the phone.)

**5. Play**: tap **Cyberpunk 2077** on the home screen. Accept the licence screen once.

**Every 7 days** (free Apple accounts): run `profile`, then `install`. Your data and saves stay.

Detailed step-by-step guide and troubleshooting:
[project-documentation/01-getting-started](project-documentation/01-getting-started/).

---

## How it works (short)

```
Your Steam install ──► setup.py prepare-game ──► build: game binaries wrapped, unchanged,
                                                  in signed containers + machprobe runtime
iPhone app ──► machprobe loader maps & links the Mac binaries ──► AppKit-on-UIKit, file/memory
              rules, offline network ──► Metal straight to the iPhone GPU
```

Read [how it works in 5 minutes](project-documentation/00-overview/how-it-works-in-5-minutes.md),
or the full [project documentation](project-documentation/) (architecture and code reference,
the bug log, the phase-by-phase history).

## For developers and AI agents working on the code

Start with [AGENTS.md](AGENTS.md) (rules and scope), then [CONTEXT.md](CONTEXT.md) (current state and plan).

## Credits and licence

Built by the project owner with AI coding agents (Astra/GPT for phases 1–5.5, Claude for 6–8);
see [credits](project-documentation/00-overview/credits.md). MIT licence for machprobe's code.
Cyberpunk 2077 is © CD PROJEKT RED; Steam is Valve's; iPhone and Metal are Apple's. This project
is not affiliated with any of them. The original phase-1 inspector README is in
[docs/inspector-and-phase2-README.md](docs/inspector-and-phase2-README.md).
