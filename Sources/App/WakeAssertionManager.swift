import Foundation
import IOKit.pwr_mgt

/// Holds IOKit power assertions while armed, and lets them be reconciled LIVE:
///  - PreventUserIdleSystemSleep, ALWAYS while armed: lidawake keeps the Mac awake
///    with the lid open too, and that is not a setting. It overlaps rather than
///    complements the helper's `pmset disablesleep` and the heartbeat's
///    `.userInitiated` activity, which disables idle sleep as well — this is the
///    one that is meant to, so the heartbeat can stop doing it without changing
///    what the user gets.
///  - PreventUserIdleDisplaySleep, only with "Keep the screen on".
/// `apply(screenOn:)` is idempotent, so the app can call it any time settings
/// change — no disarm/re-arm needed.
final class WakeAssertionManager {
    private var systemID: IOPMAssertionID = 0
    private var displayID: IOPMAssertionID = 0
    private var systemHeld = false
    private var displayHeld = false

    /// Reconcile the held assertions to the desired state. Safe to call repeatedly.
    func apply(screenOn: Bool) {
        setSystem(true)
        setDisplay(screenOn)
    }

    func release() {
        setSystem(false)
        setDisplay(false)
    }

    private func setSystem(_ on: Bool) {
        guard on != systemHeld else { return }
        if on {
            let reason = "\(LidAwakeIDs.appBundleID): keep awake while armed" as CFString
            if IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &systemID) == kIOReturnSuccess {
                systemHeld = true
            }
        } else {
            IOPMAssertionRelease(systemID); systemHeld = false; systemID = 0
        }
    }

    private func setDisplay(_ on: Bool) {
        guard on != displayHeld else { return }
        if on {
            let reason = "\(LidAwakeIDs.appBundleID): keep the screen on while armed" as CFString
            if IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &displayID) == kIOReturnSuccess {
                displayHeld = true
            }
        } else {
            IOPMAssertionRelease(displayID); displayHeld = false; displayID = 0
        }
    }
}
