# Address space and memory

A desktop game assumes a huge virtual address space and a RAM size of 8-64 GB.
An iPhone app gets neither. Most of the Cyberpunk bring-up (commits `0908351`,
`538ebc6`, `04c412a`, `0cb6e9e`) was fitting RED Engine's Mac memory assumptions
into iOS limits **without changing a byte of the game**. Everything here is
policy that sits between the guest's imports and libSystem/Metal.

Source: `phase8/runtime/Policy.c` (address space, `hw.memsize`),
`phase8/runtime/CPMetal.m` (GPU heaps), `phase8/host/Main.m` (telemetry,
`env.json`).

## The three limits

| Limit | Value | Source |
|---|---|---|
| Virtual address space | about 66 GB: a 64 GB window `0x7000000000`-`0x8000000000` plus about 1.5 GB low. `MAP_FIXED` anywhere else is refused. | Measured by the `MP_VA_PROBE` experiment in `phase8/host/Main.m`; recorded in `CONTEXT.md` and the comment above `struct Shrunk` in `Policy.c` |
| Physical memory (jetsam) | about 3.44 GB by default; about 6.0-6.4 GB with `com.apple.developer.kernel.increased-memory-limit`. Extended Virtual Addressing did **not** work on the free account; the increased-memory-limit entitlement did. | `CONTEXT.md` "Hardware / accounts" and "Open risks" |
| What the game believes about RAM | `hw.memsize`; the layer answers 3 GB | `guest_sysctlbyname` in `Policy.c` |

The device itself reports more RAM than an app may use (the `Policy.c` comment
says 12 GB for the iPhone 18 Pro; the Metal `recommendedMaxWorkingSetSize` is
about 8 GB). Both exceed what the jetsam limit allows, which is why the game
must be told a smaller number.

## Address-space rationing (`guest_mmap` and friends)

### The problem

RED Engine's allocator reserves three huge regions up front: 16 GB (small), 64 GB
(medium) and 32 GB (large). That is 112 GB against a 64 GB window. It fills each
region from its start, and `free()` decides which allocator owns a pointer **by
range**: first small, then medium, otherwise large.

### The design (`guest_mmap`, `clip`, `struct Shrunk`)

```
 0x8000000000  +--------------------+  <- top of the usable window
               | small  16 GB real  |  placed first, on top
 0x7C00000000  +--------------------+
               | medium  8 GB real  |  (claimed 64 GB; tail is NOT mapped)
 0x7A00000000  +--------------------+
               | large   8 GB real  |  (claimed 32 GB; tail is NOT mapped)
 0x7800000000  +--------------------+
               | everything else (malloc, Metal, thread stacks, ...)
```

- An anonymous, non-fixed `mmap` of **16 GB or more** is placed explicitly,
  stacked **top-down** from `0x8000000000` in request order (`top` static).
  Exactly 16 GB gets 16 GB of real address space; larger requests get
  `MP_VA_CAP_GB` (default 8) of real space and the remainder is recorded as an
  unbacked "tail" (`shrunk[]`: `base`, `real`, `claimed`).
- Because placement is top-down in the same order `free()` checks ranges, each
  region's unbacked tail overlaps only regions that are checked *before* it, or
  addresses beyond the window that nothing can occupy. So a pointer in the real
  part of a lower region is never mistaken for a higher region's, and `free()`
  routing stays correct even though the "claimed" ranges overlap.
- Later calls that reach into a tail are made safe: `guest_munmap`,
  `guest_mprotect` and `guest_madvise` call `clip()` to cut the range to the
  backed part (returning success when nothing backed remains); `MAP_FIXED` into a
  tail is **refused** with `ENOMEM` and logged (`refused MAP_FIXED ... into a
  rationed tail`). Unmapping a rationed region unmaps only its real part.
- If the placement `mmap` does not land at the requested address it is unmapped
  and the call falls back to a normal `mmap` (logged as `could not place ...`).
- Crash reports use `mp_cp_va_tail` (`phase8/host/Main.m` signal handler): a
  fault inside a tail prints "fault is in the unbacked tail of a rationed guest
  reservation (raise MP_VA_CAP_GB)".

