import Foundation
import IOKit

/// Watches the laptop lid (clamshell) state while armed and fires `onLidClosed`
/// on the open→closed edge. We poll once a second by reading IOPMrootDomain's
/// `AppleClamshellState` (readable without root) rather than registering an
/// IOKit interest notification — simpler, no C-callback bridging, and 1 Hz is
/// negligible. Edge-triggered: each close fires exactly once.
final class LidMonitor {
    private var timer: Timer?
    private var lastClosed = false
    var onLidClosed: (() -> Void)?   // called on the main thread

    func start() {
        guard timer == nil else { return }
        lastClosed = Self.isLidClosed()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)   // keep firing during menu tracking
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastClosed = false
    }

    private func tick() {
        let closed = Self.isLidClosed()
        if closed && !lastClosed { onLidClosed?() }   // open -> closed edge only
        lastClosed = closed
    }

    /// true == lid closed. false if unavailable (e.g., a desktop Mac with no lid).
    static func isLidClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        guard let cf = IORegistryEntryCreateCFProperty(
                service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() else { return false }
        return (cf as? Bool) ?? false
    }
}
