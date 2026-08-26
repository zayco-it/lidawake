// Pure-logic checks for WakeSummary. Run:
//   swiftc -parse-as-library Sources/App/WakeSummary.swift tools/wakesummary-selftest.swift -o /tmp/wst && /tmp/wst
// No UI, no notifications, no app — just the sentence the user actually reads.

import Foundation

var failures = 0
func check(_ label: String, _ got: String, _ want: String) {
    if got == want { print("  PASS  \(label): \(got)") }
    else { print("  FAIL  \(label): got \"\(got)\", want \"\(want)\""); failures += 1 }
}

@main struct SelfTest {
    static func main() {
        print("duration")
        check("exact hours",  WakeSummary.duration(2 * 3600), "2 h")
        check("h + min",      WakeSummary.duration(7 * 3600 + 43 * 60), "7 h 43 min")
        check("minutes only", WakeSummary.duration(43 * 60), "43 min")
        check("under a min",  WakeSummary.duration(20), "0 min")
        check("rounds",       WakeSummary.duration(59 * 60 + 59.6), "1 h")

        print("thermal")
        check("nominal",  WakeSummary.thermal(.nominal),  "stayed cool")
        check("fair",     WakeSummary.thermal(.fair),     "warmed up a little")
        check("serious",  WakeSummary.thermal(.serious),  "got hot")
        check("critical", WakeSummary.thermal(.critical), "got very hot")

        print("finish")
        var s = WakeSummary()
        if s.finish(battery: 50, peakThermal: .nominal) != nil {
            print("  FAIL  finish with no session should return nil"); failures += 1
        } else { print("  PASS  no session -> nil") }

        // Too short to be worth a notification.
        s = WakeSummary(); s.begin(battery: 100)
        if s.finish(battery: 99, peakThermal: .nominal) != nil {
            print("  FAIL  a 0s session should be below the reportable floor"); failures += 1
        } else { print("  PASS  under 5 min -> nil") }

        // finish() must clear the session, so a second call says nothing.
        s = WakeSummary(); s.begin(battery: 100)
        _ = s.finish(battery: 99, peakThermal: .nominal)
        if s.isRunning { print("  FAIL  finish() left the session running"); failures += 1 }
        else { print("  PASS  finish() clears the session") }

        // cancel() must make it silent — the disarm path depends on this.
        s = WakeSummary(); s.begin(battery: 100); s.cancel()
        if s.finish(battery: 41, peakThermal: .nominal) != nil {
            print("  FAIL  cancel() did not silence the session"); failures += 1
        } else { print("  PASS  cancel() -> nil") }

        print(failures == 0 ? "\nall WakeSummary checks passed" : "\n\(failures) FAILURES")
        exit(failures == 0 ? 0 : 1)
    }
}
