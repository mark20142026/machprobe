# Phase 8 runtime: function reference

Covers `phase8/runtime/`: `Policy.c`, `CPMetal.m`, `CPAppKit.m`, `CPDesktop.m`,
`CPControls.m`. Each file has a table: function, what it does, why it exists. Small
stubs that share one job are grouped into one row. Names in `backticks` are real symbols.

The layer is "lean": the game gets Apple's real Metal device, and the adapters only
answer what macOS has and iOS does not. Phase 8 adds code for the Cyberpunk-specific
call sites found with the selector survey (`MP_SEL_SURVEY`, see
[debugging-playbook.md](debugging-playbook.md)). The Mac build (`make -C phase8`) links
only `Policy.c`; the others are iPhone-only (see [host-app.md](host-app.md)).

---

## 1. `Policy.c`: loader policy and address-space rationing

Entry point: `mp_cp_policy()` (line 257). It copies the shared Phase 5.5 large-game policy and
replaces `library_allowed` and `resolve`. It also sets `max_image_bytes` to 256 MB (the
executable is 151 MB), and enables guest dylibs, categories, weak imports, and metadata
registration.

| Function / state | What it does | Why it exists |
|---|---|---|
| `allowed(name)` (16) | Accepts a library if the shared policy does, or if it is one of six extra system libraries (AudioUnit, CoreHaptics, MetalFX, MetricKit, `libbz2.1.0`, `libcurl.4`). | Cyberpunk imports these; the shared list does not include them. |
| `guest_executable_path(buf, size)` (35) | Serves `_NSGetExecutablePath` from `MP_GUEST_EXECUTABLE_PATH` when set. | The game finds `archive/`, `engine/`, `r6/` by walking up from its own executable path. |
| `tracing()` (49) | Reads `MP_MEM_TRACE` once. | Gates the memory trace. |
| `shrunk[]`, `shrunk_count` (60-61) | Table of reservations that were given less real memory than they claimed. | Needed to clip calls that reach the unbacked tail. |
| `va_cap()` (62) | Real bytes given to each reservation above 16 GB: `MP_VA_CAP_GB`, default 8. | iOS offers about 66 GB of address space; RED Engine reserves 16/64/32 GB regions. |
| `clip(addr, n)` (67) | Trims a range so it excludes unbacked tails; returns 0 if nothing backed remains. | Keeps later `mmap`, `munmap`, `mprotect`, `madvise` calls out of the unbacked part. |
| `mp_cp_va_tail(addr)` (79) | Returns a description if `addr` is in an unbacked tail, else NULL. | Used by the crash handler to explain an address fault. |
| `trace_callers()` (83) | Prints up to five guest frames for the current call, using `mp_locate`. | Attributes a mapping to its caller when `MP_MEM_TRACE` is set. |
| `guest_mmap()` (87) | On iOS, places `n >= 16 GB` anonymous reservations top-down from `0x8000000000`, with real size capped at `va_cap()`. Refuses `MAP_FIXED` into a tail. Logs failures. | Stacks the allocator's large regions so their free-routing works; avoids the 66 GB limit. |
| `guest_munmap` (112) | Unmaps a rationed reservation at its real size, or clips the range. | Frees the backed part only. |
| `guest_mprotect`, `guest_madvise` (120, 125) | Apply to the backed part only (an mprotect fully in a tail fails with ENOMEM). | Same reason as munmap. |
| `guest_malloc` (130) | Logs `malloc` of 64 MB or more. Installed only under `MP_MEM_TRACE`. | Keeps the hot allocator path free unless tracing. |
| `guest_sysctlbyname`, `guest_sysctl` (138, 224) | Report `hw.memsize` as `MP_MEMSIZE_GB` (default 3). | The game sizes its budgets from `hw.memsize`; the app may use only about 6 GB, so the budget must be smaller. |
| `home_path(path, out)` (167) | Maps `/Users/<name>/...` to `$HOME/...` on iOS. | Game files contain Mac home paths (for example the GameServices log path). |
| `ci(path, out)` (176) | Resolves a path case-insensitively, component by component, when it does not exist as given. | The iOS data volume is case-sensitive; the game asks for `archive/mac` and the install has `archive/Mac`. |
| `guest_opendir`, `guest_stat`, ... `guest_statfs` (199-216), macros `CI`, `TRACE` | File-system wrappers: apply `ci()` first, then call the real function. `MP_FS_TRACE` logs each call. | Case-insensitive lookup and tracing for every path operation. |
| `guest_open` (203) | Same as above; reads the mode argument only when `O_CREAT` is set. | `open` is variadic. |
| `paths[]` (217) | Maps `libSystem` symbol names (`_stat`, `_open`, `_realpath$DARWIN_EXTSN`, ...) to the wrappers. | Read by `resolve()`. |
| `resolve(library, symbol)` (234) | Returns the replacement for a guest import. Order: `__NSGetExecutablePath`; libSystem overrides; Metal device factories (iPhone only); `mp_cp_desktop_symbol`; `mp_stk_desktop_symbol`; then the shared policy. | One place decides what each import binds to. |

