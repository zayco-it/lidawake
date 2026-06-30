import Foundation

/// The actual privileged work, exposed over XPC. Runs as root. The single
/// privileged operation is `pmset -a disablesleep 0|1`; there is deliberately
/// nothing else here to abuse.
final class HelperImplementation: NSObject, LidAwakeHelperProtocol {

    /// Whether THIS client currently holds the awake-lock. Read by the
    /// connection's invalidation handler to power the dead man's switch.
    private(set) var disableSleepActive = false

    /// Run pmset with the given args as root. Returns the exit status,
    /// or -1 if the process couldn't be launched.
    @discardableResult
    static func runPmset(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = args
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus }
        catch { return -1 }
    }

    func setDisableSleep(_ disable: Bool, reply: @escaping (String?) -> Void) {
        switch HelperImplementation.runPmset(["-a", "disablesleep", disable ? "1" : "0"]) {
        case 0:
            disableSleepActive = disable
            NSLog("[lidawake-helper] disablesleep -> \(disable ? 1 : 0)")
            reply(nil)
        case -1:
            reply("failed to run pmset")
        case let status:
            reply("pmset exited with status \(status)")
        }
    }

    /// Sleep the display immediately (used when the lid closes while armed, so a
    /// closed lid isn't left backlit). Runs as root via the helper to avoid any
    /// permission ambiguity. The system stays awake; only the panel sleeps.
    func sleepDisplayNow(reply: @escaping (String?) -> Void) {
        switch HelperImplementation.runPmset(["displaysleepnow"]) {
        case 0:
            NSLog("[lidawake-helper] displaysleepnow")
            reply(nil)
        case -1:
            reply("failed to run pmset displaysleepnow")
        case let status:
            reply("pmset displaysleepnow exited with status \(status)")
        }
    }

    func helperVersion(reply: @escaping (String) -> Void) {
        reply(LidAwakeIDs.helperVersion)
    }
}
