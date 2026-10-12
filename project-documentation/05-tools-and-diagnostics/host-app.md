# The iOS host app and the Mac load harness

Two entry points. `phase8/host/Main.m` is the iPhone app (`CP2077Host`). It loads the
guest images, runs the game, and writes the telemetry. `phase8/host/LoadCLI.m` is the
Mac-only load harness (`build/phase8/cp-load`). It loads the same images without
starting the game, and offers introspection flags.

The host is "lean" by design (its own header says so): real Metal objects, and
diagnostics only when they are asked for.

---

## 1. Main.m: startup sequence

Line numbers refer to `phase8/host/Main.m`.

1. **Exception and signal setup** (lines 86-89). `NSSetUncaughtExceptionHandler(exception)`.
   A 64 KB alternate signal stack (`sigaltstack`) so stack overflows can be reported. The
   crash handler is installed for SIGILL, SIGTRAP, SIGABRT, SIGBUS, SIGSEGV, SIGFPE, SIGSYS.
2. **env.json** (lines 91-94). Reads `Documents/env.json`. Each key that starts with `MP_`
   and has a string value is set with `setenv` before anything else reads the environment.
   This lets you change tuning without rebuilding. See section 4 for the timing caveat.
3. **Log redirection** (lines 95-99). If `MP_CONSOLE` is not set, stderr and stdout are
   redirected to `Documents/runtime-stderr.log` and `runtime-stdout.log`. Both are
   line-buffered. With `MP_CONSOLE` set, output goes to the `devicectl --console` stream.
4. **Report init** (lines 100-101). `Documents/runtime.json` is the status file. It gets a
   `run_id` (UUID), `pid`, `game`, and then `stage("start")`.
5. **Debug flag** (line 103). `debug` is true if `Documents/debug` exists. In the current
   code it controls only the watchdog (section 6). The file's header comment says "diagnostics
   only with Documents/debug present", but the telemetry threads run regardless.
6. **VA probe** (lines 104-117, only with `MP_VA_PROBE`). Runs the address-space experiment
   and calls `exit(0)`. See [debugging-playbook.md](debugging-playbook.md).
7. **GPU install** (line 118). `mp_cp_metal_install()` installs the Metal adapters
   (`CPMetal.m`); `report["gpu"]` records the device features; `stage("gpu ready")`.
8. **Manifest and guest hashes** (lines 119-133). Reads `target.json` from the bundle. For
   each entry (1-32 images), `dlopen`s the container from `privateFrameworksPath`, finds its
   header with `_dyld_get_image_header`, and reads the `__TEXT,__guest` section with
   `getsectiondata`. It hashes the first `slice_size` bytes with SHA-256 and compares with
   the manifest. On mismatch: `stage("guest hash mismatch")` and return 1. Then
   `stage("guest hashes verified")`.
9. **Virtual executable and data layout** (lines 134-141). The guest's executable path is
   `Documents/Cyberpunk 2077/Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077`. The file is
   created as an empty path anchor (the code is in the containers). It is exported as
   `MP_GUEST_EXECUTABLE_PATH`, which `Policy.c` reads. The `~/Library/Logs/Cyberpunk 2077`
   folder is created for the game's GameServices log. `report["data_present"]` records
   whether `archive`, `engine` and `r6` exist.
10. **Working directory and shim** (lines 142-143). `chdir` to `Documents/Cyberpunk 2077`.
    `mp_extended_set_shim(mp_ios_shim)` installs the Swift shim.
11. **Guest arguments** (lines 144-146). Reads `Documents/arguments.json` (an array of
    strings). The guest's `argv` is `Cyberpunk2077` followed by up to 32 of them.
12. **Group load** (lines 147-150). `mp_group_open(sources, count, services, error)` with
    `services.extensions = mp_cp_policy()` (`Policy.c`). Failure: `stage("group load failed")`.
13. **Selector survey** (lines 151-158, only with `MP_SEL_SURVEY`). Compares the selectors in
    `selectors.txt` against all methods of all host classes. Prints `[sel] missing <name>`
    for each absent one, then `exit(0)`.
