# Bring-up journal: Cyberpunk 2077 on iPhone

Chronological, milestone by milestone. Commit hashes are short hashes on branch
`phase6-supertuxkart`. Bug numbers refer to `bug-log.md`. Items marked
"(CONTEXT history)" come from earlier revisions of `CONTEXT.md` (`git log -p -- CONTEXT.md`),
not from commit bodies.

## Starting point (before 9 Oct)

- Phases 1 to 7 had already run SuperTuxKart unmodified on the iPhone (phase 7,
  `cdcbf0c`). The loader, the group-open model (`mp_group_open`), the signed
  per-image containers and the AppKit/SDL adapters all existed. Phase 8 reused
  them.
- Cyberpunk is a much larger target: five arm64 images (the executable, Bink,
  GameServices Steam, REDGalaxy, steam_api), about 151 MB executable, and a RED
  Engine that reserves huge virtual address ranges up front.
- The first Mac check was load-only: `make -C phase8 && build/phase8/cp-load build/cyberpunk/thin Cyberpunk2077`.
  Running the game on the Mac was ruled out after an early `--run` took over the
  screen and reached red engine threads (CONTEXT).

## Milestone 1: Prepare the loader and a lean host (`e831216`)

What was done:
- Loader features needed by the game: export-trie exports for stripped images
  (Bink), modern `__init_offsets` initializers (7,458 in this build), special
  chained ordinals, chained-import deferral to named abort stubs for functions
  only, and acceptance of `LC_ENCRYPTION_INFO_64` when `cryptid` is 0.
- Cyberpunk policy in `phase8/runtime/Policy.c`: 256 MB per image limit, a
  virtual executable path so the game finds `archive/`, `engine/` and `r6/`.
- Offline import-gap analysis against the SDK `.tbd` files:
  `python3 phase8/tools/import_gaps.py build/cyberpunk/thin Cyberpunk2077`.
  About 75 real gaps; the `<weak-def-coalesce>` and libbz2 entries are false positives.
- Adapters for the uncovered CoreGraphics, IOKit, Metal-observer, libcurl and
  Security imports (`phase8/runtime/CPDesktop.m`), and "lean Metal" in
  `phase8/runtime/CPMetal.m`: Apple's real `MTLDevice`, macOS-only methods added to
  the concrete classes, Managed storage rewritten to Shared.
- Result on the Mac: 5 images, 685,682 rebases, 71,348 binds, 495 selectors,
  7,458 initializers.

## Milestone 2: Data on the phone (9 Oct)

- Game data layout chosen to match a normal install: the app's Documents folder
  holds `Cyberpunk 2077/{archive,engine,r6}`. The host builds a virtual executable
  path inside it (`MP_GUEST_EXECUTABLE_PATH`, set in `phase8/host/Main.m`), so the
  game walks up and finds its data.
- Copy order in `phase8/tools/phone.py push-data`: r6, engine, archive. Small folders
  first; archive is about 60 GB. USB 2 cable measured about 29 MB/s (CONTEXT).
- `phase8/tools/push_resume.py` was added (`0908351`) so an interrupted copy resumes.
  All data was on the phone and verified before the link fix below.
- Phone tool: `phase8/tools/phone.py` (check, deploy, push-data, launch, report,
  logs, args, debug). Signing uses the free development team and a profile for the
  App ID that the script selects by App ID, not by age.

## Milestone 3: First boot on the device (`d5c3f08`)

- First launch: GPU initialized, then the image failed to link on
  `_OBJC_CLASS_$_NSTrackingArea`. Fixed by adding AppKit adapters
  (NSTrackingArea, NSWindowController, NSWorkspace) in `phase6/runtime/AppKitExtras.m`
  and `phase6/runtime/Desktop.m`. (CONTEXT history, 9 Oct status.)
- The first runtime crashes were read from `runtime.json` in the app container
  (`phone.py report`) and from `runtime-stderr.log` (`phone.py logs`).
- Debugging channel from here on: `Documents/runtime-stderr.log` and
  `runtime-stdout.log` (written by `phase8/host/Main.m` unless `MP_CONSOLE` is set,
  in which case `devicectl --console` streams them live).

## Milestone 4: Main menu (`0908351`, "Cyberpunk 2077 reaches the main menu")

Three blockers fell in one commit (all in our layer; game bytes untouched):

1. Address space. iOS gave about 66 GB of virtual address space for the app. RED
   reserves 16 GB, 64 GB and 32 GB allocator regions up front. `Policy.c` stacks
   them top-down from `0x8000000000` (see bug 1 in `bug-log.md`, and `memory.md`).
