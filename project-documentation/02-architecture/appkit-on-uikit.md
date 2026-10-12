# AppKit on UIKit

macOS games talk to AppKit (`NSApplication`, `NSWindow`, `NSEvent`, `NSScreen`,
`NSView`, ...) and a ring of desktop frameworks. iOS has none of that. The layer
provides **stand-in classes** backed by UIKit and binds the game's AppKit class
imports to them. It is not a general AppKit: each stand-in implements what real
games were observed to call, and answers the rest honestly or loudly.

Files, in the order they were added:

| Directory | Files | Added for |
|---|---|---|
| `phase5/runtime/` | `AppKitCompat.m`, `Lifecycle.m`, `Window.m`, `Input.m`, `Menu.m`, `Controls.m` | First AppKit guests (DashboardCalculator, Strataris, Veloren) |
| `phase5_5/runtime/` | `Display.m`, `Keyboard.m`, `Constants.m` | CoreGraphics display model, Carbon keyboard layout, measured AppKit constants |
| `phase6/runtime/` | `AppKitExtras.m`, `Desktop.m`, `GameControls.m`, `Survey.m`, `Watchdog.m` | SuperTuxKart (SDL2 Cocoa backend) |
| `phase8/runtime/` | `CPAppKit.m`, `CPControls.m` | Cyberpunk 2077 |

## Binding the game to the stand-ins

`mp_game_appkit_symbol` (`phase5/runtime/AppKitCompat.m`) is the AppKit resolver
that `mp_resolve` consults. Examples: `_OBJC_CLASS_$_NSApplication` ->
`MPGameApplication`, `NSWindow` -> `MPGameWindow`, `NSEvent` -> `MPKeyEvent`,
`NSScreen` -> `MPGameScreen`, `NSCursor`, `NSMenu`, `NSMenuItem`,
`NSRunningApplication`; `NSView`, `NSButton`, `NSTextField` come from
`mp_game_control_class` (`Controls.m`). A class that is merely *declared* by the
import list becomes a placeholder `MPDeclared<Name>` that raises on every
message, so a missing feature fails visibly instead of "working" silently.
Extra classes for SDL/Cyberpunk (`NSTrackingArea`, `NSWindowController`,
`NSWorkspace`, `NSGraphicsContext`, `NSColorSpace`, `NSOpenGLContext`) come from
`mp_stk_appkit_class` (`phase6/runtime/AppKitExtras.m`). `NSImage` maps to
`MPCompatImage` (`phase4/runtime/ImageShim.m`). `objc_getClass` is routed through
`mp_guest_get_class` (`phase5_5/runtime/ObjCRuntime.m`) so games that look up
classes by name get the same mapping.

### Key functions

| Function / class | File | What it does |
|---|---|---|
| `mp_game_appkit_symbol` | `phase5/runtime/AppKitCompat.m` | Import map: AppKit class, constant and weight symbols to stand-ins. |
| `MPGameApplication` (`+sharedApplication`, `-run`, `-finishLaunching`, `-sendEvent:`, `-nextEventMatchingMask:untilDate:inMode:dequeue:`) | `phase5/runtime/Lifecycle.m` | NSApplication: launch notifications, event pump, activation. |
| `mp_game_post`, `take()` | `phase5/runtime/Lifecycle.m` | Event queue with AppKit-style mouse coalescing. |
| `mp_game_run_uikit` | `phase5/runtime/Lifecycle.m` | `UIApplicationMain` with the scene delegate that builds the host window. |
| `MPGameWindow` | `phase5/runtime/Window.m` | NSWindow: frame == content rect, presents `contentView` inside the UIKit host view, sheets, fullscreen notifications. |
| `mp_game_key_window` | `phase5/runtime/Window.m` | Key window, falling back to the first window. |
| `MPPhysicalWindow -sendEvent:` | `phase5/runtime/Input.m` | Turns `UITouch` into NSEvent-like pointer events. |
| `mp_game_dispatch_event` | `phase5/runtime/Input.m` | Routes an event to a responder (first responder, chain, fallback view). |
| `mp_game_key`, `mp_game_modifier`, `mp_mac_keycode` | `phase5/runtime/Input.m` | Hardware keys (USB HID usage) to Mac virtual key codes; modifiers as `flagsChanged`. |
| `mp_game_pointer`, `mp_game_pointer_here`, `mp_game_pointer_to`, `mp_game_scroll` | `phase5/runtime/Input.m` | Absolute, cursor-relative, finger-to-cursor and scroll-wheel events. |
| `mp_display_set_modes`, `mp_display_symbol` | `phase5_5/runtime/Display.m` | CoreGraphics display/mode API on the single iOS screen. |
| `MPZero`, `install_safety_net` | `phase8/runtime/CPAppKit.m` | Unimplemented-selector safety net. |
| `mp_cp_refocus`, `mp_game_touch_began` | `phase8/runtime/CPAppKit.m` | Re-assert the game's focus/visibility/cursor gates. |

## Lifecycle: UIKit first, guest later

