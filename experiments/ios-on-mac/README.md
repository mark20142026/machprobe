# HelloIOS: iOS app on Mac experiment

This is a minimal UIKit app intended to test Apple Silicon Mac execution paths. It displays “Hello from iOS ARM64” and whether `NSProcessInfo.isiOSAppOnMac` is true.

The Xcode project targets iOS 14 and device families iPhone and iPad. Its build settings enable Designed for iPhone/iPad apps on Mac and disable Mac Catalyst. A normal Xcode build should produce an iOS device binary (`platform=2`), not a Catalyst (`platform=6`) or Simulator (`platform=7`) binary. This host has Command Line Tools but no full Xcode installation or iPhoneOS SDK, so that normal build route could not be used here.

## Observed experiment

The app was also compiled using the macOS 27 Foundation and CoreGraphics headers, a small hand-written UIKit declaration surface, and minimal text stubs for iOS libraries. The resulting thin arm64 executable is marked `LC_BUILD_VERSION platform IOS` (2), minimum iOS 14.0, SDK 0.0.0, and has `cryptid=0`. Its ad-hoc app signature passes `codesign --verify --strict`. The zero SDK value and minimal UIKit surface mean this is a narrow experiment, not a complete iOS SDK build.

The original platform-2 app was refused by macOS when launched directly (`open -n` returned “incorrect executable format”). A separate copy whose build-version command was converted to Mac Catalyst (platform 6) opened successfully. The parent task reported that visual and accessibility inspection found both labels, with `iOS app on Mac: NO`. This is evidence that the converted Catalyst app opened; it does **not** show a native iOS-on-Mac launch or prove that macOS can execute an iOS binary directly.

PlayCover was researched but not installed or run. Its installer converts app Mach-O build-version commands to Mac Catalyst before re-signing, so it would not preserve the platform-2 executable for this test. The source inspected was pinned at commit [`8235158caca3232dcf526ad6ae9881707bd08728`](https://github.com/PlayCover/PlayCover/tree/8235158caca3232dcf526ad6ae9881707bd08728). In that revision, [`Installer.install`](https://github.com/PlayCover/PlayCover/blob/8235158caca3232dcf526ad6ae9881707bd08728/PlayCover/AppInstaller/Installer.swift#L48) drives installation; [`Macho.replaceVersionCommand`](https://github.com/PlayCover/PlayCover/blob/8235158caca3232dcf526ad6ae9881707bd08728/PlayCover/Utils/Macho.swift#L132) writes `PLATFORM_MACCATALYST`, and PlayTools injection is optional ([`PlayTools.installInIPA`](https://github.com/PlayCover/PlayCover/blob/8235158caca3232dcf526ad6ae9881707bd08728/PlayCover/Utils/PlayTools.swift#L76)). PlayCover’s documentation describes SIP and AMFI changes for certain game login/signing scenarios; those steps were not performed and are not established as requirements for this tiny app ([official troubleshooting guide](https://docs.playcover.io/getting_started/troubleshoot_login)).

## Build and run in Xcode

1. Open `HelloIOS.xcodeproj` in Xcode.
2. Select the shared `HelloIOS` scheme and the **My Mac (Designed for iPad)** destination.
3. If Xcode requires signing, choose your own development team in the target’s Signing & Capabilities settings.
4. Build and run. The app should show the greeting and the runtime’s iOS-on-Mac value.

The project has no external dependencies, assets, or storyboards. It uses an application delegate and creates its window and views in code. The experimental stub-based compile files and generated IPA are separate from the Xcode project.

## Command line

From this directory, the intended build command is:

```sh
xcodebuild -project HelloIOS.xcodeproj -scheme HelloIOS -configuration Debug \
  -destination 'platform=macOS,variant=Designed for [iPad,iPhone]' build
```

This destination must be available in Xcode. Do not substitute a Mac Catalyst or iOS Simulator destination: those do not test the intended app-on-Mac path. The preflight and observed results are recorded in `status.json`. The next section documents the measured alternative route.

## Reproduce the measured experiment

From the repository root:

```sh
make all
python3 experiments/ios-on-mac/build_experiment.py --launch
```

Omit `--launch` to build and compare without opening windows. The script writes the original IPA to `build/ios-on-mac/HelloIOS.ipa`, adapts a copy as `build/ios-on-mac/HelloIOS-Catalyst.app`, and writes command/metadata/hash evidence to `docs/evidence/ios-on-mac.json`. It asserts platform 2 versus 6, preservation of the original hash, and identical `__TEXT,__text` instruction bytes. Successful `open` alone is not treated as a rendered UI result: `docs/evidence/ui-observation.json` records the separate visual/accessibility check. The converted SDK/minimum-version fields deliberately match the values observed in PlayCover’s conversion code; they do not represent a build with that SDK.