2. Case-sensitive paths. The game asks for `archive/mac/content`; the install has
   `archive/Mac`. Path wrappers in `Policy.c` (`ci()`) match components ignoring
   case (bug 2).
3. Metal heaps. The Mac build asks for multi-GB heaps; iOS commits heaps whole and
   the app was jetsam-killed within about 2 s. Heaps capped at 512 MB at this
   stage (`MP_HEAP_CAP_MB`; bug 6). Later the default became 96 MB (see
   `memory.md`).

Also in this commit: AppKit stand-ins for NSScreen, NSWindow, NSApplication, NSEvent
and NSImage (`phase8/runtime/CPAppKit.m`); a zero-returning safety net for
selectors the stand-ins lack (logs `[appkit] unimplemented ...`); a crash reporter
in `Main.m` that prints the faulting guest offset and the running initializer; and
memory, GPU and filesystem traces (`MP_MEM_TRACE`, `MP_FS_TRACE`).

## Milestone 5: Main-menu load passes (`b5dd60b`)

- After the menu began loading, the game crashed around the curl stubs.
- Cause, as the commit message gives it: the offline libcurl added in `e831216`
  did not keep request state. `curl_easy_setopt` and `curl_easy_getinfo` are
  variadic; on arm64 Apple the trailing argument is on the stack, and the stub
  must read it with `va_arg`. `CURLINFO_PRIVATE` came back NULL, and the game uses
  that pointer to find its request object, so a NULL there corrupted memory
  (bugs 3, 4, 5).
- Fix: valid easy and multi handles; `setopt` keeps `CURLOPT_PRIVATE` (10103) and
  `CURLOPT_URL` (10002); every transfer completes with `CURLE_COULDNT_CONNECT` (7),
  so the game sees an offline network rather than a crash.
- Paths under `/Users/<build user>/...` in game config map to the app home
  (`home_path()` in `Policy.c`), and failed texture creation and heap sub-allocation
  are logged.
- The menu loads.

## Milestone 6: Input (`2dee2ac`, `e43a29b`, `e348889`, `a9bb2bc`)

Taps and keys did nothing at first. The causes below are listed in the order the fix commits landed:

1. Events never reached the game view. Cyberpunk drains the AppKit event queue
   itself (`nextEventMatchingMask:`), so the shared queue in `phase5/runtime/Lifecycle.m`
   had to be exposed to it: `mp_game_queue_events` (`2dee2ac`). The game view
   also never became first responder, so `Input.m` falls back to the first
   accepting view in the key window (`2dee2ac`).
2. The window never becomes key. `mp_game_key_window()` falls back to the first
   guest window (`e43a29b`).
3. Coordinates. The game's view wants AppKit bottom-left `locationInWindow`; the
   converter `mp_game_appkit_points` flips the y axis (`e43a29b`).
4. The game ignores the pointer until its focus state is set. `GameWindowController`
   gets `windowDidBecomeKey:` again once the window is on screen and on app
   activation (`mp_cp_refocus`, `e348889`). Three gates must hold: the controller's
   `m_windowFocus`, the static `+[GameWindow isWindowVisible]`, and
   `GameView.cursorInView`. They are re-asserted at every touch start
   (`mp_game_touch_began`, `a9bb2bc`).
5. Buttons teleported the cursor to the top-left corner: they sent `(0,0)` and the
   game re-associated the mouse. Buttons and look pads now use
   `mp_game_pointer_here`, which acts at the current cursor (`a9bb2bc`).

Touch controls arrived with `2dee2ac` (`phase8/runtime/CPControls.m`, a WASD stick,
action keys, mouse look, an iPhone keyboard) and were refined in `e348889`
(one finger moves and taps, two fingers scroll or right-click; look only while the
pad is shown). See `input-and-controls.md`.

Diagnostics added for this milestone: `MP_CURSOR_TRACE` (game-side mouse location,
focus checks, engine input flags), `MP_AUTOPRESS` and `MP_AUTOTAP` (unattended key
and tap scripts), and `[focus]` and `[keys]` lines in the logs.

## Milestone 7: Night City (`538ebc6`, `3455929`)

- Spill-over heaps (bug 6 follow-up): when a capped heap fills, a new heap is
  created only while `os_proc_available_memory()` keeps a margin. Residency hooks
  make the spill-over heaps resident with the capped one.
