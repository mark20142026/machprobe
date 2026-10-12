# What to expect

An honest picture before you spend an afternoon copying 61 GB.

## The good

- The **real game** — your own save, the full open world, driving, combat, menus, audio.
- **30–40 fps** at 1564×720 with tuned settings (benchmark 39.44 fps on an iPhone 18 Pro).
- An Xbox **controller works** like on a Mac (tested); other GameController-compatible pads
  (PlayStation, MFi) should too but are untested. Touch works for menus and basic play.
- Your Mac saves can be copied over and carry on where you left off.

## ⚠️ Read first: hardware and heat

- **Use a recent, high-end iPhone.** The **iPhone 18 Pro** (12 GB RAM) is the fully verified device; the iPhone 17 Pro and
  iPad Pro will probably work. **Models older than the iPhone 15 Pro are not recommended due to low memory limits** (6 GB RAM or
  less; iOS's per-app memory limit is too low); 8 GB models are **untested but may work** (a user measured ~6 GB allowed per app on an 8 GB iPhone 15 Pro Max with the extra-memory entitlement). **Best experience: 12 GB iPhones or 16 GB iPad Pros.** Phones with
  less memory will likely crash or fail to start (see [tested-hardware.md](tested-hardware.md)).
- **Heat safety.** Expect the phone to get hot within minutes; it can become *very* hot. iOS
  protects itself by slowing down, dimming the screen and eventually closing the game.
  - Don't play while charging, under covers, in a thick case or in direct sun.
  - Cap the frame rate at 60, or 40 for long sessions.
  - Take breaks. **Stop if the phone is uncomfortable to hold.**
  - A clip-on phone cooler helps a lot.
- This is experimental software with no warranty (MIT licence). Use at your own risk.

## The rough edges

| Expect | Why | What helps |
|---|---|---|
| **Heat** within minutes | A AAA game is pushing a phone GPU | 60 or 40 fps cap, unplug while playing, a clip-on cooler |
| **Occasional memory kills** (app just closes) | iOS's ~6 GB per-app limit; bursts like car crashes spike memory | Recommended settings; memory governor is being worked on |
| **A black blob near the sun while turning the camera** (known bug) | Motion blur interacting with the sun's brightness on iPhone | **Fixed by Motion Blur Off** (the default in the recommended settings; [details](../04-cyberpunk/known-issues.md)) |
| **Touch controls are basic** | Current pad is a first version | Use a controller; rebuild planned |
| **Lower resolution than the screen** | The GPU budget | Pick a mode in the game's settings (1564×720 recommended) |
| **Long first setup** | 61 GB over USB (about 40 minutes), plus build and signing | Resumable copier (`push_resume.py`) |
| **Weekly re-signing** | Free developer profiles last 7 days | Re-sign + install over the same App ID; data stays |
| **No online features** | Network services answer "offline" | — |
| **No App Store / no sharing** | Sideload only; your build contains your own copy | Each person builds their own |

## Time to get running

The one measured step: copying 58.5 GB of game archives took **about 38 minutes** over USB on the
tested setup. Installing Xcode, making a profile, building and signing come on top of that.

Then follow [../01-getting-started/](../01-getting-started/).
