import Foundation
import IOKit.pwr_mgt

/// Holds IOKit power assertions while armed, and lets them be reconciled LIVE:
///  - PreventUserIdleSystemSleep blocks *idle* system sleep with the lid OPEN
///    (complementary to the helper's `pmset disablesleep`, which covers lid-close).
///  - PreventUserIdleDisplaySleep optionally keeps the screen on while the lid is
///    open (the "keep the screen on too" setting).
/// `apply(systemAwake:screenOn:)` is idempotent, so the app can call it any time
/// settings change — no disarm/re-arm needed.
final class WakeAssertionManager {
    private var systemID: IOPMAssertionID = 0
    private var displayID: IOPMAssertionID = 0
    private var systemHeld = false
    private var displayHeld = false

    /// Reconcile the held assertions to the desired state. Safe to call repeatedly.
    func apply(systemAwake: Bool, screenOn: Bool) {
        setSystem(systemAwake)
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
