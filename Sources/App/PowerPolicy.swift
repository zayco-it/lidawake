import Foundation
import IOKit.ps

struct PowerState {
    let isOnAC: Bool
    let percent: Int      // -1 == unknown / battery-less Mac
    let charging: Bool
}

/// Snapshot of the current power source. On a battery-less Mac, returns
/// isOnAC=true / percent=-1 ("no constraint").
func readPowerState() -> PowerState {
    guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
        return PowerState(isOnAC: true, percent: -1, charging: false)
    }
    // "Get" rule: providing-type string is owned by the snapshot, not us.
    let providing = IOPSGetProvidingPowerSourceType(snap).takeUnretainedValue() as String
    let onAC = (providing == kIOPSACPowerValue)

    guard let list = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef] else {
        return PowerState(isOnAC: onAC, percent: -1, charging: false)
    }
    for src in list {
        guard let d = IOPSGetPowerSourceDescription(snap, src)?.takeUnretainedValue() as? [String: Any],
              d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
        return PowerState(isOnAC: onAC,
                          percent: d[kIOPSCurrentCapacityKey] as? Int ?? -1,
                          charging: d[kIOPSIsChargingKey] as? Bool ?? false)
    }
    return PowerState(isOnAC: onAC, percent: -1, charging: false)
}

/// Enforces the battery policy from user Settings (default: AC only, with a 20%
/// floor). While armed, a live power-source callback re-checks and trips
/// `onViolation` on a policy violation (e.g. unplugged when battery isn't allowed).
final class PowerPolicy {
    var onViolation: ((String) -> Void)?   // invoked on the main thread; carries the turn-off reason
    private var runLoopSource: CFRunLoopSource?

    /// True if it's currently safe to be armed; `reason` explains any refusal.
    static func armingAllowed() -> (ok: Bool, reason: String?) {
        let s = readPowerState()
        if !Settings.allowOnBattery && !s.isOnAC {
            return (false, "Your Mac is on battery. Plug it in, or turn on \u{201C}Keep going on battery power\u{201D} in Settings.")
        }
        let floor = Settings.batteryFloorPercent
        if s.percent >= 0 && s.percent < floor {
            return (false, "Battery is below \(floor)%. Charge up a bit, then try again.")
        }
        return (true, nil)
    }

    /// If it's no longer safe/allowed to stay armed, a short reason phrased for a
    /// "lidawake turned off because ___" message — distinguishing an unplug from a
    /// battery-floor trip (they look the same to the monitor but read very
    /// differently to the user). nil if it's still fine to stay armed.
    static func disarmReason() -> String? {
        let s = readPowerState()
        return disarmReason(onAC: s.isOnAC, percent: s.percent,
                            allowOnBattery: Settings.allowOnBattery, floor: Settings.batteryFloorPercent)
    }

    /// Pure decision behind `disarmReason()` — split out so it's unit-testable
    /// without real hardware. Unplug-when-not-allowed takes precedence over floor.
    static func disarmReason(onAC: Bool, percent: Int, allowOnBattery: Bool, floor: Int) -> String? {
        if !allowOnBattery && !onAC { return "it was unplugged from power" }
        if percent >= 0 && percent < floor { return "the battery reached your \(floor)% limit" }
        return nil
    }

    /// Begin watching live AC/battery changes; fire `onViolation` on a trip.
    func startMonitoring() {
        guard runLoopSource == nil else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        // The callback must be a capture-less C function; context carries `self`.
        guard let src = IOPSNotificationCreateRunLoopSource({ raw in
            guard let raw else { return }
            let me = Unmanaged<PowerPolicy>.fromOpaque(raw).takeUnretainedValue()
            if let reason = PowerPolicy.disarmReason() { me.onViolation?(reason) }
        }, ctx)?.takeRetainedValue() else { return }
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
    }

    func stopMonitoring() {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        runLoopSource = nil
    }
}
