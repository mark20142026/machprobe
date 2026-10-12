# Memory: where the RAM goes, the limits, and the open leak hunt

Memory was the hardest constraint on the phone. This file records the limits, how
the layer shapes the game's view of memory, what the telemetry shows, and the
leak that is still open. Sources: `phase8/runtime/Policy.c`, `phase8/runtime/CPMetal.m`,
`phase8/runtime/CPDesktop.m`, `phase8/host/Main.m`, and the commits named below.

## The limits

| Limit | Value | Source |
|-------|-------|--------|
| App memory with `com.apple.developer.kernel.increased-memory-limit` | about 6.0-6.4 GB available (`os_proc_available_memory`) | CONTEXT (hardware notes) |
| Without the entitlement | about 3.44 GB (the earlier risk) | CONTEXT |
| `com.apple.developer.kernel.extended-virtual-addressing` | does NOT work on the free team | CONTEXT |
| Virtual address space | about 66 GB: a 64 GB window at `0x7000000000` plus about 1.5 GB low (MAP_FIXED elsewhere refused) | `0908351` body; CONTEXT |
| GPU recommended working set | about 8 GB on the A20 Pro (device value, recorded in CONTEXT) | CONTEXT |
| Largest single Metal buffer | 6 GB (device value) | CONTEXT |

The entitlement is set in the signed profile; `phase8/tools/phone.py` takes the
entitlements from the profile.

## How the layer shapes the game's view of memory

The game budgets itself from what it is told, so the layer lies on purpose in
three places.

1. `hw.memsize`. `sysctl` and `sysctlbyname` return `MP_MEMSIZE_GB` gigabytes
   (default 3, in `phase8/runtime/Policy.c` `guest_sysctlbyname` and
   `phase8/runtime/CPDesktop.m` `guest_sysctl`). RED sets its GPU budget to
   0.75 x `hw.memsize`, so the default gives about 2.25 GB of planned GPU memory.
   Commit `538ebc6` first used 8 GB (about 6 GB of planned GPU memory, too
   much); commit `04c412a` set 3 GB. Note: `Policy.c` and `CPDesktop.m` disagree
   with CONTEXT on the default (see `known-issues.md`).
2. Metal heaps. `heap()` in `phase8/runtime/CPMetal.m` caps each heap at
   `MP_HEAP_CAP_MB` (default 96 MB in code; 512 MB in `0908351`). iOS commits a
   heap whole at creation, so a 3 GB heap was a jetsam risk.
3. Spill-over heaps. When a capped heap is full, `spill_heap()` adds a heap of at
   least 64 MB, but only while `os_proc_available_memory()` is at least the
   request plus a margin (`marginBytes`, 900 MB in code; CONTEXT and `538ebc6`
   say 600 MB). Total spill is capped by `MP_SPILL_CAP_MB` (default 1024).
   Residency hooks make spill-over heaps resident wherever the capped heap is
   used (`useHeap:` variants on the render and compute encoders).

Address space (`0908351`, `Policy.c`):
- RED reserves allocator regions of 16 GB (small), 64 GB (medium) and 32 GB (large)
  with `mmap`. Requests of 16 GB or more are placed top-down from `0x8000000000`
  (small on top), so each region's unbacked tail covers only regions checked before it.
- Above 16 GB, real backing is limited to `MP_VA_CAP_GB` (default 8 GB). The
  unbacked tail is tracked in `shrunk[]` (up to 32 entries).
- `guest_munmap`, `guest_mprotect` and `guest_madvise` clip to the backed part.
  `guest_mmap` with `MAP_FIXED` into a tail is refused with `ENOMEM`.
- The crash reporter says "fault is in the unbacked tail ... (raise MP_VA_CAP_GB)"
  when a fault lands in a tail (`mp_cp_va_tail`).

## VM tags and the telemetry

`Main.m` prints one line per 5 s (`[budget]`) and, every 10 s, a vmmap-style line
(`[vmtags]`):

- `[budget] t=Ns fps=... footprint=... MB gpu=... MB cpu=... MB free=... MB`.
  `footprint` is `phys_footprint`; `gpu` is `MTLDevice.currentAllocatedSize`;
  `cpu` is footprint minus gpu; `free` is `os_proc_available_memory()`.
- `[vmtags] t=Ns engine-regions=... MB tagN=... MB ...`. Engine regions are the
  VM regions in `0x7000000000`-`0x8000000000` with user tag 0. Other tags are
  listed by size (only tags above 64 MB).
