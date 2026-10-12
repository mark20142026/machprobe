# iOS host app project

`Phase2Host.xcodeproj` is a conventional iOS application target for the Phase 2 UIKit host. It is configured to compile the existing host and runtime sources against the real UIKit, Foundation, CoreFoundation, Metal, and Objective-C runtime SDK interfaces. It does not define `MP_MINIMAL_UIKIT`.

The app bundle copies the four Phase 1 sample executables and the three Phase 2 guests (including the interactive ABI guest) as resources. They are copied as data without a CodeSignOnCopy rule; the project does not rebuild, patch, or re-sign those original guest files. Build them first from the repository root:

```sh
make all
make -f phase2/Makefile all
```

Run the read-only SDK preflight, then build for an iOS simulator:

```sh
phase2/ios/scripts/preflight.sh
xcodebuild -project phase2/ios/Phase2Host.xcodeproj \
  -scheme Phase2Host -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

To compile the device variant without signing, use:

```sh
xcodebuild -project phase2/ios/Phase2Host.xcodeproj \
  -scheme Phase2Host -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Installing on a device requires normal signing configured by the developer in Xcode. This project specifies no team or signing identity. Simulator builds can run from Xcode after selecting an available simulator destination.

**Status: UNTESTED.** This environment has Command Line Tools but no full Xcode installation or iOS SDK, so Xcode project loading, simulator/device compilation, signing, and app execution have not been verified. The preflight reports that limitation and does not install software or change system settings. This iOS project also does not establish that macOS can directly execute an iOS binary.
