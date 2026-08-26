// Launch-at-login registration for the app itself.
//
// Deliberately NOT part of HelperManager: that registers the root LaunchDaemon
// via `SMAppService.daemon(plistName:)`, which needs the user's approval in
// System Settings. This is `SMAppService.mainApp` — the ordinary "Open at
// Login" entry — which needs no approval and no admin rights. Two different
// registrations against two different services; keeping them apart keeps the
// privileged one easy to audit.
//
// Why it exists: without it lidawake does not come back after a reboot. To a
// non-technical user that does not read as a missing feature — it reads as
// "it stopped working". The helper is still enabled, the Mac still sleeps the
// moment the lid shuts, and nothing on screen explains why.

import Foundation
import ServiceManagement

enum LoginItem {

    /// Internal bookkeeping. Deliberately not a `Settings.Key`: Settings has five
    /// user-facing keys and this is not one of them — there is no toggle for this
    /// and no Settings row. It records only that we have asked macOS once, ever.
    private static let didRegisterKey = "loginItemRegisteredOnce"

    /// Register the app to open at login — once, and only once.
    ///
    /// The once-only part is the entire design. `SMAppService.mainApp.status`
    /// reports `.notRegistered` both for "we have never registered" and for "the
    /// user switched it off in System Settings", and nothing distinguishes them.
    /// Registering on every launch would therefore silently undo a deliberate
    /// choice every single launch, with no way for the user to make it stick —
    /// the app would be quietly fighting its owner. So: ask macOS once, record
    /// that we asked, and never touch it again.
    ///
    /// Call this when the helper has just answered, i.e. the moment lidawake is
    /// genuinely working on this Mac. Registering at first launch instead would
    /// leave an "Open at Login" entry behind for someone who opened it once,
    /// never finished the one setup step, and dragged it to the Trash.
    static func registerOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didRegisterKey) else { return }

        let service = SMAppService.mainApp

        // Already on — the user (or a previous install) got there first. Record it
        // so we never re-register, and leave their setting alone.
        if service.status == .enabled {
            defaults.set(true, forKey: didRegisterKey)
            return
        }

        do {
            try service.register()
            defaults.set(true, forKey: didRegisterKey)
            NSLog("[lidawake] set to open at login, status=\(service.status.rawValue)")
        } catch let e as NSError {
            // Left UNFLAGGED on purpose, so a transient failure is retried on the
            // next launch. This cannot resurrect a setting the user turned off:
            // that state is only reachable after a registration that succeeded and
            // therefore already set the flag.
            //
            // Non-fatal by design either way. Failing to open at login is an
            // inconvenience; it must never block arming or raise an error at
            // someone who was only trying to keep their Mac awake.
            NSLog("[lidawake] open-at-login registration failed: \(e.localizedDescription) code=\(e.code)")
        }
    }

    /// Drop the "Open at Login" entry. Part of Uninstall — leaving it behind would
    /// keep a deleted app listed in System Settings › General › Login Items.
    ///
    /// "Never registered" counts as success: most users uninstalling will never
    /// have reached `registerOnce()`, and reporting that as a failure would send
    /// them hunting in System Settings for an entry that was never there.
    @discardableResult
    static func unregister() -> Bool {
        let service = SMAppService.mainApp
        guard service.status != .notRegistered else { return true }
        do {
            try service.unregister()
            return true
        } catch let e as NSError {
            NSLog("[lidawake] open-at-login unregister failed: \(e.localizedDescription) code=\(e.code)")
            return false
        }
    }
}
