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
    /// The helper can't run because the app isn't installed in Applications —
    /// retrying is pointless, so we show the real fix instead.
    @Published var needsMove = false
    /// Tailors the wording: opened straight from the mounted DMG vs. installed
    /// somewhere else that can't host the helper.
    @Published var onDiskImage = false
    var onRetry: () -> Void = {}
    var onOpenLoginItems: () -> Void = {}
    var onCancel: () -> Void = {}
    var onOpenApplications: () -> Void = {}
}

struct PreparingView: View {
    @ObservedObject var model: PreparingModel

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
            if model.needsMove {
                Text("Move lidawake to your Applications folder").font(.headline)
                Text(model.onDiskImage
                     ? "lidawake is running from the disk image, and it can\u{2019}t work from there \u{2014} macOS won\u{2019}t let it start the small background helper it needs.\n\nDrag lidawake into your Applications folder, then open it from there."
                     : "lidawake can only start its background helper when it lives in your Applications folder.\n\nQuit lidawake, move it into Applications, then open it again.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Open Applications Folder") { model.onOpenApplications() }
                    Button("Quit") { model.onCancel() }.keyboardShortcut(.defaultAction)
                }.padding(.top, 2)
            } else if model.failed {
                Text("lidawake couldn\u{2019}t start its helper").font(.headline)
                Text("Give it a few seconds and try again. If it keeps happening, switch lidawake\u{2019}s background item off and back on in System Settings \u{203A} Login Items \u{2014} that\u{2019}s the one listed as running in the background, not \u{201C}Open at Login\u{201D}.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Open Login Items\u{2026}") { model.onOpenLoginItems() }
                    Button("Try Again") { model.onRetry() }.keyboardShortcut(.defaultAction)
                }.padding(.top, 2)
                Button("Cancel") { model.onCancel() }
            } else {
                ProgressView().controlSize(.large).padding(.vertical, 4)
                Text("Getting lidawake ready\u{2026}").font(.headline)
                Text("This usually takes a few seconds.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(28)
        .frame(width: 380)
    }
}

final class PreparingWindowController {
    let model = PreparingModel()
    private var window: NSWindow?

    private func ensureWindow() {
        guard window == nil else { return }
        let host = NSHostingController(rootView: PreparingView(model: model))
        // Let the window track the SwiftUI content's size, so it fits both the
        // spinner and (taller) error state without clipping the text.
        host.sizingOptions = [.preferredContentSize]
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
        model.needsMove = false
        ensureWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Switch the window to the error state (retry / open Login Items).
    func showFailed() {
        model.needsMove = false
        model.failed = true
        ensureWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The app isn't in Applications, so the helper can never launch — show the
    /// actual fix rather than a Try Again that cannot succeed.
    func showFailedNeedsMove(onDiskImage: Bool = false) {
        model.failed = true
        model.needsMove = true
        model.onDiskImage = onDiskImage
        ensureWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.orderOut(nil) }
}
