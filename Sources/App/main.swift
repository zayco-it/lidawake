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
    private var isRecovering = false   // guards the auto-repair of a stale post-update helper

    /// Whether the RESIDENT helper implements the hang watchdog. After a Sparkle
    /// update launchd can still be running the previous helper binary, which doesn't
    /// export `heartbeat` — and calling a selector the remote doesn't export can
    /// invalidate the NSXPC connection, which would fire that helper's dead man's
    /// switch and silently turn lidawake off under the user. So we ask its version
    /// once per arm and only check in when it's new enough. An older helper simply
    /// behaves as it always did: no watchdog, no harm.
    private var helperHasWatchdog = false

    /// True once the helper has been genuinely set up (approved) on this Mac.
    /// Persisted. This is what lets us tell a stale helper after an update ("just
    /// reconnect") apart from a brand-new install ("first-time setup") — only the
    /// latter ever shows the Welcome window. Migrated for existing users in
    /// applicationDidFinishLaunching.
    private var helperApprovedOnce: Bool {
        get { UserDefaults.standard.bool(forKey: "helperApprovedOnce") }
        set { UserDefaults.standard.set(newValue, forKey: "helperApprovedOnce") }
    }

    private let helperManager  = HelperManager()
    private let helperClient   = HelperClient()
    private let wake           = WakeAssertionManager()
    private let thermal        = ThermalGuard()
    private let power          = PowerPolicy()
    private let lid            = LidMonitor()
    private let heartbeat      = Heartbeat()
    private let settingsWindow = SettingsWindowController()
    private let onboardingWindow = OnboardingWindowController()
    private let license = LicenseController(provider: LicenseConfig.makeProvider())
    private let licenseWindow = LicenseWindowController()
    private let preparingWindow = PreparingWindowController()
    // Sparkle auto-updater (reads SUFeedURL + SUPublicEDKey from Info.plist).
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    // Dynamic menu items, refreshed on every open.
    private var toggleItem: NSMenuItem!
    private var statusLineItem: NSMenuItem!
    private var licenseItem: NSMenuItem!
    private var approveItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        installEditMenu()

        // The helper can only be launched when we live in Applications. Anywhere else
        // — the mounted disk image, Downloads, a home folder — macOS refuses to spawn
        // it and lidawake can never work. Say so and quit BEFORE registering anything:
        // registering from such a path leaves a system-wide daemon record that keeps
        // pointing there, and clearing it needs an admin BTM reset. Refusing to start
        // is far kinder than running broken and poisoning the machine.
        // Present on the next runloop turn: an accessory (LSUIElement) app can't take
        // focus this early, so an alert shown here flashes and dies — the user would
        // just see lidawake vanish.
        if InstallLocation.cannotHostHelper {
            DispatchQueue.main.async { [weak self] in self?.showMustInstallAndQuit() }
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        thermal.onOverheat = { [weak self] in self?.autoDisarm("your Mac was getting too warm") }
        power.onViolation  = { [weak self] reason in self?.autoDisarm(reason) }
        lid.onLidClosed    = { [weak self] in self?.handleLidClosed() }
        heartbeat.onBeat   = { [weak self] in self?.sendHeartbeat() }
        thermal.start()

        // Apply setting changes LIVE while armed — no disarm/re-arm dance.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.reconcileSettings()
        }

        // Register the daemon (and surface the approval UI if it isn't enabled yet).
        _ = helperManager.ensureRegistered()

        // Decide once: existing free user (grandfathered) vs. new (start the 14-day
        // trial). MUST run before maybeShowOnboarding(), which sets "seenWelcome".
        let usedBefore = UserDefaults.standard.bool(forKey: "seenWelcome")
            || helperManager.state == .enabled
        if usedBefore { helperApprovedOnce = true }   // returning user: the helper was set up before
        license.bootstrap(usedBefore: usedBefore)
        license.revalidateIfNeeded()

        buildMenu()
        updateIcon()
        maybeShowOnboarding()
        warmUpHelperIfStale()
    }

    /// After an update, the helper launchd is actually serving may not be the one
    /// this bundle ships. Two cases, both repaired the same way:
    ///
    ///  - **unreachable** — the classic stale job: registered, mach service dead.
    ///  - **reachable but OLD** — the bundle was replaced under a running daemon, so
    ///    launchd keeps serving the previous helper binary until the next reboot.
    ///    Nothing looks wrong from the outside — arming works normally — which is
    ///    exactly why this went unnoticed. The app just silently loses every
    ///    helper-side change in the update, the hang watchdog among them. See
    ///    `HelperClient.probeCurrent` for the mechanism.
    ///
    /// Either way, reconnect QUIETLY in the background now — no window, no arming —
    /// so the right helper is up by the time the user turns lidawake on (no
    /// "Getting ready…" wait). Purely a head start: it yields the instant the user
    /// interacts (see the `!armed && !isRecovering` guards), so the click-time path
    /// always wins and this can never fight it. If the user does arm first, the
    /// reload has already killed the old daemon, so that attempt routes through
    /// `prepareAndRecover()` and lands on the new helper anyway.
    private func warmUpHelperIfStale() {
        guard helperApprovedOnce else { return }
        helperClient.probeCurrent { [weak self] current in
            guard let self, !current, !self.armed, !self.isRecovering else { return }
            NSLog("[lidawake] resident helper missing or older than the bundled \(LidAwakeIDs.helperVersion) — reloading in the background")
            self.warmUpRound(roundsLeft: 3)
        }
    }

    private func warmUpRound(roundsLeft: Int) {
        guard !armed, !isRecovering else { return }   // user took over — let the click-time path own it
        helperManager.reload()
        helperClient.disconnect()
        warmUpPoll(attemptsLeft: 24, roundsLeft: roundsLeft)   // ~14s per round
    }

    private func warmUpPoll(attemptsLeft: Int, roundsLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.armed, !self.isRecovering else { return }
            // Poll for CURRENT, not merely reachable: mid-reload the outgoing helper
            // can still answer, and treating that as success would land us right back
            // on the binary we are trying to replace.
            self.helperClient.probeCurrent { [weak self] current in
                guard let self, !self.armed, !self.isRecovering else { return }
                if current { NSLog("[lidawake] helper warmed up and ready"); return }
                if attemptsLeft > 1 {
                    self.helperClient.disconnect()
                    self.warmUpPoll(attemptsLeft: attemptsLeft - 1, roundsLeft: roundsLeft)
                } else if roundsLeft > 1 {
                    self.warmUpRound(roundsLeft: roundsLeft - 1)
                }
                // else: give up quietly — the click-time reconnect is the safety net
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // SAFETY: never leave sleep disabled behind us. Synchronous restore.
        if armed { helperClient.setDisableSleepSync(false) }
        stopArmedWatchers()
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

        // Trial/buy line — clickable to open the buy / enter-key window. Hidden once
        // licensed or grandfathered.
        licenseItem = NSMenuItem(title: "", action: #selector(showLicense), keyEquivalent: "")
        licenseItem.target = self
        menu.addItem(licenseItem)

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

    /// An accessory (LSUIElement) app shows no menu bar, so text fields lose the
    /// standard Cut/Copy/Paste/Select-All shortcuts (macOS routes them through the
    /// Edit menu). Install a minimal Edit menu so the key-equivalents are handled —
    /// the menu bar stays hidden for an accessory app. Needed for the license field.
    private func installEditMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
    }

    // Helper status isn't pushed, so refresh whenever the menu opens.
    func menuWillOpen(_ menu: NSMenu) { refreshItems() }

    private func refreshItems() {
        let helperEnabled = (helperManager.state == .enabled)
        let entitled = license.isEntitled
        approveItem.isHidden = helperEnabled
        toggleItem.state = armed ? .on : .off
        toggleItem.isEnabled = helperEnabled && entitled && !isRecovering

        // Trial / buy line — only while unlicensed.
        switch license.status {
        case .licensed, .grandfathered:
            licenseItem.isHidden = true
        case .trial(let d):
            licenseItem.isHidden = false
            licenseItem.title = "Free trial \u{2014} \(d) day\(d == 1 ? "" : "s") left \u{2014} Buy\u{2026}"
        case .expired:
            licenseItem.isHidden = false
            licenseItem.title = "Free trial ended \u{2014} Buy lidawake\u{2026}"
        }

        // Status line.
        if isRecovering {
            statusLineItem.title = "Reconnecting lidawake\u{2019}s helper\u{2026}"
        } else if !helperEnabled {
            statusLineItem.title = "Finish the one-time setup to begin"
        } else if !entitled {
            statusLineItem.title = "Your free trial has ended \u{2014} buy to keep using lidawake"
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

    /// Buy / enter-license window. Refresh the menu after, since status may change.
    @objc private func showLicense() {
        licenseWindow.show(controller: license) { [weak self] in self?.refreshItems() }
    }

    /// Native About panel — name, version, copyright, plus a line showing the current
    /// license state (trial days left / licensed) in the credits area.
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let line: String
        switch license.status {
        case .licensed:      line = "Licensed \u{2014} thank you!"
        case .grandfathered: line = "Licensed \u{2014} early supporter, thank you!"
        case .trial(let d):  line = "Free trial \u{2014} \(d) day\(d == 1 ? "" : "s") left"
        case .expired:       line = "Free trial ended \u{2014} buy to keep using lidawake"
        }
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let credits = NSAttributedString(string: line, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: para,
        ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
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
        // Only a genuine first-time user (helper never approved) gets the Welcome
        // window. A returning user whose helper is merely stale after an update is
        // guided by the "Getting ready…" flow when they turn on — never onboarding.
        if !helperApprovedOnce && helperManager.state != .enabled {
            showOnboarding()
        }
        UserDefaults.standard.set(true, forKey: "seenWelcome")
    }

    @objc private func toggleArmed() {
        guard !isRecovering else { return }   // busy recovering the helper — ignore clicks
        if armed { disarm() } else { arm() }
    }

    private func arm() {
        // Paywall gate: no arming once the trial's over and there's no license.
        guard license.isEntitled else { showLicense(); return }
        // Genuine first-time setup ONLY (helper never approved on this Mac) → the
        // friendly Welcome window. A previously-approved helper that's merely
        // unreachable (stale after an update) must NOT come here — it goes through
        // the "Getting ready…" recovery instead, so the Welcome window can't reappear.
        if !helperApprovedOnce && helperManager.state != .enabled {
            _ = helperManager.ensureRegistered()
            showOnboarding()
            return
        }
        let (ok, reason) = PowerPolicy.armingAllowed()
        guard ok else { offerSettings("Can\u{2019}t turn on yet", reason ?? "Power policy refused."); return }

        helperClient.setDisableSleep(true) { [weak self] err in   // completion on main
            guard let self else { return }
            if let err {
                if err.isUnreachable { self.prepareAndRecover() }   // stale helper: reconnect + retry
                else { self.notify("Couldn\u{2019}t turn on", err.message) }
                return
            }
            self.finishArming()
        }
    }

    /// Wire up the app side once the helper has accepted disablesleep(true):
    /// lid-open assertions, live power watch, lid-close watcher, UI. Idempotent
    /// (its sub-parts guard against double-start), so it's safe to reach here from
    /// either a normal arm or the recovery probe.
    private func finishArming() {
        helperApprovedOnce = true    // the helper answered → it's genuinely set up on this Mac
        preparingWindow.close()      // no-op if it wasn't showing
        wake.apply(systemAwake: Settings.keepAwakeLidOpen,
                   screenOn: Settings.keepAwakeLidOpen && Settings.keepScreenOnLidOpen)
        power.startMonitoring()
        lid.start()
        armed = true
        refreshItems(); updateIcon()
        startWatchdogHeartbeat()
    }

    /// Everything that only runs while armed, torn down in one place — there are
    /// four disarm paths (manual, safety trip, uninstall, quit) and a watcher that
    /// has to be remembered in each of them is a watcher that will be forgotten.
    private func stopArmedWatchers() {
        wake.release()
        power.stopMonitoring()
        lid.stop()
        heartbeat.stop()
    }

    /// Begin checking in with the helper's hang watchdog — but only once we know the
    /// resident helper actually has one (see `helperHasWatchdog`).
    private func startWatchdogHeartbeat(retriesLeft: Int = 3) {
        helperHasWatchdog = false
        helperClient.helperVersion { [weak self] version in
            guard let self, self.armed else { return }
            guard let version else {
                // Couldn't reach it to ask — usually transient (a connection torn down
                // mid-reconnect). Worth retrying, because "armed with nobody watching"
                // is precisely the state this whole feature exists to prevent.
                guard retriesLeft > 0 else {
                    NSLog("[lidawake] couldn't reach the helper to ask about its watchdog — not checking in")
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, self.armed else { return }
                    self.startWatchdogHeartbeat(retriesLeft: retriesLeft - 1)
                }
                return
            }
            guard lidAwakeVersionAtLeast(version, LidAwakeWatchdog.minHelperVersion) else {
                NSLog("[lidawake] helper \(version) predates the hang watchdog — not checking in")
                return
            }
            self.helperHasWatchdog = true
            self.heartbeat.start()
        }
    }

    /// One check-in, sent from the main run loop (that's the point — see Heartbeat).
    /// The reply is the helper's own view of our state: if it says sleep is no longer
    /// disabled for us, it gave up on us while we were unresponsive and restored it.
    /// We are then off, whatever the menu says, so reconcile rather than keep showing
    /// a checked toggle over a Mac that now sleeps normally.
    private func sendHeartbeat() {
        guard armed, helperHasWatchdog else { return }
        helperClient.heartbeat { [weak self] stillDisabled in
            guard let self, self.armed else { return }
            guard let stillDisabled else { return }   // unreachable — not a trip
            guard !stillDisabled else { return }      // normal case: still armed
            NSLog("[lidawake] helper watchdog restored sleep while we were unresponsive — reconciling to off")
            self.stopArmedWatchers()
            self.armed = false
            self.refreshItems(); self.updateIcon()
        }
    }

    private func disarm() {
        helperClient.setDisableSleep(false) { [weak self] err in
            guard let self else { return }
            if let err { NSLog("[lidawake] disarm error: \(err.message)") }
            self.stopArmedWatchers()
            self.armed = false
            self.refreshItems(); self.updateIcon()
        }
    }

    /// Triggered by the safety guards (thermal/power). Restore immediately with a
    /// synchronous call — no async wait — then update UI.
    private func autoDisarm(_ why: String) {
        guard armed else { return }
        helperClient.setDisableSleepSync(false)
        stopArmedWatchers()
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
        // Clamshell: with an external monitor connected, closing the lid means the
        // user wants to keep using it — never sleep the external. Only sleep the
        // screen when the built-in panel is the only display (nothing to see behind
        // a closed lid). Fixes "external monitor goes dark on lid close".
        if Displays.hasExternal() {
            NSLog("[lidawake] lid closed with an external display — leaving screens on (clamshell)")
            return
        }
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
        stopArmedWatchers(); armed = false
        let removed = helperManager.unregister()
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        let done = NSAlert()
        if removed {
            done.messageText = "lidawake removed"
            done.informativeText = "The background helper is gone and your settings were cleared. Drag lidawake to the Trash to finish. Quitting now\u{2026}"
            done.addButton(withTitle: "OK")
        } else {
            // Don't claim a clean removal we didn't achieve — macOS can refuse to
            // drop the registration, and it then lingers in Login Items.
            done.messageText = "lidawake\u{2019}s settings were cleared"
            done.informativeText = "Your Mac will sleep normally again, but macOS didn\u{2019}t remove lidawake\u{2019}s background item. You can switch it off in System Settings \u{203A} Login Items.\n\nAfterwards, drag lidawake to the Trash to finish."
            done.addButton(withTitle: "Open Login Items\u{2026}")
            done.addButton(withTitle: "OK")
        }
        if done.runModal() == .alertFirstButtonReturn && !removed {
            helperManager.openLoginItems()
        }
        NSApp.terminate(nil)
    }

    /// Shown when lidawake isn't installed in Applications, so its helper could never
    /// start. Offers to open the Applications folder so the drag is one step away.
    /// Shown when lidawake isn't installed in Applications, so its helper could never
    /// start. Uses the same window as the "Getting ready…" flow rather than an
    /// NSAlert: an accessory (LSUIElement) app can't reliably bring a modal alert to
    /// the front at launch — it just bounces in the Dock with nothing readable.
    /// A real window ordered front works, and is what the rest of the app already uses.
    private func showMustInstallAndQuit() {
        NSApp.setActivationPolicy(.regular)   // a Dock presence so it can come forward
        preparingWindow.model.onOpenApplications = {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        }
        preparingWindow.model.onCancel = { NSApp.terminate(nil) }
        preparingWindow.showFailedNeedsMove(onDiskImage: InstallLocation.isOnDiskImage)
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

    /// The helper is registered but unreachable — the classic "stale daemon after
    /// a Sparkle update" state, where `status` still reads `.enabled` but the mach
    /// service is dead. Re-register the daemon (what a Login Items disable→enable
    /// does by hand), give launchd a moment to start the fresh helper, then retry
    /// arming once. Only runs when the helper is genuinely unreachable, so a
    /// healthy install is never touched.
    /// The helper is registered but unreachable — the stale-after-update state.
    /// Show a "Getting ready…" window, re-register the daemon, then keep probing the
    /// REAL turn-on until the helper answers (gating on reachability, not the
    /// registration status, which lies about readiness). Arms and closes the window
    /// the instant it answers; NEVER shows the Welcome window.
    private func prepareAndRecover() {
        guard !isRecovering else { return }
        isRecovering = true
        preparingWindow.model.onRetry = { [weak self] in self?.preparingWindow.close(); self?.arm() }
        preparingWindow.model.onOpenLoginItems = { [weak self] in self?.helperManager.openLoginItems() }
        preparingWindow.model.onOpenApplications = {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        }
        preparingWindow.model.onCancel = { [weak self] in
            self?.isRecovering = false
            self?.preparingWindow.close()
            self?.refreshItems()
        }
        preparingWindow.showPreparing()
        refreshItems()
        NSLog("[lidawake] helper unreachable — reconnecting")
        reconnectRound(roundsLeft: 3)
    }

    /// One reconnect attempt: re-register the daemon, then poll the real turn-on for
    /// a while. If this round runs out, start another round with a fresh
    /// re-registration — this AUTOMATES the manual "Try Again" that reliably works
    /// (a freshly-registered daemon can take a while to come up after an update), so
    /// the user never has to click it. Gives up only after several rounds.
    private func reconnectRound(roundsLeft: Int) {
        NSLog("[lidawake] reconnect round (\(roundsLeft) remaining) — reload + poll")
        helperManager.reload()
        helperClient.disconnect()
        pollRound(attemptsLeft: 24, roundsLeft: roundsLeft)   // ~14s per round
    }

    private func pollRound(attemptsLeft: Int, roundsLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.isRecovering else { return }
            self.helperClient.setDisableSleep(true) { [weak self] err in
                guard let self, self.isRecovering else { return }
                guard let err else {                     // helper answered -> arm + close the window
                    self.isRecovering = false
                    self.finishArming()
                    return
                }
                if err.isUnreachable, attemptsLeft > 1 {
                    self.helperClient.disconnect()       // fresh connection each probe
                    self.pollRound(attemptsLeft: attemptsLeft - 1, roundsLeft: roundsLeft)
                    return
                }
                if err.isUnreachable, roundsLeft > 1 {
                    self.reconnectRound(roundsLeft: roundsLeft - 1)   // auto "Try Again"
                    return
                }
                // Genuinely not coming back — error state (retry / Login Items), never onboarding.
                self.isRecovering = false
                self.refreshItems()
                // If we're installed somewhere the helper can't legally be launched
                // from, no amount of retrying will help — name the real cause.
                if err.isUnreachable, InstallLocation.cannotHostHelper {
                    self.preparingWindow.showFailedNeedsMove()
                } else if err.isUnreachable { self.preparingWindow.showFailed() }
                else { self.preparingWindow.close(); self.notify("Couldn\u{2019}t turn on", err.message) }
            }
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

// Single-instance guard: if another copy of lidawake is already running (classic
// cause: launched once from the mounted DMG and again from /Applications), bow out
// quietly so the user never ends up with two menu-bar icons. The instance already
// holding the menu bar keeps running; this later launch just exits.
if let bundleID = Bundle.main.bundleIdentifier {
    let mine = NSRunningApplication.current.processIdentifier
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0.processIdentifier != mine }
    if !others.isEmpty {
        NSLog("[lidawake] another instance is already running — exiting this one")
        exit(0)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
