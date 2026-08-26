import Foundation

/// Auto-disarms when the Mac gets hot. Closing the lid blocks the main vent
/// (it's in the hinge), so sustained load can cook the machine. We trip only on
/// .serious/.critical — on Apple Silicon .fair already means mild throttling and
/// would false-trigger under normal sustained load.
final class ThermalGuard {
    private var obs: NSObjectProtocol?
    var onOverheat: (() -> Void)?   // invoked on the main thread

    /// Warmest state seen since the last `resetPeak()`. The guard only ever
    /// reacted to heat; the post-wake summary needs to remember it too.
    private(set) var peak: ProcessInfo.ThermalState = .nominal

    /// Start a fresh high-water mark, seeded with where we are right now.
    func resetPeak() { peak = ProcessInfo.processInfo.thermalState }

    func start() {
        obs = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.evaluate() }
        evaluate()
    }

    func stop() {
        if let obs { NotificationCenter.default.removeObserver(obs) }
        obs = nil
    }

    private func evaluate() {
        let now = ProcessInfo.processInfo.thermalState
        if now.rawValue > peak.rawValue { peak = now }
        switch now {
        case .serious, .critical:
            NSLog("[lidawake] thermal \(now.rawValue) -> auto-disarm")
            onOverheat?()
        case .nominal, .fair:
            break
        @unknown default:
            break
        }
    }
}
