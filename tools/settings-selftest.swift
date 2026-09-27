// Headless self-test for the lid-open screen-switch migration
// (Settings.migrateLidOpenScreenSwitch). Compiles with the REAL source against an
// in-memory UserDefaults, so it tests the shipping migration and touches no
// preferences on disk. Dev-only; NOT part of the app build.
//
//   swiftc -O -parse-as-library tools/settings-selftest.swift Sources/App/Settings.swift \
//       -framework AppKit -framework SwiftUI \
//       -o /tmp/lidawake-settings-selftest && /tmp/lidawake-settings-selftest
//
// The promise is that nobody's screen behaves differently after the update. The
// old app kept the screen on when "Let lidawake manage the screen" AND "Keep the
// screen on" were both on, with defaults true and false. So for every state the
// old app could have stored — each key absent, true or false — the new app's
// single switch must come out equal to what the old app would have done. The
// table is exhaustive over those nine states, not a sample of them.

import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { print("  PASS  \(label)") }
    else { print("  FAIL  \(label) \(detail())"); failures += 1 }
}

/// In-memory defaults: a real suite cannot be cleaned up after — cfprefsd writes
/// an emptied domain back to disk seconds later (see lidwarning-selftest.swift).
final class MemoryDefaults: UserDefaults {
    private var store: [String: Any] = [:]
    init() { super.init(suiteName: nil)! }
    override func object(forKey key: String) -> Any? { store[key] }
    override func set(_ value: Any?, forKey key: String) { store[key] = value }
    override func removeObject(forKey key: String) { store[key] = nil }
}

let PARENT = Settings.Key.legacyKeepAwakeLidOpen
let CHILD  = Settings.Key.keepScreenOnLidOpen

/// What the OLD app did with these stored values: registered defaults were
/// parent = true, child = false, and screenOn = parent && child.
func oldScreenOn(parent: Any?, child: Any?) -> Bool {
    ((parent as? Bool) ?? true) && ((child as? Bool) ?? false)
}
/// What the NEW app does: one key, registered default false.
func newScreenOn(_ d: UserDefaults) -> Bool { (d.object(forKey: CHILD) as? Bool) ?? false }
func show(_ v: Any?) -> String { v.map { "\($0)" } ?? "absent" }

@main struct SettingsSelfTest {
    static func main() {
        print("migration — every state the old app could have stored")
        let states: [Any?] = [nil, true, false]
        for parent in states {
            for child in states {
                let d = MemoryDefaults()
                if let parent { d.set(parent, forKey: PARENT) }
                if let child { d.set(child, forKey: CHILD) }
                let before = oldScreenOn(parent: parent, child: child)

                Settings.migrateLidOpenScreenSwitch(d)
                let label = "parent \(show(parent)), child \(show(child))"
                check("\(label) → screen on = \(before), same as before",
                      newScreenOn(d) == before, "got \(newScreenOn(d))")
                check("\(label) → old key gone", d.object(forKey: PARENT) == nil)
                if parent == nil {
                    // Never written: nothing to migrate, and nothing may be written.
                    check("\(label) → child left exactly as it was",
                          show(d.object(forKey: CHILD)) == show(child))
                }
                // An older build after a downgrade re-registers parent = true.
                check("\(label) → a downgraded older build still agrees",
                      oldScreenOn(parent: d.object(forKey: PARENT), child: d.object(forKey: CHILD)) == before)

                let afterFirst = show(d.object(forKey: CHILD))
                Settings.migrateLidOpenScreenSwitch(d)
                check("\(label) → a second run changes nothing",
                      show(d.object(forKey: CHILD)) == afterFirst && d.object(forKey: PARENT) == nil)
            }
        }

        print("stored as a number rather than a bool (`defaults write -int`)")
        do {
            let d = MemoryDefaults()
            d.set(NSNumber(value: 0), forKey: PARENT)
            d.set(true, forKey: CHILD)
            Settings.migrateLidOpenScreenSwitch(d)
            check("parent 0, child true → screen on = false", newScreenOn(d) == false)
        }

        print("registered defaults")
        Settings.registerDefaults()
        let reg = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        check("the old key is no longer registered", reg[PARENT] == nil)
        check("Keep the screen on still defaults to off", (reg[CHILD] as? Bool) == false)

        print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
