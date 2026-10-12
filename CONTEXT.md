# machprobe — full working context (handoff for any agent)

> **Agents: read `AGENTS.md` first.** machprobe is an MIT-licensed compatibility layer that runs the
> owner's own purchased, unmodified macOS game on the owner's own iPhone. No game files are in git,
> no DRM is bypassed, sideload only. Leaked/stolen source code is never used.

Last updated: 9 Oct 2026 by Claude (Opus 5.5). Read this first, then `progress.md`
(phase work log) and `docs/phase6-findings.md`.

## What this project is
A macOS → iOS translation layer: it runs **unmodified macOS arm64 game binaries
on iPhone** by loading their Mach-O images ourselves (custom loader) inside a
signed iOS host app, and adapting missing macOS APIs (AppKit, CoreGraphics,
Carbon, IOKit, Metal-on-Mac quirks…) to iOS equivalents. No JIT: the game code
is already arm64. Game bytes are never modified (hash-verified at launch).

- Phases 1–5.5 were built by "Astra" (GPT-6 via Codex, Sep–Oct 2026): loader,
  iOS runtime, DashboardCalculator, Strataris, Veloren.
- Phase 6 (Claude): SuperTuxKart 1.5 (19 images) in the vphone VM, 60 fps.
- Phase 7 (Claude): SuperTuxKart on the user's **physical iPhone 18 Pro**, 60 fps.
- Phase 8 (Claude, IN PROGRESS): **Cyberpunk 2077** (Steam macOS build) on iPhone.

