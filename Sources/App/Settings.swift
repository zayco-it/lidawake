// Settings — persistent user preferences (UserDefaults) plus the small SwiftUI
// Settings window. The window writes via @AppStorage; the AppKit side reads the
// same keys through the `Settings` enum. Defaults are registered once at launch
// and MUST match the @AppStorage defaults below.

import AppKit
import SwiftUI

enum Settings {
    enum Key {
        static let screenOffOnLidClose = "screenOffOnLidClose"
        static let allowOnBattery      = "allowOnBattery"
        static let batteryFloorPercent = "batteryFloorPercent"
        static let keepAwakeLidOpen    = "keepAwakeLidOpen"
        static let keepScreenOnLidOpen = "keepScreenOnLidOpen"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.screenOffOnLidClose: true,
            Key.allowOnBattery:      false,
            Key.batteryFloorPercent: 20,
            Key.keepAwakeLidOpen:    true,
            Key.keepScreenOnLidOpen: false,
        ])
    }

    static var screenOffOnLidClose: Bool { UserDefaults.standard.bool(forKey: Key.screenOffOnLidClose) }
    static var allowOnBattery:      Bool { UserDefaults.standard.bool(forKey: Key.allowOnBattery) }
    static var batteryFloorPercent: Int  { UserDefaults.standard.integer(forKey: Key.batteryFloorPercent) }
    static var keepAwakeLidOpen:    Bool { UserDefaults.standard.bool(forKey: Key.keepAwakeLidOpen) }
    static var keepScreenOnLidOpen: Bool { UserDefaults.standard.bool(forKey: Key.keepScreenOnLidOpen) }
}

/// The Settings window content — native toggles, plain language for non-technical users.
struct SettingsView: View {
    @AppStorage(Settings.Key.screenOffOnLidClose) private var screenOff = true
    @AppStorage(Settings.Key.allowOnBattery)      private var allowOnBattery = false
    @AppStorage(Settings.Key.batteryFloorPercent) private var floor = 20
    @AppStorage(Settings.Key.keepAwakeLidOpen)    private var keepOpen = true
    @AppStorage(Settings.Key.keepScreenOnLidOpen) private var screenOnOpen = false

    var body: some View {
        Form {
            Section {
                Text("When it's on, lidawake keeps your Mac awake even with the lid closed. These settings fine-tune what happens.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("When you close the lid") {
                Toggle("Turn the screen off", isOn: $screenOff)
                Toggle("Keep going on battery power", isOn: $allowOnBattery)
                if allowOnBattery {
                    Stepper("Stop when the battery reaches \(floor)%", value: $floor, in: 10...90, step: 5)
                    Label("Closing the lid blocks cooling. On battery with the lid shut your Mac can get warm — keep it on a hard, flat surface.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("When the lid is open") {
                Toggle("Also keep my Mac awake", isOn: $keepOpen)
                if keepOpen {
                    Toggle("Keep the screen on too", isOn: $screenOnOpen)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 430)
    }
}

/// Lazily-created, reused Settings window hosting `SettingsView`.
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: host)
            w.title = "lidawake Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
