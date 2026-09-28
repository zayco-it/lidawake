// The two ways lidawake can be on, and what a click on either does.
//
// "Keep awake until I turn it off" is what the app has always done. "Keep awake
// until it goes quiet" is the SAME arming — the helper's `disablesleep 1`, the
// heartbeat, every guard — with the quiet detector (IdleWatcher) running as
// well. So switching between them while on touches nothing but the detector,
// and clicking the mode that is already on turns lidawake off, as a checked
// menu item does everywhere on macOS. Nothing is persisted: the app is off at
// launch, as it always was. Pure, so the selftest walks every transition
// without a helper or a menu. Design: attended-mac-spec.md §11.1.

import Foundation

enum ArmMode: CaseIterable {
    case off, untilOff, untilQuiet

    var isOn: Bool { self != .off }

    /// The menu item's title. Both items are always shown; the checkmark is the state.
    var menuTitle: String {
        switch self {
        case .off:        return ""
        case .untilOff:   return "Keep awake until I turn it off"
        case .untilQuiet: return "Keep awake until it goes quiet"
        }
    }
}

/// What clicking a mode item does. `helper` is the only part that reaches the
/// root helper; `detector` the only part that starts or stops IdleWatcher.
struct ModeTransition: Equatable {
    enum Helper: Equatable { case none, arm, disarm }
    enum Detector: Equatable { case none, start, stop }

    let mode: ArmMode
    let helper: Helper
    let detector: Detector

    static func clicked(_ item: ArmMode, while current: ArmMode) -> ModeTransition {
        precondition(item != .off, "off is not a menu item")
        if item == current {            // the checked item: off
            return ModeTransition(mode: .off, helper: .disarm,
                                  detector: current == .untilQuiet ? .stop : .none)
        }
        if current == .off {            // off → on, in the mode clicked
            return ModeTransition(mode: item, helper: .arm,
                                   detector: item == .untilQuiet ? .start : .none)
        }
        // On in the other mode: switch. The helper is not touched.
        return ModeTransition(mode: item, helper: .none,
                              detector: item == .untilQuiet ? .start : .stop)
    }
}

/// The status line under the two items while lidawake is on. `quietAge` is the
/// detector's current quiet age, nil when it is not running; `quietMinutes` is
/// the window, derived rather than typed so the sentence stays true under the
/// test hook that shortens it.
enum StatusLine {
    static func text(mode: ArmMode, quietAge: TimeInterval?, quietMinutes: Int) -> String {
        switch mode {
        case .off:      return "Off \u{2014} your Mac will sleep normally"
        case .untilOff: return "On \u{2014} you can close the lid"
        case .untilQuiet:
            let age: String
            if let quietAge, quietAge >= 60 { age = "quiet for \(Int(quietAge / 60)) min" }
            else { age = "active now" }
            return "On \u{2014} stops after \(quietMinutes) min of quiet (\(age))"
        }
    }
}