14. **Load statistics** (lines 159-161). Sums rebases, binds and initializers over the group
    and stores them as `report["load"]`.
15. **Watchdog** (lines 162-164, only when `debug`). Starts the hang detector and the
    main-stack sampler.
16. **Exit stage** (line 165). `atexit_b` writes `stage("process exit")`.
17. **Telemetry thread** (lines 166-200). Detached thread that prints `[perf]`, `[vmtags]`
    and `[budget]` every 5 s. Section 5 describes it.
18. **Memory watch** (lines 201-203, only with `MP_CONSOLE`). `[memwatch]` once a second.
19. **Launch hook** (lines 204-211). The guest's `main` is not run here. It is registered
    with `mp_game_set_launch_hook`, which runs it from UIKit's run loop. When it returns:
    `entry_status`, `guest_exit`, `stage("guest returned")`, then `exit`.
20. **Report sampler** (lines 212-215). A utility-QoS dispatch timer starts after 2 s and
    fires every 2 s. It calls `mp_game_sample()`, which rewrites `runtime.json`.
21. **Input mode** (line 216). `mp_game_queue_events = YES`: the game drains the AppKit
    event queue itself.
22. **Display modes** (lines 217-224). See section 3.
23. **Input and controls** (lines 225-226). `mp_game_touch_scroll` and `mp_game_appkit_points`
    are set, then `mp_cp_install_controls()` (section 3).
24. **Run UIKit** (line 227). `return mp_game_run_uikit()`.

---

## 2. Crash handler and the alternate stack

`crash(sig, si, context)` (lines 73-83) runs on the alternate stack. It writes plain text
to stderr with `write(2, ...)` (no allocation, no locks), so it works from a signal handler.

Output, in order:

- `[crash] signal N at <fault address>; initializer <image> #<index> offset <off>`:
  the initializer the loader was running, from the globals `mp_init_image`, `mp_init_index`,
  `mp_init_offset` (`runtime/services.c`).
- If the fault address falls in an unbacked tail of a rationed reservation,
  `[crash] fault is in the unbacked tail of a rationed guest reservation (raise MP_VA_CAP_GB)`.
  This comes from `mp_cp_va_tail` in `Policy.c`.
- `pc`, `lr`, and `x0` to `x8` through `crash_line`.
- Up to 40 frames of the frame-pointer chain, labelled `frame`.

`crash_line(label, addr)` resolves an address in this order:

1. `mp_locate(addr, &off)` (`runtime/image.c`): if the address lies in a guest image,
   prints `<image>+<offset>`. The offset is relative to the image's load base.
