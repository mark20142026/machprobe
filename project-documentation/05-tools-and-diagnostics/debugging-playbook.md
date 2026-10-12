# Debugging playbook

Recipes for the Phase 8 app, in the order a bug is usually worked. Each recipe names the
code it depends on. Where the repo does not provide a command, the recipe says so.

**Working rules (from `CONTEXT.md`).** Never install or relaunch the app on the phone without
the user's explicit yes, unless the user has granted overnight autonomy. Prefer read-only log
checks. Never run Cyberpunk on the Mac (no `--run`). Never touch the STKHost App ID. Keep
status updates short.

---

## 0. Baseline: what the app writes

Read these before anything else.

| File (in `Documents/`) | Read with | Contains |
|---|---|---|
| `runtime.json` | `phone.py report` (pulls to `build/phase7/runtime.json`) | Stage, load stats, GPU features, frame window, free memory, last 300 events. |
| `runtime-stderr.log` | `phone.py logs [N]` | Everything printed (`[budget]`, `[perf]`, `[crash]`, `[gpu]`, ...). |
| `runtime-stdout.log` | `phone.py logs [N]` | Stdout (usually little). |

`runtime.json`'s `stage` says how far the launch got. The sequence is in
[host-app.md](host-app.md) section 1: `start`, `gpu ready`, `guest hashes verified`,
`loading group`, `guest entry`, and so on. A stage that stops early names the failed step;
`error` and `exception` say why.

`phone.py logs` and `phone.py report` need a finished or running launch. Logs are redirected
to files unless `MP_CONSOLE` is set (section 2).

---

## 1. Reading a crash

A fatal signal is written to stderr as `[crash]` lines. The crash does **not** update
`runtime.json`. An uncaught Objective-C exception does (`exception` and `stack`).

1. Get the log: `python3 phase8/tools/phone.py logs 400`, then search for `[crash]`.
2. The first line:
   `[crash] signal N at <address>; initializer <image> #<index> offset <off>`.
   It names the initializer the loader was running. Signals are the `Main.m` list
   (SIGILL, SIGTRAP, SIGABRT, SIGBUS, SIGSEGV, SIGFPE, SIGSYS).
3. `[crash] fault is in the unbacked tail of a rationed guest reservation (raise MP_VA_CAP_GB)`
   means the fault is in address space the layer did not back. Raise `MP_VA_CAP_GB` (default 8).
4. `pc` and `lr` lines show where the program counter was:
   - `<image>+<offset>` for a guest image (from `mp_locate`). The offset is relative to the
     image's base.
   - `<library>`<symbol>+<offset>` for host or system code (from `dladdr`).
   The `x0`-`x8` lines are argument registers at the fault. Frame lines (`frame`) follow the
   frame-pointer chain, up to 40 frames.
5. **Symbolicate a guest address.** For the main executable, the link-time address is
   `offset + 0x100000000`. This is the convention in `phase8/host/LoadCLI.m`. Then on the Mac
   (load only, no `--run`):

   ```sh
   make -C phase8
   MP_FIND_ADDR=<hex link address> build/phase8/cp-load build/cyberpunk/thin Cyberpunk2077
   ```

   The output names the nearest guest method below that address (`±[Class selector] @addr`).
   The `build/cyberpunk/thin` copy is the user's own binary and is not in the repo.
   For dylibs, the base is not stated in the repo: **unknown**.
6. **Runtime address from a link address** (used in `CPAppKit.m`): `runtime = mp_guest_base(0) +
   (link - 0x100000000)`. Useful when adding a trace at a known address.
7. `lr` is the return address of the caller. When `pc` is a host function, `lr` tells you
   which guest or host code called it.
8. iOS system crash logs from the device (the `.ips` files) are not handled by any repo tool.
   **Unknown** how to fetch them here; the `[crash]` lines above are the supported source.

**Uncaught ObjC exception.** `phone.py report` prints `exception` and the first 25 `stack`
lines. The full stack is in `runtime.json`.

---

## 2. Streaming logs live

Two ways. Pick one per launch.

**A. After the fact (default).** The app writes logs to files. Run the launch, then:

```sh
python3 phase8/tools/phone.py launch
python3 phase8/tools/phone.py logs 200
python3 phase8/tools/phone.py report
```

`logs` and `report` pull the files over USB into `build/phase7/`. They are snapshots, not a stream.

**B. Live console.** `CONTEXT.md` gives this command. It sets `MP_CONSOLE` so output goes to the
console stream instead of files:

```sh
xcrun devicectl device process launch --device <DEVICE-UDID> --terminate-existing --console \
  --environment-variables '{"MP_CONSOLE":"1"}' <your-bundle-prefix>.CP2077
