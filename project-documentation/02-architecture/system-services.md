# System services: filesystem, sysctl, network, desktop stubs

Besides AppKit and Metal, a Mac game imports a long tail of system APIs: file
access with Mac semantics, `sysctl`, libcurl (which iOS does not ship),
CoreGraphics display functions, IOKit, Security and Carbon. This page covers how
each is answered. The pattern is always the same: the loader binds the import
through `mp_resolve`, the policy chain returns an adapter, and the adapter either
does the real iOS equivalent or fails with the framework's *own* error code. It
never reports success for something that did not happen.

Primary sources: `phase8/runtime/Policy.c`, `phase8/runtime/CPDesktop.m`,
`phase6/runtime/Desktop.m`, `phase5_5/runtime/Display.m`,
`phase5_5/runtime/Keyboard.m`, `phase5_5/runtime/Constants.m`,
`phase5_5/runtime/LazyImports.c`.

## Filesystem

### Case-insensitive path resolution (`ci()` in `Policy.c`)

macOS volumes ignore case by default; the iOS data volume is case-sensitive. The
Steam build asks for `archive/mac/content` while the install contains
`archive/Mac`, so the game could not find its data on iOS.

`ci(path, out)` resolves a path the way a case-insensitive volume would:

1. `access(path)`; if it exists (or fails with anything but `ENOENT`) the path is
   returned unchanged. For existing paths this is the whole cost, one `access()`.
2. Otherwise it walks the path component by component. A component that does not
   exist as spelled is matched by listing the parent directory (`opendir` /
   `readdir`) for a same-length name equal under `strncasecmp`.
3. Components that match nothing are **kept as given**, so creating new files and
   directories still works.

`MP_FS_TRACE` logs each rewrite as `[fs] case <asked> -> <found>`.

The wrappers (`CI(p)` macro + `guest_*`): `opendir`, `stat`, `lstat`, `access`,
`open` (variadic mode argument handled), `fopen`, `freopen`,
`realpath$DARWIN_EXTSN`, `mkdir`, `rmdir`, `unlink`, `rename` (both paths),
`chmod`, `utime`, `truncate`, `statfs`. `getcwd` passes through. They are bound
by the `paths[]` table in `resolve`. Calls not in that table (for example
`openat`, `readlink`, `scandir`) are **not** rewritten; none has been needed so far
(not exhaustively audited).

### Home directory remapping (`home_path()`)

Game config files carry absolute build-machine paths, for example
`gameservices.ini` with a `LogPath` of `/Users/<build user>/Library/Logs/...`. On
iOS, any path starting with `/Users/` is rewritten to `$HOME` + the remainder
before the case-insensitive step (commit `b5dd60b`). The host creates the
corresponding directories (`Library/Logs/Cyberpunk 2077`, for `GameServices.log`).

### Virtual executable path

The game locates `archive/`, `engine/`, `r6/` by walking up from
`_NSGetExecutablePath`. `guest_executable_path` returns `MP_GUEST_EXECUTABLE_PATH`
(set by `phase8/host/Main.m` to a placeholder file at
`Documents/Cyberpunk 2077/Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077`; the
real code is in the signed containers). The host `chdir`s to the data root.

### Key functions

| Function | File | What it does |
|---|---|---|
| `ci` | `phase8/runtime/Policy.c` | Case-insensitive component-wise resolution. |
| `home_path` | `phase8/runtime/Policy.c` | `/Users/<x>/...` to the app's `$HOME`. |
| `guest_open`, `guest_fopen`, `guest_stat`, ... | `phase8/runtime/Policy.c` | Path-taking libSystem calls wrapped with `ci`. |
| `guest_executable_path` | `phase8/runtime/Policy.c` | Virtual `_NSGetExecutablePath`. |

### Design decisions

- **Fix it at the import, not on disk.** The game bytes and the 61 GB data tree
  stay exactly as Steam delivered them; no renaming or lowercase aliases are
  created.
- **Fast common path.** The game opens thousands of existing files; only a miss
  pays for directory listings.
- **Keep unmatched components** so file creation (saves, logs, caches) behaves
  normally.

## sysctl