- Tags seen in CONTEXT: tag 2 (`malloc-small`), tag 100 (`IOACCELERATOR`, about 820 MB).
- `[memwatch]` (one line per second) only with `MP_CONSOLE` set.
- `[gpu]` allocation trace (`MP_MEM_TRACE`): allocations of 16 MB or more with the
  guest caller, and running totals.

Numbers recorded in CONTEXT:
- Menu, first run after `0908351`: about 2.4 GB free (512 MB heaps).
- City, 9 Oct: about 2.6 GB GPU and 3.1 GB CPU, about 450 MB free.
- Engine regions about 2.37 GB after world load; the engine's allocator regions
  grow about 1.2 GB on world load.
- Killed during a car crash at about 265 MB free (9 Oct end-of-day notes, CONTEXT).

## Changes and their measured effect

| Change | Commit | Effect recorded |
|--------|--------|-----------------|
| Top-down address-space rationing | `0908351` | Main menu reached |
| Heaps capped at 512 MB | `0908351` | Main menu runs with about 2.4 GB free (CONTEXT) |
| `hw.memsize` 8 GB | `538ebc6` | RED budgets smaller; still over-planned |
| Spill-over heaps and residency hooks | `538ebc6` | Heaps grow as the game fills them |
| `hw.memsize` 3 GB; heaps 96 MB and grow on demand | `04c412a` | Menu GPU 2.5 GB to 1.7 GB |
| Spill-over cap 1024 MB | `0cb6e9e` | Bounds spill growth; no measured effect recorded yet |
| Managed storage rewritten to Shared | `e831216` | Unified memory; lost lossless compression on Apple GPUs (see `performance.md`) |
| Managed render targets to Private (experiment) | `0cb6e9e` | Built, `MP_MANAGED_RT_PRIVATE`, not yet run on the phone |

## The malloc-small creep (open)

- Observed: VM tag 2 (`malloc-small`) grows about 1.4 MB/s during play. Over a
  few minutes that closes the gap to the 265 MB kill point (CONTEXT).
- Tag 2 is the system small-object allocator. The GPU side is tagged separately
  (`IOACCELERATOR`, tag 100), so the creep is on the CPU side of the ledger.
- Our layer's allocation paths were checked in the code and found not to allocate
  per call on the hot paths:
  - the safety net `forward()` in `CPAppKit.m` returns a shared singleton
    (`MPZero`) and deduplicates with a lock-free table, so repeated unknown
    selectors cost no allocation;
  - `counted_commit()` (`CPMetal.m`) adds a completion handler per command buffer.
    Its block captures nothing, so the block itself is not allocated per call, but
    Metal retains it per command buffer. Unverified as a cause;
  - the memory and budget loops run once every 5 s and allocate report strings
    only then.
  - Malloc is wrapped only when `MP_MEM_TRACE` is set (`guest_malloc`), so the
    default build does not count allocations.
- Not yet tested: whether the growth tracks frames or time.

## The autorelease-pool theory (hypothesis, not verified)

- Hypothesis: Objective-C objects autoreleased on threads that never drain a pool
  accumulate, and show up as malloc-small growth.
- Repository state: `phase8/host/Main.m` wraps `main()` in `@autoreleasepool`, and
  the game's entry runs inside the UIKit run loop, which drains a pool each turn
  on the main thread. Worker threads started by the guest's engine are not
  visible in `phase8/`, so whether they have pools is unknown.
- What would confirm it: a per-thread census of autoreleased objects, or an
  `autoreleasepool` wrapper around the guest's worker-thread entry points
  (those are in the guest image; locating them is the open step).
- Status: no code in the repository implements or measures this theory.

## The open leak hunt: next steps

1. Install the current build (`phase8/tools/build.py`) with `MP_MEM_TRACE` off and
   record `[vmtags]` every 10 s for a 10-minute drive. Compare tag 2 against frames.
2. Repeat with the Managed-to-Private experiment on (`MP_MANAGED_RT_PRIVATE=1` in
   `Documents/env.json`), to see whether texture storage affects the creep.
3. Add a per-thread autorelease pool wrapper for guest threads only if step 1 shows
   growth that tracks wall time rather than frames.
4. Keep the spill cap (`MP_SPILL_CAP_MB`) as the backstop until the creep is fixed.

Install and relaunch need the user's explicit yes (see `known-issues.md`).