---

## 2. `CPMetal.m`: Metal on the real device

Entry points: `mp_cp_metal_install()` (150), `mp_cp_metal_devices()`, `mp_cp_metal_default_device()`,
`mp_cp_metal_features()` (175), `mp_cp_gpu_timing_install()` (191), `mp_cp_gpu_busy_nanos()` (190).
The guest gets Apple's `MTLDevice`. Per-frame calls are not proxied.

| Function / state | What it does | Why it exists |
|---|---|---|
| `yes`, `no`, `zero`, `one32`, `zero32`, `nop1`, `nop_range`, `nop_tex`, `barycentric` (8-17) | Trivial implementations of macOS-only `MTLDevice`/`MTLBuffer`/`MTLBlitCommandEncoder` methods. `barycentric` forwards to the real query. | The Mac build calls these; iOS marks them unavailable. Answers match a built-in Apple GPU. |
| `add(cls, sel, imp, types)` (18) | `class_addMethod` only if the class does not already respond. | Adds the stubs without overriding real iOS methods. |
| `shared_options(o)` (20) | Rewrites Managed storage (1) to Shared. | Managed does not exist on iOS; unified memory makes Shared equivalent for the game's access. |
| `buf_len`, `buf_bytes`, `buf_nocopy` (33-35) | Wrap buffer creation to apply `shared_options`. | The storage rewrite for buffers. |
| `gpu_trace(kind, bytes, caller)` (25) | With `MP_MEM_TRACE`: running totals, and a line for each allocation of 16 MB or more, with its guest caller. | Finds what fills the GPU budget. |
| `tex(self, sel, desc)` (41) | Counts texture creations by kind (`mp_tex_census`). Rewrites Managed to Shared (or Private for render targets with `MP_MANAGED_RT_PRIVATE=1`). Logs failures. | Measures the Mac build's storage choices; tests the Managed-to-Private experiment. |
| `mp_tex_census[4]` (40) | Cumulative counts: managed render target, managed other, shared, private. | Read by `[perf]` (see [telemetry.md](telemetry.md)). |
| `overflows(heap)`, `spill_heap(heap, need)` (64, 71) | Creates a spill-over heap (at least 64 MB) when a capped heap fills. Respects the total cap `MP_SPILL_CAP_MB` (default 1024) and a 900 MB memory margin (`os_proc_available_memory`). | Heaps are charged whole on iOS. Spill-over lets the game keep streaming without jetsam. |
| `heap_tex`, `heap_buf` (92, 100) | Heap sub-allocation: try the heap, then its spill-over heaps, then create one. Warns (first 20) when all fail. | The game may not check for nil. |
| `watch_heap(h)` (108) | Once, replaces `newTextureWithDescriptor:` and `newBufferWithLength:options:` on the heap's class. | Hooks heap sub-allocation. |
| `useHeapR`, `useHeapStagesR`, `useHeapsR`, `useHeapsStagesR`, `useHeapC`, `useHeapsC` (115-120) | Wrap `useHeap:` variants on render and compute encoders so spill-over heaps are made resident too. | Otherwise resources in a spill-over heap are not valid on the GPU. |
| `install_encoder_hooks(device)` (122) | Once: finds the concrete render and compute encoder classes and installs the `useHeap` hooks. | Encoder classes are only known at run time. |
| `heap(self, sel, desc)` (135) | Caps heap size to `MP_HEAP_CAP_MB` (default **96** in code; `CONTEXT.md` records an earlier 512 MB setting), converts Managed to Shared, and watches the new heap. | Grow-on-demand heaps; the cap stops iOS charging large heaps at creation. |
| `wrap(cls, sel, replacement)` (144) | Adds or replaces a method on the concrete class and returns the original IMP. | Changes only this device's Metal objects. |
| `mp_cp_metal_install()` (150) | Once: gets the default device; installs the stubs and wrappers; no-ops `didModifyRange:`, `synchronizeResource:`, `synchronizeTexture:slice:level:`. | macOS-only synchronisation is unnecessary on unified memory. |
| `mp_cp_metal_devices()`, `mp_cp_metal_default_device()` | Return `@[device]` and the device. | Targets of `resolve()` for `MTLCopyAllDevices` and `MTLCreateSystemDefaultDevice`. |
| `mp_cp_metal_features()` (175) | Returns the device name, GPU family support, BC texture support, recommended working set and max buffer length. | Written to `runtime.json` as `gpu`. |
| `counted_commit(cb, sel)`, `gpuBusyNanos`, `origCommit` (185-189) | On each command buffer's commit, adds a completion handler that adds `GPUEndTime - GPUStartTime` (ignoring values not in (0,1) s). | Measures GPU busy time for `[perf]`. Overlapping buffers are summed, so the total can exceed 100%. |

