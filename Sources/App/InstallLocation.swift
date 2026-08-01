// Where the app is installed decides whether its privileged helper can run at all.
//
// lidawake's helper is a ROOT LaunchDaemon whose executable lives inside this app
// bundle (SMAppService registers `Contents/MacOS/lidawake-helper` relative to the
// bundle). macOS refuses to spawn a root daemon out of a location a non-root user
// could rewrite — it would be a straight privilege-escalation hole — so launchd
// rejects the spawn with EX_CONFIG, silently and forever. The app sees only an
// unreachable helper, which used to leave it spinning on "Getting lidawake ready…"
// with no explanation.
//
// The commonest way a real person lands here is running lidawake straight from the
// mounted disk image instead of dragging it to Applications first.

import Foundation

enum InstallLocation {
    static var bundlePath: String { Bundle.main.bundleURL.resolvingSymlinksInPath().path }

    /// Running from a mounted disk image (the DMG the user just opened).
    static var isOnDiskImage: Bool { bundlePath.hasPrefix("/Volumes/") }

    /// Installed somewhere the privileged helper can actually be launched from.
    static var isInApplications: Bool {
        bundlePath.hasPrefix("/Applications/") || bundlePath.hasPrefix("/System/Applications/")
    }

    /// True when the helper is very unlikely to ever start from here.
    static var cannotHostHelper: Bool { !isInApplications }
}