- `hw.memsize` reported as a configurable value so RED sizes its streaming budgets
  for the app's real limit (`MP_MEMSIZE_GB`). The first value was 8 GB; the
  default later became 3 GB (`04c412a`). See `memory.md`.
- Resolution (`3455929`): the game was rendering at 874x402 points with 50-65 %
  dynamic resolution scaling. `mp_display_set_modes` (`phase5_5/runtime/Display.m`,
  `phase8/host/Main.m`) now lists render modes at the panel's aspect ratio, and
  `CGDisplayModeGetWidth/Height` report pixels. The host offers 900, 1080, 804, 720,
  603 and native; the user settings were set to 1956x900 with ResolutionScaling and
  DRS off.

## Milestone 8: Playable (9 Oct, `11a407d` CONTEXT)

- The user's own level-50 Steam save was copied from
  `~/Library/Application Support/CD Projekt Red/Cyberpunk 2077/saves` into the
  app's container at the same relative path. `user.gls` (EULA acceptance) on the
  phone is never overwritten.
- Xbox-style controller works through GameController. Buttons opt out of iOS
  system gestures (`claim_buttons` in `Main.m`, `04c412a`).
- Driving in Night City at about 22-24 fps at 804p Low in the first session
  (CONTEXT), later improved by the performance work in `performance.md`.

## Milestone 9: Performance and memory telemetry (`25bef28`, `04c412a`, `0cb6e9e`)

- `25bef28`: TLS fast path (a thunk that reads `TPIDRRO_EL0` plus a per-image pthread
  key, modelled on dyld's `tlv_get_addr`; slow path only on a thread's first access). Layer overhead measured at
  about 1-5 % afterwards (CONTEXT). Lock-free safety-net dedupe.
- `04c412a`: found that RED budgets the GPU at 0.75 x `hw.memsize`, so the 8 GB
  report planned about 4.5 GB of GPU memory inside a 6 GB app. Reported value
  changed to 3 GB; heaps start at 96 MB and grow by spill-over heaps (menu GPU
  2.5 GB to 1.7 GB). `[perf]` line added: GPU busy, main thread and whole-process
  CPU per 5 s.
- `0cb6e9e`: thermal state and a texture census (Managed, Shared, Private) in
  `[perf]`; spill-over cap `MP_SPILL_CAP_MB` (default 1024). The Managed-to-Private
  experiment (`MP_MANAGED_RT_PRIVATE`) was built but not yet run on the phone.

## Milestone 10: Tuned settings and the VSync finding (10 Oct, `aa32a9b`)

- Settings were tuned on the phone by the user and saved as
  `phase8/config-recommended-UserSettings.json`: 1564x720 native, VSync 120 with
  MaximumFPS 60, most graphics options Low. Result: 30-40 fps in the city.
- Finding recorded in CONTEXT history (`0cb6e9e`): the game's VSync list is
  dynamic (values such as "120" and "30"). Writing "60" into `UserSettings.json`
  was invalid and the game silently capped at 30 fps. Setting VSync to 120 in the
  game gave a locked 16.7 ms frame in calm scenes.
- Still open: something holds the presentation at 60 fps even with VSync 120.
  `Info.plist` already has `CADisableMinimumFrameDurationOnPhone` (`phase8/tools/build.py`).
  Whether `CAMetalDisplayLink` sets a preferred frame rate range is unverified.

## Milestone 11: Own icon and own App ID (10 Oct, `ed2227a`, `5e022eb`)

- `ed2227a`: the home-screen icon is built at build time from the installed game's
  `AppIcon.icns` (`phase8/tools/make_icon.swift`); padding trimmed, corners filled,
  opaque iOS sizes. Nothing is stored in the repo.
- `5e022eb`: another app was installed over `research.machprobe.STKHost` on the
  same phone, and the reinstall wiped the Cyberpunk container, including the copied
  game data and the phone-side saves. Restored from the Mac copies. Cyberpunk now
  uses `research.machprobe.CP2077`. `build.py` and `phone.py` are pinned to that ID,
  and `phone.py` picks the newest provisioning profile for that App ID.
  The free developer account allows 10 App IDs a week, so new IDs are not created
  without the user asking.

## Open at the end of the documented work

- Frame pacing above 60 fps in menus, and the cap that holds gameplay at 60.
- A slow leak in malloc-small (about 1.4 MB/s) and the autorelease theory (see `memory.md`).
- Touch pad rebuild (the current pad is a quick hack the user dislikes).
- Resolution sweep and a measured default.
- In-app Steam sign-in and download: planned only, not started in the repo.