```

Killing `devicectl` sends SIGTERM to the app, which ends the run (per `CONTEXT.md`). `phone.py launch`
does not pass `--console`, and it does not pass environment variables either. With
`MP_CONSOLE`, `[memwatch]` prints once a second.

---

## 3. Instruments and xctrace (Metal System Trace)

`CONTEXT.md` records that `xctrace` showed the phone as "offline". Its notes say:

- Xcode must be open for the phone to be visible to the trace tools (CoreDevice). Confirm
  `phone.py check` reports the device and Developer Mode, then retry.
- It is possible to attach to a running process (the note in `CONTEXT.md`), so the app can be
  launched first, then traced.
- The Metal System Trace is the planned capture (`CONTEXT.md`, next steps item 5).

The repo has no `xctrace` script. The exact command line used is **unknown** (not in the repo).
Use Xcode's Instruments UI, or `xcrun xctrace list devices` to see whether the phone is listed.

---

## 4. Selector survey (`MP_SEL_SURVEY`)

Finds Objective-C selectors the game sends that no class in the process implements.

1. The survey list is `phase8/host/selectors.txt`, copied into the bundle by `build.py`. The file
   contains some non-selector lines (for example `Contents of (__TEXT,__objc_methname) section`).
   Those will show as missing; ignore them.
2. Turn it on with `Documents/env.json`: `{"MP_SEL_SURVEY": "1"}`. `env.json` is read at the start of
   `main()`, before this check, so it works. There is no `phone.py` subcommand for `env.json`; copy the
   file with the same `devicectl device copy to` used by `device.py`'s `push()`.
3. Launch, then `phone.py logs 2000` and search for `[sel] missing`.
4. The app exits after the survey (`exit(0)`), so `runtime.json` shows the load stage only.
5. Each missing selector is a method to implement or to answer. Previous findings went into
   `phase8/runtime/CPAppKit.m`.
6. Remove `MP_SEL_SURVEY` from `env.json` afterwards. Otherwise the next normal launch exits
   before the game starts.

---

## 5. Address-space probe (`MP_VA_PROBE`)

Measures which address ranges the process can reserve. Used to size `MP_VA_CAP_GB`.

1. Put `{"MP_VA_PROBE": "1"}` in `Documents/env.json`, launch, read the log.
2. The probe runs in `main()` and then calls `exit(0)`. The game does not start.
3. Output `[va]` lines, in order:
   - `hint 0x... -> ...`: a `mmap` at a hint address (1 GB each, 16 GB steps).
   - `FIXED ok 0x...-0x... (N MB) then kr=...`: a contiguous range that accepted `vm_allocate` at
     fixed addresses, and where it stopped.
   - `FIXED 512GB -> ...`, `PROT_NONE 1 GB -> ...`: fixed and PROT_NONE tests.
   - `single N GB -> ...`: largest single anonymous mapping from 128 GB down to 8 GB.
   - `+N MB at ...` and `total reservable ~N MB`: greedy allocation from 64 GB down, then the total.
4. Compare the total with the ~66 GB figure in `phase8/runtime/Policy.c`'s comment.
5. Remove the variable from `env.json` before the next real launch.

---

## 6. File-system and memory traces

**`MP_FS_TRACE=1`** (`phase8/runtime/Policy.c`): logs each guest call through the file-system
wrappers (`opendir`, `stat`, `access`, `open`, `fopen`, `realpath`, ...), with the result, and each
case-insensitive remap (`[fs] case A -> B`).

- To find a missing file, search for `-> -1` or `strerror` text such as `No such file`, and
  check the path.
- A remap line shows the layer resolved a case mismatch, which is expected for `archive/mac`.

**`MP_MEM_TRACE=1`**: logs large mappings (64 MB or more), malloc of 64 MB or more, every
`sysctlbyname` call, and GPU allocations of 16 MB or more with the guest caller
(`[gpu] ... from <symbol>+off`). Map the caller with `MP_FIND_ADDR` (section 1).

- The malloc hook is installed only while tracing; with the variable off, the hot allocator path is
  not wrapped.
- Expect large logs. Use it for a short run.
- The variable is read lazily, so `env.json` works.

---

## 7. The `Documents/debug` toggle (watchdog)

1. `python3 phase8/tools/phone.py debug on` writes `Documents/debug`. It is read at launch, so
   relaunch after changing it.
2. With the file present, the watchdog starts. A 5-second stall of the game's event loop writes
   `main_stack_stalled` to `runtime.json` and the stage `main thread stalled (watchdog)`. A stack
   sample is taken every 10 s (`main_stack_sample`). See [telemetry.md](telemetry.md) section 5.
3. The stack is in `runtime.json`, not in `phone.py report`. Read `build/phase7/runtime.json` after
   `phone.py report` (it pulls the file there).
4. `phone.py debug off` copies a file that is never created, and the failure is silent. **Unknown
   whether it removes `Documents/debug`.** Check it with
   `xcrun devicectl device info files --device <DEVICE-UDID> --domain-type appDataContainer --domain-identifier <your-bundle-prefix>.CP2077 --subdirectory Documents`,
   the same command `phase8/tools/push_resume.py` uses for listings.

---

## 8. Environment variables and `env.json`

**`Documents/env.json`** is a JSON object. Each `MP_*` key with a string value is set with `setenv`
at the start of `main()` (`phase8/host/Main.m` lines 91-94). Numbers must be quoted strings.

- Works for variables read inside `main()` or later: `MP_SEL_SURVEY`, `MP_VA_PROBE`, `MP_CONSOLE`,
  `MP_FS_TRACE`, `MP_MEM_TRACE`, `MP_MEMSIZE_GB`, `MP_VA_CAP_GB`, `MP_HEAP_CAP_MB`, `MP_SPILL_CAP_MB`,
  `MP_MANAGED_RT_PRIVATE`, `MP_HDR`, `MP_CURSOR_TRACE`.
- Not overridable: `MP_GUEST_EXECUTABLE_PATH` is set by `main()` itself (`Main.m` line 139), so an
  `env.json` value is overwritten.
- **Does not work** for C-constructor variables, because they run before `main()`:
  `MP_AUTOPRESS` and `MP_AUTOTAP` (`phase8/runtime/CPControls.m`). Pass these as process
  environment (for example `devicectl ... --environment-variables`). This is from reading the code,
  not a device test.

**Tuning values.** `MP_MEMSIZE_GB` (default 3), `MP_VA_CAP_GB` (8), `MP_HEAP_CAP_MB` (96),
`MP_SPILL_CAP_MB` (1024). Current defaults are listed in
[phase8-runtime-reference.md](phase8-runtime-reference.md).

---

## 9. Unattended reproduction

When a bug needs the same state each time:

- `MP_AUTOPRESS="15:49,30:36"` presses key 49 (Space) at 15 s and key 36 (Return) at 30 s
  (`CPControls.m`). Format: `seconds:keycode`, comma-separated.
- `MP_AUTOTAP="20:437,300,30:437,120"` sends a touch at (437, 300) at 20 s and (437, 120) at
  30 s, through the real touch path.

Both are read in constructors (section 8). Set them through the process environment.

---

## 10. Load-only checks on the Mac

Use these to inspect the binary without running the game.

```sh
make -C phase8                                          # builds build/phase8/cp-load
build/phase8/cp-load build/cyberpunk/thin Cyberpunk2077  # load only: prints GROUP LOADED
MP_DUMP_CLASSES=GameView build/phase8/cp-load build/cyberpunk/thin Cyberpunk2077
MP_FIND_SELECTOR=<selector> build/phase8/cp-load build/cyberpunk/thin Cyberpunk2077
MP_FIND_ADDR=<hex> build/phase8/cp-load build/cyberpunk/thin Cyberpunk2077
```

Expected `GROUP LOADED` figures in `CONTEXT.md` (for build 20383525): five images, 685,682 rebases,
71,348 binds, 495 selectors, 7,458 initializers.

---

## 11. Working a bug (the order used so far)

Derived from the `CONTEXT.md` "Fixes that got here" list and the `git log` subjects.

1. **Reproduce** with the same input each time (section 9) or the same save and location.
2. **Read the status**: `runtime.json` stage, `error`, `exception`, `frame_window`, and the last
   `[budget]` / `[perf]` lines (see [telemetry.md](telemetry.md)).
3. **Name the missing piece.** `[appkit] unimplemented`, `[sel] missing` (section 4), `[gpu] FULL` or
   `FAILED`, `[mem] refused`, `[fs]` misses.
4. **Find the call site.** `[crash]` (section 1), `MP_MEM_TRACE` `[gpu] from ...`, or
   `MP_FIND_ADDR`.
5. **Fix in our layer, not the game.** Changes go in `phase8/runtime/` (or shared runtime files), never
   in the game's bytes; the manifest hash check in `Main.m` enforces that the guest code is unchanged.
6. **Build and check locally:** `python3 phase8/tools/build.py --quick`, then the Mac load-only check
   (section 10). The phone install (`phone.py deploy`) needs the user's yes.
7. **Verify on the phone** with `phone.py launch`, `logs`, `report`, and the `[budget]` / `[perf]`
   numbers. Compare with the previous run.

Examples from the history: the libcurl offline layer (`b5dd60b`), touch and focus fixes
(`e43a29b`, `e348889`, `a9bb2bc`), spill-over heaps (`538ebc6`, `04c412a`), and the VA
rationing in `phase8/runtime/Policy.c`.