2. Otherwise `dladdr`: prints `<library>`<symbol>+<offset>` for host code.
3. Otherwise the raw address.

After printing, the handler calls `signal(sig, SIG_DFL)` and returns, so the default
action applies. Signal crashes go only to stderr (or the console). They do not update
`runtime.json`. Uncaught Objective-C exceptions go to `exception()`, which does update it
(section 4).

`sigaltstack` (line 87) is what makes this work after a stack overflow.

---

## 3. Display modes and control install

**Display modes** (lines 217-224). Takes `UIScreen.nativeBounds` (in landscape: width larger
than height). For each height in `{900, 1080, 804, 720, 603}` at or below the native height,
width is `lround(height * aspect)` rounded down to even. The native size is appended last.
`mp_display_set_modes` (`phase5_5/runtime/Display.m`) registers them; per the comment there,
the first one is the current mode, so 900p is the one the game starts with. On the iPhone 18 Pro, the native size is 2622x1206 in the code's comment,
which gives 1956x900, 2348x1080, 1748x804, 1564x720, and 1310x603 (matching the modes in
`CONTEXT.md`).

**Control install** (`mp_cp_install_controls`, in `phase8/runtime/CPControls.m`). Called
from line 226. A 0.5 s timer waits until the game's view has a window, then installs the
overlay once, and starts the cursor, engine and key traces (all gated on `MP_CURSOR_TRACE`).
It schedules `mp_cp_refocus()` one second later. Details in
[phase8-runtime-reference.md](phase8-runtime-reference.md).

---

## 4. Diagnostic file and environment inputs

| Path in the app container (`Documents/`) | Written by | Read by | Purpose |
|---|---|---|---|
| `env.json` | user, by hand (no `phone.py` subcommand) | `Main.m` at start | JSON object of `MP_*` string values, applied with `setenv`. |
| `arguments.json` | `phone.py args` | `Main.m` at launch | Guest argv (after `Cyberpunk2077`). |
| `debug` | `phone.py debug on` | `Main.m` at start | Enables the watchdog. |
| `runtime.json` | `Main.m` (`stage`, `mp_game_trace`, sampler) | `phone.py report`, `device.py` | Status: stage, load, gpu features, frame window, memory, events. |
| `runtime-stderr.log`, `runtime-stdout.log` | `Main.m` (unless `MP_CONSOLE`) | `phone.py logs` | All `fprintf` output. |
| `Cyberpunk 2077/` | `push-data` / `push_resume.py` | the guest | Game data (`archive`, `engine`, `r6`). |

**Timing caveat (from the code; not tested on device).** `env.json` is applied at the start of
`main()`. Anything read inside a C `__attribute__((constructor))` runs before `main()`, so
`env.json` cannot set those values. In `CPControls.m`, `MP_AUTOPRESS` and `MP_AUTOTAP` are read
in constructors. They must come from the real process environment (for example
`devicectl --environment-variables`). `MP_CURSOR_TRACE` is read later, in timers, so
`env.json` works for it. Most other `MP_*` variables are read lazily when first used.

**`runtime.json`.** Written with `NSJSONSerialization` and an atomic file write, under
`reportLock`. Keys: `run_id`, `pid`, `game`, `stage`, `frame_window` (from `FrameCounter.m`),
`input` (main thread only), `memory_available_bytes`, `gpu`, `data_present`, `load`,
`error`, `entry_status`, `guest_exit`, `exception`, `stack`, `events` (last 300), and,
with `debug`, `main_stack_stalled` and `main_stack_sample`.

`mp_game_trace(event)` (lines 46-56) appends to `events`, sets `stage`, and writes at most
twice a second. Calls faster than that schedule one trailing write 0.6 s later. A write off
the main thread (utility QoS) keeps the game's thread free.

---

## 5. Telemetry threads

The 5-second loop (lines 170-199) runs on a detached thread that is always started. Each
iteration, at `t = 0, 5, 10, ...`:

- Reads main-thread and whole-process CPU time (`thread_info`, `getrusage`).
- Reads GPU busy time from `mp_cp_gpu_busy_nanos()` (`CPMetal.m`).
- Reads the thermal state (`NSProcessInfo.thermalState`) and the texture census
  (`mp_tex_census`).
- Prints `[perf]` (not at `t = 0`).
- Every 10 s, walks the VM regions (`vm_region_recurse_64`) and prints `[vmtags]`.
- Prints `[budget]` with the frame rate from `mp_stk_frame_window()`, and the memory numbers.

The formats and how to read them are in [telemetry.md](telemetry.md). `gpu` uses
`dev.currentAllocatedSize`, and `cpu` is the footprint minus that (floored at 0).

---

## 6. Recording the main thread

`mp_game_sample()` (line 57) calls `stage` with the current `stage` value, so the
`runtime.json` memory and frame fields refresh every 2 s even without events.

`stage()` (lines 35-42) updates the stage, the frame window, the input state (main thread
only), and free memory, then rewrites `runtime.json`.

`exception()` (line 44) sets `exception` and `stack` (the call stack from
`callStackSymbols`) and calls `stage("exception")`.

---

## 7. LoadCLI.m (Mac load harness)

Built by `make -C phase8` into `build/phase8/cp-load`. It links the core loader, the
Phase 4 and 5 `Extended.c` and `Policy.c` files, the Phase 8 `Policy.c`, and `LoadCLI.m`.
It does **not** link `CPMetal.m`, `CPDesktop.m`, `CPAppKit.m`, or `CPControls.m`:
`Policy.c` calls their functions only under `#if TARGET_OS_IPHONE`.

