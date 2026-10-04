#!/usr/bin/env bash
# Build Tempo.app (ad-hoc signed). Pass --install to copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Tempo.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macos14.0 \
    Sources/*.swift -o "$APP/Contents/MacOS/Tempo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Tempo || true
    rm -rf /Applications/Tempo.app
    ditto "$APP" /Applications/Tempo.app
    open /Applications/Tempo.app
fi
echo "Built $APP"
