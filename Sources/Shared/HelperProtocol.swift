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
    public static let helperVersion   = "2.1.0"
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