---

## 3. `CPAppKit.m`: AppKit behaviour the game expects

Adds category methods to the Phase 5 AppKit stand-ins (`MPGameScreen`, `MPGameWindow`,
`MPGameApplication`, `MPKeyEvent`, `MPCompatImage`) and to `UIView`. The header says these
were found by `MP_SEL_SURVEY` on the device.

| Function / state | What it does | Why it exists |
|---|---|---|
| `headroom(potential)` (17) | Returns 1 (SDR) unless `MP_HDR` is set; then the real EDR headroom. | Reporting HDR headroom makes the game render HDR, which costs bandwidth on a phone. |
| `MPGameScreen` methods (22-30) | EDR headroom, `maximumFramesPerSecond` from UIKit, refresh intervals, `localizedName`, `colorSpace`. | Screen queries the game makes. |
| `MPGameWindow` methods (33-44) | Content layout rect, point conversion, occlusion (visible), no-op window sizing and miniaturise. | The window is one full-screen view on iOS. |
| `MPGameApplication` methods (47-55) | `mainWindow`/`keyWindow` from `mp_game_key_window()`; `occlusionState` visible; `terminate:` calls `exit(0)`; presentation options no-ops. | Application state the game queries. |
| `MPKeyEvent` methods (58-62) | No precise scrolling deltas; scroll deltas from `deltaX/Y`; mouse coalescing flags. | Touch scrolls arrive as wheel lines. |
| `MPCompatImage` methods (65-74) | `initWithSize:` makes a blank image; `drawInRect:` draws the UIKit image. | The game builds its hidden cursor from a blank image. |
| `setLayer:`, `wantsLayer`, etc. on `UIView` (82-92) | Stores the adopted layer as a full-size sublayer. | AppKit lets a view use any layer; a UIView's backing layer is fixed. The game keeps its own `CAMetalLayer` pointer. |
| `hostedLayout`, `install_hosted_layout` (95-103) | Wraps `layoutSublayersOfLayer:` to keep the hosted layer at the view's bounds. | The hosted layer must follow the view when it resizes. |
| `zero` (naked asm), `MPZero` (109-116) | Returns zero in x0 and d0-d3 for any selector, through `resolveInstanceMethod:`. | A safe answer for selectors the stand-ins lack. |
| `forward(self, cmd, sel)`, `seenSlots[]` (120-130) | `forwardingTargetForSelector:` to `MPZero`. Logs each (class, selector) once through a lock-free hash table. | Safety net. Each `[appkit] unimplemented ...` line names a method to implement. |
| `install_safety_net()` (131) | Adds the forwarding method to the listed Phase 5 classes and their metaclasses. | Enables the safety net on each stand-in class. |
| `trackedInitWithWindow`, `controllers` (146-148) | Records each `MPWindowController` as it is created (weakly). | `mp_cp_refocus` must reach the game's window controllers. |
| `mp_cp_refocus()` (150) | Sends `windowDidBecomeKey:` to tracked controllers and the content view's controllers; posts the app-activation notification; sets `GameWindow.isWindowVisible` to YES; logs `m_windowFocus`. | The game ignores the pointer until it believes its window has focus. |
| `install_focus()` (172) | Once: tracks controllers, and calls `mp_cp_refocus` on `UIApplicationDidBecomeActiveNotification`. | The source says macOS re-sends focus on activation; the same is done here. |
| `traced_mouseLocation`, `traced_windowActive`, `traced_convert`, `mp_cp_cursor_trace_install()` (182-200) | With `MP_CURSOR_TRACE`: wraps `+[NSEvent mouseLocation]`, `isWindowActive`, and `convertMousePosToGame`, logging on change. | Shows what the game sees of the pointer. |
| `mp_cp_engine_cursor_trace()` (205) | With `MP_CURSOR_TRACE`: every 0.1 s, logs the engine input state at link-time address `0x107c63220` (flag, floats, mode). | Shows the engine's cursor state directly. The address is specific to this build. |
| `mp_game_touch_began()` (218) | On every touch start: re-asserts `cursorInView`, the controller's `m_windowFocus` (calls `mp_cp_refocus` if false), and `GameWindow.isWindowVisible`. | The game may reset these at any time; re-asserting makes touch input reach it. |
| `mp_cp_key_state_log()` (237) | With `MP_CURSOR_TRACE`: every 0.05 s, logs held W/A/S/D/Space from the engine's keyboard array. | Shows whether key presses reach the engine. |

