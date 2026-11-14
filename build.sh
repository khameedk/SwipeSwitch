#!/bin/bash
# Builds build/SwipeSwitch.app. Run: ./build.sh
#   --install  copy it to /Applications and open it
#   --dev      include the demo and test hooks (SWIPESWITCH_DEMO etc.); release builds leave them out
set -euo pipefail
cd "$(dirname "$0")"
# SHA-1 of the "SwipeSwitch Signing" certificate releases are signed with. Releases must use exactly this one: a
# different certificate would make every user's permissions stop matching.
RELEASE_CERT_SHA1=b678dd37bae89565b1909356961618d9f172a710

INSTALL=0; FLAGS=()
for arg in "$@"; do
  case "$arg" in
    --print-cert-sha1) echo "$RELEASE_CERT_SHA1"; exit 0 ;;
    --install) INSTALL=1 ;;
    --dev) FLAGS+=(-D SWIPESWITCH_DEV) ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done
APP=build/SwipeSwitch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  -import-objc-header Sources/Bridge.h ${FLAGS[@]+"${FLAGS[@]}"} Sources/*.swift \
  -o "$APP/Contents/MacOS/SwipeSwitch"

cp Info.plist "$APP/Contents/Info.plist"
if [ ! -f build/AppIcon.icns ]; then
  swift make_icon.swift build/AppIcon.iconset >/dev/null
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Signing. macOS ties permissions (Accessibility etc.) to the app's "designated requirement".
# - With the "SwipeSwitch Signing" certificate in a keychain (how releases are built), the requirement is "this
#   identifier, signed by this certificate": permissions survive updates, and nothing else can claim them.
# - Without it (anyone else building from source), the app is signed ad hoc and the requirement is the identifier
#   alone, so permissions still survive rebuilds on that Mac. SWIPESWITCH_REQUIRE_CERT=1 (set by the release
#   workflow) makes a missing certificate an error instead.
# --options runtime turns on the hardened runtime: other programs can't inject code into SwipeSwitch (and so borrow
# its permissions). The entitlements file allows the one thing that then needs permission: Apple Events to BTT.
IDENTITY="SwipeSwitch Signing"
ID="io.github.khameedk.swipeswitch"
CERT_SHA1=$(security find-certificate -c "$IDENTITY" -Z 2>/dev/null | awk '/^SHA-1 hash:/ { print tolower($3); exit }')
if [ "${SWIPESWITCH_REQUIRE_CERT:-}" = 1 ] && [ -n "$CERT_SHA1" ] && [ "$CERT_SHA1" != "$RELEASE_CERT_SHA1" ]; then
  echo "error: found a \"$IDENTITY\" certificate, but not the release one ($RELEASE_CERT_SHA1)" >&2; exit 1
fi
if [ -n "$CERT_SHA1" ]; then
  codesign --force --sign "$CERT_SHA1" --options runtime --entitlements SwipeSwitch.entitlements \
    -r="designated => identifier \"$ID\" and certificate leaf = H\"$CERT_SHA1\"" "$APP"
elif [ "${SWIPESWITCH_REQUIRE_CERT:-}" = 1 ]; then
  echo "error: the \"$IDENTITY\" certificate isn't in any keychain" >&2; exit 1
else
  codesign --force --sign - --options runtime --entitlements SwipeSwitch.entitlements \
    -r="designated => identifier \"$ID\"" "$APP"
fi
echo "Built $APP"

if [ "$INSTALL" = 1 ]; then
  pkill -x SwipeSwitch || true
  rm -rf /Applications/SwipeSwitch.app
  cp -R "$APP" /Applications/
  open /Applications/SwipeSwitch.app
  echo "Installed to /Applications/SwipeSwitch.app"
fi
