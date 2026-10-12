# Read this first — what machprobe is and isn't

> **machprobe is not piracy.** It contains **no game files** and does not help anyone get
> a game they haven't bought. It is an MIT-licensed compatibility layer that runs **your own,
> legally purchased** macOS copy of a game on **your own** iPhone.

## The short version

| Question | Answer |
|---|---|
| Is this pirated / does it include the game? | **No.** Zero game files, code or assets are in this repository. |
| What licence is machprobe under? | **MIT** — see [`LICENSE`](../LICENSE). This covers machprobe's own code only. |
| Do I need to own the game? | **Yes.** You need the game on Steam **for macOS**, installed on your own Mac. |
| Is the game modified? | **No.** The original binary runs unchanged and is hash-verified at launch. |
| Does it bypass DRM or anti-cheat? | **No.** Games that need that are not supported. |
| Is it on the App Store? | **No.** You build it yourself and sideload it with your own free Apple developer account. |
| Can I share my built app with friends? | **No.** Your build contains your copy of the game. Each person builds their own. |
| Does it collect data? | **No.** No analytics, no accounts, no servers. Logs stay on your phone/Mac. See [privacy](06-policies-and-roadmap/privacy.md). |
| Is it affiliated with CD PROJEKT RED, Valve or Apple? | **No.** Independent research project. All trademarks belong to their owners. |

## What you need

- A Mac with Apple silicon and Xcode (to build and sign).
- An iPhone with Developer Mode, ~65 GB free space and a good USB cable.
- A free Apple developer account (profiles last 7 days; re-sign weekly).
- Your own copy of the game, installed through Steam on that Mac.

Full list: [01-getting-started/requirements.md](01-getting-started/requirements.md).
Tested devices: [00-overview/tested-hardware.md](00-overview/tested-hardware.md).

## ⚠️ Hardware and heat warning

- **Recommended: a recent, high-end iPhone** (✅ fully verified: iPhone 18 Pro, 12 GB RAM). The iPhone 17 Pro and
  iPad Pro will probably work. Models older than the iPhone 15 Pro are not recommended due to low memory limits (6 GB RAM or less).
- **Overheating:** the phone can get very hot within minutes. iOS will slow it down, dim the
  screen or close the game. Don't play while charging or in hot places; use a 40–60 fps cap; take
  breaks; stop if the phone gets uncomfortable to hold. Use at your own risk (no warranty).

## What to expect

It's an experiment, not a polished port. Expect 30–40 fps at reduced resolution, heat,
occasional memory kills, a 61 GB copy, and weekly re-signing. Read
[00-overview/what-to-expect.md](00-overview/what-to-expect.md) before you start.

## Legal and privacy

- [06-policies-and-roadmap/legal-and-ethics.md](06-policies-and-roadmap/legal-and-ethics.md)
- [06-policies-and-roadmap/privacy.md](06-policies-and-roadmap/privacy.md)
- This is not legal advice. Check that your use follows the game's EULA, the store's terms
  and Apple's developer terms where you live.
