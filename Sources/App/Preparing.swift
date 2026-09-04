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
    /// macOS reports the background item as switched ON, but the helper never
    /// answers. The generic failure text tells the user to go and switch on something
    /// that is already switched on — the one piece of advice that cannot help here —
    /// so this state gets its own wording. Issue #2.
    @Published var stillRegistered = false
    /// A different copy of lidawake already holds the menu bar. This launch is
    /// bowing out — but it says so rather than vanishing, which is issue #1.
    @Published var duplicate = false
    /// Where that other copy lives. nil when macOS wouldn't tell us.
    @Published var otherPath: String?
    var onRetry: () -> Void = {}
    var onOpenLoginItems: () -> Void = {}
    var onCancel: () -> Void = {}
    var onOpenApplications: () -> Void = {}
    var onRevealOther: () -> Void = {}
}

struct PreparingView: View {
    @ObservedObject var model: PreparingModel

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
            if model.duplicate {
                Text("lidawake is already running").font(.headline)
                Text(duplicateBody)
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if model.otherPath != nil {
                        Button("Show Me Where") { model.onRevealOther() }
                    }
                    Button("OK") { model.onCancel() }.keyboardShortcut(.defaultAction)
                }.padding(.top, 2)
            } else if model.needsMove {
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
                Text(model.stillRegistered
                     ? "lidawake\u{2019}s helper isn\u{2019}t answering"
                     : "lidawake couldn\u{2019}t start its helper").font(.headline)
                Text(model.stillRegistered
                     ? "macOS lists lidawake\u{2019}s background item as switched on, so the setting you\u{2019}d normally check is already correct \u{2014} turning it on won\u{2019}t help. lidawake has re-registered it several times without getting a reply.\n\nSwitching that item off and back on in System Settings \u{203A} Login Items sometimes clears it. If it keeps happening, email support@zayco.it."
                     : "Give it a few seconds and try again. If it keeps happening, switch lidawake\u{2019}s background item off and back on in System Settings \u{203A} Login Items \u{2014} that\u{2019}s the one listed as running in the background, not \u{201C}Open at Login\u{201D}.")
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

    /// Names the copy that holds the menu bar, so a user whose install "did nothing"
    /// can see it actually worked — and find the copy if it's the wrong one.
    private var duplicateBody: String {
        let tail = "This copy won\u{2019}t open, so you don\u{2019}t end up with two lidawake icons in your menu bar. lidawake is already working \u{2014} look for its icon up in the menu bar.\n\nIf that\u{2019}s the copy you want rid of, quit it from its menu-bar icon first, then drag it to the Trash."
        guard let path = model.otherPath else {
            return "Another copy of lidawake is already running.\n\n" + tail
        }
        return "lidawake is already running from:\n\n\(path)\n\n" + tail
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
        model.duplicate = false
        model.stillRegistered = false
        ensureWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Switch the window to the error state (retry / open Login Items).
    func showFailed(stillRegistered: Bool = false) {
        model.needsMove = false
        model.duplicate = false
        model.stillRegistered = stillRegistered
        model.failed = true
        ensureWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The app isn't in Applications, so the helper can never launch — show the
    /// actual fix rather than a Try Again that cannot succeed.
    func showFailedNeedsMove(onDiskImage: Bool = false) {
        model.duplicate = false
        model.stillRegistered = false
        model.failed = true
        model.needsMove = true
        model.onDiskImage = onDiskImage
        ensureWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A different copy already holds the menu bar — name it instead of exiting mute.
    func showDuplicate(otherPath: String?) {
        model.failed = false
        model.needsMove = false
        model.stillRegistered = false
        model.duplicate = true
        model.otherPath = otherPath
        ensureWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.orderOut(nil) }
}