**Usage.** `cp-load DIR EXECUTABLE [--run args...]`. `DIR` holds `EXECUTABLE` plus
`Frameworks/*.dylib` (up to 32 images in total).

**What `main()` does.**

1. Builds the source list: the executable, then every `*.dylib` in `DIR/Frameworks`.
2. `mp_group_open` with `mp_cp_policy()`. Failure prints `GROUP: <error>` and returns 1.
3. Prints `GROUP LOADED in <s>: images=… rebases=… binds=… selectors=… initializers=…`.
4. Runs the three introspection flags below. Each is load-only, and each can be combined
   with the others.
5. Returns without running anything unless `--run` is given. With `--run`, it calls
   `mp_image_main` on the main image with the trailing arguments.

**Introspection flags.** All are environment variables read with `getenv`.

| Flag | Input | Output |
|---|---|---|
| `MP_DUMP_CLASSES` | Comma-separated class names | For each class: superclass, every method as `selector@addr`, and every ivar with its offset. `addr` is the method's offset within its guest image plus `0x100000000` (the link-time address). Classes not found print `not found`. |
| `MP_FIND_SELECTOR` | One selector name | Each guest class that overrides the selector (its IMP differs from the superclass's), with the method's `@addr`. |
| `MP_FIND_ADDR` | A hex address | The guest method whose code starts closest below the address, as `±[Class selector] @addr`. Use it to name a crash address. |

Example (from the Phase 8 notes in `CONTEXT.md`):
`MP_DUMP_CLASSES=GameView build/phase8/cp-load build/cyberpunk/thin Cyberpunk2077`.

The `+0x100000000` convention matches the link-time address of the main executable.
For dylibs the offset is relative to their own base, and the repo does not say what base
they use, so the same arithmetic may not apply to them. **Unknown for dylibs.**

---

## Key functions

| Function | File | Role |
|---|---|---|
| `main()` | `phase8/host/Main.m` | Startup sequence (section 1). |
| `stage(NSString *)` | `Main.m` | Updates and rewrites `runtime.json`. |
| `exception(NSException *)` | `Main.m` | Records uncaught ObjC exceptions. |
| `mp_game_trace(NSString *)` | `Main.m` | Rate-limited event log into `runtime.json`. |
| `mp_game_sample(void)` | `Main.m` | Periodic refresh of `runtime.json`. |
| `sha256(bytes, size)` | `Main.m` | Hex SHA-256 via CommonCrypto (guest hash check). |
| `crash_line(label, addr)` | `Main.m` | Formats one `[crash]` line (section 2). |
| `crash(sig, si, ctx)` | `Main.m` | Signal handler (section 2). |
| `mp_locate(addr, &off)` | `runtime/image.c` | Address to guest image name and offset. |
| `mp_guest_base(i)` | `runtime/image.c` | Runtime load base of group member `i` (0 = main executable). |
| `mp_stk_frame_window()` | `phase6/runtime/FrameCounter.m` | Frame statistics (section 5, [telemetry.md](telemetry.md)). |
| `mp_cp_policy()` | `phase8/runtime/Policy.c` | Loader policy for the group. |
| `mp_cp_metal_install()` | `phase8/runtime/CPMetal.m` | Metal adapters. |
| `mp_cp_gpu_timing_install(dev)`, `mp_cp_gpu_busy_nanos()` | `CPMetal.m` | GPU busy-time accounting. |
| `mp_display_set_modes(sizes, n)` | `phase5_5/runtime/Display.m` | Registers the render modes. |
| `mp_cp_install_controls()` | `phase8/runtime/CPControls.m` | Installs the touch overlay after the view appears. |
| `mp_game_set_launch_hook(block)`, `mp_game_run_uikit()` | `phase5/runtime/Lifecycle.m` | Starts the guest from the UIKit run loop. |
| `mp_watchdog_start`, `mp_watchdog_set_sampler` | `phase6/runtime/Watchdog.m` | Hang detector and sampler (debug only). |
| `main()` | `phase8/host/LoadCLI.m` | Mac load harness (section 7). |
