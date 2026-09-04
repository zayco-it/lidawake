// The buy / enter-license window — shown when the user taps the license line in the
// menu, or when they try to arm after the trial has ended. Mirrors the Onboarding
// window pattern. Plain language, no nagging: a Buy button and a key field.

import AppKit
import SwiftUI

struct LicenseView: View {
    let controller: LicenseController
    let onChange: () -> Void      // tell the menu to refresh (status may have changed)
    let onClose: () -> Void
    @State private var key = ""
    @State private var busy = false
    @State private var error: String?
    @State private var activated = false

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
                    TextField("Paste your license key", text: $key)
                        .textFieldStyle(.roundedBorder).disabled(busy)
                        .onSubmit(activate)
                    Button(busy ? "\u{2026}" : "Activate", action: activate)
                        .disabled(busy || key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }

            Button(activated ? "Done" : "Close") { onChange(); onClose() }
                .keyboardShortcut(.defaultAction).controlSize(.large).padding(.top, 4)
        }
        .padding(28).frame(width: 400)
    }

    @ViewBuilder private var headline: some View {
        switch controller.status {
        case .trial(let d):
            Text("You\u{2019}re on the free trial").font(.headline)
            Text("\(d) day\(d == 1 ? "" : "s") left. Buy now to keep lidawake after the trial ends.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
