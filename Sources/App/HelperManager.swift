import Foundation
import ServiceManagement

/// Registers / inspects / removes the root LaunchDaemon via SMAppService.
/// Registration is instant and prompt-free; the user approves the daemon once
/// in System Settings > General > Login Items (a GUI admin prompt on a Standard
/// account), after which the app talks to it over XPC with no further prompts.
final class HelperManager {

    private var service: SMAppService { SMAppService.daemon(plistName: LidAwakeIDs.helperPlistName) }

    enum State { case enabled, requiresApproval, notRegistered, notFound, unknown }

    var state: State {
        switch service.status {
        case .enabled:          return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered:    return .notRegistered
        case .notFound:         return .notFound
        @unknown default:       return .unknown
        }
    }

    /// Make sure the daemon is registered. Safe to call repeatedly:
    ///   notRegistered  -> register() (then usually requiresApproval)
    ///   requiresApproval -> open System Settings so the user can flip it on
    ///   enabled        -> nothing to do
    /// Returns the state after the attempt.
    @discardableResult
    func ensureRegistered() -> State {
        switch state {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound, .unknown:
            do {
                try service.register()
                NSLog("[lidawake] helper registered, status=\(service.status.rawValue)")
            } catch let e as NSError {
                // code 1   (EPERM): stale job in /Library, or unstable signing identity.
                // code 108 (bad plist): legacy SMJobBless keys present, or wrong plist name.
                NSLog("[lidawake] helper register failed: \(e.localizedDescription) code=\(e.code)")
            }
            return state
        }
    }

    func unregister() {
        do { try service.unregister() }
        catch { NSLog("[lidawake] helper unregister failed: \(error)") }
    }

    /// Opens System Settings ▸ Login Items — on a Standard account this is the
    /// only no-admin way to re-enable a stopped daemon, so it's the last-resort
    /// fallback if the helper somehow doesn't self-restart.
    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
