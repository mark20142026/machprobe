# Privacy

## What machprobe collects: nothing

- **No analytics, no telemetry upload, no accounts, no servers.** machprobe's source contains no
  networking code. (Checked: no `NSURLSession`, sockets, `getaddrinfo` or URLs in the loader,
  runtime or host sources.)
- The game's own online features are answered by an **offline libcurl replacement**, so the
  game's HTTP requests made through libcurl don't leave the phone.
- **Telemetry stays local.** `[budget]`, `[vmtags]`, `[perf]` lines and crash reports are written
  to the app's own folder on the phone. You pull them to your Mac over USB yourself, if you want.

## What stays on your devices

| Data | Where | Who can see it |
|---|---|---|
| Game files (61 GB) | Your Mac's Steam folder and the app's folder on your phone | You |
| Saves, settings, EULA acceptance | The app's `Library/Application Support/CD Projekt Red/…` folder | You |
| Logs and crash reports | The app's `Documents`/log folders | You (via USB) |
| Signing identity and profile | Your Mac's keychain and Xcode folders | You and Apple (normal developer signing) |

## Apple

Creating a free developer profile signs you in to Apple through Xcode. Apple sees your Apple ID,
your device's identifier (for the profile) and the App ID you register, as for any developer.

## Planned Steam sign-in

The planned in-app Steam download would use **Steam's QR-code login**: you approve the login in
the Steam app on another device, and machprobe never sees your password. Download traffic would
go only to Valve's servers. This feature doesn't exist yet; this section will be updated when it does.

## If you publish logs or bug reports

Logs can contain your device name, file paths with your Mac username, and your App ID / team ID.
Before posting logs publicly, replace:

| Value | Replace with |
|---|---|
| Device UDID | `<DEVICE-UDID>` |
| Apple team ID | `<TEAM-ID>` |
| Signing identity hash | `<SIGNING-IDENTITY-SHA1>` |
| `/Users/<your name>` | `~` |
| Email addresses, device names | remove |

Never post API tokens, provisioning profiles or certificates.
