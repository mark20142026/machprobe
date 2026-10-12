# Input and controls on the phone

How the user plays Cyberpunk 2077 on the iPhone: the touch overlay, mouse look,
the virtual stick, the iPhone keyboard, and game controllers. The game itself is
unchanged. Every control emits the same Mac key and mouse events a keyboard and
mouse would, through the shared input path in `phase5/runtime/Input.m`.

Sources: `phase8/runtime/CPControls.m` (the overlay), `phase8/runtime/CPAppKit.m`
(focus and pointer gates), `phase8/host/Main.m` (controller claiming, install
hooks), and `phase5/runtime/Input.m` and `phase5/runtime/Lifecycle.m` (shared event path).

## Layers

```
UIKit touches on the game window
  -> MPCPOverlay (CPControls.m): passes through everything except its own controls
       stick    -> key down/up for W A S D (mp_game_key)
       keys     -> key down/up (mp_game_key), modifier (mp_game_modifier), mouse (mp_game_pointer_here)
       look     -> relative mouse motion (mp_game_pointer_here, type 5)
       keyboard -> UIKeyInput -> key codes via code_for()
  -> everything else: the game's own touch path (Input.m), used for menu clicks and scrolls
GameController buttons -> GCController (claimed in Main.m, see below)
```

`MPCPPassthrough` returns `nil` from `hitTest` when the touch lands on the overlay
itself, so menus stay tappable underneath (`CPControls.m`).

## Touch overlay

The overlay is installed once the game's view is on screen (`mp_cp_install_controls`
in `CPControls.m`, polling every 0.5 s). It is always visible from the start: the
`install()` function does not hide the pad.

| Control | Place (landscape layout, from `layoutSubviews`) | Emits |
|---------|----------------------------------------------------------|-------|
| Left stick (140 pt) | Bottom-left | W A S D keys; dead zone 0.3; diagonals press two keys |
| SPACE (big) | Bottom-right | key 49 |
| LMB (big) | Right, above SPACE | left mouse down/up (`mp_game_pointer_here` 1/2) |
| RMB | Right, above LMB | right mouse down/up (3/4) |
| F, R, C | Bottom-right, left of SPACE | keys 3, 15, 8 |
| SHIFT | Left, above the stick | modifier flag Shift (1 << 17) |
| ESC, TAB | Top-left | keys 53, 48 |
| ENTER | Top-right, left of the buttons | key 36 |
| Gamepad-icon button | Top-right | shows or hides the whole pad |
| Keyboard-icon button | Top-right, left of that | toggles the iPhone keyboard |

Each key is a `MPCPKey` view that presses on touch-begin and releases on touch-end
or cancel. Multiple touches are enabled, so a player can hold a stick and press a
key at once.

## Mouse look

- `MPCPLook` covers the right 55 % of the screen (`x` from 0.45 x width). It is
  active only while the pad is shown: `poll()` sets `look.hidden = pad.hidden`.
  The comment in the code gives the reason: Cyberpunk always hides the system
  cursor, so the look area is only enabled when the player has asked for the pad.
- Each finger movement sends `mp_game_pointer_here(5, delta)` with the delta
  multiplied by 2.2 (points to mouse units). The 2.2 factor is a constant in
  `CPControls.m`, with no setting.
- Look is single-touch (`multipleTouchEnabled = NO` on the look view).

## Menus and the game's own touch path

When the overlay does not own a touch, `Input.m` turns it into a mouse event
(`e43a29b`, `e348889`):

- One finger moves the cursor and taps click on release.
- Dragging scrolls: drag becomes scroll-wheel lines (`MPKeyEvent` reports
  `hasPreciseScrollingDeltas = NO`, `CPAppKit.m`).
- Two-finger tap sends right-click; two-finger drag scrolls.
- `mp_game_appkit_points` makes positions AppKit bottom-left, as the game expects.
- Before every touch-begin, `mp_game_touch_began` re-asserts the pointer gates
  (`cursorInView`, `m_windowFocus`, `+[GameWindow isWindowVisible]`) so the game does
  not ignore the pointer (`a9bb2bc`; see `bug-log.md` row 10).

## iPhone keyboard

> **Untested and not useful in practice.** The ⌨️ button exists in the code but was never verified
> in play; it is planned for removal in the touch-controls rebuild.

- The keyboard icon makes `MPCPTyping` (a `UIKeyInput`) first responder.
- `insertText:` maps each character to a Mac ANSI key code through a table in
  `code_for()` (letters, digits, space, return, tab). Characters with no code are dropped.
- `deleteBackward` sends key 51 (Delete).

## Game controllers

- Xbox-style controller: confirmed working (CONTEXT, 9 Oct) through the GameController
  framework. Buttons reach the game without the touch overlay.
- `Info.plist` declares `GCSupportedGameControllers` as `ExtendedGamepad`
  (`phase8/tools/build.py`). Other pads (MFi, PlayStation) are expected to work the
  same way; they are not recorded as tested.
- iOS takes Menu, Options and Home presses for system gestures (Games overlay,
  search) unless the app opts out. `claim_buttons()` in `phase8/host/Main.m` sets
  `preferredSystemGestureState` to disabled on every button of every connected
  controller, and again on each connect notification (`04c412a`, bug 17).

## Pointer gates (why the game ignored the phone at first)

The game drops mouse moves unless three state gates are set. Each is set and
re-asserted in `phase8/runtime/CPAppKit.m`:

1. `GameWindowController.m_windowFocus`, set by `windowDidBecomeKey:`.
2. `+[GameWindow isWindowVisible]`, a static flag that the game sets when its window
   occlusion changes. On iOS the window counts as visible whenever the app is active.
3. `GameView.cursorInView`.

Diagnostics: `MP_CURSOR_TRACE` prints `[cursor]` lines (mouse location,
`isWindowActive`, game position) and `[focus]` lines (`m_windowFocus` values).

## Known problems

- The touch pad is a quick version and the user considers it bad (CONTEXT, 10 Oct).
  The planned rebuild (below) names what is missing: an analog stick that floats under
  the thumb, a bigger button layout, and a sensitivity setting for look. The current
  stick is digital (WASD only), and look exists only while the pad is shown.
- Look sensitivity is one constant (2.2); there is no in-game control for it.
- The stick sends WASD keys, so the game sees a full press, not an analog value.
- Look and the pad are coupled: with the pad hidden there is no look.
- Cursor gates are re-asserted on each touch, which is a workaround. The game's own
  focus model is not understood in full.
- A Bluetooth keyboard or controller is described in `CPControls.m` as "the better
  way to play". Bluetooth keyboards are not recorded as tested with Cyberpunk.

## Planned rebuild (CONTEXT, plan of 10 Oct)

1. Floating left stick: appears under the thumb, analog walk and run by deflection.
2. Bigger, mobile-shooter button layout.
3. Right-side look area with adjustable sensitivity.

The rebuild replaces `phase8/runtime/CPControls.m`. The interface between the overlay
and the shared input path (`mp_game_key`, `mp_game_modifier`, `mp_game_pointer_here`,
`mp_game_touch_began`) stays as it is.

## Test hooks (no touch needed)

- `MP_AUTOPRESS="15:49,30:36"`: press key 49 at 15 s and key 36 at 30 s after launch.
- `MP_AUTOTAP="20:437,300,30:437,120"`: tap view point (437, 300) at 20 s and (437, 120) at 30 s.
- These run through the same path as real touches (`mp_game_touch_began`, then move,
  press, release). Both are read from the environment in `phase8/runtime/CPControls.m`.
