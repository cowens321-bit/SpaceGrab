#!/bin/bash
# Builds build/SpaceGrab.app, signed with the local identity (falls back to ad-hoc).
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(cat VERSION)
swift build -c release
APP=build/SpaceGrab.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/SpaceGrab" "$APP/Contents/MacOS/SpaceGrab"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
 <key>CFBundleIdentifier</key><string>com.cowens.SpaceGrab</string>
 <key>CFBundleName</key><string>SpaceGrab</string>
 <key>CFBundleExecutable</key><string>SpaceGrab</string>
 <key>CFBundlePackageType</key><string>APPL</string>
 <key>CFBundleShortVersionString</key><string>$VERSION</string>
 <key>CFBundleVersion</key><string>$VERSION</string>
 <key>LSMinimumSystemVersion</key><string>13.0</string>
 <key>LSUIElement</key><true/>
</dict></plist>
PL
KC="$HOME/Library/Keychains/spacegrab-signing.keychain-db"
if [ -f "$KC" ] && security unlock-keychain -p spacegrab "$KC" 2>/dev/null && security find-identity -p codesigning "$KC" | grep -q "SpaceGrab Local Signing"; then
  codesign --force --sign "SpaceGrab Local Signing" --keychain "$KC" "$APP"
else
  echo "warning: signing identity missing (run Scripts/setup-signing.sh); using ad-hoc signature"
  codesign --force --sign - "$APP"
fi
echo "Built $APP v$VERSION"
