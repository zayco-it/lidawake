// First-run onboarding — a friendly Welcome window that guides a brand-new user
// through the single setup step (allowing the background helper). On a Mac that
// already approved lidawake it shows the "you're all set" state instead.

import AppKit
import SwiftUI

struct OnboardingView: View {
    let isEnabled: () -> Bool
    let openLoginItems: () -> Void
    let onClose: () -> Void
    // Hand-expanded `@State`. SwiftUI's `@State` became an external macro in
    // Swift 6.4 (`SwiftUIMacros.StateMacro`), and the Command Line Tools ship no
    // SwiftUI macro plugin — so the macro spelling cannot be compiled without
    // Xcode, and the README promises a CLT-only build. This is the storage the
    // property wrapper always desugared to: SwiftUI discovers `DynamicProperty`
    // members by reflection, so the leading underscore is a naming convention,
    // not the mechanism. Setters must stay `nonmutating` — `body` and button
    // actions assign to these from a non-mutating context.
    private var _enabled: State<Bool>
    private var enabled: Bool {
        get { _enabled.wrappedValue }
        nonmutating set { _enabled.wrappedValue = newValue }
    }
    private var _stillOff = State(initialValue: false)
    private var stillOff: Bool {
        get { _stillOff.wrappedValue }
        nonmutating set { _stillOff.wrappedValue = newValue }
    }

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
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("One quick step").font(.headline)
                Text("Allow lidawake to run in the background so it can keep your Mac awake.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Login Items\u{2026}") { openLoginItems() }
                    .controlSize(.large)
                Text("Find lidawake under \u{201C}Allow in the Background,\u{201D} switch it on, then click below.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("I\u{2019}ve turned it on") {
                    if isEnabled() { enabled = true; stillOff = false } else { stillOff = true }
                }
                if stillOff {
                    Text("Hmm — I don\u{2019}t see it enabled yet. Make sure the lidawake switch is on under \u{201C}Allow in the Background,\u{201D} then try again.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
