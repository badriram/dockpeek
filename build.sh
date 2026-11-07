#!/bin/bash
# Builds DockPeek.app from source. No package manager, no dependencies, no network.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/DockPeek.app
IDENTITY="${SIGN_IDENTITY:-Apple Development}"   # a stable identity keeps TCC grants across rebuilds

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos14.0" \
    Sources/*.swift -o "build/DockPeek-$arch"
done
lipo -create build/DockPeek-arm64 build/DockPeek-x86_64 -output "$APP/Contents/MacOS/DockPeek"
rm build/DockPeek-arm64 build/DockPeek-x86_64

cp Resources/Info.plist "$APP/Contents/Info.plist"

# APP_SANDBOX=1 re-tests the App Sandbox entitlement (broken on macOS 27: cannot read the Dock).
ENTITLEMENTS=Resources/DockPeek.entitlements
[ "${APP_SANDBOX:-0}" = "1" ] && ENTITLEMENTS=Resources/AppSandbox.entitlements

codesign --force --options runtime --timestamp=none \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" "$APP"

echo "Built $APP"
echo "--- entitlements (should be empty) ---"
codesign -d --entitlements - "$APP" 2>/dev/null
