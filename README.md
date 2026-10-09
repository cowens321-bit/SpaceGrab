# SpaceGrab

Menu bar app: when you activate an app whose windows are on another Space, the window is moved to your current Space instead of macOS switching you away.

## Install
Download the latest `.dmg` from [Releases](https://github.com/cowens321-bit/SpaceGrab/releases/latest), drag SpaceGrab to Applications. After that it updates itself from GitHub Releases (checks at launch and every 6 hours; menu → "Check for Updates…").

## Publishing an update
    Scripts/release.sh 1.0.1 "What changed"
Bumps `VERSION`, builds, makes the dmg, tags, pushes, and creates the GitHub release. Run `Scripts/setup-signing.sh` once on a new machine first: a stable local signing identity keeps the Accessibility permission across updates.

## Build / run
    ./build.sh && open build/SpaceGrab.app

## How it works
- Turns off the macOS setting "When switching to an application, switch to a Space with open windows for the application" (`com.apple.dock workspaces-auto-swoosh`) — with your consent on first launch.
- On app activation (Dock, Cmd-Tab, Spotlight) or a Dock re-click, finds the app's windows via `CGWindowListCopyWindowInfo`, and if none is on your current Space, moves the most recent one (or all, via menu) with the private SkyLight `SLSMoveWindowsToManagedSpace`.
- Raises/focuses the window via the Accessibility API (needs Accessibility permission).
- Skips full-screen Spaces, excluded apps and SpaceGrab itself.

## Restore / uninstall
Menu bar icon → "Quit and restore macOS setting", or:
    defaults delete com.apple.dock workspaces-auto-swoosh && killall Dock

## Diagnostics
- `SpaceGrab --selftest` prints whether private symbols resolve and the Spaces of each window.
- `SpaceGrab --movetest` moves its own throwaway window to another Space and back.

Uses private APIs; may break on future macOS releases. Not App Store compatible.
