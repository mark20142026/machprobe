# First launch

Prerequisites: app installed (`setup.py install`,
[build-and-install.md](build-and-install.md)), data copied (`setup.py
copy-data`, [copying-game-data.md](copying-game-data.md)), profile still valid
([provisioning.md](provisioning.md); `setup.py doctor` shows the days left).
The whole sequence is in Part 2 of the [top-level README](../../README.md); an
agent follows Stage 9 of [AGENT-SETUP.md](../../AGENT-SETUP.md).

## 1. Launch

Tap the "Cyberpunk 2077" icon, or from the Mac:

```sh
python3 phase8/tools/setup.py launch     # same as phone.py launch: devicectl process launch --terminate-existing
python3 phase8/tools/phone.py report     # read-only status, safe to repeat
```

`launch` restarts the app if it is already running, so do not use it while
someone is playing.

The app is landscape-only. Keep the phone unlocked; plugging it in while
playing adds heat (see below).

## 2. What the host does at startup

`phase8/host/Main.m` records its progress in `Documents/runtime.json`, which
`phone.py report` prints (`stage`, `error`, `data_present`,
`memory_available_bytes`, `gpu`, `load`, `frame_window`). Stages you may see,
in order: `start`, `gpu ready`, `loading group`, `guest hashes verified`,
`guest entry`. Failure stages: `container failed`, `missing resident section`,
`guest hash mismatch` (the game files are not the expected build),
`group load failed`, `main thread stalled (watchdog)`, `exception`.

`data_present` shows whether `archive`, `engine` and `r6` exist in
`Documents/Cyberpunk 2077/`.

## 3. What you will see

1. A short pause on the launch screen while images load and are
   hash-verified.
2. The game's own start-up and, on first run, the **EULA screen**. Accept it
   with a tap. Acceptance is stored in the game's `user.gls` file in the
   container's `Library/Application Support/CD Projekt Red/Cyberpunk 2077/saves/` folder, so it is not asked again as long as the container survives
   (reinstalling over the same App ID keeps it; deleting the app does not).
   `setup.py restore` deliberately does not copy your Mac's `user.gls`, so
   accepting the licence once on the phone is expected.
3. The main menu. Touch works for menus. Loading a save takes a while because
   the data comes from phone flash and the game streams a lot; I have no
   measured loading times in the repo, so treat any number you read elsewhere
   as unverified.

Controls in game: an Xbox/MFi/PS controller works natively. Touch controls
(`phase8/runtime/CPControls.m`) are a first version: a WASD stick, action
buttons (SPACE, F, R, C, SHIFT, mouse buttons, ESC, TAB, ENTER), right-half
drag for mouse look, plus buttons to show the iPhone keyboard and a gamepad
toggle. The roadmap lists a rebuild of these.

## 4. Recommended settings

If `setup.py restore` copied `phase8/config-recommended-UserSettings.json`
(it skips the file when the phone already has one), they are already applied.
Otherwise set them in the in-game menu. They were tuned by
hand for the iPhone 18 Pro and give roughly 30s to 40 fps in the city:

| Setting | Value |
|---------|-------|
| Resolution | 1564x720 (native; ResolutionScaling Off, dynamic resolution off) |
| **VSync** | **120** |
| Maximum FPS | On, value 60 |
| Texture quality | Low |
| Local shadows | Off |
| Cascaded / distant shadows resolution | Low |
| Shadow mesh, LOD, crowd density | Low |
| SSR, ambient occlusion, SSS, volumetric fog, mirror, decals | Low |
| Volumetric clouds | Medium |
| Color precision | Medium |
| Film grain, chromatic aberration, depth of field | Off |
| Motion blur | Low |

The in-game window mode is Fullscreen. No upscaling (MetalFX) is used by
design.

### The VSync trap

The game's VSync list is dynamic: valid values look like `"120"` or `"30"`.
**Choose 120.** A value of `"60"` is not valid in that list; written into
`UserSettings.json` it was silently treated as a **30 fps cap**. Frame-rate
limiting is done with **Maximum FPS** (on, 60), not with VSync. If you see a
flat 30 fps, check VSync first ([troubleshooting.md](troubleshooting.md)).

### Heat and frame cap

The iPhone 18 Pro (non-Max) throttles within minutes at uncapped frame
rates; charging adds heat. A cap of 40 or 60 fps, unplugged, and a cooler
phone help most. The project notes state GPU load, not the translation layer
(~1-5% overhead), is the limit.

## 5. If it does not start

See [troubleshooting.md](troubleshooting.md); more diagnostics are in
[../05-tools-and-diagnostics/](../05-tools-and-diagnostics/) and
Cyberpunk specifics in [../04-cyberpunk/](../04-cyberpunk/).
