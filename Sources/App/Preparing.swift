// A small "Getting lidawake ready…" window shown while the app reconnects to its
// background helper — e.g. after an update, when the freshly-reloaded daemon needs
// a moment to come up. It polls in the background and closes itself the instant the
// helper answers, so turning lidawake on stays a single click. Deliberately NOT the
// Welcome window: a set-up user must never see onboarding again just because the
// helper is briefly settling.

import AppKit
import SwiftUI

final class PreparingModel: ObservableObject {
    @Published var failed = false
    var onRetry: () -> Void = {}
    var onOpenLoginItems: () -> Void = {}
    var onCancel: () -> Void = {}
}

struct PreparingView: View {
    @ObservedObject var model: PreparingModel

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
            if model.failed {
                Text("lidawake couldn\u{2019}t start its helper").font(.headline)
                Text("Give it a few seconds and try again. If it keeps happening, switch lidawake off and back on in System Settings \u{203A} Login Items.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button("Open Login Items\u{2026}") { model.onOpenLoginItems() }
                    Button("Try Again") { model.onRetry() }.keyboardShortcut(.defaultAction)
                }.padding(.top, 2)
                Button("Cancel") { model.onCancel() }
            } else {
                ProgressView().controlSize(.large).padding(.vertical, 4)
                Text("Getting lidawake ready\u{2026}").font(.headline)
                Text("Reconnecting the background helper — this can take a moment right after an update.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(28).frame(width: 360)
    }
}

final class PreparingWindowController {
    let model = PreparingModel()
    private var window: NSWindow?

    private func ensureWindow() {
        guard window == nil else { return }
        let host = NSHostingController(rootView: PreparingView(model: model))
        let w = NSWindow(contentViewController: host)
        w.title = "lidawake"
        w.styleMask = [.titled]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
    }

    /// Show the spinner ("getting ready") state and bring the window forward.
    func showPreparing() {
        model.failed = false
        ensureWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Switch the window to the error state (retry / open Login Items).
    func showFailed() {
        model.failed = true
        ensureWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.orderOut(nil) }
}
