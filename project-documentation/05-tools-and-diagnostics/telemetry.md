# Telemetry: log lines, status file, and what they were used for

Everything the Phase 8 app prints goes to `Documents/runtime-stderr.log` (or the
`devicectl --console` stream when `MP_CONSOLE` is set). The status file is
`Documents/runtime.json`. Each family below is listed with its source, format, and
meaning. The last section shows how the numbers were used to find real bugs. Numbers
quoted there come from `CONTEXT.md`; they are not re-measured in this document.

| Family | Source | When |
|---|---|---|
| `[budget]` | `phase8/host/Main.m` telemetry thread | every 5 s, always |
| `[vmtags]` | `phase8/host/Main.m` telemetry thread | every 10 s, always |
| `[perf]` | `phase8/host/Main.m` telemetry thread | every 5 s from t=5 s, always |
| `[memwatch]` | `phase8/host/Main.m` | every 1 s, only with `MP_CONSOLE` |
| `frame_window` (in `runtime.json`) | `phase6/runtime/FrameCounter.m` | continuous, read by the loops above |
| watchdog (`main_stack_*`, stage `main thread stalled`) | `phase6/runtime/Watchdog.m` | only with `Documents/debug` |
| `[mem]`, `[gpu]`, `[fs]`, `[va]`, `[sel]`, `[crash]`, `[cursor]`, `[engine]`, `[keys]`, `[focus]`, `[auto]`, `[appkit]` | various (see below) | mostly gated by an env variable |

---

## 1. `[budget]`: frame rate and memory

Format (N = a number):

```
[budget] t=Ns fps=N footprint=N MB gpu=N MB cpu=N MB free=N MB
```

| Field | Meaning | Source in code |
|---|---|---|
| `t` | Seconds since the telemetry thread started (0, 5, 10, ...). | loop counter |
| `fps` | Guest frame rate over the last up to 240 drawable acquisitions. | `mp_stk_frame_window()["window_fps"]` |
| `footprint` | The app's physical memory footprint (what jetsam counts). | `task_vm_info.phys_footprint` |
| `gpu` | Memory allocated on the GPU device. | `MTLDevice.currentAllocatedSize` |
| `cpu` | Footprint minus GPU, floored at 0. An estimate of the non-GPU part. | derived |
| `free` | Memory the system still allows this process to use before a memory kill. | `os_proc_available_memory()` |

Read the `free` field first: it is the figure the system uses to decide on a memory kill.
The `footprint` trend shows how fast it is falling.

## 2. `[vmtags]`: where the memory is, by VM tag

Format (N = a number; the list has up to eight `tagN=N` entries):

```
[vmtags] t=Ns engine-regions=N MB tagN=N MB ...
```

Only regions with dirty or swapped-out pages are counted (their size in MB). Field meanings:

- `engine-regions`: the sum of regions at addresses `0x7000000000` to `0x8000000000` with
  user tag 0. These are the RED Engine allocator's reservations (`phase8/runtime/Policy.c`).
- `tagN=MB`: the top eight VM tags by size, each over 64 MB. The tags that matter here are
  `tag2` = `VM_MEMORY_MALLOC_SMALL` and `tag100` = `VM_MEMORY_IOACCELERATOR` (both checked
  in the macOS SDK header `mach/vm_statistics.h`). Other tags are not named in the code.

## 3. `[perf]`: GPU, CPU, thermal, textures

Format (N = a number):

```
[perf] t=Ns gpu_busy=N% main_thread=N% all_cpu=N% thermal=<state> textures(managedRT=N managed=N shared=N private=N)
```

| Field | Meaning | Caveat |
|---|---|---|
| `gpu_busy` | Sum of `GPUEndTime - GPUStartTime` over every command buffer committed in the last 5 s, as a percent of 5 s (`CPMetal.m`, `counted_commit`). | Command buffers that overlap are both counted. A value above 100% means overlap, not more than one GPU. `CONTEXT.md` says this overstates busy time and that intervals should be merged. |
| `main_thread` | CPU time of the main thread over 5 s, as a percent. | 100% is one full core. |
| `all_cpu` | CPU time of the whole process over 5 s, as a percent. | Can exceed 100% (multi-core). |
| `thermal` | `NSProcessInfo.thermalState`: `nominal`, `fair`, `SERIOUS`, `CRITICAL`, or `?`. | Added in the commit `0cb6e9e` after the phone overheated. |
| `textures(...)` | Cumulative counts of texture creations since launch, by storage mode: `managedRT` (managed render targets), `managed` (other managed), `shared`, `private`. | These count `newTextureWithDescriptor` calls on the device object only; heap textures are not counted. They are not live totals. |

## 4. `frame_window` (FrameCounter)