---

## 4. `CPDesktop.m`: macOS-only APIs answered for iOS

Entry point: `mp_cp_desktop_symbol(library, symbol)` (109). It returns a function pointer
or a data pointer for a symbol the iOS SDK lacks, or NULL. Header values were measured on
macOS (the source cites `docs/evidence/phase8-desktop-constants.txt`).

| Function / state | What it does | Why it exists |
|---|---|---|
| `cpConstantNames`, `cpConstantValues` (11-14) | AppKit notification and mode-name constants. Each value is its own name. | The game compares these by pointer and value. |
| `is_builtin`, `in_mirror_set`, `vendor_number`, `model_number`, `serial_number`, `active_displays` (17-22) | CoreGraphics display queries. One built-in display, ID 1, unmirrored, generic vendor/model. | The game queries the display list. |
| `event_source_create`, `event_source_suppression` (25-26) | Returns an empty dictionary as the source; suppression is a no-op. | The game creates and configures an event source; events do not come from it. |
| `display_float_parameter` (29) | Returns `kIOReturnUnsupported`. | An IOKit display parameter that iOS does not provide. |
| `copy_devices_observer`, `remove_observer` (35-40) | Returns the Metal device list and a dummy observer token that never fires. | iOS has one GPU and no hot-plug events. |
| `CurlEasy`, `CurlMulti`, `CurlMsg` (50-52) | Structures that mimic libcurl's handle layout. | Code written against libcurl reads these. |
| `curl_easy_init_`, `curl_easy_cleanup_`, `curl_easy_setopt_`, `curl_easy_getinfo_` (57-76) | Handles, option storage (URL, `CURLOPT_PRIVATE`), and `getinfo` for private and effective URL. Variadic functions are read with `va_arg`. | Valid handles and accepted options, so the game does not take an error path. |
| `curl_easy_perform_` (68) | Returns 7 (`CURLE_COULDNT_CONNECT`). | An offline network. |
| `curl_easy_strerror_` (77) | Text for codes 7 and others. | Error messages. |
| `curl_multi_*_` (78-98) | Multi-handle add, remove, perform, and `info_read`. Each added handle immediately gets a `CURLMSG_DONE` with code 7. | The multi interface also reports the offline error. |
| `curl_slist_append_`, `curl_slist_free_all_` (99-103) | Standard string list. | Headers lists are always valid. |
| `sec_unimplemented`, `sec_long_description` (106-107) | Return `errSecUnimplemented` (-4) and NULL. | macOS certificate APIs used by RED Galaxy. |
| `mp_cp_desktop_symbol` table (109-127) | Maps symbol names (`_CGDisplayIsBuiltin`, `_curl_easy_init`, `_SecItemImport`, ...) to the functions above. | The single lookup `resolve()` calls. |

