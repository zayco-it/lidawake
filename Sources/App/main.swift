// lidawake — Milestone 3 (UI).
// Menu-bar app that keeps the Mac awake with the lid closed via a root
// SMAppService helper (pmset disablesleep) reached over XPC. The daily control is
// one menu toggle ("Keep my Mac awake"); behaviour is tuned in a small SwiftUI
// Settings window. Safety guards (thermal / battery / dead-man's switch) stay on.
//
// Build: ./build.sh   Sign+build: SIGN=1 ./build.sh   Run: open build/lidawake.app

import AppKit
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var armed = false

    private let helperManager  = HelperManager()
    private let helperClient   = HelperClient()
    private let wake           = WakeAssertionManager()
    private let thermal        = ThermalGuard()
    private let power          = PowerPolicy()
    private let lid            = LidMonitor()
    private let settingsWindow = SettingsWindowController()
    private let onboardingWindow = OnboardingWindowController()
    // Sparkle auto-updater (reads SUFeedURL + SUPublicEDKey from Info.plist).
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    // Dynamic menu items, refreshed on every open.
    private var toggleItem: NSMenuItem!
    private var statusLineItem: NSMenuItem!
    private var approveItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        thermal.onOverheat = { [weak self] in self?.autoDisarm("your Mac was getting too warm") }
        power.onViolation  = { [weak self] in self?.autoDisarm("it was unplugged from power") }
        lid.onLidClosed    = { [weak self] in self?.handleLidClosed() }
        thermal.start()

        // Apply setting changes LIVE while armed — no disarm/re-arm dance.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.reconcileSettings()
        }

        // Register the daemon (and surface the approval UI if it isn't enabled yet).
        _ = helperManager.ensureRegistered()

        buildMenu()
        updateIcon()
        maybeShowOnboarding()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // SAFETY: never leave sleep disabled behind us. Synchronous restore.
        if armed { helperClient.setDisableSleepSync(false) }
        wake.release()
        power.stopMonitoring()
        lid.stop()
        thermal.stop()
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // The one daily control: a checkable "Keep my Mac awake".
        toggleItem = NSMenuItem(title: "Keep my Mac awake", action: #selector(toggleArmed), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        statusLineItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusLineItem.isEnabled = false
        menu.addItem(statusLineItem)

        menu.addItem(.separator())

        // Shown only until the one-time helper approval is done.
        approveItem = NSMenuItem(title: "Finish setup\u{2026}", action: #selector(approveHelper), keyEquivalent: "")
        approveItem.target = self
        menu.addItem(approveItem)

        let aboutItem = NSMenuItem(title: "About lidawake", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Custom action so we can activate the app first (see checkForUpdates()).
        let updatesItem = NSMenuItem(title: "Check for Updates\u{2026}",
                                     action: #selector(checkForUpdates),
                                     keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)

        menu.addItem(.separator())

        let uninstallItem = NSMenuItem(title: "Uninstall lidawake\u{2026}", action: #selector(uninstall), keyEquivalent: "")
        uninstallItem.target = self
        menu.addItem(uninstallItem)

        let quit = NSMenuItem(title: "Quit lidawake", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        refreshItems()
    }

    // Helper status isn't pushed, so refresh whenever the menu opens.
    func menuWillOpen(_ menu: NSMenu) { refreshItems() }

    private func refreshItems() {
        let enabled = (helperManager.state == .enabled)
        approveItem.isHidden = enabled
        toggleItem.state = armed ? .on : .off
        toggleItem.isEnabled = enabled
        if !enabled {
            statusLineItem.title = "Finish the one-time setup to begin"
        } else if armed {
            statusLineItem.title = "On \u{2014} you can close the lid"
        } else {
            statusLineItem.title = "Off \u{2014} your Mac will sleep normally"
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let base = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "lidawake")
        if armed {
            // brand-blue laptop = actively keeping awake
            let blue = NSColor(srgbRed: 90/255.0, green: 170/255.0, blue: 1.0, alpha: 1)
            let img = base?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [blue]))
            img?.isTemplate = false
            button.image = img
        } else {
            base?.isTemplate = true        // monochrome, adapts to the menu bar
            button.image = base
        }
    }

    // MARK: - Actions

    @objc private func approveHelper() { showOnboarding() }
    @objc private func openSettings()  { settingsWindow.show() }

    /// Native About panel — shows name, version, and copyright from Info.plist + the app icon.
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    // Activate first (we're an accessory app) so Sparkle's window takes focus on the
    // FIRST click — otherwise the first check's window can't hold focus and vanishes.
    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    private func showOnboarding() {
        onboardingWindow.show(
            isEnabled: { [weak self] in self?.helperManager.state == .enabled },
            openLoginItems: { [weak self] in self?.helperManager.openLoginItems() })
    }

    /// Show the Welcome window on the first launch, or whenever the helper still
    /// needs approval — so a new user is always guided to the one setup step.
    private func maybeShowOnboarding() {
        let seen = UserDefaults.standard.bool(forKey: "seenWelcome")
        if !seen || helperManager.state != .enabled {
            showOnboarding()
            UserDefaults.standard.set(true, forKey: "seenWelcome")
        }
    }

    @objc private func toggleArmed() {
        if armed { disarm() } else { arm() }
    }

    private func arm() {
        guard helperManager.state == .enabled else {
            _ = helperManager.ensureRegistered()
            showOnboarding()
            return
        }
        let (ok, reason) = PowerPolicy.armingAllowed()
        guard ok else { offerSettings("Can\u{2019}t turn on yet", reason ?? "Power policy refused."); return }

        helperClient.setDisableSleep(true) { [weak self] err in   // completion on main
            guard let self else { return }
            if let err {
                if err.isUnreachable { self.helperNotReady() }
                else { self.notify("Couldn\u{2019}t turn on", err.message) }
                return
            }
            self.wake.apply(systemAwake: Settings.keepAwakeLidOpen,
                            screenOn: Settings.keepAwakeLidOpen && Settings.keepScreenOnLidOpen)  // lid-open assertions
            self.power.startMonitoring()     // live AC/battery watch
            self.lid.start()                 // watch for lid close -> sleep display
            self.armed = true
            self.refreshItems(); self.updateIcon()
        }
    }

    private func disarm() {
        helperClient.setDisableSleep(false) { [weak self] err in
            guard let self else { return }
            if let err { NSLog("[lidawake] disarm error: \(err.message)") }
            self.wake.release()
            self.power.stopMonitoring()
            self.lid.stop()
            self.armed = false
            self.refreshItems(); self.updateIcon()
        }
    }

    /// Triggered by the safety guards (thermal/power). Restore immediately with a
    /// synchronous call — no async wait — then update UI.
    private func autoDisarm(_ why: String) {
        guard armed else { return }
        helperClient.setDisableSleepSync(false)
        wake.release()
        power.stopMonitoring()
        lid.stop()
        armed = false
        refreshItems(); updateIcon()
        notify("lidawake turned off", "Stopped because \(why).")
    }

    /// Re-apply settings live while armed, so flipping a toggle takes effect
    /// immediately (no disarm/re-arm). Idempotent; safe on any UserDefaults change.
    private func reconcileSettings() {
        guard armed else { return }
        // A power-setting change may make being armed unsafe here (e.g. battery no
        // longer allowed) — cut out cleanly if so.
        let (ok, _) = PowerPolicy.armingAllowed()
        guard ok else { autoDisarm("battery use isn\u{2019}t allowed with the new settings"); return }
        wake.apply(systemAwake: Settings.keepAwakeLidOpen,
                   screenOn: Settings.keepAwakeLidOpen && Settings.keepScreenOnLidOpen)
    }

    /// Lid just closed while armed — sleep the display (if the user wants it) so a
    /// closed lid isn't left backlit. The system stays awake; only the panel sleeps.
    private func handleLidClosed() {
        guard armed, Settings.screenOffOnLidClose else { return }
        helperClient.sleepDisplayNow { err in
            if let err { NSLog("[lidawake] sleepDisplayNow error: \(err)") }
        }
    }

    /// Cleanly remove the privileged helper (a privileged-helper app must offer
    /// this). Restores sleep, unregisters the daemon, clears settings, then quits.
    @objc private func uninstall() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Remove lidawake from your Mac?"
        a.informativeText = "This turns keep-awake off and removes its background helper. Your Mac will sleep normally again. Afterwards, drag lidawake to the Trash to finish."
        a.addButton(withTitle: "Remove")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }

        if armed { helperClient.setDisableSleepSync(false) }   // never leave sleep disabled behind
        wake.release(); power.stopMonitoring(); lid.stop(); armed = false
        helperManager.unregister()
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        let done = NSAlert()
        done.messageText = "lidawake removed"
        done.informativeText = "The background helper is gone and your settings were cleared. Drag lidawake to the Trash to finish. Quitting now\u{2026}"
        done.runModal()
        NSApp.terminate(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)   // applicationWillTerminate does the safety restore
    }

    private func notify(_ title: String, _ body: String) {
        NSLog("[lidawake] \(title): \(body)")
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body
        a.runModal()
    }

    /// The helper isn't answering yet — almost always because it's still starting
    /// (it self-restarts via KeepAlive, which can take a few seconds after an
    /// update or a restart). Honest message + one-click retry; Login Items is the
    /// last resort if it genuinely never comes up.
    private func helperNotReady() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Just a moment \u{2014} lidawake is starting up"
        a.informativeText = "Its background helper isn\u{2019}t ready yet. Give it a few seconds, then try again."
        a.addButton(withTitle: "Try Again")
        a.addButton(withTitle: "Open Login Items\u{2026}")
        a.addButton(withTitle: "Cancel")
        switch a.runModal() {
        case .alertFirstButtonReturn:  arm()                       // retry once the helper is up
        case .alertSecondButtonReturn: helperManager.openLoginItems()
        default: break
        }
    }

    /// Like `notify`, but offers a one-click jump to Settings — used when the
    /// refusal is something the user can fix there (e.g. allow battery use).
    private func offerSettings(_ title: String, _ body: String) {
        NSLog("[lidawake] \(title): \(body)")
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body
        a.addButton(withTitle: "Open Settings\u{2026}")
        a.addButton(withTitle: "OK")
        if a.runModal() == .alertFirstButtonReturn { settingsWindow.show() }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
