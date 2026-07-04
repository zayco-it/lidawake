// Headless self-test for the licensing entitlement logic (LicenseController).
// Compiles with the REAL sources — so it tests the shipping code, not a copy —
// against a throwaway UserDefaults suite, so it never touches the installed app's
// settings. Dev-only; NOT part of the app build.
//
//   swiftc -O tools/license-selftest.swift \
//       Sources/App/LicenseController.swift Sources/App/LicenseProvider.swift \
//       -framework AppKit -framework IOKit -o /tmp/lidawake-selftest && /tmp/lidawake-selftest

import Foundation

// These key strings mirror LicenseController's private `K` enum.
let kTrial  = "lic.trialStart"
let kRecord = "lic.record"
let kEval   = "lic.evaluated"

let day = 86_400.0
var failures = 0

func check(_ cond: Bool, _ label: String) {
    print("\(cond ? "  ok  " : "FAIL  ")\(label)")
    if !cond { failures += 1 }
}

func freshSuite(_ name: String) -> UserDefaults {
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@main struct SelfTest {
    static func main() {
        // 1) Brand-new user → 14-day trial.
        do {
            let d = freshSuite("selftest.new")
            let c = LicenseController(provider: MockProvider(), defaults: d)
            c.bootstrap(usedBefore: false)
            check(c.status == .trial(daysLeft: 14), "new install → 14-day trial (got \(c.status))")
            check(c.isEntitled, "trial is entitled")
        }

        // 2) Existing 1.0.x user → grandfathered, and the decision is sticky.
        do {
            let d = freshSuite("selftest.grand")
            let c = LicenseController(provider: MockProvider(), defaults: d)
            c.bootstrap(usedBefore: true)
            check(c.status == .grandfathered, "used-before → grandfathered (got \(c.status))")
            check(c.isEntitled, "grandfathered is entitled")
            c.bootstrap(usedBefore: false)   // must NOT downgrade an already-decided user
            check(c.status == .grandfathered, "bootstrap is sticky (still grandfathered)")
        }

        // 3) Trial countdown math.
        do {
            let d = freshSuite("selftest.count")
            d.set(true, forKey: kEval)
            d.set(Date().addingTimeInterval(-10 * day), forKey: kTrial)  // 10 days in
            let c = LicenseController(provider: MockProvider(), defaults: d)
            check(c.status == .trial(daysLeft: 4), "10 days into a 14-day trial → 4 left (got \(c.status))")
        }

        // 4) Trial expired → arming gated.
        do {
            let d = freshSuite("selftest.exp")
            d.set(true, forKey: kEval)
            d.set(Date().addingTimeInterval(-20 * day), forKey: kTrial)
            let c = LicenseController(provider: MockProvider(), defaults: d)
            check(c.status == .expired, "20 days in → expired (got \(c.status))")
            check(!c.isEntitled, "expired is NOT entitled (arming blocked)")
        }

        // 5) A valid cached license → licensed, even past the trial window.
        do {
            let d = freshSuite("selftest.lic")
            d.set(true, forKey: kEval)
            d.set(Date().addingTimeInterval(-20 * day), forKey: kTrial)   // trial long gone
            let rec = LicenseRecord(key: "ABC", uid: "u", installId: "1", installToken: "t",
                                    planName: "Pro", expiresAt: nil, lastValidated: Date())
            d.set(try! JSONEncoder().encode(rec), forKey: kRecord)
            let c = LicenseController(provider: MockProvider(), defaults: d)
            check(c.status == .licensed, "valid cached license → licensed past trial (got \(c.status))")
            check(c.isEntitled, "licensed is entitled")
        }

        // 6) An EXPIRED license record is ignored (falls back to trial/expired).
        do {
            let d = freshSuite("selftest.licexp")
            d.set(true, forKey: kEval)
            d.set(Date().addingTimeInterval(-20 * day), forKey: kTrial)
            let rec = LicenseRecord(key: "ABC", uid: "u", installId: "1", installToken: "t",
                                    planName: "Pro", expiresAt: Date().addingTimeInterval(-day),
                                    lastValidated: Date())
            d.set(try! JSONEncoder().encode(rec), forKey: kRecord)
            let c = LicenseController(provider: MockProvider(), defaults: d)
            check(c.status == .expired, "expired license record ignored → expired (got \(c.status))")
        }

        print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