Only `hw.memsize` is altered, in both `sysctl` (MIB `{CTL_HW, HW_MEMSIZE}`) and
`sysctlbyname("hw.memsize")`, and only when the output buffer is 8 bytes on iOS
(`guest_sysctl`, `guest_sysctlbyname`). The default answer is 3 GB; reasoning and
history are in [address-space-and-memory.md](address-space-and-memory.md). All other queries
(CPU count, page size, model, ...) pass through to the real kernel.

## Offline libcurl (`CPDesktop.m`)

The Steam build imports `libcurl.4.dylib` (allowed as a path in `allowed()`); iOS
does not provide it. The game's online code calls it during startup.
The adapter behaves like libcurl on a machine with no connectivity:

| libcurl call | Behaviour |
|---|---|
| `curl_global_init_mem`, `curl_global_cleanup` | succeed / no-op |
| `curl_easy_init` / `curl_easy_cleanup` | real, valid handle (`CurlEasy`: magic, private pointer, URL) |
| `curl_easy_setopt` | accepts everything, returns 0; **stores `CURLOPT_PRIVATE` (10103) and `CURLOPT_URL` (10002)** |
| `curl_easy_getinfo` | returns the stored private pointer for `CURLINFO_PRIVATE` (0x100015) and URL for `CURLINFO_EFFECTIVE_URL` (0x100001); any other info writes 8 zero bytes |
| `curl_easy_perform` | returns 7 (`CURLE_COULDNT_CONNECT`) |
| `curl_multi_*` | `add_handle` queues a `CURLMSG_DONE` with result 7 (up to 64); `perform` reports 0 running; `info_read` hands out the queued messages and reuses slots once drained |
| `curl_slist_append`, `curl_slist_free_all` | a real linked list (no NULL/empty header list) |
| `curl_easy_strerror` | "Couldn't connect to server" for 7 |

### Two bugs that forced the shape

1. **Variadic functions on arm64 Apple.** `curl_easy_setopt(handle, option, ...)` and
   `curl_easy_getinfo(handle, info, ...)` are variadic. On the arm64 Apple ABI,
   variadic arguments are passed **on the stack**, not in registers. An adapter
   declared with a fixed third parameter would read a register the caller never
   set. The adapter is declared `(..., ...)` and reads exactly one 8-byte slot with
   `va_arg` (a `long`, a pointer and an `off_t` each occupy 8 bytes).
2. **`CURLOPT_PRIVATE` must round-trip.** The game attaches its request object
   with `CURLOPT_PRIVATE` and finds it again through `CURLINFO_PRIVATE`. An early
   stub returned NULL there and the game then corrupted memory on the way to the main menu (commit `b5dd60b`, "offline libcurl
   keeps request state"). Fixing it, with valid handles and `CURLMSG_DONE`
   results, let Cyberpunk pass the main-menu load.

Design decision: **be a realistic offline network, not an absent one.** Code
written against libcurl never expects a NULL handle or a missing result message;
failing at the transport (`COULDNT_CONNECT`) exercises the game's normal "no
connection" path instead of an untested one. (Real network access is out of scope
for now; the Steam sign-in/download feature in the roadmap is a separate host
component, see [../06-policies-and-roadmap/](../06-policies-and-roadmap/).)

## CoreGraphics, CoreVideo, IOKit and friends

All display functions model **one built-in display, ID 1**, built from `UIScreen`.

