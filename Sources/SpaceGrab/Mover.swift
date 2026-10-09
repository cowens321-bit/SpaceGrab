import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Pulls an app's windows from other Spaces into the Space the user is currently on.
final class Mover {
    var log: (String) -> Void = { _ in }

    private struct Win { let id: CGWindowID; let spaces: [UInt64] }

    func pullWindows(of app: NSRunningApplication, force: Bool = false) {
        guard Prefs.enabled, SkyLight.isAvailable else { return }
        if !force {
            guard app.activationPolicy == .regular,
                  app.processIdentifier != getpid(),
                  !(app.bundleIdentifier.map(Prefs.excluded.contains) ?? false) else { return }
        }

        let screen = screenUnderMouse()
        let displayUUID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .flatMap { SkyLight.uuid(forDisplay: CGDirectDisplayID($0.uint32Value)) }
        guard let current = SkyLight.currentSpace(forDisplayUUID: displayUUID) else { return }
        // Never push windows into a full-screen app Space.
        if SkyLight.isFullscreenOrSystem(space: current) { return }

        let wins = windows(of: app.processIdentifier)
        guard !wins.isEmpty else { return }
        // Already has a window here: macOS shows it normally.
        if wins.contains(where: { $0.spaces.contains(current) }) { return }

        // Skip windows living in full-screen Spaces; list is front-to-back so first == most recent.
        let movable = wins.filter { w in
            !w.spaces.isEmpty && !w.spaces.contains(where: { SkyLight.isFullscreenOrSystem(space: $0) })
        }
        guard !movable.isEmpty else { return }
        let toMove = Prefs.moveAllWindows ? movable : [movable[0]]

        SkyLight.move(windows: toMove.map(\.id), to: current)
        log("Moved \(toMove.count) window(s) of \(app.localizedName ?? "app") to space \(current)")

        app.unhide()
        app.activate(options: [.activateIgnoringOtherApps])
        raise(windowID: toMove[0].id, pid: app.processIdentifier)
    }

    /// Normal, sized, visible-style windows for a pid, front-to-back, across all Spaces.
    private func windows(of pid: pid_t) -> [Win] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        var out: [Win] = []
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let num = w[kCGWindowNumber as String] as? UInt32,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  (b["Width"] ?? 0) >= 80, (b["Height"] ?? 0) >= 50 else { continue }
            let id = CGWindowID(num)
            out.append(Win(id: id, spaces: SkyLight.spaces(of: id)))
        }
        return out
    }

    private func raise(windowID: CGWindowID, pid: pid_t) {
        guard AXIsProcessTrusted() else { return }
        let ax = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &ref) == .success,
              let axWins = ref as? [AXUIElement] else { return }
        for w in axWins {
            var id: CGWindowID = 0
            if _AXUIElementGetWindow(w, &id) == .success, id == windowID {
                AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(ax, kAXFocusedWindowAttribute as CFString, w)
                return
            }
        }
    }

    private func screenUnderMouse() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main
    }
}
