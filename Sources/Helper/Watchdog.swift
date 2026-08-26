import Foundation

/// SAFETY LAYER 3 — the hang watchdog.
///
/// Layer 1 (`resetDisableSleep`, Helper/main.swift) covers a helper restart.
/// Layer 2 (the invalidation handler in HelperDelegate) covers a client that
/// DIED — crash, force-kill, unclean quit.
///
/// Neither covers a client that is alive but wedged: spinning, deadlocked, or
/// stopped in a debugger. Its XPC connection stays open, so nothing fires and
/// `disablesleep` stays 1 with no process able to clear it.
///
/// That is the dangerous case rather than a tidy one, because ThermalGuard and
/// PowerPolicy both live in the app and both run on its main run loop: a wedged
/// app takes the thermal cut-off and the battery cut-off down with it, at the
/// exact moment the Mac has been told never to sleep. The helper is then the
/// only component still independent, and until now it wasn't watching.
///
/// So: while armed, the client checks in every `heartbeatInterval`. If check-ins
/// stop for `timeout`, this restores normal sleep on its own authority.
///
/// Threading: XPC invocations arrive on an internal queue and the timer fires on
/// `queue`, so ALL state lives on that one serial queue and needs no locking.
/// The timer uses the default (uptime) clock, which does not advance across
/// system sleep — a Mac that slept cannot wake to an already-expired deadline.
final class Watchdog {

    private let queue = DispatchQueue(label: "it.zayco.lidawake.helper.watchdog")
    private var timer: DispatchSourceTimer?

    /// Restore normal sleep. Set once at construction, before any timer exists;
    /// invoked on `queue`. Same callback shape as ThermalGuard / PowerPolicy.
    var onTimeout: (() -> Void)?

    deinit { timer?.cancel() }

    /// (Re)start the countdown. Called when the client arms — NOT on its first
    /// check-in, so the arm-to-first-heartbeat window is covered too — and again
    /// on every heartbeat after that.
    func refresh() {
        queue.async { [self] in
            let deadline = DispatchTime.now() + LidAwakeWatchdog.timeout
            if let timer {
                timer.schedule(deadline: deadline)
            } else {
                let t = DispatchSource.makeTimerSource(queue: queue)
                t.setEventHandler { [weak self] in self?.fire() }
                t.schedule(deadline: deadline)   // must be scheduled before activation
                timer = t
                t.activate()
            }
        }
    }

    /// Clean disarm, or the client went away — nothing left to watch.
    func cancel() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    /// Runs on `queue`. One-shot by design: there is no retry and no way back,
    /// because re-arming is a decision only the user gets to make.
    private func fire() {
        timer?.cancel()
        timer = nil
        onTimeout?()
    }
}
