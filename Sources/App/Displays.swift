import CoreGraphics

/// External-display detection, for clamshell behaviour.
///
/// When an external monitor is connected, closing the lid means the user wants
/// to keep using that monitor (clamshell mode) — so lidawake must NOT sleep the
/// display. Sleeping the screen on lid-close is only correct when the built-in
/// panel is the only screen (nothing to see behind a closed lid).
enum Displays {
    /// True if at least one connected ("online") display is not the built-in panel.
    /// Uses the online list rather than the active list because it stays stable
    /// through the lid-close transition, when the built-in briefly drops out.
    static func hasExternal() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }
}
