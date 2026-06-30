import Foundation

/// Gatekeeper for the XPC service. Authenticates every incoming connection by
/// audit token (NOT by pid — pids are racy and reusable) via
/// `setCodeSigningRequirement`, called BEFORE `resume()`. Only our own,
/// properly-signed app is allowed to request root pmset changes.
final class HelperDelegate: NSObject, NSXPCListenerDelegate {

    private let appRequirement = lidAwakeRequirement(identifier: LidAwakeIDs.appBundleID)

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // macOS 13+, audit-token based. Enforced for this connection; set before resume().
        connection.setCodeSigningRequirement(appRequirement)
        let impl = HelperImplementation()
        connection.exportedInterface = NSXPCInterface(with: LidAwakeHelperProtocol.self)
        connection.exportedObject = impl
        connection.invalidationHandler = {
            // DEAD MAN'S SWITCH: if the client that armed us vanished without a
            // clean disarm (crash / force-kill), restore sleep so a dead app can't
            // leave the Mac stuck awake. A clean disarm already sets this false.
            if impl.disableSleepActive {
                NSLog("[lidawake-helper] client gone while armed — restoring sleep (dead man's switch)")
                HelperImplementation.runPmset(["-a", "disablesleep", "0"])
            } else {
                NSLog("[lidawake-helper] connection invalidated")
            }
        }
        connection.interruptionHandler = { NSLog("[lidawake-helper] connection interrupted") }
        connection.resume()
        return true
    }
}