### Key functions

| Function | File | What it does |
|---|---|---|
| `guest_mmap` | `phase8/runtime/Policy.c` | Bound as the guest's `_mmap`. Places >=16 GB anonymous reservations top-down, rations oversized ones, refuses fixed maps into tails, logs failures and (with `MP_MEM_TRACE`) every mapping >=64 MB with the guest caller (`trace_callers`). |
| `guest_munmap` / `guest_mprotect` / `guest_madvise` | `phase8/runtime/Policy.c` | Clip to backed ranges so they never touch another mapping. |
| `clip` | `phase8/runtime/Policy.c` | Subtracts every unbacked tail from `[a, a+n)`. |
| `va_cap` | `phase8/runtime/Policy.c` | Reads `MP_VA_CAP_GB` (default 8). |
| `mp_cp_va_tail` | `phase8/runtime/Policy.c` | Classifies a fault address for the crash reporter. |
| `guest_malloc` | `phase8/runtime/Policy.c` | Bound only when `MP_MEM_TRACE` is set (a wrapper on the hottest path is not worth the cost otherwise). |

### Design decisions

- **Explicit top-down stacking, not "just cap the size".** Merely shrinking the
  reservations would have broken the allocator's range-based `free()` routing.
- **Real size 8 GB, claimed 64/32 GB.** Virtual space is free; physical use is on
  demand. 8 GB per big region is more than the process can ever touch under a
  6 GB jetsam limit, but keeps the claimed layout intact.
- **Reserve, don't commit.** The rationing only changes *where* and *how much*
  address space exists; it does not pre-commit memory.

## Jetsam limit and how the app stays under it

- The entitlement `com.apple.developer.kernel.increased-memory-limit` is in the
  provisioning profile (works with a free Personal Team; see `phase7/signing`).
  Without it the app is limited to about 3.44 GB, with it about 6.0-6.4 GB.
- The host measures `os_proc_available_memory()` and prints, every 5 s,
  `[budget] ... footprint gpu cpu free` (`phase8/host/Main.m`): `gpu` is
  `MTLDevice.currentAllocatedSize`, `cpu` is footprint minus that, plus
  `[vmtags]` (a `vmmap`-style breakdown by VM tag and an "engine regions"
  figure for untagged memory in the `0x7000000000` window), and `[perf]` with
  thermal state and the texture storage census.
- Findings that shaped the design (end of day 9 Oct, `CONTEXT.md`): in the city
  about 2.6 GB GPU + 3.1 GB CPU left roughly 450 MB free; a memory kill occurred
  at about 265 MB free after a car crash; `malloc-small` (VM tag 2) was growing
  about 1.4 MB/s, IOAccelerator (tag 100) about 820 MB, engine regions about
  2.37 GB. The leak source in the layer vs. the engine was **not yet determined**.

## The `hw.memsize` answer

RED Engine sets its GPU budget to **0.75 x `hw.memsize`** (the Mac working-set
rule). With a 6 GB figure it planned 4.5 GB of GPU memory in an app that can use
about 6 GB in total (commit `04c412a`). `guest_sysctlbyname` and `guest_sysctl`
(`Policy.c`) therefore return `MP_MEMSIZE_GB` GB for `hw.memsize` (default **3**,
so a 2.25 GB GPU budget) when the guest asks with an 8-byte buffer, on iOS only.
History: 8 GB in commit `538ebc6`, then 3 GB in `04c412a`; `CONTEXT.md` still
contains the older "8 GB" line, the code is authoritative. Every other sysctl
passes through to the real kernel.

## Metal heaps: grow on demand, spill over

(Implementation in `phase8/runtime/CPMetal.m`; API additions are described in
[metal.md](metal.md).)

**Why heaps matter:** on Mac the game creates multi-GB `MTLHeap`s (3 GB plus
about 1.15 GB and more). iOS charges a heap **whole at creation**, so the first
build was jetsam-killed within about 2 seconds.

### Evolution

