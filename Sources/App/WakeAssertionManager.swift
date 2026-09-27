import Foundation
import IOKit.pwr_mgt

/// Holds IOKit power assertions while armed, and lets them be reconciled LIVE:
///  - PreventUserIdleSystemSleep, ALWAYS while armed: lidawake keeps the Mac awake
///    with the lid open too, and that is not a setting. It overlaps rather than
///    complements the helper's `pmset disablesleep` and the heartbeat's
///    `.userInitiated` activity, which disables idle sleep as well — this is the
///    one that is meant to, so the heartbeat can stop doing it without changing
///    what the user gets.
///  - PreventUserIdleDisplaySleep, only with "Keep the screen on" AND the lid
///    open — the switch sits under "When the lid is open" and means only that.
///    Held with the lid shut it kept an external monitor lit all night in
///    clamshell: nobody reading that heading expects it.
/// Both inputs are remembered, so the switch and the lid can each change on their
/// own and every call reconciles to "switch on and lid open". Idempotent — the app
/// calls it on any settings change, no disarm/re-arm needed.
final class WakeAssertionManager {
    private var systemID: IOPMAssertionID = 0
    private var displayID: IOPMAssertionID = 0
    private var systemHeld = false
    private var displayHeld = false

    private var keepScreenOn = false
    private var lidClosed = false
    /// Between apply() and release() — armed. A lid change outside it is only
    /// recorded: acting on it would take back assertions release() just dropped.
    private var active = false

    /// Armed, or "Keep the screen on" changed. Safe to call repeatedly.
    func apply(keepScreenOn: Bool) {
        self.keepScreenOn = keepScreenOn
        active = true
        reconcile()
    }

    /// The lid moved. Call before apply() at arming, with the lid as it is now.
    func setLidClosed(_ closed: Bool) {
        lidClosed = closed
        if active { reconcile() }
    }

    func release() {
        active = false
        setSystem(false)
        setDisplay(false)
    }

    private func reconcile() {
        setSystem(true)
        setDisplay(keepScreenOn && !lidClosed)
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
