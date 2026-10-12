# Loader (`runtime/`)

The loader is a purpose-built subset of dyld. It maps macOS arm64 Mach-O images
that iOS itself would refuse to load (platform `PLATFORM_MACOS`, desktop
frameworks), applies their fixups against iOS symbols, and runs their
initializers. Public API: `runtime/runtime.h`; internals: `runtime/internal.h`.

Files: `image.c` (parse/map/link/start/group), `fixups.c` (rebase, bind,
chained fixups), `group.c` (exports, special ordinals, guest dlopen family,
unwind registration), `services.c` (import resolver, selector fixup,
initializers), `tls.c` (see [tls.md](tls.md)).

## Why a custom loader, and why signed containers

- The iOS dyld cannot load a `PLATFORM_MACOS` image, and copying a signed Mac
  executable into the app's Documents does not make iOS admit its code: in the
  Phase 3 experiment every guest failed `fcntl(F_ADDFILESIGS_RETURN)` with
  `EBADEXEC` (errno 85), while the same call succeeded on the installed host
  (`docs/phase3-ios-admission.md`). Installation, not extraction, establishes
  code-signing state.
- Design that followed: **each guest image is embedded, byte for byte, in its own
  signed iOS "container" dylib** (`MPGuest-N.dylib`) as sections
  `__TEXT,__guest` (the original bytes up to the end of `__TEXT`) and
  `__DATA,__guest` (the rest, plus zero capacity for BSS). iOS dyld maps and
  validates the container; the loader then treats the container's text as the
  guest's text. No RWX pages and no signature bypass: executable pages are
  never remapped or written. Built by `container()` in `phase6/tools/build.py`
  (phase 8 reuses it).
- Veloren (Phase 5.5) had a `__DATA` zero-fill tail, so the guest spans more
  virtual bytes than file bytes and the first container design failed with
  `invalid resident guest range` (`docs/phase5.5-findings.md`). Hence the
  trailing signed RW capacity and the "restore original layout on unload" logic.
- Containers also carry the guest's `__unwind_info` with every image-relative
  offset shifted by the container offset (`rebase_unwind` in the build script),
  because libunwind asks dyld first and dyld only knows the container
  (`docs/phase6-findings.md`).
- Outside iOS (the Mac "load-only" harness), `mp_image_open` maps the file
  directly: a `PROT_NONE` reservation, then `MAP_FIXED` file-backed mappings per
  segment. Executable pages still come from the signed file, never from a
  writable buffer.

## The three phases

```
 mp_group_open(sources[], count, services)
   1. MAP    image_map() for every member     parse + validate + register signature + place segments
   2. LINK   image_link() for every member    chains/rebase/bind/weak-bind/lazy-bind, TLS, selectors,
                                              __DATA_CONST -> read-only, register unwind sections
   3. START  register_metadata (ObjC)         then image_start() per member, dependencies first,
             initializers; main last          then the caller runs mp_image_main() on member 0
```

Order inside `mp_group_open` (`runtime/image.c`): map all members; resolve each
library ordinal to a group member (`mp_group_find`); link all members; if the
`unresolved` probe callback is set, stop ("import probe complete, no guest code
ran"); `mp_group_activate`; call `register_metadata` on each member (last member
back to the main executable); run initializers via `visit()` for every dylib
(with its dependencies first), then the main executable.

### Key functions

