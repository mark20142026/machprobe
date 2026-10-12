#!/bin/sh
set -eu

if ! command -v xcodebuild >/dev/null 2>&1 || ! command -v xcrun >/dev/null 2>&1; then
    echo "Xcode command-line tools are unavailable; install/select Xcode manually before building this project." >&2
    exit 2
fi

echo "Selected developer directory:"
xcode-select -p || {
    echo "No Xcode developer directory is selected." >&2
    exit 2
}
echo "Xcode version:"
if ! xcodebuild -version; then
    echo "A full Xcode installation is required; the selected developer directory does not provide xcodebuild/iOS SDKs." >&2
    exit 2
fi
echo "Available SDKs:"
xcodebuild -showsdks || true

for sdk in iphoneos iphonesimulator; do
    if path=$(xcrun --sdk "$sdk" --show-sdk-path 2>/dev/null) && [ -d "$path" ]; then
        echo "$sdk: $path"
    else
        echo "Required $sdk SDK is unavailable. Select a full Xcode installation; this script will not install one." >&2
        exit 2
    fi
done

echo "Preflight passed. The project has not been built or signed by this script."
