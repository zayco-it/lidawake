import Foundation

/// App side of the hang watchdog. The helper side is Sources/Helper/Watchdog.swift.
///
/// WHY THE MAIN RUN LOOP, SPECIFICALLY — this is the whole design, not a detail.
/// Every other safety mechanism we have runs there: ThermalGuard's notification
/// observer (`queue: .main`), PowerPolicy's IOPS source (`CFRunLoopGetMain`), and
/// LidMonitor's timer. One wedged main thread takes all three down at once.
/// Beating from a background queue would keep reassuring the helper while the
/// thermal and battery cut-offs were dead — a watchdog certifying exactly the
/// wrong thing. The heartbeat has to share the liveness it is vouching for, so it
/// lives where the guards live.
///
/// `.common` mode, like LidMonitor: menu tracking and NSAlert's modal run loop are
/// normal app life and must not read as a hang.
final class Heartbeat {

    private var timer: Timer?
    private var activity: NSObjectProtocol?

    /// Sends one check-in. Called on the main thread.
    var onBeat: (() -> Void)?

    func start() {
        guard timer == nil else { return }

        // An LSUIElement app with no open windows is an App Nap candidate, and App
        // Nap coalesces timers — napped check-ins arrive late and read as a hang,
        // which would sleep the Mac under a perfectly healthy app. Being armed IS a
        // user-initiated ongoing activity, so declare it and opt out.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "lidawake is keeping this Mac awake")

        let t = Timer(timeInterval: LidAwakeWatchdog.heartbeatInterval, repeats: true) {
            [weak self] _ in self?.onBeat?()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        onBeat?()   // check in now — don't leave the first interval silent
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }
}
