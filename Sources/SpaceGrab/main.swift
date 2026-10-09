import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let mover = Mover()
    private var lastLog = "Ready"
    private var clickMonitor: Any?
    private let updater = Updater()

    func applicationDidFinishLaunching(_ n: Notification) {
        mover.log = { [weak self] in self?.lastLog = $0; NSLog("SpaceGrab: %@", $0) }
        setupStatusItem()
        updater.status = { [weak self] in self?.lastLog = $0 }
        updater.startAutomaticChecks()

        if !SkyLight.isAvailable {
            alert("Unsupported macOS version",
                  "These window-server functions are missing on this macOS: \(SkyLight.missingSymbols.joined(separator: ", ")). SpaceGrab can't move windows.")
        }
        if !Prefs.onboarded { onboard() }
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        // Re-clicking the Dock icon of an already-frontmost app posts no activation notification.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            let p = NSEvent.mouseLocation
            guard let s = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }),
                  !NSMouseInRect(p, s.visibleFrame, false) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if let app = NSWorkspace.shared.frontmostApplication { self?.mover.pullWindows(of: app) }
            }
        }
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.mover.pullWindows(of: app) }
    }

    // MARK: Onboarding / Dock setting

    private func onboard() {
        let a = NSAlert()
        a.messageText = "Stop macOS from switching Spaces?"
        a.informativeText = """
        For SpaceGrab to work, macOS's setting "When switching to an application, switch to a Space with open windows for the application" must be off. \
        SpaceGrab will turn it off (and restart the Dock). You can restore the original value any time from the menu bar icon.
        """
        a.addButton(withTitle: "Turn It Off")
        a.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { DockSetting.disableAutoSwitch() }
        Prefs.onboarded = true
    }

    // MARK: Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "SpaceGrab")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text
        NSApp.activate(ignoringOtherApps: true); a.runModal()
    }

    @objc private func toggleEnabled() { Prefs.enabled.toggle() }
    @objc private func toggleAll() { Prefs.moveAllWindows.toggle() }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { alert("Launch at login failed", error.localizedDescription) }
    }
    @objc private func toggleDockSetting() {
        if DockSetting.autoSwitchEnabled { DockSetting.disableAutoSwitch() } else { DockSetting.restore() }
    }
    @objc private func excludeFront() {
        guard let id = NSWorkspace.shared.menuBarOwningApplication?.bundleIdentifier ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
        var ex = Prefs.excluded
        if let i = ex.firstIndex(of: id) { ex.remove(at: i) } else { ex.append(id) }
        Prefs.excluded = ex
    }
    @objc private func openAX() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func checkUpdates() { updater.check(interactive: true) }
    @objc private func quitRestore() { DockSetting.restore(); NSApp.terminate(nil) }
    @objc private func quit() { NSApp.terminate(nil) }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func item(_ t: String, _ s: Selector?, on: Bool = false, enabled: Bool = true) {
            let i = NSMenuItem(title: t, action: enabled ? s : nil, keyEquivalent: "")
            i.target = self; i.state = on ? .on : .off
            menu.addItem(i)
        }
        item("Enabled", #selector(toggleEnabled), on: Prefs.enabled)
        item("Move all windows of the app", #selector(toggleAll), on: Prefs.moveAllWindows)
        item("Disable macOS Space auto-switch", #selector(toggleDockSetting), on: !DockSetting.autoSwitchEnabled)
        let front = NSWorkspace.shared.frontmostApplication
        let name = front?.localizedName ?? "frontmost app"
        let isEx = front?.bundleIdentifier.map(Prefs.excluded.contains) ?? false
        item("Exclude \(name)", #selector(excludeFront), on: isEx)
        menu.addItem(.separator())
        item("Launch at login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled)
        if !AXIsProcessTrusted() { item("Grant Accessibility access…", #selector(openAX)) }
        menu.addItem(.separator())
        item("Check for Updates… (v\(Updater.currentVersion))", #selector(checkUpdates))
        item(lastLog, nil, enabled: false)
        menu.addItem(.separator())
        item("Quit and restore macOS setting", #selector(quitRestore))
        item("Quit", #selector(quit))
    }
}

if CommandLine.arguments.contains("--versiontest") {
    let cases = [("1.0.1", "1.0.0", true), ("1.0.0", "1.0.0", false), ("1.10.0", "1.9.9", true), ("2.0", "1.9.9", true), ("1.0.0", "1.0.1", false)]
    var ok = true
    for (a, b, want) in cases where Updater.isNewer(a, than: b) != want { print("FAIL", a, b); ok = false }
    print(ok ? "version compare PASS" : "version compare FAIL"); exit(ok ? 0 : 1)
}

if CommandLine.arguments.contains("--selftest") {
    print("missing symbols:", SkyLight.missingSymbols)
    let uuid = SkyLight.mainDisplayUUID()
    print("main display:", uuid ?? "nil", "current space:", SkyLight.currentSpace(forDisplayUUID: uuid).map(String.init) ?? "nil")
    if let cur = SkyLight.currentSpace(forDisplayUUID: uuid) { print("current is fullscreen/system:", SkyLight.isFullscreenOrSystem(space: cur)) }
    if let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] {
        for w in list where (w[kCGWindowLayer as String] as? Int) == 0 {
            let id = CGWindowID(w[kCGWindowNumber as String] as? UInt32 ?? 0)
            print(w[kCGWindowOwnerName as String] ?? "?", id, "spaces:", SkyLight.spaces(of: id))
        }
    }
    print("auto-switch enabled:", DockSetting.autoSwitchEnabled)
    exit(0)
}

if CommandLine.arguments.contains("--movetest") {
    // Creates its own throwaway window, moves it to another Space and back; touches no user windows.
    let a = NSApplication.shared; a.setActivationPolicy(.accessory)
    let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    w.title = "SpaceGrab test"; w.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    let id = CGWindowID(w.windowNumber)
    let uuid = SkyLight.mainDisplayUUID()
    let cur = SkyLight.currentSpace(forDisplayUUID: uuid)!
    print("current space:", cur, "window spaces:", SkyLight.spaces(of: id))
    let other: UInt64 = cur == 6 ? 5 : 6
    SkyLight.move(windows: [id], to: other)
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    print("after move to", other, "->", SkyLight.spaces(of: id), "still on current space:", SkyLight.currentSpace(forDisplayUUID: uuid)! == cur)
    SkyLight.move(windows: [id], to: cur)
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    print("after move back ->", SkyLight.spaces(of: id))

    // End-to-end: park the window on another Space, then let Mover pull it back.
    SkyLight.move(windows: [id], to: other)
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    let m = Mover(); m.log = { print("mover:", $0) }
    m.pullWindows(of: NSRunningApplication.current, force: true)
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    let final = SkyLight.spaces(of: id)
    print("after Mover.pullWindows ->", final, final == [cur] ? "PASS" : "FAIL")
    // Second call must be a no-op when a window is already on the current Space.
    m.pullWindows(of: NSRunningApplication.current, force: true)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
