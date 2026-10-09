import AppKit

/// Self-updater that follows GitHub Releases of the SpaceGrab repo.
/// Downloads the .dmg asset of the latest release, swaps the installed app bundle, and relaunches.
final class Updater {
    static let repo = "cowens321-bit/SpaceGrab"

    var status: (String) -> Void = { _ in }
    private var busy = false
    private var timer: Timer?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func startAutomaticChecks() {
        check(interactive: false)
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.check(interactive: false)
        }
    }

    /// `interactive` = user chose "Check for Updates…": always report the outcome.
    func check(interactive: Bool) {
        guard !busy else { return }
        busy = true
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Updater.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            DispatchQueue.main.async { self?.handle(data: data, resp: resp, err: err, interactive: interactive) }
        }.resume()
    }

    private func handle(data: Data?, resp: URLResponse?, err: Error?, interactive: Bool) {
        guard let data, (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            busy = false
            status("Update check failed")
            if interactive { info("Couldn't check for updates", err?.localizedDescription ?? "GitHub didn't return a release.") }
            return
        }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard Updater.isNewer(latest, than: Updater.currentVersion) else {
            busy = false
            status("Up to date (v\(Updater.currentVersion))")
            if interactive { info("You're up to date", "SpaceGrab \(Updater.currentVersion) is the latest version.") }
            return
        }
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let dmg = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
              let urlStr = dmg["browser_download_url"] as? String, let url = URL(string: urlStr) else {
            busy = false
            status("Update \(latest) has no .dmg")
            return
        }
        status("Downloading v\(latest)…")
        download(url: url, version: latest)
    }

    private func download(url: URL, version: String) {
        URLSession.shared.downloadTask(with: url) { [weak self] tmp, _, err in
            guard let self else { return }
            guard let tmp else {
                DispatchQueue.main.async { self.busy = false; self.status("Download failed") }
                return
            }
            // The temp file is deleted when this handler returns; move it first.
            let dmg = FileManager.default.temporaryDirectory.appendingPathComponent("SpaceGrab-\(version).dmg")
            try? FileManager.default.removeItem(at: dmg)
            do { try FileManager.default.moveItem(at: tmp, to: dmg) } catch {
                DispatchQueue.main.async { self.busy = false; self.status("Download failed") }
                return
            }
            let ok = Updater.install(dmg: dmg)
            DispatchQueue.main.async {
                if ok { NSApp.terminate(nil) } else { self.busy = false; self.status("Install failed") }
            }
        }.resume()
    }

    /// Mounts the dmg, stages the app, and launches a detached script that replaces the running bundle after we quit.
    private static func install(dmg: URL) -> Bool {
        let fm = FileManager.default
        let mount = fm.temporaryDirectory.appendingPathComponent("SpaceGrabMount-\(UUID().uuidString)")
        let stage = fm.temporaryDirectory.appendingPathComponent("SpaceGrabStage-\(UUID().uuidString)")
        try? fm.createDirectory(at: mount, withIntermediateDirectories: true)
        try? fm.createDirectory(at: stage, withIntermediateDirectories: true)
        guard run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mount.path]) == 0 else { return false }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        let src = mount.appendingPathComponent("SpaceGrab.app")
        let staged = stage.appendingPathComponent("SpaceGrab.app")
        guard run("/usr/bin/ditto", [src.path, staged.path]) == 0 else { return false }
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])

        let target = Bundle.main.bundleURL.path
        guard fm.isWritableFile(atPath: (target as NSString).deletingLastPathComponent) else { return false }
        let script = """
        while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done
        rm -rf '\(target).old'
        mv '\(target)' '\(target).old' && mv '\(staged.path)' '\(target)' && rm -rf '\(target).old' || mv '\(target).old' '\(target)'
        open '\(target)'
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", script]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        return (try? p.run()) != nil
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private func info(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text
        NSApp.activate(ignoringOtherApps: true); a.runModal()
    }
}
