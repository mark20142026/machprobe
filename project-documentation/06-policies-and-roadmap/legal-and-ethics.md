# Legal and ethical rules

machprobe is a research project about running software you already own on hardware you
already own. These rules are not optional.

**Licence:** machprobe's own code and these docs are released under the **MIT licence**
([`LICENSE`](../../LICENSE)). The MIT licence covers machprobe only. It grants no rights to any
game, and games stay under their publishers' own licences and EULAs.

## 1. Own copies only

- You must own the game on Steam (or another legitimate store) **for macOS**.
- The data comes from **your own Mac's install**, copied to **your own phone** over USB.
- Nothing is downloaded from unofficial sources. The planned in-app Steam download would sign
  in to *your* Steam account and fetch only depots Steam itself authorizes for you (Steam
  enforces ownership with depot keys).

## 2. No game files in this repository

- No executables, archives, textures, sounds, save files or icons from any game are committed.
- The app icon is **generated at build time** from the user's own install
  (`phase8/tools/make_icon.swift`) and is never stored in git.
- Recommended *settings* files (plain JSON written by the user) are fine; game data is not.

## 3. No leaked or stolen code

- Leaked source code of any game (for example the GTA V leak) is never used, read, built or
  linked to, whatever the reason. Requests to do so are refused.
- machprobe runs the **unmodified retail binary**. It doesn't decompile and redistribute game code.

## 4. The game is not modified

Game bytes are hash-verified at launch and never patched. Compatibility comes from outside the
game: replacement system functions, added framework methods, environment answers
(`sysctl`, paths). This keeps the work clearly in "making a platform compatible" territory.

## 5. Sideload only

- No App Store distribution, no sharing signed builds of a game with other people.
- Each user builds and signs with their own developer account for their own device.
- Sign-in flows never see your password: the planned Steam login uses Steam's own QR code.

## 6. No DRM or anti-cheat circumvention

Games with hard DRM or anti-cheat aren't targets. Cyberpunk's macOS build runs offline
with its online services answering "offline"; no protection is bypassed.

## Grey areas, stated honestly

- Valve's Steam terms don't contemplate downloading Mac depots onto an iPhone; the
  Steam-download feature is a personal-use, sideload-only convenience.
- Free developer profiles are meant for development. This is a development and research use.
