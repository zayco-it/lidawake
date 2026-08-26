// The app's only notification code. Owns UNUserNotificationCenter, the one
// authorization request, and posting.
//
// NOTE FOR ANYONE REACHING FOR `notify()` IN main.swift: that is NOT this. It is
// an NSAlert that calls activate(ignoringOtherApps:) and runModal() — a modal
// that steals focus and blocks the main thread. Correct for "lidawake turned
// off because your Mac got hot", where the user must acknowledge. Wrong for
// anything transient. Use this instead.
//
// Authorization is requested lazily, on the first message we actually want to
// send — never up front. Asking during onboarding would request something that
// gives the user nothing yet, they would deny it, and macOS never asks again.
// Asking at the moment there is something to say makes the request explain
// itself. It also covers people who set lidawake up before any of this shipped:
// they never see onboarding, but they do hit the first real message.

import Foundation
import UserNotifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate {

    /// Why a post did not reach the user. Callers use this to fall back.
    enum Outcome {
        case posted
        case denied          // user said no, now or previously
        case failed(String)  // scheduling error
    }

    private var center: UNUserNotificationCenter { .current() }

    /// Must be set before the first post so banners appear even when lidawake
    /// happens to be frontmost (rare for an LSUIElement app, but it is what makes
    /// the difference between "shown" and "silently swallowed" when it is).
    func start() {
        center.delegate = self
    }

    /// Post `title`/`body`, requesting permission first if we have never asked.
    /// The completion always runs on the main thread.
    ///
    /// `.notDetermined` is the interesting case: `requestAuthorization` does not
    /// call back until the user actually clicks the system prompt, which may be
    /// minutes away or never. Callers must not treat "no callback yet" as
    /// success — see WakeNotice for how the login-item disclosure stays visible
    /// in the menu until this definitively lands.
    func post(title: String, body: String, completion: ((Outcome) -> Void)? = nil) {
        let done: (Outcome) -> Void = { o in DispatchQueue.main.async { completion?(o) } }

        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.deliver(title: title, body: body, done: done)
            case .denied:
                done(.denied)
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert]) { granted, err in
                    if let err { done(.failed(err.localizedDescription)); return }
                    granted ? self.deliver(title: title, body: body, done: done) : done(.denied)
                }
            @unknown default:
                done(.denied)
            }
        }
    }

    private func deliver(title: String, body: String, done: @escaping (Outcome) -> Void) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        // No sound: this is information, not an alarm. A Mac that has been quietly
        // awake all night should not announce itself with a chime.
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        center.add(req) { err in
            if let err { done(.failed(err.localizedDescription)) } else { done(.posted) }
        }
    }

    // Show the banner even if lidawake is frontmost. Default macOS behaviour is to
    // suppress it, which would silently drop the message in exactly the case where
    // the user is looking at the screen.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner])
    }
}
