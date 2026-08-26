import Foundation

/// Distinguishes a dead / unreachable helper (offer Repair) from a helper that
/// ran but reported a failure (just show the message).
enum HelperError {
    case unreachable(String)   // XPC connection failed — daemon down or signature mismatch
    case rejected(String)      // helper answered but reported an error (e.g. pmset)
    var message: String { switch self { case .unreachable(let m), .rejected(let m): return m } }
    var isUnreachable: Bool { if case .unreachable = self { return true }; return false }
}

/// Talks to the root helper over XPC. Validates the helper's code signature (so
/// a swapped binary can't impersonate it), and exposes both an async-style
/// completion API (for arm/disarm) and a synchronous one (for the quit-time and
/// safety-trip restores, which have no time to wait on the run loop).
///
/// Threading: `connection` is only mutated on the main thread. XPC reply blocks
/// arrive on a private queue; the async API bounces completions back to main.
final class HelperClient {

    private var connection: NSXPCConnection?
    private let helperRequirement = lidAwakeRequirement(identifier: LidAwakeIDs.helperBundleID)

    private func newConnection() -> NSXPCConnection {
        let c = NSXPCConnection(machServiceName: LidAwakeIDs.machServiceName, options: [])
        c.remoteObjectInterface = NSXPCInterface(with: LidAwakeHelperProtocol.self)
        c.setCodeSigningRequirement(helperRequirement)   // app authenticates the helper
        return c
    }

    /// The long-lived connection used for normal arm/disarm. Recreated lazily
    /// after an invalidation.
    private func activeConnection() -> NSXPCConnection {
        if let c = connection { return c }
        let c = newConnection()
        c.invalidationHandler = { [weak self] in DispatchQueue.main.async { self?.connection = nil } }
        c.interruptionHandler = { [weak self] in DispatchQueue.main.async { self?.connection = nil } }
        c.resume()
        connection = c
        return c
    }

    /// Async arm/disarm. `completion` runs on the MAIN thread:
    /// nil == success; .unreachable == helper down (offer Repair); .rejected == helper said no.
    func setDisableSleep(_ disable: Bool, completion: @escaping (HelperError?) -> Void) {
        let c = activeConnection()
        let proxy = c.remoteObjectProxyWithErrorHandler { err in
            DispatchQueue.main.async { completion(.unreachable(err.localizedDescription)) }  // connection failure -> no hang
        } as? LidAwakeHelperProtocol
        guard let proxy else { completion(.unreachable("Could not reach the helper.")); return }
        proxy.setDisableSleep(disable) { msg in
            DispatchQueue.main.async { completion(msg.map { .rejected($0) }) }
        }
    }

    /// Ask the helper to sleep the display now (lid closed while armed). Completion on main.
    func sleepDisplayNow(completion: @escaping (String?) -> Void) {
        let c = activeConnection()
        let proxy = c.remoteObjectProxyWithErrorHandler { err in
            DispatchQueue.main.async { completion(err.localizedDescription) }
        } as? LidAwakeHelperProtocol
        guard let proxy else { completion("could not obtain helper proxy"); return }
        proxy.sleepDisplayNow { msg in
            DispatchQueue.main.async { completion(msg) }
        }
    }

    /// Read-only check that the RUNNING helper is both reachable AND at least as new
    /// as the one inside this app bundle. Changes no state; used by the background
    /// warm-up after an update. Completion on main.
    ///
    /// Reachability alone is the wrong question, and that distinction is
    /// load-bearing. Replacing the app bundle does NOT disturb an already-running
    /// LaunchDaemon: launchd's job is untouched and the old helper process keeps its
    /// already-mapped image, so it goes on answering XPC — with a live mach service —
    /// until the machine reboots. Its signature still satisfies our `csreq`, because
    /// that pins team and identifier but deliberately not version. An updated app
    /// therefore keeps talking to the PREVIOUS helper binary indefinitely, and every
    /// helper-side change in the update silently never takes effect.
    ///
    /// Observed 2026-08-26 on a real in-place install: bundle replaced at 12:06, the
    /// daemon serving it had been up since 19:51 the day before and stayed up.
    func probeCurrent(completion: @escaping (Bool) -> Void) {
        helperVersion { version in          // already completes on main
            guard let version else { completion(false); return }
            completion(lidAwakeVersionAtLeast(version, LidAwakeIDs.helperVersion))
        }
    }

    /// Reads the RUNNING helper's version (which is not necessarily the one in this
    /// bundle — after an update launchd can still be running the previous binary).
    /// Completion on main; nil if it couldn't be reached.
    func helperVersion(completion: @escaping (String?) -> Void) {
        let c = activeConnection()
        let proxy = c.remoteObjectProxyWithErrorHandler { _ in
            DispatchQueue.main.async { completion(nil) }
        } as? LidAwakeHelperProtocol
        guard let proxy else { completion(nil); return }
        proxy.helperVersion { v in DispatchQueue.main.async { completion(v) } }
    }

    /// Hang-watchdog check-in. Completion on main:
    ///   true  == the helper still has sleep disabled for us (the normal case)
    ///   false == it gave up on us and restored sleep; we are not on any more
    ///   nil   == the call didn't get through (helper down, mid-reconnect). That is
    ///            NOT a trip and must never be treated as one — an unreachable
    ///            helper is a helper that isn't holding sleep disabled either.
    func heartbeat(completion: @escaping (Bool?) -> Void) {
        let c = activeConnection()
        let proxy = c.remoteObjectProxyWithErrorHandler { _ in
            DispatchQueue.main.async { completion(nil) }
        } as? LidAwakeHelperProtocol
        guard let proxy else { completion(nil); return }
        proxy.heartbeat { active in DispatchQueue.main.async { completion(active) } }
    }

    /// Blocking restore for app termination and safety trips, where async has no
    /// time to run. Uses a dedicated short-lived connection and signals the
    /// semaphore from the XPC queue (never from main), so it cannot deadlock the
    /// main thread it is called on. Returns true if pmset reported success.
    @discardableResult
    func setDisableSleepSync(_ disable: Bool, timeout: TimeInterval = 2) -> Bool {
        let c = newConnection()
        c.resume()
        let sema = DispatchSemaphore(value: 0)
        var ok = false
        let proxy = c.remoteObjectProxyWithErrorHandler { _ in sema.signal() } as? LidAwakeHelperProtocol
        proxy?.setDisableSleep(disable) { msg in ok = (msg == nil); sema.signal() }
        _ = sema.wait(timeout: .now() + timeout)
        c.invalidate()
        return ok
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }
}