| Area | Answer | File |
|---|---|---|
| `CGMainDisplayID`, `CGDisplayBounds`, `CGGetOnlineDisplayList`, `CGGetActiveDisplayList`, `CGDisplayIsMain`, `CGDisplayIsBuiltin` | display 1; bounds of the screen; built-in yes; no mirroring | `Display.m`, `Desktop.m`, `CPDesktop.m` |
| Display modes (`CGDisplayCopyAllDisplayModes`, `CGDisplayModeGet*`) | one current mode, or the host-provided list (pixel-exact, aspect-correct) | `Display.m`, `Desktop.m`; see [appkit-on-uikit.md](appkit-on-uikit.md) |
| `CGDisplayVendorNumber`, `ModelNumber`, `SerialNumber` | `kDisplayVendorIDUnknown` (0x756e6b6e), generic product ID (0x717), 0 | `CPDesktop.m` |
| Mode switching, display capture, gamma tables, fades | refused with `1000` (failure) or `1004` (cannot complete); nothing pretends to succeed | `Desktop.m` |
| `CVDisplayLink` (create, nominal period, release) | period = `UIScreen.maximumFramesPerSecond`; `Start` / `SetOutputCallback` return `kCVUnsupported` (-6663) | `Desktop.m` |
| `IODisplayGetFloatParameter` | `kIOReturnUnsupported` | `CPDesktop.m` |
| `IODisplayCreateInfoDictionary` | empty dictionary | `Desktop.m` |
| `CGEventSourceCreate`, `...SetLocalEventsSuppressionInterval` | placeholder object / no-op: the adapter's events never come from a hardware event source | `CPDesktop.m` |
| ForceFeedback (`FF*`) | `FFERR_NOINTERFACE` (device has no force feedback) | `Desktop.m` |
| IOBluetooth, Apple Events | factories return nil / handlers are recorded and never invoked | `Desktop.m` |
| OpenGL (`NSOpenGLContext`, pixel format) | no current context; creation returns nil, so SDL's GL path reports an error | `AppKitExtras.m` |
| Carbon text input (`TISCopyCurrentKeyboardLayoutInputSource`, `UCKeyTranslate`, `LMGetKbdType`) | explicit ANSI-US layout; dead keys and Option combinations return an error instead of an approximation | `Keyboard.m` |
| `LSOpenCFURLRef`, `NSWorkspace openURL:` | `UIApplication openURL:` | `Desktop.m`, `AppKitExtras.m` |
| `kCGDisplayShowDuplicateLowResolutionModes` and AppKit string/notification constants | values **measured on macOS** (`docs/evidence/phase6-desktop-constants.txt`, `phase8-desktop-constants.txt`) | `Desktop.m`, `CPDesktop.m`, `Constants.m` |

## Security (certificates)

The game's Galaxy library (`libREDGalaxy64`) is the stated user of these macOS-only certificate functions (per the `CPDesktop.m` comment). They fail the way an
unavailable API does: `SecItemImport`, `SecItemExport` and
`SecIdentityCreateWithCertificate` return `errSecUnimplemented` (-4);
`SecCertificateCopyLongDescription` returns NULL with a cleared error
(`CPDesktop.m`). Nothing fabricates a certificate or an identity.

## Safety nets underneath

- **Named abort stubs** (`phase5_5/runtime/LazyImports.c`, `mp_deferred_import`):
  an unresolved *function* import is bound to a precompiled stub that, when
  actually called, prints `MISSING LAZY IMPORT: <symbol> from <library>` and
  aborts. Up to 64 distinct imports. They are precompiled and signed because iOS
  cannot generate code at run time.
- **Offline gap analysis** (`phase8/tools/import_gaps.py`): checks the game's
  imports against the iOS SDK's `.tbd` files before any run; about 75 real gaps
  were found for Cyberpunk, each then implemented in `CPDesktop.m` (or the stubs
  above). See [../05-tools-and-diagnostics/](../05-tools-and-diagnostics/).
- **AppKit safety net** (`MPZero`) for unimplemented Objective-C methods is
  described in [appkit-on-uikit.md](appkit-on-uikit.md).

## Key functions (summary)

| Function | File | What it does |
|---|---|---|
| `mp_cp_desktop_symbol` | `phase8/runtime/CPDesktop.m` | Symbol table for Cyberpunk's CG/IOKit/Metal-observer/curl/Security stubs and nine measured AppKit string constants. |
| `mp_stk_desktop_symbol` | `phase6/runtime/Desktop.m` | Shared desktop adapters (display management, CVDisplayLink, FF, Bluetooth, Apple Events, URL open) plus class and metaclass lookups for SDL's statically compiled subclasses. |
| `mp_display_symbol` | `phase5_5/runtime/Display.m` | Display and display-mode functions. |
| `mp_keyboard_symbol` | `phase5_5/runtime/Keyboard.m` | Carbon keyboard functions. |
| `mp_desktop_constant` | `phase5_5/runtime/Constants.m` | Measured AppKit/Carbon string constants. |
| `mp_deferred_import` | `phase5_5/runtime/LazyImports.c` | Named abort-on-call stubs. |
| `curl_easy_setopt_`, `curl_easy_getinfo_`, `curl_multi_*_` | `phase8/runtime/CPDesktop.m` | Offline libcurl. |
