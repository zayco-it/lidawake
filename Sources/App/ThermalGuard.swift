import Foundation

/// Auto-disarms when the Mac gets hot. Closing the lid blocks the main vent
/// (it's in the hinge), so sustained load can cook the machine. We trip only on
/// .serious/.critical — on Apple Silicon .fair already means mild throttling and
/// would false-trigger under normal sustained load.
final class ThermalGuard {
    private var obs: NSObjectProtocol?
    var onOverheat: (() -> Void)?   // invoked on the main thread

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
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            NSLog("[lidawake] thermal \(ProcessInfo.processInfo.thermalState.rawValue) -> auto-disarm")
            onOverheat?()
        case .nominal, .fair:
            break
        @unknown default:
            break
        }
    }
}