| Function | File | What it does |
|---|---|---|
| `mp_group_open` | `runtime/image.c` | Opens main executable + dylibs as one link unit; runs map, link, metadata, start in the order above. A failure pins all members (process-lifetime) because constructors may already have run. |
| `image_map` | `runtime/image.c` | Parses and validates the Mach-O (single arm64 slice, `PLATFORM_MACOS`, segment/section/library limits, no overlaps, alignment to host page size), registers the existing code signature with `F_ADDFILESIGS_RETURN` and `F_CHECK_LV`, then places segments (file mmap, or resident container). |
| `embedded_source` | `runtime/image.c` | Verifies a container: exactly one `__TEXT,__guest` and one `__DATA,__guest` section, contiguous, correct protections, one code signature, data capacity at least the guest's remaining bytes. |
| `image_link` | `runtime/image.c` | Phase 2: `mp_apply_chains`, `mp_apply_rebase`, `mp_apply_bind` (regular, weak, lazy), `mp_prepare_tls`, `mp_prepare_objc`; protects `__DATA_CONST`; computes entry; `mp_register_unwind_image`. |
| `image_start` / `visit` | `runtime/image.c` | Phase 3: `mp_initialize`, DFS over `dependencies[]` so dependencies start first (cycles tolerated, as dyld does). |
| `mp_image_main` | `runtime/image.c` | Calls the guest's `LC_MAIN` entry with `mp_active` set; returns its result code. |
| `mp_image_open_embedded` | `runtime/image.c` | Single-image open of a container-embedded guest (earlier phases). |
| `release_mapping` | `runtime/image.c` | For resident images, restores the original file bytes in the data capacity (undoing the BSS relocation) and zeroes the tail; unmaps otherwise. |
| `mp_group_find` | `runtime/image.c` | Maps an install name to a member; `@executable_path`, `@loader_path`, `@rpath` spellings match by file basename. |
| `mp_locate`, `mp_guest_base` | `runtime/image.c` | Address-to-`image+offset` lookup for crash reports (used from signal handlers). |

### Design decisions

- **Three phases, group-wide.** Map everything, then link everything, then
  start. Members bind against each other's *immutable symbol tables*, so link
  order does not matter. This mirrors dyld and was needed once Phase 6 loaded
  19 images (SuperTuxKart) and Phase 8 five.
- **Validate, never trust.** Every offset, count and range is checked
  (`range()`, `slot()`); fixups may only target aligned, writable, non-executable
  data pointers. Counts have ceilings (`max_fixups` up to 1,048,576, image size
  up to 512 MiB). The header comment of `runtime.h` is explicit that this is for
  trusted, hash-verified games: "This loader provides no isolation."
- **Opt-in feature flags (`MPExtensions`).** `allow_chained_fixups`,
  `allow_thread_locals`, `allow_weak_coalescing`, `allow_guest_dylibs`,
  `allow_categories`, `allow_weak_imports`, `max_image_bytes`, `max_fixups`.
  Phase 5.5 findings tie them to specific real games (TLS and weak coalescing to
  Veloren, group dylibs and categories to SuperTuxKart); images that need an
  unflagged feature are rejected with a specific message (for
  example `TLS/terminators unsupported`).
- **Accept `LC_ENCRYPTION_INFO_64` only when `cryptid == 0`.** Cyberpunk's Bink
  library carries the command with cryptid 0; encrypted images stay rejected.
- **Failed opens are pinned, not unmapped.** A constructor may have registered
  TLS destructors or ObjC classes; unmapping would leave dangling code
  (`mp_image_pin`, `image_discard`).

## Fixups (`runtime/fixups.c`)

| Function | What it does |
|---|---|
| `mp_apply_rebase` | Legacy `REBASE_OPCODE_*` stream. Validates the target against the image range, adds the runtime base while **preserving the high-byte tag** (legacy relocations carry language/runtime tags; found with Veloren). Reaching stream end without `DONE` is accepted, as dyld does (libmbedx509 in SuperTuxKart). |
| `mp_apply_bind` | `BIND_OPCODE_*` for regular (0), lazy (1), and weak (2) streams. Handles special ordinals, signed addends, and `DO_BIND_ADD_ADDR_ULEB` deltas that wrap modulo 2^64 (Apple ld emits them; seen in SuperTuxKart). Unresolved lazy function binds fall back to `resolve_lazy` (named abort stubs). |
| `mp_apply_chains` | `LC_DYLD_CHAINED_FIXUPS`, format `DYLD_CHAINED_PTR_64_OFFSET` only (the format the first real game used). Decodes from the immutable file bytes, never from memory already rebound. Authenticated, compressed and multi-start formats fail deliberately until a controlled experiment exercises them. |

