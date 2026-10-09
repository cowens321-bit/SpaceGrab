import Foundation

/// User preferences plus the Dock setting bookkeeping.
enum Prefs {
    private static let d = UserDefaults.standard

    static var enabled: Bool {
        get { d.object(forKey: "enabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "enabled") }
    }
    /// false = move only the most recent window; true = every window of the app.
    static var moveAllWindows: Bool {
        get { d.bool(forKey: "moveAllWindows") }
        set { d.set(newValue, forKey: "moveAllWindows") }
    }
    static var excluded: [String] {
        get { d.stringArray(forKey: "excluded") ?? [] }
        set { d.set(newValue, forKey: "excluded") }
    }
    static var onboarded: Bool {
        get { d.bool(forKey: "onboarded") }
        set { d.set(newValue, forKey: "onboarded") }
    }
}

/// Manages `com.apple.dock workspaces-auto-swoosh` ("switch to a Space with open windows for the application").
enum DockSetting {
    private static let key = "workspaces-auto-swoosh"
    private static let domain = "com.apple.dock"
    /// Stored state of the original value: "unset", "true" or "false".
    private static let savedKey = "originalAutoSwoosh"

    /// Current effective value (macOS default when unset is true).
    static var autoSwitchEnabled: Bool {
        let v = CFPreferencesCopyAppValue(key as CFString, domain as CFString)
        return (v as? Bool) ?? true
    }

    static func disableAutoSwitch() {
        if UserDefaults.standard.string(forKey: savedKey) == nil {
            let v = CFPreferencesCopyAppValue(key as CFString, domain as CFString)
            UserDefaults.standard.set((v as? Bool).map { $0 ? "true" : "false" } ?? "unset", forKey: savedKey)
        }
        run("/usr/bin/defaults", ["write", domain, key, "-bool", "false"])
        run("/usr/bin/killall", ["Dock"])
    }

    static func restore() {
        switch UserDefaults.standard.string(forKey: savedKey) {
        case "true": run("/usr/bin/defaults", ["write", domain, key, "-bool", "true"])
        case "false": run("/usr/bin/defaults", ["write", domain, key, "-bool", "false"])
        default: run("/usr/bin/defaults", ["delete", domain, key])
        }
        UserDefaults.standard.removeObject(forKey: savedKey)
        run("/usr/bin/killall", ["Dock"])
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