1. `main` of the host calls `mp_game_run_uikit` (`UIApplicationMain`).
2. The scene delegate (`MPGameScene` in `Lifecycle.m`) creates `MPPhysicalWindow`
   with an `MPInputController`, attaches the presentation surface, and disables
   the idle timer.
3. If the host installed a **launch hook** (`mp_game_set_launch_hook`; Phase 8 uses it to
   call `mp_image_main`), it is scheduled with a zero-delay `NSTimer`. Otherwise
   the stand-in `NSApplication` calls the delegate's
   `applicationWillFinishLaunching:` / `applicationDidFinishLaunching:`.
4. If the guest then calls `-[NSApp run]` it never returns (AppKit semantics): the
   stand-in just keeps servicing the main run loop.

Design decisions:

- **Timer, not a main-queue block.** The main dispatch queue is serial; a guest
  loop running inside a main-queue block would starve every later
  `dispatch_async(main)`, and SDL waits on exactly those (`Lifecycle.m` comment;
  SDL's own iOS backend does the same). Found in Phase 6.
- **`NSApp` is nil until the first `+sharedApplication`.** A statically
  compiled subclass (`SDLApplication`) must become the shared instance with its
  overrides; `sharedApplication` uses the first receiver's class, as AppKit does.
- **No menu bar.** `MPGameMenu` is kept so the guest can read it back;
  `-hostMenu` converts it to a `UIMenu` behind a small "Menu" button. `menuBarVisible`
  is always NO.

## Windows

`MPGameWindow` has no title bar or border: `contentRectForFrameRect:` returns
the frame unchanged, `setFrame:display:` resizes the content view and posts
`NSWindowDidResizeNotification`. `makeKeyAndOrderFront:` adds the content view to the
UIKit host view, sets it key, and posts `NSWindowDidBecomeKeyNotification`.
Additional behaviour in `AppKitExtras.m` / `CPAppKit.m`:

- **Delegate auto-subscription.** AppKit subscribes a window's delegate to the
  notifications whose delegate methods it implements. `setDelegate:` is swizzled
  to do the same. SDL learns keyboard focus from `windowDidBecomeKey:`; without this
  the SuperTuxKart window never got keys (commit `c74c865`).
- **Separate AppKit responder chain.** `setNextResponder:` stores an unretained
  pointer in an associated object (`mp_appKitNextResponder`) so UIKit's own
  `nextResponder` and touch delivery are untouched.
- **View layer hosting.** An AppKit view may adopt any layer; a `UIView`'s backing
  layer is fixed. `-[UIView setLayer:]` makes the adopted layer (Cyberpunk's
  `CAMetalLayer`) a full-size sublayer, kept sized by a swizzled
  `layoutSublayersOfLayer:`. `wantsLayer` is always YES.
- **Screen.** `MPGameScreen` reports EDR headroom 1 (SDR) by default. A headroom
  above 1 makes the game render and present HDR (wider formats, more bandwidth),
  costly on a phone; `MP_HDR=1` reports the real panel headroom.
- **Safety net.** Messages the stand-ins lack are forwarded (via
  `forwardingTargetForSelector:`) to `MPZero`, which answers every selector with 0
  in `x0`/`d0`-`d3` (ids, integers, BOOL, CGFloat, CGPoint/Size/Rect) and logs
  `[appkit] unimplemented -[Class sel] -> 0` once per (class, selector) through a
  lock-free hash. `respondsToSelector:` stays truthful so the game's own feature
  checks are unaffected. Each log line is a method to implement; the survey mode
  (`phase6/runtime/Survey.m`, `MP_SEL_SURVEY` in the Phase 8 host) lists missing
  selectors in one pass. The hash replaced a string+lock+set per call in `25bef28`
  so selectors sent every frame cost a few loads.

## Event queue and coalescing

Two delivery modes (`mp_game_queue_events` in `Lifecycle.m`):

- **Direct (default, SDL):** `mp_game_post` calls `-sendEvent:` immediately.
- **Queued (Cyberpunk, `mp_game_queue_events = YES` in `phase8/host/Main.m`):** the
  game drains the AppKit queue itself with `nextEventMatchingMask:untilDate:inMode:dequeue:`
  and calls `-sendEvent:` per event. Events wait in a queue (cap 512) and
  `CFRunLoopWakeUp` wakes the main loop.

Design decisions:

- **Mouse coalescing.** A move (5), left drag (6), right drag (7) or scroll (22)
  directly after one of the same type is merged into it (latest position, summed
  deltas), as AppKit does. Otherwise a 120 Hz touch stream piles up behind a
  30 fps game loop (commit `e43a29b`).
- **Polling drains all ready sources.** With `wait == 0` in queued mode,
  `CFRunLoopRunInMode(..., returnAfterSourceHandled = NO)` services every ready
  source, so all pending touches reach the queue within one frame instead of
  one per call.
- **`mp_watchdog_beat()`** (weak symbol; `phase6/runtime/Watchdog.m` overrides) is
  called from `nextEventMatchingMask:`; if the guest stops pumping events the
  watchdog captures the main thread's stack.

## Key window and first-responder fallbacks

Cyberpunk shows its window through `NSWindowController` and never asks to become
key, and its `GameView` becomes first responder only from a key-window callback.
Without help the game ignores all input. The layer handles it in three places:

1. `mp_game_key_window` returns the key window **or the first guest window**
   (`windows.allObjects.firstObject`).
2. `mp_game_dispatch_event` follows AppKit's order (first responder, else the window,
   then local monitors from `+addLocalMonitorForEventsMatchingMask:`, then the AppKit
   responder chain up to 8 links); if nothing in the chain responds, it searches the
   key window's views breadth-first for the first view that accepts first responder,
   implements the selector and is not a `UIControl`, makes it first responder for
   key events, and delivers there.
