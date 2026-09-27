// Self-test for WakeAssertionManager: "Keep the screen on" holds the display awake
// only while the lid is open, and lid-open wakefulness is unconditional while armed.
// Compiles with the REAL source and asks macOS — IOPMCopyAssertionsByProcess, for
// this process — what is actually held, rather than trusting the manager's own
// flags. The assertions it takes last only as long as the run, milliseconds.
// Dev-only; NOT part of the app build.
//
//   swiftc -O -parse-as-library tools/wakeassertion-selftest.swift \
//       Sources/App/WakeAssertionManager.swift Sources/Shared/HelperProtocol.swift \
//       -o /tmp/lidawake-wakeassertion-selftest && /tmp/lidawake-wakeassertion-selftest
//
// Why a test: before this, the screen assertion was held whenever armed, lid open or
// shut, so an external monitor in clamshell never slept — and nothing would have
// noticed if a later change put that back.

import Foundation
import IOKit.pwr_mgt

var failures = 0
func check(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { print("  PASS  \(label)") }
    else { print("  FAIL  \(label) \(detail())"); failures += 1 }
}

/// This process's assertions, as macOS reports them: (type, name) pairs.
func held() -> [(type: String, name: String)] {
    var byPid: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&byPid) == kIOReturnSuccess,
          let dict = byPid?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
    let mine = dict.first { $0.key.int32Value == getpid() }?.value ?? []
    return mine.map { ($0[kIOPMAssertionTypeKey] as? String ?? "", $0[kIOPMAssertionNameKey] as? String ?? "") }
}
func count(_ type: String) -> Int {
    held().filter { $0.type == type && $0.name.hasPrefix(LidAwakeIDs.appBundleID) }.count
}
let SYSTEM  = kIOPMAssertionTypePreventUserIdleSystemSleep as String
let DISPLAY = kIOPMAssertionTypePreventUserIdleDisplaySleep as String

func expect(_ label: String, system: Int, display: Int) {
    let s = count(SYSTEM), d = count(DISPLAY)
    check("\(label) → system \(system), screen \(display)", s == system && d == display,
          "got system \(s), screen \(d)")
}

@main struct WakeAssertionSelfTest {
    static func main() {
        let w = WakeAssertionManager()
        expect("before arming", system: 0, display: 0)

        print("switch on, lid open")
        w.setLidClosed(false)
        w.apply(keepScreenOn: true)
        expect("armed", system: 1, display: 1)
        w.apply(keepScreenOn: true)
        expect("applied again — nothing doubles", system: 1, display: 1)

        print("the lid follows")
        w.setLidClosed(true)
        expect("lid closes — screen let go, Mac kept awake", system: 1, display: 0)
        w.setLidClosed(true)
        expect("closed again — still let go", system: 1, display: 0)
        w.setLidClosed(false)
        expect("lid opens — screen taken back", system: 1, display: 1)

        print("the switch, with the lid either way")
        w.apply(keepScreenOn: false)
        expect("switch off, lid open", system: 1, display: 0)
        w.setLidClosed(true); w.setLidClosed(false)
        expect("switch off, lid shut and opened — screen never taken", system: 1, display: 0)
        w.setLidClosed(true)
        w.apply(keepScreenOn: true)
        expect("switch on while the lid is shut — not yet", system: 1, display: 0)
        w.setLidClosed(false)
        expect("…then the lid opens — now", system: 1, display: 1)

        print("disarm")
        w.release()
        expect("released", system: 0, display: 0)
        w.setLidClosed(true); w.setLidClosed(false)
        expect("a lid change after disarm takes nothing back", system: 0, display: 0)

        print("armed with the lid already shut")
        let w2 = WakeAssertionManager()
        w2.setLidClosed(true)
        w2.apply(keepScreenOn: true)
        expect("switch on, lid shut at arming", system: 1, display: 0)
        w2.setLidClosed(false)
        expect("lid opens", system: 1, display: 1)
        w2.release()
        expect("released", system: 0, display: 0)

        print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
