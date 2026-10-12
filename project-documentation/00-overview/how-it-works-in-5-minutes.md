# How it works in 5 minutes

This is the whole journey of one frame of Cyberpunk 2077, from a Mac `.app` on disk to
pixels on an iPhone screen. Each step links to the detailed page.

```
 Mac (build time)                         iPhone (run time)
 ────────────────                         ────────────────────────────────────────────
 Steam install of the game                 CP2077Host.app  (signed iOS app)
   Cyberpunk2077.app (arm64 Mach-O) ──┐      │
                                      │      ├─ host/Main.m        starts, reads env.json, telemetry
 phase8/tools/build.py               │      ├─ runtime/ loader    maps + links the game's Mach-O images
   packs images into signed dylib  ◄─┘      ├─ AppKit-on-UIKit    NSApplication/NSWindow/NSEvent
   "containers" + our runtime               ├─ Policy / Desktop   files, memory, sysctl, curl…
 phase8/tools/phone.py deploy  ─────USB────►├─ Metal pass-through  real iPhone GPU (AGX)
 push_resume.py (61 GB data)  ─────USB────► └─ Documents/Cyberpunk 2077/{archive,engine,r6}
```

## Step 1 — Packaging (on the Mac)

iOS will only execute code that is inside a signed bundle. `build.py` therefore takes the
game's own executable and dylibs and wraps each one, byte-for-byte, inside a signed dylib
"container" (in a `__TEXT,__guest` section). Our runtime, the host app and the app icon
(generated from the user's own install) are added, and the bundle is signed with the user's
free developer profile. → [../05-tools-and-diagnostics/build-tools.md](../05-tools-and-diagnostics/build-tools.md)

## Step 2 — Loading (on the phone, before `main`)

The host app starts and hands the guest images to machprobe's **group loader**:

1. **map** — reserve address space and place every segment where the image expects it;
2. **link** — apply chained fixups, resolve each import through export tries, to another guest image,
   an iOS system library, or one of machprobe's replacement symbols;
3. **start** — set up thread-local variables, register Objective-C classes and categories,
   run initializers in dependency order.

Cyberpunk runs more than 6,000 initializers before `main` (a crash in initializer
#6191 was one of the first bugs).
→ [../02-architecture/loader.md](../02-architecture/loader.md), [../02-architecture/tls.md](../02-architecture/tls.md)

## Step 3 — Pretending to be a Mac

The game now calls into "macOS". Most of Foundation, Metal, CoreFoundation and libc exist
on iOS too, so those calls go straight to the real thing. The rest is supplied by machprobe:

| The game asks for… | machprobe answers with… |
|---|---|
| `NSApplication`, `NSWindow`, `NSEvent`, `NSScreen` | AppKit classes built on UIKit, one fullscreen window |
| A Mac display and its modes | Aspect-correct iPhone pixel modes (e.g. 1564×720) |
| `/Users/<someone>/Library/...` paths | The app's own home folder |
| `archive/PC/content` (any letter case) | Case-insensitive path resolution |
| 64 GB address-space regions | Rationed placement inside iOS's ~64 GB window |
| `hw.memsize` | 3 GB, so the game sizes its GPU budget to fit iOS limits |
| libcurl network calls | An offline libcurl that answers "no network" cleanly |

→ [../02-architecture/appkit-on-uikit.md](../02-architecture/appkit-on-uikit.md), [../02-architecture/system-services.md](../02-architecture/system-services.md)

## Step 4 — Drawing

Metal on Mac and on iPhone is nearly the same API driving the same family of Apple GPUs.
machprobe passes the game's Metal objects straight to the real device. It only adds Mac-only
methods, turns `Managed` storage into `Shared`, and grows GPU heaps on demand, because iOS
counts a whole heap against the app's memory limit. → [../02-architecture/metal.md](../02-architecture/metal.md)

## Step 5 — Input

Touches and controller buttons are turned into the `NSEvent`s a Mac would produce
(mouse moves, clicks, key presses) and queued for the game, which pulls them with
`nextEventMatchingMask`. Game controllers use Apple's GameController framework
directly. → [../04-cyberpunk/input-and-controls.md](../04-cyberpunk/input-and-controls.md)

## Step 6 — Staying alive

iOS kills apps that use too much memory ("jetsam"). Telemetry lines (`[budget]`,
`[vmtags]`, `[perf]`) show fps, memory footprint, GPU allocation and thermal state, so
problems can be found from logs. → [../04-cyberpunk/memory.md](../04-cyberpunk/memory.md),
[../05-tools-and-diagnostics/telemetry.md](../05-tools-and-diagnostics/telemetry.md)