3. `mp_cp_refocus` (`CPAppKit.m`) re-sends `windowDidBecomeKey:` to every
   window controller the game created (tracked by wrapping `MPWindowController`'s
   `initWithWindow:`) or that is reachable from `GameView.m_windowController`, posts
   `NSApplicationDidBecomeActiveNotification`, and forces
   `+[GameWindow isWindowVisible]` to YES. `mp_game_touch_began` repeats the
   check **on every touch start**, also setting `GameView.cursorInView`. The game
   re-creates or resets these gates at times and drops `mouseMoved:` while any is off
   (commits `e348889`, `a9bb2bc`).

## Touch, keyboard and pointer model

- **Trackpad-style touch** (`mp_game_touch_scroll = YES` for Cyberpunk): one finger
  moves the cursor, a tap clicks on release (movement over 8 pt cancels the click),
  two fingers scroll, a two-finger tap right-clicks. Scrolling converts finger
  travel to wheel lines at 6 pt per line with carried remainders, because the
  game scales precise deltas far down.
- **Relative mode.** When the guest detaches the cursor
  (`CGAssociateMouseAndMouseCursorPosition(false)`, mapped to
  `mp_game_associate_mouse`), `mp_game_pointer_to` sends exactly the delta that
  puts the guest's own cursor under the finger. `CGWarpMouseCursorPosition`
  moves only the virtual cursor; the user's host pointer is never warped.
- **Buttons and look pads** (`CPControls.m`) have no screen position of their own;
  they use `mp_game_pointer_here`, which acts at the current cursor. Using (0,0)
  teleported the cursor once the game re-associated the mouse (`a9bb2bc`).
- **Keyboard.** `UIPress` -> `mp_mac_keycode(HID usage)` -> `mp_game_key`;
  modifiers become `flagsChanged` (type 12) events carrying the new state;
  `isARepeat` is derived from a held set. A touch overlay (`CPControls.m`,
  `GameControls.m`) emits the same Mac key/mouse events, so the game is unchanged;
  Bluetooth keyboards and `GameController` pads work directly.

## Coordinates

Three spaces meet here: UIKit (origin top-left), AppKit window/view (origin
bottom-left unless the view's `isFlipped` is YES), and AppKit screen
(bottom-left).

- `mp_game_point_for_view` flips Y for views that do **not** declare `isFlipped`,
  and leaves flipped views alone (so a flipped view is never inverted twice).
- `mp_game_appkit_points` (YES for Cyberpunk) makes `locationInWindow` use the
  AppKit bottom-left convention, because Cyberpunk's `GameView` computes
  `height - y` itself and otherwise reads an inverted pointer.
- `+[MPKeyEvent mouseLocation]` returns screen coordinates as
  `(x, screenHeight - y)`.
- Window geometry: frame and content coincide, so `convertPointToScreen:` is just
  an origin offset.
- Known gap, stated in `Input.m`: full AppKit flipped-view mapping for arbitrary
  nested views is not implemented; the exact composition for `MTKView` is the
  UIKit convention.

## Display modes (`phase5_5/runtime/Display.m`, `phase6/runtime/Desktop.m`)

Games enumerate CoreGraphics display modes and pick a resolution. The layer models
**one display** (ID 1) built from `UIScreen`:

- By default there is a single mode, the current UIKit mode in pixels.
- A host may call `mp_display_set_modes(sizes, n)` to list 1x render modes at the
  panel's aspect ratio, first = current. `CGDisplayModeGetWidth/Height` then
  report logical size equal to pixel size, so the guest renders exactly that many
  pixels and the compositor scales to the panel.
- `phase8/host/Main.m` lists heights 900, 1080, 804, 720 and 603 with
  `width = round(h * aspect) & ~1`, then the native panel size. The panel was
  2622x1206 on the iPhone 18 Pro (code comment), so 900p is 1956x900.

Why (commit `3455929`): before this, the game ran at 874x402 points with 50-65 percent
dynamic resolution scaling. Pixel-exact, aspect-correct modes let the game render
natively at 1956x900 (later tuned to 1564x720 by the user; see
[../04-cyberpunk/](../04-cyberpunk/)) with `ResolutionScaling` off. Operations
iOS cannot do (mode switching, display capture, gamma, fades) fail with the
framework's own error codes, never silent success.

See also [system-services.md](system-services.md) (CoreGraphics/IOKit stubs),
[metal.md](metal.md) (what the presentation layer renders into) and
[../03-phase-history/](../03-phase-history/).
