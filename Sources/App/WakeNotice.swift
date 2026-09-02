// The menu carrier: anything lidawake needs to tell you that you must not miss.
//
// Why it exists at all: the app registers itself in Login Items, and the author
// of the app did not know it was doing that. A normal user certainly would not,
// and quietly appearing in System Settings is the kind of surprise this product
// promises not to spring. There is deliberately no toggle for it — macOS already
// owns that switch, and a second one would be a second source of truth for one
// piece of state. What was missing was disclosure, not control.
//
// Two channels, and the ORDER matters:
//
//   - The **menu line** is the carrier. It is raised synchronously, before
//     anything asynchronous can go wrong, and it is persisted, so it survives a
//     quit or a crash.
//   - The **notification** is the courtesy. It says the same thing sooner,
//     without the user having to open the menu.
//
// THE RULE THAT WAS BROKEN AND IS NOW FIXED: only the USER clears this — by
// opening the menu with the line visible, or by clicking the notification. It is
// NOT cleared because a notification was accepted by the system. A post that
// lands while the display is asleep, or under a Focus mode, is accepted and then
// never presented; clearing on that leaves the user with neither channel, which
// is exactly the failure this carrier exists to prevent.

import Foundation

enum WakeNotice {

    private static let textKey       = "noticeMenuText"
    private static let actionableKey = "noticeActionable"
    /// 1.2.1–1.4.3 stored only a Bool, because the login-item disclosure was the
    /// only thing that used this. Read once so upgrading mid-notice does not
    /// silently drop a disclosure the user has not seen yet.
    private static let legacyKey     = "loginItemNoticePending"

    static let loginItemTitle = "lidawake now opens at login"
    static let loginItemBody  = "So it keeps working after you restart. You can turn this off in System Settings › General › Login Items."
    /// Shorter, because it sits in a menu next to the on/off state.
    static let loginItemMenu  = "lidawake now opens at login — change…"

    /// The line to show in the menu, or nil when there is nothing to say.
    static var text: String? {
        if let t = UserDefaults.standard.string(forKey: textKey), !t.isEmpty { return t }
        if UserDefaults.standard.bool(forKey: legacyKey) { return loginItemMenu }
        return nil
    }

    /// True when clicking the line does something (the login-item disclosure
    /// opens System Settings). Informational notices are shown disabled, the same
    /// way the status line is.
    static var isActionable: Bool {
        if UserDefaults.standard.string(forKey: textKey) != nil {
            return UserDefaults.standard.bool(forKey: actionableKey)
        }
        return UserDefaults.standard.bool(forKey: legacyKey)
    }

    static var pending: Bool { text != nil }

    static func raise(_ line: String, actionable: Bool) {
        UserDefaults.standard.set(line, forKey: textKey)
        UserDefaults.standard.set(actionable, forKey: actionableKey)
    }

    /// The user has demonstrably seen it. Idempotent.
    static func markSeen() {
        UserDefaults.standard.removeObject(forKey: textKey)
        UserDefaults.standard.removeObject(forKey: actionableKey)
        UserDefaults.standard.set(false, forKey: legacyKey)
    }
}
