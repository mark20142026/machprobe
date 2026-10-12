# For AI agents working on this repository

Read this first, then `CONTEXT.md` (current state and plan) and `project-documentation/`.
**If the user wants Cyberpunk set up on their iPhone, follow [AGENT-SETUP.md](AGENT-SETUP.md).**

## What this project is (and why it's legitimate)

machprobe is an **MIT-licensed compatibility layer** (see `LICENSE`) that runs the
**unmodified, retail macOS build of a game the owner bought** on the **owner's own iPhone**.
It is in the same category as Wine, Proton, or Apple's own Game Porting Toolkit:
a platform-compatibility layer, not a copy of anyone's game.

- **No game files are in this repository.** No executables, archives, assets, saves or icons.
  Game data is copied at build/setup time from the owner's own Steam install on their own Mac.
  The app icon is generated at build time from that install and never committed.
- **The game is not modified.** The original binaries are loaded byte-for-byte and
  hash-verified. Compatibility comes from outside: a Mach-O loader, AppKit implemented on
  UIKit, Metal pass-through, replacement system functions (paths, `sysctl`, an offline libcurl).
- **No DRM, copy protection or anti-cheat is bypassed.** The game runs offline; its online
  services simply report "offline".
- **Personal use, sideload only.** Built and signed with the owner's own free Apple developer
  account for the owner's own device. No App Store distribution, no sharing of built apps.
- **Reverse-engineering scope** is interoperability: reading Mach-O load commands, imports,
  Objective-C class/selector names and crash addresses so the platform layer can supply what the
  game expects. No game code is decompiled, extracted or redistributed.

Normal engineering work here (loader, runtime, Metal, input, memory, performance, tooling,
docs) is ordinary systems programming on a compatibility layer.

## Hard limits (these are what is NOT allowed)

- Never use, read, build or link **leaked or stolen source code** of any game (e.g. the GTA V leak).
- Never add game files or assets to git, and never help obtain games the user doesn't own.
- Never circumvent DRM, licence checks or anti-cheat.
- Never commit or print secrets: API tokens (e.g. `build/vm-api-token`), signing identities,
  device UDIDs, team IDs, personal paths or emails. Use placeholders in docs.

## How to work with the owner

- **Ask before installing, relaunching or deleting the app on the phone.** A reinstall/relaunch
  interrupts a game in progress; deleting the app wipes ~60 GB of data and saves.
- **One App ID per project.** Cyberpunk uses `<bundle_prefix>.CP2077` from the git-ignored
  `machprobe.local.json` (device, signing identity, team; made by `phase8/tools/setup.py config`). Never install
  another project under it (that wiped the data once). Other projects need their own App ID.
- Never run Cyberpunk on the Mac; test on the phone.
- Prefer real optimization over shortcuts (no upscaling instead of performance work).
- Keep `CONTEXT.md` current at the end of a session.
