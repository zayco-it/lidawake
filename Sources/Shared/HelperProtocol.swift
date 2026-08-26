// Shared between the app and the root helper — compiled into BOTH targets.
// Defines the XPC contract plus the identifiers and the code-signing requirement
// each side uses to authenticate the other. Keep everything ObjC-bridgeable:
// @objc, reply-block style, no async/throws/structs/enums in the protocol.

import Foundation

@objc(LidAwakeHelperProtocol)
public protocol LidAwakeHelperProtocol {
    /// disable == true  -> `pmset -a disablesleep 1` (block lid-close sleep)
    /// disable == false -> `pmset -a disablesleep 0` (restore normal sleep)
    /// reply: nil on success, otherwise a human-readable error string.
    func setDisableSleep(_ disable: Bool, reply: @escaping (String?) -> Void)

    /// Sleep the display immediately (lid closed while armed). reply: nil on success.
    func sleepDisplayNow(reply: @escaping (String?) -> Void)

    /// Lightweight liveness/version probe.
    func helperVersion(reply: @escaping (String) -> Void)

    /// Hang-watchdog check-in from the armed client. Must be sent from the app's
    /// MAIN run loop — see Sources/App/Heartbeat.swift for why that specific
    /// thread is the only one that proves anything.
    /// reply: whether the helper still has sleep disabled for this client. `false`
    /// means the watchdog already gave up on it and restored sleep, so a client
    /// that was wedged can reconcile instead of going on claiming to be on.
    func heartbeat(reply: @escaping (Bool) -> Void)
}

// One source of truth for every identifier. These must stay in lockstep with
// Info.plist (app), Helper-Info.plist (helper), the LaunchDaemon plist, and the
// build/sign script. Change one, change all.
public enum LidAwakeIDs {
    public static let appBundleID     = "it.zayco.lidawake"
    public static let helperBundleID  = "it.zayco.lidawake.helper"
    public static let machServiceName = "it.zayco.lidawake.helper"
    public static let helperPlistName = "it.zayco.lidawake.helper.plist"   // note: WITH .plist
    public static let teamID          = "FXNTJBLQ2F"                       // zaYco s. r. o.
    public static let helperVersion   = "2.2.0"
}

/// Hang-watchdog timings, shared so the two sides can never drift apart.
///
/// The gap between them IS the safety margin: six missed check-ins before the
/// helper acts on its own. That asymmetry is deliberate. A late trip costs a
/// little extra heat and battery in a window where nothing thermally meaningful
/// happens. A FALSE trip sleeps the Mac under someone who was mid-something —
/// dropped session, interrupted build. The margin is bought against the second
/// one, because it is the failure that would make lidawake the flaky one rather
/// than the safe one.
public enum LidAwakeWatchdog {
    /// App -> helper check-in period, driven by the app's main run loop.
    public static let heartbeatInterval: TimeInterval = 15

    /// Silence after which the helper restores normal sleep by itself.
    public static let timeout: TimeInterval = 90

    /// First helper version that implements `heartbeat`. The app checks this before
    /// sending any: calling a selector the remote doesn't export can INVALIDATE the
    /// NSXPC connection, which would fire an old helper's dead man's switch and
    /// silently turn lidawake off. After a Sparkle update the previous helper binary
    /// can still be the resident one, so this is a live case, not a theoretical one.
    public static let minHelperVersion = "2.2.0"
}

/// Dotted-version compare (`.numeric` so 2.10.0 > 2.2.0). True if `version` is at
/// least `minimum`.
public func lidAwakeVersionAtLeast(_ version: String, _ minimum: String) -> Bool {
    version.compare(minimum, options: .numeric) != .orderedAscending
}

/// A `csreq`-style requirement that pins: an Apple-issued chain, a specific
/// bundle identifier, the Developer ID Application leaf, and our Team ID.
/// Used in BOTH directions — the helper authenticates the app (so only our app
/// can ask for root pmset changes), the app authenticates the helper (so a
/// swapped binary can't impersonate it). A mismatch is rejected by macOS.
public func lidAwakeRequirement(identifier: String) -> String {
    return "anchor apple generic "
        + "and identifier \"\(identifier)\" "
        + "and certificate 1[field.1.2.840.113635.100.6.2.6] "       // Developer ID CA (intermediate)
        + "and certificate leaf[field.1.2.840.113635.100.6.1.13] "   // Developer ID Application (leaf)
        + "and certificate leaf[subject.OU] = \"\(LidAwakeIDs.teamID)\""
}