1. `0908351`: cap every heap at 512 MB (`MP_HEAP_CAP_MB`). Menu then held about
   2.4 GB free; world streaming then filled the capped heaps.
2. `538ebc6`: when a sub-allocation from a capped heap fails, create a
   **spill-over heap** and chain it to the capped one; `useHeap:` variants on the
   concrete encoder classes make the chained heaps resident too.
3. `04c412a`: start small (**default cap 96 MB**) and grow by spill-over heaps of
   at least 64 MB. The menu's GPU memory dropped from about 2.5 to about 1.7 GB.
4. `0cb6e9e`: **hard cap on total spill** (`MP_SPILL_CAP_MB`, default 1024) so
   streaming drops to lower mips instead of pushing the app toward the limit.

### Key functions (all in `phase8/runtime/CPMetal.m`)

| Function | What it does |
|---|---|
| `heap` | Hook for `-newHeapWithDescriptor:`. Clamps `descriptor.size` to the cap (`MP_HEAP_CAP_MB`, default 96, 0 disables), rewrites Managed storage to Shared, then watches the resulting heap (`watch_heap`). |
| `heap_tex` / `heap_buf` | Hooks for heap sub-allocation. Try the heap, then its overflow heaps; on failure call `spill_heap`; if that returns nil, log `[gpu] heap FULL ...` (first 20 only) and return nil. The game may not check for nil, so the log is always on. |
| `spill_heap` | Creates the overflow heap if (a) total spill + need <= `MP_SPILL_CAP_MB` and (b) `os_proc_available_memory()` >= need + 900 MB margin. Size = max(need, 64 MB). Keeps overflow lists in an associated object, copy-on-write under `os_unfair_lock`. |
| `install_encoder_hooks`, `useHeapR` / `useHeapC` and the `...Stages...`/`...s:count:` variants | Hook the render/compute encoder classes (found by creating throwaway encoders) so `useHeap:` also covers overflow heaps. Free until a heap has spilled (`spilledHeaps` is 0), so there is no per-draw cost before that. |
| `counted_commit` (`mp_cp_gpu_timing_install`) | Adds a completed handler to every command buffer to sum GPU time for the `[perf]` line. It overstates busy time because command buffers overlap (noted in `CONTEXT.md`). |

### Design decisions

- **Margin check uses real available memory.** A spill heap is only created if
  `os_proc_available_memory()` shows room beyond the margin, so GPU growth stops
  before jetsam does. The margin grew from 600 MB (`538ebc6`) to 900 MB.
- **Hard spill cap.** Without it GPU growth consumed the headroom the CPU side
  needed. Failure is graceful in a game with streaming: lower mip levels.
- **Copy-on-write overflow lists.** `useHeap:` runs on the render thread for every
  encoder; readers must never see a mutating array.
- **Pending (not done):** a dynamic "memory governor" that grows when memory is
  free and freezes under pressure or on an iOS memory warning, and a texture
  storage experiment (see [../06-policies-and-roadmap/](../06-policies-and-roadmap/)).

## Tuning knobs

| Variable | Default | Effect |
|---|---|---|
| `MP_VA_CAP_GB` | 8 | Real address space for each >16 GB reservation |
| `MP_MEMSIZE_GB` | 3 | Value of `hw.memsize` shown to the guest |
| `MP_HEAP_CAP_MB` | 96 | Max size of any `MTLHeap` (0 = uncapped) |
| `MP_SPILL_CAP_MB` | 1024 | Total spill-over heap budget |
| `MP_MEM_TRACE` | off | Large mmap/malloc/GPU allocation trace with guest caller |
| `MP_VA_PROBE` | off | Exits after measuring free VA ranges |
| `MP_MANAGED_RT_PRIVATE` | off | Experiment: Managed render targets become Private |

All can be set without a rebuild through `Documents/env.json` (`{"MP_...":"..."}`),
applied at the top of `main` in `phase8/host/Main.m`. See
[../05-tools-and-diagnostics/](../05-tools-and-diagnostics/) for reading the
resulting `[budget]`, `[vmtags]` and `[gpu]` lines.
