import Foundation
import IOKit.pwr_mgt

/// Holds IOKit power assertions while armed:
///  - PreventUserIdleSystemSleep blocks *idle* system sleep with the lid OPEN
///    (complementary to the helper's `pmset disablesleep`, which covers lid-close).
///  - PreventUserIdleDisplaySleep optionally keeps the screen on while the lid is
///    open (the "keep the screen on too" setting).
/// We hold the system assertion (and optionally the display one) while armed.
final class WakeAssertionManager {
    private var systemID: IOPMAssertionID = 0
    private var displayID: IOPMAssertionID = 0
    private var systemHeld = false
    private var displayHeld = false

    /// Acquire the system-sleep assertion, and — if requested — the display one.
    func acquire(keepDisplayOn: Bool) {
        if !systemHeld {
            let reason = "\(LidAwakeIDs.appBundleID): keep awake while armed" as CFString
            if IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &systemID) == kIOReturnSuccess {
                systemHeld = true
            }
        }
        if keepDisplayOn && !displayHeld {
            let reason = "\(LidAwakeIDs.appBundleID): keep the screen on while armed" as CFString
            if IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &displayID) == kIOReturnSuccess {
                displayHeld = true
            }
        }
    }

    func release() {
        if systemHeld { IOPMAssertionRelease(systemID); systemHeld = false; systemID = 0 }
        if displayHeld { IOPMAssertionRelease(displayID); displayHeld = false; displayID = 0 }
    }
}