Chained-fixup specifics that came from Cyberpunk (commit `e831216`):

- 8-bit library ordinals 0, 0xFF, 0xFE, 0xFD map to self, main executable, flat
  lookup, weak lookup (`mp_resolve_special`).
- A chained import that the host lacks is not a link failure when it is a
  *function* (and not `_OBJC_*`): it is bound to a named abort-on-call stub
  (`resolve_lazy` = `mp_deferred_import`, `phase5_5/runtime/LazyImports.c`). Chained
  images bind everything at load, so without this one unused missing function
  would prevent launch. Data and ObjC class imports must still resolve.
- The `unresolved` extension turns the whole link into a *probe*: it reports every
  failing import and stops before any guest code runs. This produced the
  75-entry offline gap list used to plan the Cyberpunk adapters
  ([../04-cyberpunk/](../04-cyberpunk/), [../05-tools-and-diagnostics/](../05-tools-and-diagnostics/)).

## Exports and the export trie (`runtime/group.c`)

| Function | What it does |
|---|---|
| `build` / `mp_export` | Builds (once, under `export_lock`) an open-addressed FNV-1a table from the symbol table **plus the export trie**; `mp_export` looks a name up and runs `N_SYMBOL_RESOLVER` resolvers. |
| `trie_node` | Recursive walk of the `EXPORT_SYMBOL` trie with depth and name-length limits; skips re-exports and absolute symbols. |
| `group_search`, `mp_resolve_special` | dyld ordering for weak/flat lookups: first strong definition in member order (main executable wins), else first weak one, then the host via `dlsym(RTLD_DEFAULT)`. |

Design decision: the trie is needed because **stripped images keep only a few
symtab entries** while dyld exports everything through the trie (Cyberpunk's
`libBink2MacArm64`). Trie entries missing from the symtab are added.

## Guest dlopen family and unwinding (`runtime/group.c`)

- `mp_group_dl_import` gives guest code its own `dlopen`, `dlsym`, `dlclose`,
  `dlerror`, `dladdr` (`mp_dlopen` and friends). Handles are `&image->dl_token`;
  anything else falls through to the host. Reason: SDL in SuperTuxKart
  `dlopen`s `@executable_path/../libs/libMoltenVK.dylib`, whose ID is
  `@rpath/libMoltenVK.dylib`; that must resolve to the already-loaded member.
  Desktop framework paths are rewritten to iOS shallow-bundle spelling
  (`host_dlopen`).
- `mp_register_unwind_image` hooks libunwind's `__unw_add_find_dynamic_unwind_sections`
  for **directly mapped** guests (the Mac harness) so C++ exceptions and Rust
  panics can unwind through them. Resident (container) images are inside a dyld
  image, so libunwind finds them through the shifted `__unwind_info` instead.

## Initializers and Objective-C (`runtime/services.c`, `phase4/runtime/Extended.c`)

| Function | File | What it does |
|---|---|---|
| `mp_initialize` | `runtime/services.c` | Runs `S_MOD_INIT_FUNC_POINTERS` lists **and** `S_INIT_FUNC_OFFSETS` (`__TEXT,__init_offsets`, 32-bit image-relative offsets) in section order; refuses a function outside executable code; records the running initializer in `mp_init_image/index/offset` for the crash reporter. |
| `mp_prepare_objc` | `runtime/services.c` | For every `__objc_selrefs` slot, validates that it points at a NUL-terminated string in the image and replaces it with `sel_registerName(...)`. |
| `mp_register_metadata` | `phase4/runtime/Extended.c` | Pins the image, then `objc_readClassPair` for each `__objc_classlist` entry, the three `swift_register*` calls, and `apply_categories`. |
| `apply_categories` / `apply_methods` | `phase4/runtime/Extended.c` | Attaches compiled category methods with `class_replaceMethod` (so category methods override class methods), handling both relative ("small") and pointer method lists; adds protocols the host already knows. |