## User + hard rules (MUST follow)
- Work autonomously on code, builds and logs, and report in short plain language (user types
  casually, half-watching) — BUT **ask before any install, relaunch or delete on the phone**
  (it interrupts the user's game; user was clear about this on 10 Oct).
- **Cyberpunk App ID: `research.machprobe.CP2077`** (since 2026-10-10, user's request).
  Another project (a GPT session, app "Muguet") was installed over `research.machprobe.STKHost`
  and the reinstall wiped the Cyberpunk data container (game data + phone saves lost;
  restored from the Mac). STKHost now belongs to that other project — never install
  Cyberpunk there and never touch it. Free account = 10 App IDs/week; don't create more
  App IDs unless the user asks.
- **Never run Cyberpunk on the Mac** (`cp-load ... --run` / CPMacHarness.app). It
  took over the screen. Load-only checks (no `--run`) are OK. Play-test on iPhone.
- User is in the **EU** (no iPhone Mirroring).
- Commits: on branch `phase6-supertuxkart`; end messages with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Not pushed.
- `caffeinate -dims` is running (PID 83282) to keep the Mac awake.

## Hardware / accounts
- Mac: Apple M2 (host), Xcode 27, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- iPhone: **iPhone 18 Pro** (iPhone19,2), iOS 27.0.1, UDID
  `<DEVICE-UDID>`, 256 GB (~190 GB free), Developer Mode ON.
  GPU "Apple A20 Pro GPU": Apple7–10 + Metal3/Metal4 families, **BC textures YES**,
  recommendedMaxWorkingSet ~8 GB, maxBufferLength 6 GB.
  App memory available ≈ 6.0–6.4 GB with com.apple.developer.kernel.increased-memory-limit
  (works on the free team; Extended Virtual Addressing does NOT).
- Signing: Apple ID free **Personal Team <TEAM-ID>**; identity
  "Apple Development: mark201120142025@gmail.com (B4DFC2JL94)",
  SHA1 `<SIGNING-IDENTITY-SHA1>`; provisioning profile
  `~/Library/Developer/Xcode/UserData/Provisioning Profiles/79f2ee11-af66-49d6-989b-231643e30a10.mobileprovision` (includes increased-memory-limit)
  (App ID <TEAM-ID>.research.machprobe.CP2077, **expires 2026-10-17**; refresh with
  `cd phase7/signing && xcodebuild -project Provisioner.xcodeproj -sdk iphoneos -allowProvisioningUpdates
  PRODUCT_BUNDLE_IDENTIFIER=research.machprobe.CP2077 build` — link error is fine, only the
  profile matters). phone.py picks the newest profile whose App ID matches, not the newest overall.
  xcode-select points at CommandLineTools: export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer. Entitlements in profile:
  application-identifier, team-identifier, get-task-allow, keychain-access-groups.
- vphone VM `iphone` (iOS 27, 4 GB RAM, paravirtual GPU) — optional; launched with
  `VPHONE_API_TOKEN=$(cat build/vm-api-token) nohup "/Library/Application Support/vphone-launchpad/Bundles/2.2.5/VPhone.bundle/Contents/MacOS/vphone-cli" vm launch iphone --library-root ~/.vphone/machines --api-listen 127.0.0.1:18765`.
  Tools: `tools/vphone_install.py`, `tools/vphone_push_tree.py`, `phase6/tools/vm.py`.
  VM GPU bug: baseVertex truncated to 16 bits (workaround phase5_5/runtime/BaseVertex.m,
  auto-detected; real iPhone is fine).

## Loader (runtime/) — key facts
- `image.c` phases map → link → start; `mp_group_open` loads a set of images as one
  link unit (main first, dylibs), deps by install name / @-basename, metadata
  registration, initializers deps-first, main last.
- `group.c`: hashed exports from symtab **+ export trie** (stripped images), special
  ordinals, guest dlopen/dlsym/dladdr, libunwind dynamic sections.
- `fixups.c`: legacy opcodes + chained `DYLD_CHAINED_PTR_64_OFFSET` (incl. special
  ordinals 0/0xFF/0xFE/0xFD; unresolved non-ObjC chained imports → named abort stubs
  via resolve_lazy). `services.c`: initializers incl. **`__init_offsets`**.
- Accepts LC_ENCRYPTION_INFO_64 only when cryptid==0.
- iOS packaging: each guest image embedded in its own signed container dylib
  (`__TEXT,__guest` + `__DATA,__guest`) + rebased `__unwind_info` (phase6/tools/build.py `container()`).

## Phase 8 — Cyberpunk 2077 (current)
- Game: Steam app 1091500, build 20383525, at
  `~/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077/`
  (Cyberpunk2077.app + archive/ engine/ r6/, 61 GB). User says Cyberpunk is DRM-free.
- Thin arm64 copies + SHA256SUMS: `build/cyberpunk/thin/` (Cyberpunk2077 151 MB,
  Frameworks: libBink2MacArm64, libGameServicesSteam, libREDGalaxy64, libsteam_api).
- Mac load-only check: `make -C phase8 && build/phase8/cp-load build/cyberpunk/thin Cyberpunk2077`
  → 5 images, 685,682 rebases, 71,348 binds, 495 selectors, 7,458 initializers.
  (A `--run` on Mac reached RED engine threads — don't do it again.)
- Game finds data by walking up from `_NSGetExecutablePath`; we return a virtual path
  (`MP_GUEST_EXECUTABLE_PATH`) = `Documents/Cyberpunk 2077/Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077`.
- Offline import gaps: `python3 phase8/tools/import_gaps.py build/cyberpunk/thin Cyberpunk2077`
  (~75 real gaps; "<weak-def-coalesce>" and libbz2 entries are false positives).
- Files: `phase8/runtime/Policy.c` (mp_cp_policy), `CPDesktop.m` (CG/IOKit/Metal-observer/
  curl/Security stubs), `CPMetal.m` (lean Metal: real MTLDevice, macOS-only methods
  added to concrete classes, Managed→Shared), `phase8/host/Main.m` (lean host; debug
  diagnostics only if Documents/debug exists), `phase8/tools/build.py` (-O3 LTO; output
  `build/phase8-runtime/CP2077Host.ipa`), `phase8/tools/phone.py`
  (check|deploy|push-data|launch|report|logs|args|debug).
- Shared AppKit adapters for SDL/Cyberpunk live in `phase6/runtime/AppKitExtras.m`
  (just added NSTrackingArea, NSWindowController, NSWorkspace) and `Desktop.m`.
- Status 9 Oct (end of day): **PLAYABLE end-to-end** on iPhone 18 Pro — user's level-50 Steam
  save (copied from the Mac's saves folder; never overwrite the phone's user.gls), Xbox
  controller works natively (GameController), touch menus + touch pad work, renders native
  1956x900 / 1748x804 (aspect-correct pixel modes), no upscaling (user rejects MetalFX).
  Perf: ~22-24 fps in the city at 804p Low; telemetry says **GPU-bound** (command-buffer GPU
  time ~300%, main thread ~1%, CPU ~2 of 6 cores) and minimum settings barely help.
  Memory: GPU budget = 0.75 x hw.memsize (we report 3 GB); heaps grow on demand (96 MB +
  64 MB spill-over, 900 MB margin); city still reaches ~2.6 GB GPU + ~3.1 GB CPU, ~450 MB free.
  NEXT: (1) thermal state in telemetry (phone overheated earlier); (2) Managed->Shared
  textures lose lossless compression — try Private where the game never touches them on the
  CPU; (3) hard cap on spill-over GPU growth (~2 GB total); (4) CPU side: engine allocator
  regions grow +1.2 GB on world load — find RED's streaming budgets; (5) Instruments: xctrace
  shows the phone "offline" (needs Xcode/CoreDevice), retry for a Metal System Trace.
  LATE FINDINGS: the game's VSync list is dynamic ("120", "30", ...); writing "60" into
  UserSettings.json was invalid → silent 30 fps cap. User set VSync=120 in-game → 60 fps in
  calm scenes (locked 16.7 ms; something still caps at 60 → check CAMetalDisplayLink
  preferredFrameRateRange), ~25-40 fps driving. [perf] gpu_busy sums overlapping command
  buffers (overstates; merge intervals). Memory kill on a car crash at ~265 MB free:
  malloc-small (VM tag 2) creeps ~1.4 MB/s; IOACCELERATOR (tag 100) ~820 MB; engine regions
  2.37 GB. Built but NOT installed: thermal state + texture census + spill cap
  (MP_SPILL_CAP_MB=1024) + MP_MANAGED_RT_PRIVATE experiment. Heat: 18 Pro (not Max)
  throttles in minutes at uncapped fps; suggest FPS cap 40, unplugged, phone cooler.
  RULES learned today: never install/relaunch without the user's explicit yes; prefer
  read-only log checks; keep status updates short (no play-by-play monitors).
  Fixes that got here (all in our layer; game bytes untouched):
  * Address space: iOS gives ~66 GB VA (64 GB @0x7000000000 + ~1.5 GB low; MAP_FIXED
    elsewhere is refused). RED reserves 16/64/32 GB allocator regions; free() routes
    by range small→medium→else large, so Policy.c stacks them top-down from
    0x8000000000 (small on top) with 8 GB real for the 64/32 GB ones (MP_VA_CAP_GB).
  * Case-insensitive paths (game asks archive/mac, install has archive/Mac).
  * Metal heaps start at 96 MB (MP_HEAP_CAP_MB, was 512): Mac build makes 3 GB+1.15 GB+…
    heaps, iOS commits heaps whole → jetsam in 2 s. Menu then holds ~2.4 GB free.
  * AppKit: CPAppKit.m (NSScreen EDR=1/SDR by default, MP_HDR=1 real; NSWindow/
    NSApplication/NSEvent/NSImage extras; NSView -setLayer: hosted as sublayer;
    safety net logs `[appkit] unimplemented ...` and returns 0).
  * Input: Cyberpunk drains the AppKit queue itself → mp_game_queue_events (Lifecycle.m
    queue for nextEventMatchingMask:); GameView becomes first responder only via a
    key-window callback → dispatch falls back to the first accepting view (Input.m).
  * Touch controls: phase8/runtime/CPControls.m (WASD stick, SPACE/F/R/C/SHIFT/LMB/
    RMB/ESC/TAB/ENTER, right-half drag = mouse look in gameplay, ⌨️ iPhone keyboard, 🎮).
  * Input path (hard-won): Cyberpunk drains the AppKit queue (mp_game_queue_events); the
    window never becomes key → mp_game_key_window falls back to the first window; GameView
    wants AppKit bottom-left locationInWindow (mp_game_appkit_points); it drops mouse moves
    unless GameWindowController.m_windowFocus, +[GameWindow isWindowVisible] and
    GameView.cursorInView are set — re-asserted on every touch start (mp_game_touch_began,
    CPAppKit.m). Buttons/look pads use mp_game_pointer_here (never (0,0)).
  * Offline libcurl (CPDesktop.m): valid handles, CURLE_COULDNT_CONNECT; setopt/getinfo
    are variadic (args on the stack on arm64 Apple); CURLOPT_PRIVATE must round-trip.
  * Memory: heaps start 96 MB + grow-on-demand spill-over heaps (900 MB margin, cap MP_SPILL_CAP_MB=1024, useHeap: hooked);
    hw.memsize reported as 3 GB (MP_MEMSIZE_GB; game GPU budget = 75%) so RED budgets smaller.
  Diagnostics: crash reporter in Main.m (`[crash]` guest offsets), MP_MEM_TRACE
  (mmap + `[gpu]` allocations), MP_FS_TRACE, MP_VA_PROBE, MP_SEL_SURVEY, `[memwatch]`
  (with MP_CONSOLE), MP_AUTOPRESS. Console run:
  `xcrun devicectl device process launch --device <UDID> --terminate-existing --console
   --environment-variables '{"MP_CONSOLE":"1"}' research.machprobe.CP2077`
  (killing devicectl SIGTERMs the app). Load-only class dump on Mac:
  `MP_DUMP_CLASSES=GameView build/phase8/cp-load build/cyberpunk/thin Cyberpunk2077`.
- Open risks: **3.44 GB app memory limit** (need com.apple.developer.kernel.increased-memory-limit
  and maybe extended-virtual-addressing — likely require a paid developer account;
  adding a capability modifies the SAME App ID, allowed); Steam API on device; touch
  controls (GameController framework works natively with MFi/Xbox/PS pads).

## Setup tooling (12 Oct 2026)
- Real device/signing values are in the git-ignored `machprobe.local.json` (device_udid,
  signing_identity, team_id, bundle_prefix=research.machprobe for this owner); tracked files use
  placeholders. Loaded by `phase7/tools/localconfig.py` (also `localconfig.profile(bundle_id)`).
- `phase8/tools/setup.py`: doctor | config | prepare-game | profile | build | install | copy-data |
  restore | launch. prepare-game rebuilds build/cyberpunk/thin (4 copies + `lipo -thin arm64`
  libsteam_api) and verifies `phase8/cyberpunk-macos-20383525.sha256`. restore never overwrites
  phone files without --force (checks the parent listing; refuses if the phone is unreadable).
- push_resume.py seeds folder trees on a fresh phone (hard-linked smallest file per folder).
- README.md = user-friendly (Part 1 agent, Part 2 by hand); AGENT-SETUP.md = the agent's setup
  script; project-documentation/videos.md = video shot list (user is recording, 12 Oct).
- 12 Oct incident: testing `restore` overwrote the phone's UserSettings.json with the recommended
  file (bug: file-existence check listed the file path itself). Fixed and re-tested; user told.
- 12 Oct: black spot fixed in the sky while the camera moves; gone with Motion Blur Off. STILL OPEN.
  Tried: spill-over heaps added to an own residency set on every queue (b71df49, installed, log shows
  "resident on all queues") — spot remains (fix kept: it is correct anyway). Ruled out: Managed->Shared
  (census: all 101 textures Private), GPU-name quirks (none in binary). Next: Metal GPU frame capture.
- Docs now warn: recent high-end iPhone recommended; serious overheating possible.
- Before publishing: git HISTORY still contains the old UDID/team/identity values (scrubbed only in
  the current tree) — rewrite history or publish a fresh repo.

## SuperTuxKart (done) quick ref
- VM: `python3 phase6/tools/build.py --quick && python3 phase6/tools/vm.py install|launch|report`.
- Phone: `python3 phase7/tools/device.py deploy|launch|report|logs|args`
  (needs STK data at Documents/stkdata/data; installing CP replaced the STK app).
- Fixes found: legacy Mac Metal profile → BC formats (disabled for STK/CP);
  MTLHeap corruption on VM (MVK_CONFIG_USE_MTLHEAP=0); VM baseVertex bug; SDL needs
  UIKit-first launch + guest entered from run-loop timer; NSApp nil until
  +sharedApplication; window delegate notification auto-subscription (keyboard focus);
  full HID→Mac keycode map + flagsChanged; touch gamepad (phase6/runtime/GameControls.m, 🎮 toggle).

## Diagnostics available
Selector survey (Documents/run-selector-survey, VM), hang watchdog + main-stack sampler,
draw/pipeline probe (MP_DRAW_PROBE=1), vertex-format probe, frame counter
(CAMetalLayer nextDrawable), env.json / arguments.json launch options.

## Plan agreed 10 Oct 2026 (next session — do in this order)
1. **Touch controls rebuild** (current CPControls.m pad is a quick hack the user finds bad):
   floating left stick (appears under the thumb, analog walk/run by deflection), bigger
   mobile-shooter button layout, right-side look area with adjustable sensitivity.
   Remove the ⌨️ iPhone-keyboard button (user: untested and useless, 12 Oct).
2. **Frame pacing / heat**: 120 Hz in menus, 60 fps cap in gameplay (optional 40 "cool" mode).
   Find what still caps at 60 (CAMetalDisplayLink preferredFrameRateRange; Info.plist already
   has CADisableMinimumFrameDurationOnPhone). Game VSync list is dynamic: valid values
   look like "120"/"30" — never write "60" into UserSettings.json.
3. **Resolution vs performance**: measure each mode (1310x603, 1564x720, 1748x804, 1956x900,
   2348x1080, native) on the same drive: fps, thermal state, memory. Pick defaults from data.
4. **In-app Steam sign-in + download** (multi-session): QR-code Steam login (app never sees
   the password), list owned games, download the macOS depot of Cyberpunk (app 1091500) from
   Valve's CDN like DepotDownloader/SteamKit (Steam enforces ownership via depot keys),
   resumable ~60 GB over Wi-Fi, then Launch. Sideload-only; note Valve ToS grey area.
- Memory work still pending (see LATE FINDINGS): dynamic GPU "memory governor" (grow when
  free, freeze on pressure / iOS memory warning), find the malloc-small creep (~1.4 MB/s —
  check our own layer first: safety net, event queue, traces), texture storage experiment.
- The prepared build (thermal + census + spill cap) is committed but NOT yet installed.

## Recommended settings (user-tuned 10 Oct): 30s-40 fps in the city
1564x720 native (ResolutionScaling Off, DRS off), VSync 120 + MaximumFPS 60 (on), Custom:
TextureQuality Low, LocalShadows Off, Cascaded/Distant shadows Low, ShadowMesh Low, LOD Low,
Crowd Low, SSR/AO/SSS/VolumetricFog/Mirror/Decals Low, VolumetricClouds Medium,
ColorPrecision Medium, FilmGrain/ChromaticAberration/DoF off, MotionBlur Off (Low causes the black blob near the sun, bug #30).
Full file: phase8/config-recommended-UserSettings.json (copy into the app's
Library/Application Support/CD Projekt Red/Cyberpunk 2077/UserSettings.json for new installs).

## Facts settled in conversation (10 Oct)
- Layer overhead is ~1-5%: game code is native ARM64, Metal is pass-through to the real
  driver (only Mac-only methods, Managed->Shared, heap caps added). FPS limits are the A20
  GPU + heat, not the layer. A CDPR-native iOS port would gain mostly via mobile tuning.
- Layer is general for other **native Apple-silicon, Metal** Mac games that fit ~6 GB and
  have no hard DRM/anti-cheat (candidates: Baldur's Gate 3, No Man's Sky, Lies of P, Control,
  Stray). Per-game work: address-space layout, memory budgets, focus/cursor quirks.
- Policy: run only the user's own retail copies; never leaked/stolen source code (user asked
  about leaked GTA V source — refused; retail GTA V would need Windows+x86 translation, out
  of scope; user agreed, 120 GB not worth it).
- Profile expiry: app stays installed with data when the profile expires; re-sign + install
  over it (same App ID) keeps the 60 GB + saves. NEVER delete the app. Current expiry 17 Oct.
- Backups on the Mac: game data = Steam install (61 GB); saves = ~/Library/Application Support/
  CD Projekt Red/Cyberpunk 2077/saves (Steam Cloud copy, Oct 9); phone EULA file =
  build/phase8-runtime/userdata/user.gls; settings = phase8/config-recommended-UserSettings.json.
  Phone saves go in Library/Application Support/CD Projekt Red/Cyberpunk 2077/saves (container root).
- Heat: 18 Pro (not Max) throttles within minutes at uncapped fps; charging adds heat;
  magnetic Peltier cooler helps most; FPS cap 40/60 is the best software lever.
- User preferences: no MetalFX/upscaling ("lazy"), native resolution; ask before every
  install/relaunch unless the user explicitly grants overnight autonomy; short updates.
