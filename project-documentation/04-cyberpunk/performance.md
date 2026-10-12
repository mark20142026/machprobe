# Performance: what limits the frame rate on the phone

Cyberpunk 2077 runs at about 30-40 fps on the iPhone 18 Pro at 1564x720 with the
recommended settings, and it can hit 60 fps in calm scenes. This file records what
the telemetry shows, what the layer costs, the VSync discovery, the settings the user
chose, heat, and why upscaling was not used. Sources are the commits named inline,
`phase8/runtime/CPMetal.m`, `phase8/runtime/CPAppKit.m`, `phase8/host/Main.m`,
`phase8/tools/build.py`, `phase8/config-recommended-UserSettings.json`, and the
CONTEXT.md history.

## Bottom line

- The game is GPU-bound. Main-thread CPU is about 1 %, and about 2 of the 6 CPU
  cores are busy (CONTEXT, 9 Oct).
- Turning the graphics options down helps only a little (CONTEXT: "minimum settings
  barely help"). Resolution and shadows matter more than the CPU side.
- The layer adds about 1-5 % overhead (CONTEXT, 10 Oct). The game's code is native
  arm64 and Metal calls pass through to the real driver. The remaining limits are
  the A20 Pro GPU and heat, not the layer.
- Frame-rate cap is partly a configuration problem: a wrong VSync value silently
  halved the frame rate for a while (see below).

## Telemetry

`Main.m` prints a `[perf]` line every 5 s:

```
[perf] t=Ns gpu_busy=X% main_thread=Y% all_cpu=Z% thermal=STATE textures(managedRT=.. managed=.. shared=.. private=..)
```

- `gpu_busy` is the sum over command buffers of `GPUEndTime - GPUStartTime`
  (`counted_commit` in `CPMetal.m`, installed by `mp_cp_gpu_timing_install`). It
  overstates busy time when buffers overlap: CONTEXT notes that the 300 % reading
  from 9 Oct sums overlapping buffers and that intervals must be merged for a true
  figure.
- `main_thread` and `all_cpu` come from `thread_info` and `getrusage` deltas.
- `thermal` is `NSProcessInfo.thermalState` (nominal, fair, serious, critical),
  added in `0cb6e9e`.
- The texture census counts Managed render targets, other Managed, Shared and
  Private textures created by the game (`mp_tex_census`, `CPMetal.m`).

`[budget]` (every 5 s) carries the frame rate from the frame counter, so fps and
memory can be read on the same line. See `memory.md`.

## Layer overhead and the TLS fast path

- `25bef28`: the thread-local-storage thunk got a dyld-style fast path
  (`TPIDRRO_EL0` plus a per-image pthread key; six instructions; slow path only on a
  thread's first access). Phase 5.5 TLS tests still pass (288 workers, 12 unloads,
  per the commit body).
- The safety net in `CPAppKit.m` is lock-free and dedupes with a small atomic table,
  so a selector the game sends every frame costs a few loads.
- Report sampling and trace writes run off the game's main thread
  (`mp_game_trace`, `Main.m`).
- `useHeap:` hooks cost nothing until a spill-over heap exists (`overflows()`
  checks a flag first).
- Managed storage is rewritten to Shared at creation (`CPMetal.m`). On unified
  memory this changes no CPU or GPU view, but Apple GPUs keep lossless compression
  for Private textures and not for Shared ones (CONTEXT). That is a possible GPU
  bandwidth cost, which is why the Managed-to-Private experiment exists.

## Managed-to-Private experiment

- Flag: `MP_MANAGED_RT_PRIVATE=1` (in `Documents/env.json` or the environment).
- Effect: Managed render targets become Private. Other Managed resources stay Shared.
- Status: built in `0cb6e9e`, not yet run on the phone (CONTEXT). It is valid only
  if the CPU never writes those render targets, which is the assumption to test.

## The VSync discovery (9-10 Oct)

- The game's VSync option list is dynamic. Values seen are "120" and "30".
- Writing "60" into `UserSettings.json` produces an invalid value, and the game
  silently falls back to a 30 fps cap. That explains the 30-fps ceilings seen before
  the discovery.
- With VSync set to 120 in the game, calm scenes ran at a locked 60 fps (16.7 ms
  frames; CONTEXT). Driving stays at 25-40 fps.
- Something still limits presentation to 60 fps. Candidates checked: the Info.plist
  key `CADisableMinimumFrameDurationOnPhone` is set (`phase8/tools/build.py`), which
  allows 120 Hz. `CAMetalDisplayLink` `preferredFrameRateRange` was named in
  CONTEXT as the thing to check; the repository has no code that sets it. Status:
  unknown.
- `NSScreen` answers in `CPAppKit.m` pass through UIKit's `maximumFramesPerSecond`
  (and `minimumRefreshInterval` derived from it), so the game sees the panel's real maximum.

## Recommended settings

File: `phase8/config-recommended-UserSettings.json` (commit `aa32a9b`, tuned by the
user on the phone). Key choices, from CONTEXT:

| Setting | Value |
|---------|-------|
| Resolution | 1564x720, native (ResolutionScaling Off, DRS off) |
| VSync | 120 (valid value; see the VSync section) |
| MaximumFPS | 60, on |
| Texture quality | Low |
| Local shadows | Off |
| Cascaded and distant shadows | Low |
| Shadow mesh, LOD, crowd | Low |
| SSR, AO, SSS, volumetric fog, mirror, decals | Low |
| Volumetric clouds | Medium |
| Color precision | Medium |
| Film grain, chromatic aberration, depth of field | Off |
| Motion blur | Low |

Result: 30-40 fps in the city, with the frame cap at 60. The 1564x720 mode is
computed by the host from the panel's aspect ratio (`Main.m` mode list:
`lround(720 * aspect)` rounded down to even). With these settings the game's built-in
benchmark averaged **39.44 fps** (run on the phone by the project owner, 10 Oct 2026).