Design decisions:

- **`__init_offsets` is mandatory for modern binaries.** Cyberpunk has 7,458
  initializers in that format; legacy pointer lists alone would run none of them.
- **Metadata registration happens after all members are linked and before any
  initializer** (dyld's `map_images` ordering), so a constructor that touches
  another member's class finds it registered.
- **Pin before publishing.** There is no matching unregister for
  `objc_readClassPair` or Swift registration, so the image is pinned first and
  can never be unmapped under live metadata.
- Reference totals: Cyberpunk 5 images, 685,682 rebases, 71,348 binds,
  495 selectors, 7,458 initializers. SuperTuxKart 19 images, 99,395 rebases,
  20,735 binds, 1,441 selectors, 390 initializers.

## Import resolution and interposition (`runtime/services.c`, policies)

Guests are not patched. Their imports are *bound* to whatever `mp_resolve`
returns, which is how mmap, file, sysctl and AppKit calls reach the adapters.

Order in `mp_resolve(image, library, symbol)`:

1. Another group member's export (by install name), plus guest `dlopen` family.
2. `__NSGetArgc`/`__NSGetArgv` if the host supplied guest argv.
3. `services.extensions->resolve(library, symbol)`: **the policy chain**.
4. AppKit imports go to `mp_set_appkit_resolver` (the explicit AppKit shim).
5. A hard-coded small allowlist for the oldest fixtures; otherwise a host `dlopen` of the declared
   library + `dlsym`.

The policy chain for Cyberpunk, `mp_cp_policy` -> `resolve` in
`phase8/runtime/Policy.c`:

```
 _NSGetExecutablePath                     -> guest_executable_path   (virtual path from MP_GUEST_EXECUTABLE_PATH)
 libSystem: _mmap/_munmap/_mprotect/_madvise -> rationing interposers  (address-space-and-memory.md)
 libSystem: path functions                -> case-insensitive wrappers (system-services.md)
 libSystem: _sysctl/_sysctlbyname         -> hw.memsize answer
 Metal: MTLCreateSystemDefaultDevice/MTLCopyAllDevices -> CPMetal.m   (metal.md)
 mp_cp_desktop_symbol  (CPDesktop.m)      -> CG, IOKit, curl, Security stubs
 mp_stk_desktop_symbol (Desktop.m)        -> shared SDL-era desktop adapters
 mp_large_game_policy()->resolve          -> phase5_5 -> phase5 AppKit map -> phase4 host dlsym
```

Design decisions:

- **Policy is layered by copy** (`mp_extended_policy` < `game_policy` <
  `mp_large_game_policy` < per-game policy). A per-game file lists only its extra
  allowed libraries and its own interposers, which kept Phase 8's `Policy.c`
  to one file.
- **`library_allowed` is a dependency whitelist, separate from API
  compatibility.** `mp_cp_policy` allows AudioUnit, CoreHaptics, MetalFX,
  MetricKit, libbz2 and libcurl as *paths*; each still needs its symbols supplied
  or the link fails visibly.
- **Interposition is import-level.** It covers anything the guest binds through
  its own imports. Calls made inside system libraries, or raw syscalls from
  guest code, are not intercepted. (Not exercised by the games so far; stated
  as a limitation, not measured.)
- **Virtual executable path.** Cyberpunk finds `archive/`, `engine/`, `r6/` by
  walking up from `_NSGetExecutablePath`; `guest_executable_path` returns a
  path inside Documents instead of the host app's real path.

See also: [tls.md](tls.md), [address-space-and-memory.md](address-space-and-memory.md),
[../03-phase-history/](../03-phase-history/).
