// The app's only notification code. Owns UNUserNotificationCenter, the one
// authorization request, posting, and the rule that a message is never posted
// to a screen that cannot show it.
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

import AppKit
import CoreGraphics
import Foundation
import UserNotifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate {

    /// What happened to a post. NOTHING MAY TREAT `.accepted` AS "THE USER SAW
    /// IT" — that was the bug this type is named for. It means only that
    /// UNUserNotificationCenter took the request. A notification posted while
    /// the display is asleep, or under a Focus mode, is `.accepted`, lands
    /// silently in Notification Center, and is never presented. Every caller
    /// therefore keeps a channel that does not depend on this value.
    enum Outcome {
        case accepted        // queued with the system; NOT seen
        case denied          // user said no, now or previously
        case failed(String)  // scheduling error
    }

    /// How long after `screensDidWakeNotification` the system will actually
    /// present a banner.
    ///
    /// The signal is necessary but NOT sufficient: it fires before the system
    /// will present anything. MEASURED on this Mac, 2026-09-02, by sleeping the
    /// display, posting at a fixed offset after the signal, and looking at
    /// screen captures:
    ///
    ///     +0.07s  no banner  (two runs, frames inspected inside the window
    ///                         where a banner would still have been on screen)
    ///     +0.5s   banner
    ///     +2.5s   banner     <- this value, verified directly
    ///
    /// A control post with the display already awake banners every time, so the
    /// negative at +0.07s is the wake window and not throttling.
    ///
    /// So the floor is somewhere in (0.07, 0.5]. 2.5s is deliberately far above
    /// it — the same asymmetry as the helper watchdog. Posting too early loses
    /// the message silently, which is the entire failure being fixed here;
    /// posting too late costs a couple of seconds on a report about something
    /// that already took hours. A slower Mac, or one waking with far more
    /// restored, is the case the margin is for.
    ///
    /// MEASUREMENT TRAP, recorded because it produced three wrong answers before
    /// it was caught: do not infer "no banner" from PNG file sizes across a run.
    /// If the capture window falls entirely inside the banner's ~5s lifetime,
    /// every frame contains it, min == max, and the run reads as a clean
    /// negative. Look at the frames.
    private static let wakeSettle: TimeInterval = 2.5

    private struct Held {
        let title: String
        let body: String
        let stillWanted: () -> Bool
        let completion: ((Outcome) -> Void)?
    }

    private var center: UNUserNotificationCenter { .current() }
    private var held: Held?
    private var wakeObservers: [NSObjectProtocol] = []

    /// Called when the user actually interacts with a notification — the only
    /// signal macOS gives us that a message genuinely landed with a person.
    var onEngaged: (() -> Void)?

    /// Must be set before the first post so banners appear even when lidawake
    /// happens to be frontmost (rare for an LSUIElement app, but it is what makes
    /// the difference between "shown" and "silently swallowed" when it is).
    func start() {
        center.delegate = self
    }

    /// Post `title`/`body` when a screen can actually show it.
    ///
    /// If the display is awake, that is now. If it is asleep — which is the norm
    /// for this app, because it sleeps the panel itself on every armed lid-close
    /// — the message is held until the screens wake, plus the settle above.
    /// A held message is deliberately NOT persisted: the menu carrier raised by
    /// the caller is what survives a quit, and duplicating it here would risk
    /// announcing a stale session on the next launch.
    /// `stillWanted` is re-checked at the moment of posting, after the hold.
    /// It is what keeps the two channels mutually exclusive in the one direction
    /// that is honest: if the user opened the menu and read the line while the
    /// message was held, the notification stands down. The reverse — a post
    /// standing the menu down — is precisely the bug, because an accepted post
    /// may never be shown to anyone.
    func present(title: String, body: String,
                 stillWanted: @escaping () -> Bool = { true },
                 completion: ((Outcome) -> Void)? = nil) {
        if CGDisplayIsAsleep(CGMainDisplayID()) == 0 {
            post(title: title, body: body, completion: completion)
            return
        }
        // At most one. A newer message supersedes an older one rather than
        // stacking a queue of banners at the moment the lid comes up.
        held = Held(title: title, body: body, stillWanted: stillWanted, completion: completion)
        armWakeObserver()
        NSLog("[lidawake] display asleep — holding notification until the screens wake")
    }

    /// Both wake signals, because the two cases this has to cover are different.
    /// After a lid-close the Mac stays awake and only the panel sleeps, so
    /// opening the lid is a SCREEN wake. After the idle auto-off it hands sleep
    /// back, so the Mac really does sleep and opening the lid is a SYSTEM wake —
    /// which is the overnight case, the one that matters most here.
    ///
    /// NOTE: both are posted on NSWorkspace's OWN centre, not
    /// NotificationCenter.default. Registered on the wrong one they silently
    /// never fire, which looks exactly like the bug this exists to fix.
    private func armWakeObserver() {
        guard wakeObservers.isEmpty else { return }
        let c = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            wakeObservers.append(c.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in self?.screensWoke()
            })
        }
    }

    private func screensWoke() {
        guard let pending = held else { disarmWakeObserver(); return }
        // A signal can arrive fractionally before the panel is actually back —
        // didWake in particular. Do NOT consume the message yet; stay armed and
        // let the next signal (screensDidWake always follows) do it. Posting to a
        // display that is still asleep is the exact bug being fixed.
        guard CGDisplayIsAsleep(CGMainDisplayID()) == 0 else {
            NSLog("[lidawake] wake signal but the display is still asleep — still holding")
            return
        }
        held = nil
        disarmWakeObserver()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.wakeSettle) { [weak self] in
            guard pending.stillWanted() else {
                NSLog("[lidawake] held notification stood down — already seen in the menu")
                return
            }
            self?.post(title: pending.title, body: pending.body, completion: pending.completion)
        }
    }

    private func disarmWakeObserver() {
        guard !wakeObservers.isEmpty else { return }
        for o in wakeObservers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        wakeObservers.removeAll()
    }

    /// Post now, requesting permission first if we have never asked.
    /// The completion always runs on the main thread.
    ///
    /// `.notDetermined` is the interesting case: `requestAuthorization` does not
    /// call back until the user actually clicks the system prompt, which may be
    /// minutes away or never. Callers must not treat "no callback yet" as
    /// success — see WakeNotice for how a notice stays visible in the menu until
    /// the user has demonstrably seen it.
    private func post(title: String, body: String, completion: ((Outcome) -> Void)? = nil) {
        let done: (Outcome) -> Void = { o in
            DispatchQueue.main.async {
                NSLog("[lidawake] notification \(title.prefix(40)) -> \(o)")
                completion?(o)
            }
        }

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
            if let err { done(.failed(err.localizedDescription)) } else { done(.accepted) }
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

    // The user clicked it. This is the one moment we know a message reached a
    // person, so it is what stands the menu carrier down.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler handler: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in self?.onEngaged?() }
        handler()
    }
}
