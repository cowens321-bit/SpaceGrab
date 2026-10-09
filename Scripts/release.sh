#!/bin/bash
# Usage: Scripts/release.sh 1.0.1 ["release notes"]
# Bumps VERSION, builds, makes the dmg, commits, tags, pushes, and publishes a GitHub release.
# Installed copies of SpaceGrab pick it up automatically.
set -euo pipefail
cd "$(dirname "$0")/.."
V="${1:?usage: release.sh <version> [notes]}"; NOTES="${2:-SpaceGrab $V}"
echo "$V" > VERSION
./build.sh
DMG=$(Scripts/make-dmg.sh)
git add -A
git commit -m "Release v$V" || true
git tag "v$V"
GH_USER=cowens321-bit
git -c credential.helper= -c credential.helper='!gh auth git-credential' push origin HEAD "v$V"
GH_TOKEN=$(gh auth token -u $GH_USER) gh release create "v$V" "$DMG" --repo $GH_USER/SpaceGrab --title "SpaceGrab $V" --notes "$NOTES"
