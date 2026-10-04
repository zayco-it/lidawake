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

    /// The only place the app explains the two modes: the tooltip on each item.
    ///
    /// BOTH say where an agent running in a loop belongs — the question the
    /// people who use lidawake actually have. An agent is seen by its request
    /// to stay awake, which Claude Code makes for every turn and for nothing in
    /// between (E13a, spec §11.6.5): so it keeps quiet mode on for as long as
    /// its checks are less than the window apart, and a longer wait is what the
    /// other mode is for. Claude Code is NAMED because it is the one that was
    /// measured; "AI agents" in general would be a promise nobody checked.
    /// `quietMinutes` is derived, never typed.
    func toolTip(quietMinutes: Int) -> String {
        switch self {
        case .off:
            return ""
        case .untilOff:
            return "Stays on until you turn it off, or until your Mac gets too hot or the battery runs low. "
                + "Use this for anything that waits longer than \(quietMinutes) minutes between bursts of work."
        case .untilQuiet:
            return "Turns itself off \(quietMinutes) minutes after the last sign of activity: you using the Mac, "
                + "sound or video playing, one of your programs working hard or asking the Mac to stay awake, "
                + "the graphics chip, or steady network traffic. "
                + "An AI agent that asks the Mac to stay awake while it works \u{2014} Claude Code does \u{2014} "
                + "keeps this on, provided it checks in more often than every \(quietMinutes) minutes."
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
/// test hook that shortens it. `heldBy` is whoever is asking the Mac to stay
/// awake right now: named here because whoever opens the menu has just touched
/// the Mac, so the quiet age alone always reads "active now" — and a program
/// that never lets go would keep quiet mode on with nothing to say why.
enum StatusLine {
    static func text(mode: ArmMode, quietAge: TimeInterval?, quietMinutes: Int, heldBy: String?) -> String {
        switch mode {
        case .off:      return "Off \u{2014} your Mac will sleep normally"
        case .untilOff: return "On \u{2014} you can close the lid"
        case .untilQuiet:
            let age: String
            if let heldBy { age = "kept on by \(heldBy)" }
            else if let quietAge, quietAge >= 60 { age = "quiet for \(Int(quietAge / 60)) min" }
            else { age = "active now" }
            return "On \u{2014} stops after \(quietMinutes) min of quiet (\(age))"
        }
    }
}
