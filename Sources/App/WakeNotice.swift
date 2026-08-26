// The login-item disclosure (T2.2), and the rule that it is said exactly once
// through exactly one channel.
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
//   - The **menu item** is the carrier. `pending` is set synchronously the
//     instant registration succeeds, so it is live before anything asynchronous
//     can go wrong.
//   - The **notification** is the courtesy. It says the same thing sooner,
//     without the user having to open the menu.
//
// Whichever lands first clears `pending`; the other stands down. A denial, a
// Focus mode, an unanswered permission prompt or a scheduling error cannot
// swallow the message, because none of them touch the menu item.

import Foundation

enum WakeNotice {

    private static let pendingKey = "loginItemNoticePending"

    static let title = "lidawake now opens at login"
    static let body  = "So it keeps working after you restart. You can turn this off in System Settings › General › Login Items."
    /// Shorter, because it sits in a menu next to the on/off state.
    static let menuTitle = "lidawake now opens at login — change…"

    static var pending: Bool {
        get { UserDefaults.standard.bool(forKey: pendingKey) }
        set { UserDefaults.standard.set(newValue, forKey: pendingKey) }
    }

    /// Called the moment `LoginItem.registerOnce()` newly registers.
    static func raise() { pending = true }

    /// Called when either channel has delivered it. Idempotent.
    static func markDelivered() { pending = false }
}
