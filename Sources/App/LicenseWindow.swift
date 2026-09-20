// The buy / enter-license window — shown when the user taps the license line in the
// menu, or when they try to arm after the trial has ended. Mirrors the Onboarding
// window pattern. Plain language, no nagging: a Buy button and a key field.

import AppKit
import SwiftUI

struct LicenseView: View {
    let controller: LicenseController
    let onChange: () -> Void      // tell the menu to refresh (status may have changed)
    let onClose: () -> Void
    // Hand-expanded `@State`. SwiftUI's `@State` became an external macro in
    // Swift 6.4 (`SwiftUIMacros.StateMacro`), and the Command Line Tools ship no
    // SwiftUI macro plugin — so the macro spelling cannot be compiled without
    // Xcode, and the README promises a CLT-only build. This is the storage the
    // property wrapper always desugared to: SwiftUI discovers `DynamicProperty`
    // members by reflection, so the leading underscore is a naming convention,
    // not the mechanism. Setters must stay `nonmutating` — `body` and button
    // actions assign to these from a non-mutating context.
    private var _key = State(initialValue: "")
    private var key: String {
        get { _key.wrappedValue }
        nonmutating set { _key.wrappedValue = newValue }
    }
    private var _busy = State(initialValue: false)
    private var busy: Bool {
        get { _busy.wrappedValue }
        nonmutating set { _busy.wrappedValue = newValue }
    }
    private var _error = State<String?>(initialValue: nil)
    private var error: String? {
        get { _error.wrappedValue }
        nonmutating set { _error.wrappedValue = newValue }
    }
    private var _activated = State(initialValue: false)
    private var activated: Bool {
        get { _activated.wrappedValue }
        nonmutating set { _activated.wrappedValue = newValue }
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 72, height: 72)
            Text("lidawake").font(.title2).bold()

            if activated {
                Label("You\u{2019}re licensed \u{2014} thank you!", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green).font(.headline)
                Text("Enjoy lidawake on all your Macs.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                headline

                // No price in the button on purpose: VAT is added on top at checkout, so
                // the final total varies by country — the checkout page shows the real price.
                Button("Buy lidawake\u{2026}") { controller.openBuyPage() }
                    .controlSize(.large)
                // No Mac count. The app cannot know which tier someone is about to buy,
                // the checkout shows both, and "up to 3 Macs" went stale the day the
                // one-Mac tier shipped — in front of the person about to pay for it.
                Text("One-time purchase \u{00B7} 14-day money-back guarantee")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)

                Divider().padding(.vertical, 2)

                Text("Already bought? Enter your license key:")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    // No format hint on purpose. The old XXXX-XXXX-XXXX-XXXX was invented
                    // and Freemius keys look nothing like it, so it read as "your key is the
                    // wrong shape" to someone holding a perfectly good one. A real example
                    // would just move the problem: it would be a second thing to keep in step
                    // with whatever Freemius issues. Say what to do instead.
                    TextField("Paste your license key", text: _key.projectedValue)
                        .textFieldStyle(.roundedBorder).disabled(busy)
                        .onSubmit(activate)
                    // Return belongs to Activate while there is a key to activate. Close
                    // used to own .defaultAction, so pasting a key and pressing Return —
                    // the obvious thing to do with one field and one button — dismissed the
                    // window without trying the key, and on this screen the user cannot tell
                    // that nothing happened. A disabled Activate simply swallows Return,
                    // which is right: there is nothing to submit.
                    Button(busy ? "\u{2026}" : "Activate", action: activate)
                        .disabled(busy || key.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Default action only where nothing else wants Return: once activation has
            // succeeded there is no key field left, so Done can take it back. Before that,
            // Escape is the way out — the standard gesture for dismissing a panel, and it
            // cannot be confused with submitting.
            Button(activated ? "Done" : "Close") { onChange(); onClose() }
                .keyboardShortcut(activated ? .defaultAction : .cancelAction)
                .controlSize(.large).padding(.top, 4)
        }
        .padding(28).frame(width: 400)
    }

    @ViewBuilder private var headline: some View {
        switch controller.status {
        case .trial(let d):
            Text("You\u{2019}re on the free trial").font(.headline)
            Text("\(d) day\(d == 1 ? "" : "s") left. Buy now to keep lidawake after the trial ends.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        case .expired:
            Text("Your free trial has ended").font(.headline)
            Text("Buy lidawake to keep your Mac awake with the lid closed.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        default:
            Text("Thanks for using lidawake").font(.headline)
        }
    }

    private func activate() {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard !busy, !trimmed.isEmpty else { return }
        busy = true; error = nil
        controller.activate(key: trimmed) { result in
            busy = false
            switch result {
            case .success:        activated = true; onChange()
            case .failure(let e): error = e.message
            }
        }
    }
}

/// Lazily-created, reused license window.
final class LicenseWindowController {
    private var window: NSWindow?

    func show(controller: LicenseController, onChange: @escaping () -> Void) {
        if window == nil {
            let view = LicenseView(controller: controller, onChange: onChange,
                                   onClose: { [weak self] in self?.window?.close() })
            let host = NSHostingController(rootView: view)
            let w = NSWindow(contentViewController: host)
            w.title = "lidawake"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
