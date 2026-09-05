// Headless self-test for the battery policy decision (PowerPolicy.disarmReason).
// Compiles with the REAL source — so it tests the shipping code, not a copy — and
// drives the pure overload, so it needs no hardware, no charger and no battery.
// Dev-only; NOT part of the app build.
//
//   swiftc -O tools/power-selftest.swift \
//       Sources/App/PowerPolicy.swift Sources/App/Settings.swift \
//       -framework AppKit -framework SwiftUI -framework IOKit \
//       -o /tmp/lidawake-power-selftest && /tmp/lidawake-power-selftest
//
// The function was split out with a comment saying it was "unit-testable without
// real hardware" and then never tested. The rule it encodes is easy to get wrong
// in exactly one direction, so the table below is exhaustive over the four inputs
// rather than a sample of them.

import Foundation

let FLOOR = 20
var failures = 0

/// nil expectation means "stay armed".
struct Case {
    let onAC: Bool, pct: Int, allow: Bool, draining: Bool
    let expect: String?
    let why: String
}

let UNPLUG = "it was unplugged from power"
let LIMIT  = "the battery reached your \(FLOOR)% limit"
// On AC the floor was already crossed before the drain began, so the off-AC
// wording would be wrong. These two must never collapse back into one string.
let FALLING = "the battery is below your \(FLOOR)% limit and still falling"

@main struct PowerSelfTest {
    static func main() {
        let cases: [Case] = [

            // ---- On AC, above the floor: nothing to complain about. ----
            Case(onAC: true,  pct: 50, allow: true,  draining: false, expect: nil,
                 why: "on AC, charged, battery allowed"),
            Case(onAC: true,  pct: 50, allow: false, draining: false, expect: nil,
                 why: "on AC, charged, battery NOT allowed — AC is the allowed case"),
            Case(onAC: true,  pct: 50, allow: true,  draining: true,  expect: nil,
                 why: "on AC and draining, but still above the floor"),
            Case(onAC: true,  pct: 50, allow: false, draining: true,  expect: nil,
                 why: "on AC and draining, above the floor, battery not allowed"),

            // ---- THE FIX: on AC below the floor, not draining, must stay armed. ----
            Case(onAC: true,  pct: 15, allow: true,  draining: false, expect: nil,
                 why: "FIX: plugged in below the floor and charging — cannot exhaust"),
            Case(onAC: true,  pct: 15, allow: false, draining: false, expect: nil,
                 why: "FIX: same, with battery use not allowed — still on AC"),

            // ---- THE ADDITION: on AC below the floor AND draining → floor applies. ----
            Case(onAC: true,  pct: 15, allow: true,  draining: true,  expect: FALLING,
                 why: "ADDITION: underpowered adapter, charge actually falling"),
            Case(onAC: true,  pct: 15, allow: false, draining: true,  expect: FALLING,
                 why: "ADDITION: same; still on AC so the unplug reason must not fire"),
            Case(onAC: true,  pct: 5,  allow: true,  draining: true,  expect: FALLING,
                 why: "WORDING: on AC the message does not change with how far below"),

            // ---- Off AC, above the floor: only the battery preference matters. ----
            Case(onAC: false, pct: 50, allow: true,  draining: true,  expect: nil,
                 why: "on battery, charged, battery allowed"),
            Case(onAC: false, pct: 50, allow: false, draining: true,  expect: UNPLUG,
                 why: "on battery, charged, but battery use is not allowed"),

            // ---- Off AC, below the floor: floor applies; unplug still wins. ----
            Case(onAC: false, pct: 15, allow: true,  draining: true,  expect: LIMIT,
                 why: "on battery below the floor, battery allowed"),
            Case(onAC: false, pct: 15, allow: false, draining: true,  expect: UNPLUG,
                 why: "PRECEDENCE: unplug outranks floor — one clear message"),
            Case(onAC: false, pct: 15, allow: true,  draining: false, expect: LIMIT,
                 why: "off AC below the floor: floor applies whatever the current reads"),
            Case(onAC: false, pct: 15, allow: false, draining: false, expect: UNPLUG,
                 why: "off AC, not allowed: unplug wins regardless of current"),

            // ---- Boundary: at the floor exactly is NOT below it. ----
            Case(onAC: false, pct: FLOOR, allow: true, draining: true, expect: nil,
                 why: "exactly at the floor is not below it"),

            // ---- Battery-less Mac / unknown charge: percent -1 must never trip. ----
            Case(onAC: true,  pct: -1, allow: true,  draining: false, expect: nil,
                 why: "battery-less Mac on AC"),
            Case(onAC: false, pct: -1, allow: true,  draining: false, expect: nil,
                 why: "unknown charge must not be read as 'below the floor'"),
            Case(onAC: false, pct: -1, allow: false, draining: false, expect: UNPLUG,
                 why: "unknown charge, battery not allowed: the unplug rule still holds"),
        ]

        print("lidawake power-policy self-test — floor \(FLOOR)%\n")
        for c in cases {
            let got = PowerPolicy.disarmReason(onAC: c.onAC, percent: c.pct,
                                               allowOnBattery: c.allow,
                                               floor: FLOOR, draining: c.draining)
            let ok = got == c.expect
            if !ok { failures += 1 }
            let state = String(format: "AC=%@ pct=%3d allow=%@ drain=%@",
                               c.onAC ? "Y" : "n", c.pct,
                               c.allow ? "Y" : "n", c.draining ? "Y" : "n")
            print("\(ok ? "  ok  " : "FAIL  ")\(state)  →  \(got ?? "stay armed")")
            if !ok { print("        expected: \(c.expect ?? "stay armed")") }
            print("        \(c.why)")
        }

        print(failures == 0 ? "\nALL PASS (\(cases.count)/\(cases.count))"
                            : "\n\(failures) FAILED of \(cases.count)")
        exit(failures == 0 ? 0 : 1)
    }
}
