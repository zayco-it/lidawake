import Foundation

/// The actual privileged work, exposed over XPC. Runs as root. The single
/// privileged operation is `pmset -a disablesleep 0|1`; there is deliberately
/// nothing else here to abuse.
final class HelperImplementation: NSObject, LidAwakeHelperProtocol {

    /// Whether THIS client currently holds the awake-lock. Read by the
    /// connection's invalidation handler to power the dead man's switch.
    ///
    /// Written from the XPC queue (arm/disarm, heartbeat) and from the watchdog
    /// queue (a trip), read from the invalidation handler on a third — hence the
    /// lock. It is one Bool, but it is the Bool that decides whether the Mac is
    /// left unable to sleep.
    private let stateLock = NSLock()
    private var armedFlag = false

    var disableSleepActive: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return armedFlag
    }

    private func setActive(_ active: Bool) {
        stateLock.lock(); armedFlag = active; stateLock.unlock()
    }

    /// SAFETY LAYER 3 — see Watchdog.swift. Armed alongside `disablesleep`, fed by
    /// the client's heartbeats, and the only thing still watching if the client
    /// wedges with its connection held open. Wired in init rather than made `lazy`:
    /// lazy initialisation isn't thread-safe, and this is reached from the XPC queue.
    private let watchdog = Watchdog()

    override init() {
        super.init()
        watchdog.onTimeout = { [weak self] in self?.watchdogTripped() }
    }

    /// Run pmset with the given args as root. Returns the exit status,
    /// or -1 if the process couldn't be launched.
    @discardableResult
    static func runPmset(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = args
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus }
        catch { return -1 }
    }

    func setDisableSleep(_ disable: Bool, reply: @escaping (String?) -> Void) {
        switch HelperImplementation.runPmset(["-a", "disablesleep", disable ? "1" : "0"]) {
        case 0:
            setActive(disable)
            // Start watching from the moment we arm, not from the first check-in.
            if disable { watchdog.refresh() } else { watchdog.cancel() }
            NSLog("[lidawake-helper] disablesleep -> \(disable ? 1 : 0)")
            reply(nil)
        case -1:
            reply("failed to run pmset")
        case let status:
            reply("pmset exited with status \(status)")
        }
    }

    /// Sleep the display immediately (used when the lid closes while armed, so a
    /// closed lid isn't left backlit). Runs as root via the helper to avoid any
    /// permission ambiguity. The system stays awake; only the panel sleeps.
    func sleepDisplayNow(reply: @escaping (String?) -> Void) {
        switch HelperImplementation.runPmset(["displaysleepnow"]) {
        case 0:
            NSLog("[lidawake-helper] displaysleepnow")
            reply(nil)
        case -1:
            reply("failed to run pmset displaysleepnow")
        case let status:
            reply("pmset displaysleepnow exited with status \(status)")
        }
    }

    func helperVersion(reply: @escaping (String) -> Void) {
        reply(LidAwakeIDs.helperVersion)
    }

    /// Watchdog check-in. Only an armed client can push the deadline out — once we
    /// have given up on one, nothing it says brings it back; re-arming is the
    /// user's call, made through setDisableSleep.
    /// The reply is our own view of its state, so a client that was wedged when we
    /// tripped can stop claiming to be on.
    func heartbeat(reply: @escaping (Bool) -> Void) {
        let active = disableSleepActive
        if active { watchdog.refresh() }
        reply(active)
    }

    /// SAFETY LAYER 2 — the connection dropped, so the client died (crash,
    /// force-kill, unclean quit). Called from the listener's invalidation handler.
    ///
    /// Cancelling the watchdog here is not tidiness, it is required: a deadline
    /// belonging to a client that no longer exists must never fire later and pull
    /// `disablesleep` out from under whoever armed in the meantime. A force-kill
    /// followed by a relaunch and re-arm inside the timeout is an ordinary thing
    /// for a user to do.
    func clientGone() {
        watchdog.cancel()
        guard disableSleepActive else {
            NSLog("[lidawake-helper] connection invalidated")
            return
        }
        NSLog("[lidawake-helper] client gone while armed — restoring sleep (dead man's switch)")
        HelperImplementation.runPmset(["-a", "disablesleep", "0"])
        setActive(false)
    }

    /// SAFETY LAYER 3 — the client stopped checking in. Restore normal sleep on our
    /// own authority; this is the entire point. Runs on the watchdog queue.
    private func watchdogTripped() {
        NSLog("[lidawake-helper] no check-in for \(Int(LidAwakeWatchdog.timeout))s — client unresponsive, restoring sleep (watchdog)")
        HelperImplementation.runPmset(["-a", "disablesleep", "0"])
        setActive(false)
    }
}