In `runtime.json`, under `frame_window`. Source: `phase6/runtime/FrameCounter.m`. It
hooks `-[CAMetalLayer nextDrawable]` and keeps the last 240 acquisition times.

| Key | Meaning |
|---|---|
| `drawables` | Total drawables acquired since launch. |
| `window_frames`, `window_seconds` | Frames in the window and their time span. |
| `window_fps` | `(frames - 1) / span`. This is the guest's production rate, not the display's scan-out rate. |
| `last_second_frames` | Frames acquired in the last second. Shows menu-to-race transitions quickly. |
| `worst_interval_ms` | Largest gap between two consecutive acquisitions in the window. A steady 60 fps cap shows up as about 16.7 ms here. |
| `seconds_since_last` | Time since the last acquisition. A large value suggests the game has stopped presenting. |

The window is measured in drawables, so it tracks what the game presents, not what the
display shows.

## 5. Watchdog (debug only)

Source: `phase6/runtime/Watchdog.m`. Started only when `Documents/debug` exists (`Main.m`
line 162). The game's run loop calls `mp_watchdog_beat()` on every event poll
(`phase5/runtime/Lifecycle.m`, `nextEventMatchingMask:`). The heartbeat increments once per
poll.

- Every second, the watchdog checks the heartbeat. If it has not moved for 5 s, it captures
  the main thread's stack (frame-pointer walk; symbolised with `dladdr`, which also resolves
  guest images) and writes it to `runtime.json` as `main_stack_stalled`, with stage
  `main thread stalled (watchdog)`. It repeats every 15 s while the stall lasts.
- Every 10 s it captures a sample into `main_stack_sample` and calls the sampler, which
  rewrites `runtime.json`.

A stall is not always a bug. The game may stop polling events on purpose (for example while
loading). The stack shows where the main thread is, not why it stopped.

Note: `phone.py report` does not print `main_stack_stalled` or `main_stack_sample`. Read
`build/phase7/runtime.json` instead (`phone.py report` pulls the file there, or call
`device.pull('runtime.json')` from `phase7/tools/device.py`).

## 6. `[memwatch]` (console only)

`[memwatch] t=12s available=640 MB` once a second, only with `MP_CONSOLE`. It gives the
same `free` figure as `[budget]` at finer resolution. Use it when the console is attached.

---

## 7. Lines gated by environment variables

| Line prefix | Gate | Source | Meaning |
|---|---|---|---|
| `[mem] placed N GB reservation at ... with M GB real` | always | `Policy.c` `guest_mmap` | A large reservation was placed in the top-down stack with M GB backed. |
| `[mem] could not place ...`, `[mem] refused MAP_FIXED ...`, `[mem] mmap ... -> ... errno` | always (failures) | `Policy.c` | Address-space problems. The last one is the first thing to check after a mapping failure. |
| `[mem] mprotect ... entirely in a rationed tail` | always | `Policy.c` | A protection change hit an unbacked tail. |
| `[mem] mmap / malloc / sysctlbyname ...`, `[mem]    <caller>` | `MP_MEM_TRACE` | `Policy.c` | Large mappings (64 MB or more), malloc of 64 MB or more, all `sysctlbyname` calls, and up to five callers. |
| `[gpu] heap ... full: spill-over heap #n of M MB` | always | `CPMetal.m` `spill_heap` | A capped heap was full; a spill-over heap was added. |
| `[gpu] heap ... FULL: texture|buffer ... failed` | always (first 20) | `CPMetal.m` | No space even with a spill-over heap. |
| `[gpu] texture FAILED: ...` | always | `CPMetal.m` `tex` | The device refused a texture; the line gives its descriptor. |
| `[gpu] <kind> N MB (total ... in ... allocations) from <guest symbol>` | `MP_MEM_TRACE` | `CPMetal.m` `gpu_trace` | GPU allocations of 16 MB or more, with running totals and the guest caller. |
| `[gpu]   heap type=... ` | `MP_MEM_TRACE` | `CPMetal.m` `heap` | Heap descriptor details. |
| `[gpu] spill-over residency hooks on ...` | always, once | `CPMetal.m` | The encoder classes were hooked. |
| `[fs] opendir/stat/access/open/fopen/... -> result` | `MP_FS_TRACE` | `Policy.c` | Every file-system call the guest makes through the wrappers. |
| `[fs] case <requested> -> <found>` | `MP_FS_TRACE` | `Policy.c` `ci` | A case-insensitive remap was applied. |
| `[va] ...` | `MP_VA_PROBE` | `Main.m` | Address-space experiment (see [debugging-playbook.md](debugging-playbook.md)). |
| `[sel] missing <selector>`, `[sel] survey done` | `MP_SEL_SURVEY` | `Main.m` | Selector survey. |
| `[crash] signal ...`, `[crash] pc ...`, `[crash] frame ...` | always (on a fatal signal) | `Main.m` `crash` | Fault report. See the playbook. |
| `[appkit] unimplemented -[Class sel] -> 0` | always, once per pair | `CPAppKit.m` `forward` | The game sent a selector the stand-ins lack; it got zero. A to-do list. |
| `[focus] ...` | always | `CPAppKit.m` `mp_cp_refocus` | Focus re-send and each controller's `m_windowFocus`. |
| `[cursor] ...`, `[engine] ...`, `[keys] ...` | `MP_CURSOR_TRACE` | `CPAppKit.m` | Pointer, engine input state, and held keys, logged on change. |
| `[auto] key N` / `[auto] tap x,y` | `MP_AUTOPRESS` / `MP_AUTOTAP` | `CPControls.m` | Unattended input events. |
| `[memwatch] ...` | `MP_CONSOLE` | `Main.m` | See section 6. |

