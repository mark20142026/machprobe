# Metal pass-through

Mac games talk to Metal directly, and an iPhone has the same Metal API on an
Apple GPU. So the layer's policy for Metal is: **hand the game Apple's real
`MTLDevice` and change as little as possible.** Cyberpunk's draw calls, pipeline
states, shaders and command buffers reach the real driver (AGX) untouched.
What the layer adds is limited to the places where the macOS Metal surface and
the iOS Metal surface differ, and to memory control for the heaps.

The main file is `phase8/runtime/CPMetal.m` ("lean Metal"). Earlier phases used a
heavier proxy approach, described at the end.

## What is different between Mac and iOS Metal

| Mac-only thing the game uses | What the layer does | Where |
|---|---|---|
| Methods that exist only on macOS (`API_UNAVAILABLE(ios)`) on `MTLDevice`: `isLowPower`, `isHeadless`, `isRemovable`, `location`, `locationNumber`, `maxTransferRate`, `peerGroupID`, `peerIndex`, `peerCount`, `isDepth24Stencil8PixelFormatSupported`, `areBarycentricCoordsSupported` | Added to the device's concrete class with answers for a built-in Apple GPU (no, no, no, 0, 0, 0, 0, 0, 1, no for D24S8, and barycentric support forwarded to `supportsShaderBarycentricCoordinates`). `add()` installs a method only if the class does not already respond to it. | `mp_cp_metal_install` |
| `MTLStorageModeManaged` (value 1) for buffers, textures and heaps | Rewritten to Shared at creation (see below). | `buf_len`, `buf_bytes`, `buf_nocopy`, `tex`, `heap`, `heap_buf` |
| Managed-resource synchronisation: `-[MTLBuffer didModifyRange:]`, `-[MTLBlitCommandEncoder synchronizeResource:]`, `synchronizeTexture:slice:level:` | Added as **no-ops** on the concrete buffer and blit-encoder classes. | `mp_cp_metal_install` |
| `MTLCopyAllDevicesWithObserver` / `MTLRemoveDeviceObserver` | Return the single device and a token that never fires (iOS has one GPU and no hot-plug). | `phase8/runtime/CPDesktop.m` |
| `MTLCreateSystemDefaultDevice`, `MTLCopyAllDevices` | Bound to `mp_cp_metal_default_device` / `mp_cp_metal_devices`, which return the real device after `mp_cp_metal_install`. | `Policy.c` `resolve` |
| Multi-GB `MTLHeap`s | Capped and grown on demand; see [address-space-and-memory.md](address-space-and-memory.md). | `heap`, `spill_heap` |

### Key functions (`phase8/runtime/CPMetal.m`)

| Function | What it does |
|---|---|
| `mp_cp_metal_install` | One-time setup: creates the real device, adds the Mac-only methods, wraps the creation methods, adds the sync no-ops (discovering the concrete buffer and blit-encoder classes by creating throwaway objects). |
| `mp_cp_metal_default_device`, `mp_cp_metal_devices` | What the guest receives for `MTLCreateSystemDefaultDevice` and `MTLCopyAllDevices`. |
| `wrap` | Replaces a device-class method and returns the original; implemented by `class_addMethod`/`method_setImplementation` on the **concrete class**, not a proxy object. |
| `shared_options` | If the storage-mode nibble of `MTLResourceOptions` is 1 (Managed), clears it so the default (Shared) applies. |
| `tex` | `-newTextureWithDescriptor:` hook. Copies the descriptor and switches Managed to Shared (or to Private for render targets under `MP_MANAGED_RT_PRIVATE`); counts descriptors in `mp_tex_census`; logs a full descriptor dump if creation returns nil. |
| `heap`, `heap_tex`, `heap_buf`, `spill_heap` | Heap cap and spill-over sub-allocation (memory doc). |
| `mp_cp_metal_features` | Reports GPU families (Apple7-10, Mac2, Metal3, Metal4), BC texture support, recommended working set and max buffer length into the run report. |
| `mp_cp_gpu_timing_install` | Counts command-buffer GPU time for telemetry. |

## Managed to Shared

Managed storage means "separate CPU and GPU copies kept coherent with explicit
`didModifyRange:` / `synchronize` calls", a discrete-GPU concept. Apple silicon
has unified memory and iOS has no Managed mode in its SDK. Shared gives the same
CPU/GPU view of the same allocation, so:

