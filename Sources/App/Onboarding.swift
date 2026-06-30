// First-run onboarding — a friendly Welcome window that guides a brand-new user
// through the single setup step (allowing the background helper). On a Mac that
// already approved lidawake it shows the "you're all set" state instead.

import AppKit
import SwiftUI

struct OnboardingView: View {
    let isEnabled: () -> Bool
    let openLoginItems: () -> Void
    let onClose: () -> Void
    @State private var enabled: Bool

    init(isEnabled: @escaping () -> Bool, openLoginItems: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.openLoginItems = openLoginItems
        self.onClose = onClose
        _enabled = State(initialValue: isEnabled())
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 76, height: 76)
            Text("Welcome to lidawake").font(.title2).bold()
            Text("Keep your Mac awake — even with the lid closed.")
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 2)

            if enabled {
                Label("You're all set", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.headline)
                Text("Click the laptop in your menu bar, then \u{201C}Keep my Mac awake.\u{201D}")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else {
                Text("One quick step").font(.headline)
                Text("Allow lidawake to run in the background so it can keep your Mac awake.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Open Login Items\u{2026}") { openLoginItems() }
                    .controlSize(.large)
                Text("Find lidawake under \u{201C}Allow in the Background,\u{201D} switch it on, then click below.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("I\u{2019}ve turned it on") { enabled = isEnabled() }
            }

            Button(enabled ? "Get Started" : "Skip for now") { onClose() }
                .keyboardShortcut(.defaultAction).controlSize(.large).padding(.top, 4)
        }
        .padding(28)
        .frame(width: 380)
    }
}

/// Lazily-created, reused Welcome window.
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(isEnabled: @escaping () -> Bool, openLoginItems: @escaping () -> Void) {
        if window == nil {
            let view = OnboardingView(isEnabled: isEnabled, openLoginItems: openLoginItems,
                                      onClose: { [weak self] in self?.window?.close() })
            let host = NSHostingController(rootView: view)
            let w = NSWindow(contentViewController: host)
            w.title = "Welcome to lidawake"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
