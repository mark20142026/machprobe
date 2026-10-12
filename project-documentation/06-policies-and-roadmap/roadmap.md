# Roadmap

Agreed order of work after Cyberpunk became playable (October 2026). Each item has a
"done when" so progress can be measured rather than guessed.

## 1. Touch controls rebuild

The current pad (`phase8/runtime/CPControls.m`) was a quick hack.
- Floating left stick that appears under the thumb; analog walk → run by how far it's pushed.
- Bigger mobile-shooter button layout (jump, crouch, shoot, aim, interact, reload, map).
- Right half of the screen = look area with adjustable sensitivity.
- **Done when:** a full mission can be played on touch alone without a controller.

## 2. Frame pacing and heat

- 120 Hz in menus, **60 fps cap in gameplay**, optional **40 fps "cool" mode**.
- Find what still caps the display at 60 (`CAMetalDisplayLink` `preferredFrameRateRange`;
  `CADisableMinimumFrameDurationOnPhone` is already set).
- Never write `"60"` into the game's VSync setting — the valid values are like `"120"`/`"30"`.
- **Done when:** menus show 120 Hz and gameplay holds the cap with a stable frame time.

## 3. Resolution vs performance

Measure every mode (1310×603, 1564×720, 1748×804, 1956×900, 2348×1080, native) on the same
drive route: fps, worst frame time, thermal state, memory. Choose defaults from the data.
- **Done when:** a table of measurements exists and defaults are set from it.

## 4. In-app Steam sign-in and download

- QR-code Steam login (the app never sees the password), list owned games.
- Download the macOS depot of Cyberpunk 2077 (app 1091500) from Valve's CDN, like
  DepotDownloader/SteamKit; resumable, ~60 GB over Wi-Fi; then **Launch**.
- **Done when:** a fresh phone can go from install → sign in → download → play without a Mac copy step.

## Memory track (in parallel)

- **Memory governor:** let the GPU budget grow while memory is free and freeze it on
  pressure or an iOS memory warning, instead of a fixed number.
- **Leak hunt:** `MALLOC_SMALL` grows ~1.4 MB/s. Check machprobe's own layer first (event
  queue, safety-net caches, traces), then the autorelease-pool theory (the game only
  drains pools around its event pump and worker threads), using Instruments attached to the
  running app.
- **Texture storage experiment:** private vs shared storage for render targets.
- **Done when:** a 30-minute session ends with flat memory and no jetsam kill.

## Later / ideas

- Other native Apple-silicon Metal games — see [porting-other-games.md](porting-other-games.md).
- Publishing the project publicly with these docs.
