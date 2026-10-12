# Porting other games

machprobe isn't Cyberpunk-specific. The loader, AppKit-on-UIKit layer, Metal
pass-through and system services are general. Per-game work is mostly *adapters* and *budgets*.

## What a game needs to be a candidate

| Requirement | Why |
|---|---|
| **Native Apple-silicon (arm64) Mac build** | No emulation; Intel-only or Windows games are out of scope |
| **Metal renderer** | Metal passes straight through. Games using Vulkan through a bundled MoltenVK also work (SuperTuxKart), but OpenGL-only games need more work |
| **Fits in ~6 GB of memory** | iOS kills apps above the limit (with `increased-memory-limit`) |
| **Reasonable address-space use** | iOS gives ~64 GB of VA; engines that reserve more must be rationed |
| **No hard DRM / kernel anti-cheat** | Online-only or anti-cheat games won't run, and circumventing them isn't something we do |
| **You own it** | See [legal-and-ethics.md](legal-and-ethics.md) |

Candidates discussed (not attempted): Baldur's Gate 3, No Man's Sky, Lies of P, Control, Stray.

## The per-game checklist (what Cyberpunk needed)

Use this as a plan for a new game. Each item links to where it was solved for Cyberpunk.

1. **Package the images.** Find every Mach-O in the `.app` (main executable, frameworks,
   dylibs) and add them to a phase build script. → [../05-tools-and-diagnostics/build-tools.md](../05-tools-and-diagnostics/build-tools.md)
2. **Load-only run on the Mac.** Use the load CLI (`MP_DUMP_CLASSES`, `MP_FIND_SELECTOR`) to
   list missing symbols and selectors *without* running the game.
3. **Address space.** Watch for big `mmap` reservations; add rationing rules in the policy layer.
   → [../02-architecture/address-space-and-memory.md](../02-architecture/address-space-and-memory.md)
4. **Paths.** Case-insensitive resolution and home remapping usually just work; check the
   fs trace for misses.
5. **Missing APIs.** Each crash on an unrecognized selector or missing symbol becomes one small
   adapter method. A selector survey finds them in bulk.
6. **Network.** Offline replacements for libraries like libcurl if the game expects them.
7. **Memory budget.** Decide what `hw.memsize` to report and how big GPU heaps may grow.
8. **Display.** Offer aspect-correct modes so the game renders at the phone's shape.
9. **Input focus quirks.** Engines often drop input unless the window is "key" and the
   cursor is "in view". Find the flags and keep them set.
10. **Controls.** Touch layout and controller mapping.

## Effort estimate from experience

| Game | Images | Bring-up |
|---|---|---|
| SuperTuxKart | 19 | From 7 Oct 2026 (VM) to the physical phone (phases 6–7) |
| Cyberpunk 2077 | Large AAA engine | First commit 9 Oct 2026 → playable on 10 Oct 2026 (long sessions) |

A new AAA game would reuse most of this work (an estimate, not a measurement) and spend
most of its time on memory budgets and engine-specific input/focus quirks.
