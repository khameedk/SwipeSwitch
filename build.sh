#!/bin/bash
# Builds build/SwipeSwitch.app. Run: ./build.sh   (add --install to copy it to /Applications)
set -euo pipefail
cd "$(dirname "$0")"
APP=build/SwipeSwitch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  -import-objc-header Sources/Bridge.h Sources/*.swift \
  -o "$APP/Contents/MacOS/SwipeSwitch"

cp Info.plist "$APP/Contents/Info.plist"
if [ ! -f build/AppIcon.icns ]; then
  swift make_icon.swift build/AppIcon.iconset >/dev/null
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# A fixed designated requirement keeps macOS permissions (Accessibility) across rebuilds.
codesign --force --sign - -r='designated => identifier "io.github.khameedk.swipeswitch"' "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x SwipeSwitch || true
  rm -rf /Applications/SwipeSwitch.app
  cp -R "$APP" /Applications/
  open /Applications/SwipeSwitch.app
  echo "Installed to /Applications/SwipeSwitch.app"
fi
