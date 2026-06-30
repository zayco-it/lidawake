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