To install the file on a new phone install, copy it to the app's
`Library/Application Support/CD Projekt Red/Cyberpunk 2077/UserSettings.json`
(CONTEXT). Never write a value the game did not list (see the VSync section).

## Resolution history

| Mode | Where | Result |
|------|-------|--------|
| 874x402 points, 50-65 % DRS | before `3455929` | Render size the layer reported at the time (per the commit body) |
| 1956x900 native, DRS off | `3455929` | Native pixel mode offered first; no separate fps figure at 1956x900 is recorded. The 22-24 fps city figure in CONTEXT is for 804p Low |
| 1564x720 native | `aa32a9b` | User's choice: 30-40 fps in the city |

The resolution sweep (1310x603, 1564x720, 1748x804, 1956x900, 2348x1080, native)
is still planned (`known-issues.md`).

## Heat and thermal throttling

- The 18 Pro (not the Max) throttles within minutes at uncapped frame rates (CONTEXT).
  Charging adds heat. A magnetic cooler helped most (CONTEXT, user report).
- `[perf]` logs the thermal state every 5 s. CONTEXT suggests a frame cap of 40 for
  long sessions and 60 when the phone is cool. The settings file carries the 60 value;
  the 40 option is a runtime choice.
- The thermal telemetry (`0cb6e9e`) was built, but a thermal log from a long session
  is not recorded in the repository.

## Upscaling was rejected

- MetalFX is linked in `build.py` and allowed by the policy (`phase8/runtime/Policy.c`
  lists `/System/Library/Frameworks/MetalFX.framework`). Nothing in the repository
  turns it on for the game.
- The user rejected upscaling and asked for native resolution and real optimization
  (CONTEXT, user preferences). That choice is final for now.

## Instruments

- `xctrace` showed the phone as offline on 9 Oct (CONTEXT). Retry with a Metal System
  Trace is pending.
- Until then, all measurements are the in-app telemetry above.

## Open performance items

1. Find what caps presentation at 60 fps (`CAMetalDisplayLink`, frame pacing) and
   allow 120 Hz in menus.
2. Resolution sweep with the same drive for each mode: fps, thermal state, memory.
3. Managed-to-Private experiment on the phone.
4. Merge overlapping command-buffer intervals so `gpu_busy` is a real percentage.
5. Find the largest GPU consumers in the city (texture census by size).