Commit `b5dd60b` ("Cyberpunk passes the main-menu load: offline libcurl keeps request state")
is the change that made the curl layer keep request state.

---

## 5. `CPControls.m`: temporary touch controls

Entry point: `mp_cp_install_controls()` (168). Installed from `Main.m`. The header says
the controls are temporary, and that a paired keyboard or controller is better.

Every control emits the Mac key or mouse event a keyboard would, through `mp_game_key`,
`mp_game_modifier` and `mp_game_pointer_here` (Phase 5 `Input.m`). So the game is unchanged.

| Function / class | What it does | Why it exists |
|---|---|---|
| `key(code, chars, down)` (15) | Calls `mp_game_key`. | One place for key events. |
| `MPCPPassthrough.hitTest` (19) | Returns nil when the hit view is itself. | Touches outside controls reach the game, so menus stay tappable. |
| `MPCPStick` (23-54) | Fixed left stick (not floating, despite the plan in `CONTEXT.md`): dead zone 0.3; `apply:` sends W/A/S/D key changes as the stick moves; `recenter` releases all keys. | Movement. Diagonals press two keys. |
| `MPCPKey` (57-79) | A held button. `kind` 0 key, 1 modifier (Shift), 2 left mouse, 3 right mouse. `set:` sends press and release. | SPACE, F, R, C, SHIFT, LMB, RMB, ESC, TAB, ENTER. |
| `MPCPLook.touchesMoved` (85-89) | Sends a relative mouse move, scaled by 2.2. Hidden unless the pad is shown. | Camera look by dragging. |
| `MPCPTyping` (93-112) | `UIKeyInput` that turns typed characters into Mac key codes (`code_for`), and backspace into key 51. | The iPhone keyboard. |
| `MPCPOverlay` (114-145) | Container. `poll` shows look only with the pad. `toggle:` (gamepad button) recenters and releases keys when hiding. `keyboard:` toggles the iPhone keyboard. `layoutSubviews` positions the keys within safe-area insets. | Overlay management. |
| `install(window)` (148) | Builds the overlay, stick, keys, the two buttons, and the typing view. Adds a timer that polls the overlay and keeps it on top. | Creates the controls once the game's window exists. |
| `claim_buttons`, `claim_controllers` (214-222) | Disables iOS system gestures on each connected controller's buttons. | iOS would otherwise take Menu and Home presses; the game needs them. |
| `autopress` (181) | Constructor. With `MP_AUTOPRESS="t:code,..."`, presses and releases a key at each time. | Unattended reproduction. Read at constructor time, so `env.json` cannot set it. |
| `autotap` (196) | Constructor. With `MP_AUTOTAP="t:x,y,..."`, sends a touch at view point (x, y) at each time through the same path as a real touch. | Unattended touch reproduction. Same constructor caveat. |

---

## Cross-file notes

- `Policy.c` reads `MP_MEMSIZE_GB`, `MP_VA_CAP_GB`, `MP_MEM_TRACE`, `MP_FS_TRACE`, and
  `MP_GUEST_EXECUTABLE_PATH`. Each is read lazily, so `env.json` works for them.
- `CPMetal.m` reads `MP_MEM_TRACE`, `MP_HEAP_CAP_MB`, `MP_SPILL_CAP_MB`, and
  `MP_MANAGED_RT_PRIVATE`.
- `CPAppKit.m` reads `MP_HDR` and `MP_CURSOR_TRACE`.
- `CPControls.m` reads `MP_AUTOPRESS` and `MP_AUTOTAP` in constructors (see host-app.md).
- Defaults are the values in the code at the time of writing. `CONTEXT.md` records some
  earlier settings (for example a 512 MB heap cap) that have since changed.
