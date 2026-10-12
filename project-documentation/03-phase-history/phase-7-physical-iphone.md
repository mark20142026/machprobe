# Phase 7: SuperTuxKart on a physical iPhone 18 Pro

Dates: 2026-10-09. Commits `cdcbf0c` (first device run), `0fe687f` (touch pad
shown only on request), `5f24c6f` (status record in `progress.md`). Sources:
`progress.md` (the "Phase 7" section), `CONTEXT.md`, the commit messages, and
`phase7/`. There is no separate findings document for this phase. Device
identifiers are replaced with placeholders below.

## Goal

Take the Phase 6 package, which ran in the research VM, and run the unchanged
SuperTuxKart 1.5 on the user's own iPhone. The point was to see whether
behaviour seen in the VM, including the VM-only GPU defect, also holds on real
hardware, and whether a development-signed package could run without the VM's
custom trust.

## Device and account

- Device: iPhone 18 Pro (`iPhone19,2`), iOS 27.0.1, Developer Mode on.
  Identifier: `<DEVICE-UDID>`. The GPU is reported as Apple A20 Pro with a
  working-set limit of about 8 GB, BC textures supported.
- Signing: a free Apple development team, with one App ID for all builds,
  `research.machprobe.STKHost`. Team and identity values are `<TEAM-ID>` and
  `<SIGNING-IDENTITY-SHA1>`.
- The free account allows a limited number of App IDs per week. The phase
  notes say never to create another App ID for this app.
- The provisioning profile was recorded as expiring on 2026-10-16. Refresh
  rule: rebuild `phase7/signing/Provisioner.xcodeproj` with the same bundle ID.

## What was built

| Path | Contents |
|---|---|
| `phase7/tools/device.py` | USB helper over `xcrun devicectl`. Commands: `deploy`, `launch`, `report`, `logs`, `args`. Deploy runs the Phase 6 build, copies the package, signs it with the development identity and the single profile, then installs. Data is pushed once with `devicectl device copy to`. |
| `phase7/signing/Provisioner.xcodeproj`, `Provisioner/main.m`, `Info.plist`, `Provisioner.entitlements` | A minimal Xcode project. Building it with the same bundle ID makes Xcode create or refresh the development profile. Link errors are expected; only the profile matters. |
| `phase5_5/runtime/LegacyMetal.m` (changed) | Answers the macOS-only `MTLDevice` queries that MoltenVK asks for, which the A20 GPU does not support. Built-in Apple GPU values are returned. |
| `phase6/runtime/GameControls.m` (added) | A multitouch gamepad over the guest: a joystick mapped to arrow keys, and buttons for Fire, Nitro, Drift, Look back, Rescue and Pause. |

## How it was done

1. Built the Phase 6 package unchanged, then signed it with the development
   certificate and one profile. Installed over USB (`cdcbf0c`).
2. Launched and read the report and logs with `device.py`.
3. Answered the macOS-only `MTLDevice` queries that MoltenVK made on the
   phone, through the device shim in `LegacyMetal.m`.
4. Added the touch gamepad, then made it hidden by default after finding it
   covered the menus (`0fe687f`).
5. Recorded the status in `progress.md` (`5f24c6f`).

## Problems and bugs

| Symptom | How it was found | Root cause | Fix | Commit |
|---|---|---|---|---|
| MoltenVK asked the device for macOS-only `MTLDevice` queries (for example `isDepth24Stencil8PixelFormatSupported`), which the A20 GPU does not support | Device run; the commit message describes the fix, and the discovery method is not recorded | The phone's GPU is an iOS GPU. Those queries exist only on macOS. | Device shim in `LegacyMetal.m` answers them for a built-in Apple GPU. | `cdcbf0c` |
| Touch gamepad covered the menus | Not recorded (the commit message gives the symptom and fix) | The pad was always on. | Pad starts hidden. The gamepad button (🎮) shows it. | `0fe687f` |
| Cursor state could not tell menus from races | Not recorded | SuperTuxKart does not hide the pointer in races, so cursor state cannot signal gameplay. | Cursor-hidden state is reported in input stats, but the pad is toggled by hand, not by cursor state. | `0fe687f` |

The VM-only `baseVertex` defect from Phase 6 was **not** present on the phone.
The commit message says so directly. This means the workaround in
`phase5_5/runtime/BaseVertex.m` is detected at startup and does not trigger on
the device.

## Results / evidence

- SuperTuxKart 1.5 ran on the iPhone 18 Pro at 60 fps, with the touch gamepad
  available during races (`progress.md`, Phase 7 section).
- Real-device findings recorded in `progress.md`: signed containers install and
  run; only macOS-only `MTLDevice` queries needed answering; the VM baseVertex
  defect is absent.
- The data push was done once with `devicectl`. The phase notes do not record a
  timing for it.

Not established in this phase: audio on the phone, controller input, and any
measurement beyond the 60 fps figure. The repository does not record a
thermal or memory profile for this phase.

## What it unlocked next

- A working route from the research VM to a physical device. Phase 8 reused the
  same device tooling, with a new bundle ID (`phone.py` imports
  `phase7/tools/device.py`).
- The device shim sits in the shared `LegacyMetal.m` runtime. The touch pad
  (`GameControls.m`) is specific to SuperTuxKart. Phase 8 wrote its own touch
  controls in `phase8/runtime/CPControls.m`.
- Known problems that carried forward:
  - Every build used one App ID. `CONTEXT.md` later records that another
    project's install replaced the `STKHost` app and its data container. The
    Cyberpunk port therefore got its own App ID (`research.machprobe.CP2077`,
    commit `5e022eb`). See `../04-cyberpunk/` for that work.
  - The profile had to be refreshed before it expired.
- Phase 7 was the first phase whose result was measured on the user's own
  device rather than in the research VM.
