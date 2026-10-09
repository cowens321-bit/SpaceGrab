#!/bin/bash
# Packages build/SpaceGrab.app into build/SpaceGrab-<version>.dmg (drag-to-Applications layout).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
DMG="build/SpaceGrab-$VERSION.dmg"
STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
cp -R build/SpaceGrab.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "SpaceGrab" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "$DMG"
