# Phase 8: Cyberpunk 2077 (overview only)

Dates: 2026-10-09 to 2026-10-10. Commits `e831216` through `5e022eb` (the range has
19 commits, listed in `git log`). **This file is a brief summary.** The
detailed Cyberpunk documentation is in [`../04-cyberpunk/`](../04-cyberpunk/).
Sources for this summary: `CONTEXT.md` (the working handoff, last updated
9 October and changed on disk since), `progress.md`, and the commit messages.

**Status: in progress.** The most recent repository record describes the game
as playable on the user's iPhone, with performance and memory work still open.

## Goal

Run the user's own Steam copy of Cyberpunk 2077 (macOS build, Steam app 1091500)
on the user's iPhone 18 Pro, through the same loader and adapter layers used in
Phases 4 to 7. Game bytes are not modified; the repository says they are
hash-checked at launch. The game is 61 GB installed, so the phone receives the
data (archive, engine and r6 folders) over USB, not through the repository.

## Target

- Steam app 1091500, build 20383525, installed on the Mac.
- A thin arm64 copy of five images: `Cyberpunk2077` and four frameworks
  (`libBink2MacArm64`, `libGameServicesSteam`, `libREDGalaxy64`,
  `libsteam_api`). Kept under `build/cyberpunk/thin/`, with hashes.
- Mac load-only check: 685,682 rebases, 71,348 binds, 495 selectors and 7,458
  initializers (`CONTEXT.md`).

## Milestones (from commit messages)

| Commit | Milestone |
|---|---|
| `e831216` | Preparation: loader export-trie exports, `__init_offsets` initializers, chained-import deferral, `LC_ENCRYPTION_INFO_64` with `cryptid 0` accepted. A lean host and an offline import-gap analysis against SDK `.tbd` files (about 75 real gaps). |
| `0908351` | Main menu reached on iPhone 18 Pro. Address-space rationing, case-insensitive paths, Metal heaps capped at 512 MB, AppKit additions, crash reporter. |
| `2dee2ac` | Touch input reaches the game's view, with touch controls. |
| `b5dd60b` | Main-menu load passes. Offline libcurl keeps request state. |
| `e43a29b`, `e348889`, `a9bb2bc` | Working menu touch; window focus re-sent; pointer gates re-asserted per touch. |
| `538ebc6` | Night City reached. Spill-over GPU heaps; 8 GB reported memory size. |
| `3455929` | Native 1956 x 900 rendering with aspect-correct display modes. |
| `25bef28` | TLS fast path; no per-frame overhead in the layer. |
| `04c412a`, `0cb6e9e` | Memory reporting, grow-on-demand heaps, performance and thermal telemetry, texture census, spill-over cap. |
| `aa32a9b` | Recommended iPhone settings (1564 x 720, 60 fps cap). |
| `ed2227a` | App icon taken from the user's own install at build time (never stored in the repository). |
| `5e022eb` | Own App ID, `research.machprobe.CP2077`, after another project's install replaced the `STKHost` app. |

## Main problems (summary)

| Problem | How it appeared | Outcome recorded |
|---|---|---|
| The game reserves 16, 64 and 32 GB allocator regions, but iOS gives about 66 GB of address space | Startup failure | Policy stacks the regions top-down (`Policy.c`) with 8 GB real memory for the big ones. |
| Game asks for paths in another case (`archive/mac` vs `archive/Mac`) | File errors | Case-insensitive resolution for guest path calls. |
| The Mac build asks for multi-GB Metal heaps; iOS commits them whole | Jetsam kill within seconds | Heaps capped at 512 MB, with spill-over heaps added as needed. |
| Mouse and focus gates dropped input | Menus did not respond | Gates re-asserted per touch. Input path documented in the handoff. |
| Offline libcurl stubs did not keep request state (a NULL `CURLOPT_PRIVATE` corrupted memory) | Crash at the main menu | Valid handles, `CURLE_COULDNT_CONNECT`, variadic `setopt`/`getinfo` arguments read from the stack, and `CURLOPT_PRIVATE` and URL kept. |
| Writing `60` into the VSync setting was invalid, which gave a silent 30 fps cap | Frame rate | The game's list is dynamic; 120 with the 60 fps cap works. |
| GPU-bound at about 22 to 24 fps in the city; the phone heats up and throttles | Telemetry | Recommended settings, fps cap and cooling. Work still open. |
| Memory: the app limit was 3.44 GB before the increased-memory entitlement (about 6.0 to 6.4 GB available with it, per `CONTEXT.md`); malloc creep of about 1.4 MB/s; engine regions growing about 1.2 GB on world load | Telemetry and a memory kill on a car crash | Open. Memory governor and allocator investigation listed as next steps. |

## Results at the last repository record

- Playable end to end on the iPhone 18 Pro, with the user's own save.
- Controllers work through GameController. Touch menus and a touch pad work.
- Native 1956 x 900 or 1748 x 804 pixel modes. The user rejected upscaling.
- About 22 to 24 fps in the city at 804p Low. The telemetry reports GPU-bound.
- The recommended settings (1564 x 720, 60 fps cap) gave 30 to 40 fps in the
  city, per the user's own tuning (`aa32a9b`).

## Rules recorded during the phase

- Never run Cyberpunk on the Mac. An earlier Mac `--run` reached the engine's
  threads and took over the screen. Mac checks are load-only.
- Never install or relaunch on the phone without the user's explicit yes.
- Never overwrite the phone's user settings file or save data.
- Use one App ID for this game (`research.machprobe.CP2077`). Do not reuse the
  `STKHost` App ID.

## Next steps

See [`../04-cyberpunk/`](../04-cyberpunk/) for the detailed status, and
`CONTEXT.md` ("Plan agreed 10 Oct 2026") for the list in the repository: touch
controls, frame pacing, resolution tuning, memory work, and an in-app Steam
sign-in and download. Those items are recorded as plans, not results.