---

## 8. How the telemetry was used to find bugs

Each item lists the observation, what it led to, and the source. Items marked "per
`CONTEXT.md`" are recorded there and are not re-measured here.

1. **Memory kill in gameplay.** Per `CONTEXT.md`: a kill came in a car-crash scene at about 265 MB free. `[budget]`
   showed `free` falling, `[vmtags]` showed `tag2` (malloc small) growing about 1.4 MB/s,
   `tag100` (IOAccelerator) near 820 MB, and engine regions at 2.37 GB. The next step was to
   check the layer's own allocations before blaming the game.
2. **Jetsam within seconds of heap creation.** Per `CONTEXT.md`, the Mac build's 3 GB, 1.15 GB
   and similar heaps were committed whole on iOS. The fix was to cap heap size (`MP_HEAP_CAP_MB`)
   and add spill-over heaps as the game fills them. `CONTEXT.md` records 512 MB as the cap at the time;
   the code default is now 96 MB. Evidence: `[gpu] heap ... FULL` and the `gpu` field in `[budget]`. Commit
   `04c412a` ("grow-on-demand heaps; perf telemetry").
3. **GPU-bound rather than CPU-bound.** `[perf]` showed `gpu_busy` near 300% (overlap-summed),
   `main_thread` near 1%, and all-CPU near 2 of 6 cores. Per `CONTEXT.md` this pointed to
   the GPU, so CPU work was not the first target. Caveat above: `gpu_busy` overstates busy time.
4. **A silent 30 fps cap.** Per `CONTEXT.md`, writing `"60"` into `UserSettings.json` for
   VSync was invalid; the game's list is dynamic (`"120"`, `"30"`). The frame window showed
   about 30 fps until VSync was set to 120 in-game, which gave 60 fps in calm scenes. Lesson:
   check the value the game accepts, not the one you expect.
5. **A 60 fps ceiling still unexplained.** Per `CONTEXT.md`: locked 16.7 ms intervals
   (`worst_interval_ms`) in calm scenes, and something still caps at 60. The open suspect is
   `CAMetalDisplayLink`'s frame-rate range. Not yet resolved.
6. **Heat.** `[perf] thermal` was added after the phone overheated. Per `CONTEXT.md` the phone
   throttles within minutes at uncapped frame rate, so the recommended setting is a cap of 40 to 60 fps.
7. **Texture storage experiment.** The `textures(...)` census showed how many render targets
   were Managed. That led to `MP_MANAGED_RT_PRIVATE` (Managed render targets to Private),
   which is an experiment. Managed-to-Shared loses lossless compression, per `CONTEXT.md`.
8. **Input path.** Per commit subjects in `git log` (`e348889`, `a9bb2bc`, `2dee2ac`): the
   window never became key, and the game dropped mouse moves until its focus and visibility
   flags were set. The `[focus]`, `[cursor]` and `[engine]` lines (gated by `MP_CURSOR_TRACE`)
   showed those flags, which led to `mp_cp_refocus` and the per-touch re-assertion in
   `mp_game_touch_began`.
9. **Missing AppKit methods.** The `[appkit] unimplemented` lines, plus `MP_SEL_SURVEY`
   (`phase8/host/selectors.txt`), gave the list of methods added to the stand-ins
   (`CPAppKit.m`, per its header).
10. **Hangs.** The watchdog's `main_stack_stalled` captures the main thread's stack when the
    game stops polling events. Use it with `frame_window.seconds_since_last`.

## 9. Reading the lines together

- A healthy session shows `[budget] fps` near the cap, `free` steady, `thermal=nominal`,
  and `main_thread` low.
- `free` falling while `tag2` or `tag100` grows points at a leak in one of those areas.
  Check `[gpu]` and `[mem]` lines for the same time.
- `fps` low with `gpu_busy` high and `main_thread` low points at GPU work. Check the
  texture census and the render scale before changing game code.
- `thermal` at `SERIOUS` or above means the frame rate will fall whatever the code does.
