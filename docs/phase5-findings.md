# Phase 5 findings — Strataris

Status: stopped at the user's request on 1 October 2026 after visible gameplay,
movement and firing. This is a VM research milestone, not full certification of
all original Phase 5 requirements. No Phase 5.5 work has started.

## Preserved target

VERIFIED: official Strataris v1.0.1, release published 25 August 2026.
Release metadata: https://github.com/PerpetualBeta/Strataris/releases/tag/v1.0.1
Download: https://github.com/PerpetualBeta/Strataris/releases/download/v1.0.1/Strataris.zip
Original is `build/phase5/original/extracted/Strataris.app`; archive also preserved.
No implementation source was inspected or compiled. Binary disassembly, symbols,
Objective-C metadata, bundle metadata and resource inventory informed the adapters.

Original universal executable SHA-256:
`de87d9b9b61e4969ecc634803174e2dcd3007c5d9762c928992634ab1f913e61`

Exact ARM64 slice SHA-256:
`d31b5cacaba1948a3d0da03f34a5b9a6dcf222ca6deddcbd1305c28e92fda5d2`

VERIFIED: ARM64 slice starts at 1015808, length 951360; macOS target, minimum
macOS 14.0, SDK 26.5. Original signature verification and stapled notarization
validation passed. Six Mach-O executables are inventoried, including Sparkle
and its helpers. See `evidence/phase5/target.json`, `machos.json`, signature and
notarization outputs. The original .app and main executable remain unchanged.

## What the first real game taught the runtime

Chronological evidence is in numbered files under `evidence/phase5/`.

1. Existing runtime rejected compiled metadata, then chained fixups. Reused the
   explicit Phase 4 metadata registration policy; added opt-in chained fixups.
2. Implemented bounded `DYLD_CHAINED_PTR_64_OFFSET` with ordinary imports,
   rebases and weak imports. Tagged high8 pointers required a second correction.
   Apple SDK `mach-o/fixup-chains.h` documents the encoding. Synthetic positive
   and malformed streams pass ASan/UBSan. Other formats remain unsupported.
3. Resolved actual additional framework imports. macOS AppKit string and font
   weight constants were measured against native AppKit, not guessed.
4. Guest `_main` reached `NSApplication.setDelegate:` and failed. Added an
   application adapter: guest NSApplication.run enters UIKit; scene creation
   delivers AppKit launch notifications to the guest's original delegate.
5. Guest constructed NSMenu/NSMenuItem objects. A generic menu model maps these
   to UIMenu actions targeting the original guest selectors.
6. Sparkle's controller initializer was required during startup. Desktop
   self-updating is explicitly unavailable in this container. The capability
   adapter declines automatic updating; it does not execute Sparkle or claim
   update support. Original bundled Sparkle is preserved separately.
7. Added generic window properties, first-responder tracking and content
   presentation. The guest creates its own compiled MTKView subclass and renderer.
8. Metal rejected storageMode=1 (macOS Managed). The device adapter translates
   this to Shared only on unified-memory devices, on a copied descriptor.
   Actual textures, command queues and GPU operations remain native Metal.
   A standalone test verifies CPU upload → GPU blit → exact readback bytes,
   unchanged guest descriptor, and unchanged Private allocation semantics.
9. The actual title screen appeared. Host virtual-key input called the original
   guest keyDown:/keyUp: methods. B displayed its briefing; Enter started gameplay.
10. Gameplay queried macOS mouseLocationOutsideOfEventStream on the physical
    UIWindow. Added a touch-position adapter and cursor request accounting.
    Enter then opened the cockpit successfully. Arrow input changed the scene;
    Space produced visible firing beams. The user also verified gameplay.
11. K opens a desktop keyboard-configuration sheet. Labels/buttons/stack views
    exposed more AppKit requirements. Preliminary generic control mappings were
    added, but the path still fails because the physical UIWindow lacks the
    AppKit sheet API. At the user's request the host K shortcut was removed and
    this optional UI work stopped. Original game/menu/physical-key routes to
    unsupported sheets have not been disabled or patched.

## Actual path

```text
Original ARM64 macOS executable bytes, embedded in a separately signed iOS dylib
  → resident guest loader, chained fixups, host import resolution
  → Objective-C/Swift metadata registration (existing version-sensitive SPIs)
  → original main / AppDelegate / GameView / Renderer
  → AppKit lifecycle/window/menu/event adapters
  → UIKit physical scene + native MTKView
  → guest Metal calls → device adapter for Managed textures → iOS Metal GPU

Host touch on virtual keys / UIKit physical keyboard
  → Mac virtual-key event → guest keyDown:/keyUp: → original game state/rendering
```

VERIFIED: 3957 rebases and 686 binds in successful runs. Guest slice hash is
checked before fixups for each launch. Runtime fixups modify resident writable
DATA as a loader normally does; original executable bytes and executable TEXT
are not patched. The separate iOS container/host are ad-hoc signed locally, then
installed using the VM's existing custom-trust installer. The .icns desktop icon
is omitted from the generated host package, retained in the original .app.

VERIFIED: the host does not contain a replacement game renderer or recreate the
game's cockpit/menu textures. Metal performs the guest's actual presentation.
No remote frames or macOS rendering process supply the iOS display.
UNTESTED: exact division of the game's own CPU and GPU rendering work.

## Limits at the user-requested stop

- VERIFIED: visible title, briefing, cockpit, moving scene, firing and continued
  game state changes. See `16-first-screen.png`, `18-briefing.png`,
  `20-gameplay.png`, `21-movement-fire.png`, associated runtime JSON and user report.
- VERIFIED: an observed title-screen sample measured 326 guest draw callbacks in
  5.82 seconds (~55.8 callbacks/sec), mean guest callback 11.3 ms. This is a short
  title-screen sample, not a sustained gameplay or physical-iPhone benchmark.
- VERIFIED: instrumented AVAudioEngine startup returned -10851 at output-node
  initialization. No mixed frames were observed. Audio is not verified working;
  its underlying cause and whether observation changes behavior remain untested.
- UNTESTED: long-session stability, configuration/save persistence, full keyboard
  sheet support, complete controller input, physical pointer styling, general
  AppKit flipped coordinates, ordinary-device deployment.
- VERIFIED: SDK headers expose platform differences; observed same-CPU execution
  is not evidence of general binary compatibility.
- VERIFIED: existing VM installer adds custom trust. Normal sandbox/signing
  independence is NOT established. No root services are called by the runtime,
  but that alone does not meet the original ordinary-sandbox proof requirement.
  No security settings were changed during Phase 5.
- UNTESTED: replacements declared only for linkage are not functional framework
  implementations. Unsupported messages still fail visibly rather than return
  fake success. Optional desktop dialogs remain incomplete.

## Tests

Baseline: 70 existing test methods passed before additions. After chained-fixup
changes, Phase 2 normal/sanitizer regressions passed, followed by the eight Phase 3
methods (including synthetic fixups under ASan/UBSan). Two new Phase 5 tests pass:
original/slice integrity and a real GPU texture translation/readback test under
ASan/UBSan. Full final Phase 1–4.5 regression rerun was not completed before the
user requested stopping. These results must not be presented as a fully certified
Phase 5 completion.
