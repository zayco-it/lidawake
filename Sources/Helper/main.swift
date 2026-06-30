// lidawake-helper — the root LaunchDaemon. launchd starts it on demand when the
// app opens the Mach service. Its only privileged job is `pmset disablesleep`.
// Everything else (UI, IOPMAssertion, thermal/battery policy) lives in the
// unprivileged app, so the attack surface here is one command with one argument.

import Foundation

// ── SAFETY LAYER 1 — reset-on-launch ────────────────────────────────────────
// `disablesleep` is persisted in the power-management prefs and survives reboot.
// If the app ever crashes while armed, the Mac would be stuck unable to sleep.
// launchd restarts this daemon (KeepAlive=true), and every launch unconditionally
// clears the flag first — so a crash self-heals on the next start. Not optional.
func resetDisableSleep() {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    p.arguments = ["-a", "disablesleep", "0"]
    try? p.run()
    p.waitUntilExit()
}

NSLog("[lidawake-helper] launch uid=\(getuid()) version=\(LidAwakeIDs.helperVersion)")
resetDisableSleep()

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: LidAwakeIDs.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
