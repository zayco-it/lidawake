// The lid-closed session, and the one sentence it turns into.
//
// A session runs from the lid closing while lidawake is armed to the lid opening
// again. It exists to answer the question these tools never answer: "was it
// actually awake the whole time, and what did that cost?" One blogger verified a
// competitor by logging a timestamp every five seconds and checking for gaps.
// This says it without the user doing anything.
//
// If lidawake disarms mid-session — thermal cut-off, battery floor, the user
// switching it off — the session is CANCELLED, not reported. Two reasons: the
// Mac then slept, so a duration measured to lid-open would be a lie; and
// autoDisarm() already tells the user why it stopped, so a second message would
// be repeating a worse version of it.

import Foundation

struct WakeSummary {

    /// Sessions shorter than this are not worth a notification. Someone closing
    /// the lid to move desks does not need a report. Hard-coded on purpose —
    /// this is not a setting, and the moment it becomes one the app has started
    /// down the road T2 exists to avoid.
    static let minimumReportable: TimeInterval = 5 * 60

    private var start: Date?
    private var startBattery: Int = -1

    var isRunning: Bool { start != nil }

    mutating func begin(battery: Int) {
        start = Date()
        startBattery = battery
    }

    mutating func cancel() {
        start = nil
        startBattery = -1
    }

    /// End the session and render it, or nil if there is nothing worth saying.
    /// `peakThermal` is the warmest state seen while the lid was shut.
    mutating func finish(battery: Int, peakThermal: ProcessInfo.ThermalState) -> (title: String, body: String)? {
        guard let start else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        let from = startBattery
        cancel()
        guard elapsed >= Self.minimumReportable else { return nil }

        var parts = [Self.duration(elapsed), Self.thermal(peakThermal)]
        // Only when we have both ends and the level actually moved. A desktop Mac
        // reports -1, and "battery 87 → 87%" is noise.
        if from >= 0, battery >= 0, from != battery {
            parts.append("battery \(from) → \(battery)%")
        }
        return ("Your Mac stayed awake", parts.joined(separator: " · "))
    }

    /// "7 h 43 min", "43 min", "2 h" — never "0 h 43 min" or seconds.
    static func duration(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        let h = total / 3600, m = (total % 3600) / 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h) h" }
        return "\(h) h \(m) min"
    }

    /// Plain language, not degrees.
    ///
    /// The plan asked for "max 76 °C". There is no temperature anywhere in this
    /// app and there cannot be one honestly: ThermalGuard reads
    /// ProcessInfo.thermalState, a four-value enum, and a real figure on Apple
    /// Silicon needs private SMC/IOHIDEventSystemClient calls — which would
    /// undermine the notarized, auditable, read-every-line story the product is
    /// sold on. This says the same thing in the customer's words, which the
    /// positioning notes ask for anyway.
    static func thermal(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal:  return "stayed cool"
        case .fair:     return "warmed up a little"
        case .serious:  return "got hot"
        case .critical: return "got very hot"
        @unknown default: return "stayed cool"
        }
    }
}