- the creation call is rewritten to Shared (`shared_options`, `tex`, `heap`), and
- `didModifyRange:` and `synchronize*` become no-ops: with a single shared copy
  there is nothing to flush, so any real implementation would only cost CPU on
  every upload.

Trade-off recorded in the code: **Shared textures lose lossless compression on
Apple GPUs.** The texture census (logged in `[perf]`) separates Managed render
targets, other Managed textures, Shared and Private so the cost can be measured.
`MP_MANAGED_RT_PRIVATE=1` is an experiment that makes Managed *render targets* Private
(the CPU never writes render targets), which would restore compression for them.
It is off by default; the outcome is not recorded in the repository yet.

## Why in-place class additions rather than a proxy device

Phase 5 (`phase5/runtime/MetalCompat.m`) wrapped the device in a forwarding
object (`MPMetalDeviceAdapter`, `forwardingTargetForSelector:`). That is simple
and safe but puts an extra object and message-forwarding step in front of every
call the game makes on the device and every object it returns. Commit
`e831216` introduced the lean variant: methods are added to or wrapped on the
concrete classes Apple returns, so every other call is a direct call into the
driver. The only per-frame hooks left are (a) creation methods, which are not
per-draw, (b) `useHeap:` variants that are free until a heap has spilled, and
(c) optional telemetry on `-commit`. After this the layer's measured profile on
device was: main thread about 1 percent, CPU about 2 of 6 cores, GPU the
bottleneck (`CONTEXT.md`, status 9 Oct).

Design decisions, in short:

- **Pass-through by default.** Anything not listed above is Apple's code.
- **Concrete class, device-scoped.** Methods are installed on the class of this
  device (a driver-specific class, name not recorded in the repo), not on
  `NSObject` or protocol types.
- **Truthful capability reporting.** The device is real, so `supportsFamily:`
  answers are real (Apple7-Apple10, Metal3, Metal4 on the iPhone 18 Pro; BC
  texture compression supported according to `CONTEXT.md`). The Mac-only
  additions answer for a built-in Apple GPU rather than pretending to be a
  discrete Mac GPU.

## Earlier Metal work and the bugs that shaped it

These are kept because later phases build on their lessons.

- **Do not fake capability bundles** (SuperTuxKart, Phase 6). Phase 5.5 added a
  legacy Mac feature-set profile (`phase5_5/runtime/LegacyMetal.m`) so wgpu could
  sample border colours. With it, macOS MoltenVK enabled BC/DXT texture formats
  that the vphone VM's paravirtual GPU does not support (`bc_textures: 0`), and
  rendering broke. The profile is disabled for STK and Cyberpunk (`docs/phase6-findings.md`,
  `CONTEXT.md`: "legacy Mac Metal profile -> BC formats (disabled for STK/CP)"). Lesson: never fake capability bundles.
- **Placement `MTLHeap` corruption on the VM** with MoltenVK; fixed by
  `MVK_CONFIG_USE_MTLHEAP=0` (VM-specific).
- **GPU defect on the vphone VM**: indexed draws truncate `baseVertex` to 16 bits.
  `phase5_5/runtime/BaseVertex.m` detects it at startup with a probe draw and, only
  if present, rewrites draws with `baseVertex >= 65536` by advancing each
  per-vertex buffer by `baseVertex * stride` and drawing with base 0. The real
  iPhone does not have the defect, so the rewrite never activates there.
  Limitation: `[[vertex_id]]` then excludes the base.
- **Draw/present observation** (`phase5/runtime/Observe.m`, `LegacyMetal.m`): an
  `MTKViewDelegate` wrapper and drawable presentation statistics used in the
  vphone phases. The Phase 8 host deliberately has no diagnostic proxies; per-frame
  telemetry is limited to the GPU-time handler.

## Related

- Heap/jetsam mechanics: [address-space-and-memory.md](address-space-and-memory.md).
- How the game's `CAMetalLayer` ends up on screen: [appkit-on-uikit.md](appkit-on-uikit.md)
  (view layer hosting) and [../04-cyberpunk/](../04-cyberpunk/).
- Telemetry lines (`[gpu]`, `[perf]`): [../05-tools-and-diagnostics/](../05-tools-and-diagnostics/).
