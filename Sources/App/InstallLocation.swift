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
//
// The same question gets asked about OTHER running copies, not just our own: the
// single-instance guard only bows out to a copy that could actually be working.
// Hence the path-taking variants below.

import Foundation

enum InstallLocation {
    static var bundlePath: String { Bundle.main.bundleURL.resolvingSymlinksInPath().path }

    /// Running from a mounted disk image (the DMG the user just opened).
    static var isOnDiskImage: Bool { bundlePath.hasPrefix("/Volumes/") }

    /// Can a copy living at this path ever launch the root helper?
    static func canHostHelper(path: String) -> Bool {
        path.hasPrefix("/Applications/") || path.hasPrefix("/System/Applications/")
    }

    /// Same question about ANOTHER running copy — i.e. is it a copy that can do
    /// lidawake's job at all? One that can't never reaches the point of putting an
    /// icon in the menu bar (see the `cannotHostHelper` early return in
    /// applicationDidFinishLaunching), so it has no claim on being "the running
    /// instance". A nil URL means macOS wouldn't tell us: assume it can, which keeps
    /// the conservative pre-1.4.3 behaviour for a case that shouldn't occur.
    static func canHostHelper(_ url: URL?) -> Bool {
        guard let url else { return true }
        return canHostHelper(path: url.resolvingSymlinksInPath().path)
    }

    /// Installed somewhere the privileged helper can actually be launched from.
    static var isInApplications: Bool { canHostHelper(path: bundlePath) }

    /// True when the helper is very unlikely to ever start from here.
    static var cannotHostHelper: Bool { !isInApplications }
}
