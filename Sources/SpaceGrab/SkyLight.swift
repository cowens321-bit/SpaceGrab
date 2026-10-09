import Foundation
import CoreGraphics
import ColorSync

/// Runtime-resolved private window-server APIs (SkyLight `SLS*`, falling back to CoreGraphics `CGS*`).
/// Resolved with dlsym so a missing symbol on a future macOS fails gracefully instead of crashing at launch.
enum SkyLight {
    private static let handles: [UnsafeMutableRawPointer] = {
        let paths = [
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
        ]
        return paths.compactMap { dlopen($0, RTLD_LAZY) }
    }()

    private static func sym<T>(_ names: [String], as: T.Type) -> T? {
        for name in names {
            for h in handles {
                if let p = dlsym(h, name) { return unsafeBitCast(p, to: T.self) }
            }
        }
        return nil
    }

    private typealias MainConnFn = @convention(c) () -> Int32
    private typealias ActiveSpaceFn = @convention(c) (Int32) -> UInt64
    private typealias DisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias MoveFn = @convention(c) (Int32, CFArray, UInt64) -> Void
    private typealias SpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias SpaceTypeFn = @convention(c) (Int32, UInt64) -> Int32

    private static let mainConn = sym(["SLSMainConnectionID", "CGSMainConnectionID"], as: MainConnFn.self)
    private static let activeSpace = sym(["SLSGetActiveSpace", "CGSGetActiveSpace"], as: ActiveSpaceFn.self)
    private static let displaySpaces = sym(["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"], as: DisplaySpacesFn.self)
    private static let moveWindows = sym(["SLSMoveWindowsToManagedSpace", "CGSMoveWindowsToManagedSpace"], as: MoveFn.self)
    private static let spacesForWindows = sym(["SLSCopySpacesForWindows", "CGSCopySpacesForWindows"], as: SpacesForWindowsFn.self)
    private static let spaceType = sym(["SLSSpaceGetType", "CGSSpaceGetType"], as: SpaceTypeFn.self)

    /// Names of required symbols that could not be resolved on this macOS version.
    static var missingSymbols: [String] {
        var m: [String] = []
        if mainConn == nil { m.append("MainConnectionID") }
        if activeSpace == nil { m.append("GetActiveSpace") }
        if displaySpaces == nil { m.append("CopyManagedDisplaySpaces") }
        if moveWindows == nil { m.append("MoveWindowsToManagedSpace") }
        if spacesForWindows == nil { m.append("CopySpacesForWindows") }
        return m
    }

    static var isAvailable: Bool { missingSymbols.isEmpty }

    private static var cid: Int32 { mainConn?() ?? 0 }

    /// Space type 4 == full-screen app Space, 2 == system Space.
    static func isFullscreenOrSystem(space: UInt64) -> Bool {
        guard let t = spaceType?(cid, space) else { return false }
        return t == 4 || t == 2
    }

    /// Active Space ID for the display that currently contains the mouse (falls back to the global active Space).
    static func currentSpace(forDisplayUUID uuid: String?) -> UInt64? {
        guard isAvailable else { return nil }
        if let uuid, let arr = displaySpaces?(cid)?.takeRetainedValue() as? [[String: Any]] {
            for display in arr {
                let ident = display["Display Identifier"] as? String
                // The primary display may report "Main" instead of its UUID.
                if ident == uuid || (ident == "Main" && uuid == mainDisplayUUID()) {
                    if let cur = display["Current Space"] as? [String: Any],
                       let id = (cur["id64"] as? NSNumber)?.uint64Value ?? (cur["ManagedSpaceID"] as? NSNumber)?.uint64Value {
                        return id
                    }
                }
            }
        }
        return activeSpace?(cid)
    }

    static func spaces(of windowID: CGWindowID) -> [UInt64] {
        guard let f = spacesForWindows else { return [] }
        // mask 0x7 == all Spaces (current | other | user)
        guard let res = f(cid, 7, [NSNumber(value: windowID)] as CFArray)?.takeRetainedValue() as? [NSNumber] else { return [] }
        return res.map { $0.uint64Value }
    }

    static func move(windows: [CGWindowID], to space: UInt64) {
        guard let f = moveWindows, !windows.isEmpty else { return }
        f(cid, windows.map { NSNumber(value: $0) } as CFArray, space)
    }

    static func uuid(forDisplay id: CGDirectDisplayID) -> String? {
        guard let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, u) as String?
    }

    static func mainDisplayUUID() -> String? { uuid(forDisplay: CGMainDisplayID()) }
}
