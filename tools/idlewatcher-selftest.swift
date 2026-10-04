// The quiet rule, tested without a machine: QuietPolicy, the median windows,
// the two classification rules, the mode transitions, the status line, the
// tooltips and the stop message. Every threshold is passed in explicitly; the
// fixtures are what E10 and E11 actually met on macOS 27.0.1 (spec §11.6).
//
//   swiftc -O -parse-as-library Sources/App/IdleWatcher.swift Sources/App/ArmMode.swift \
//       tools/idlewatcher-selftest.swift -o /tmp/lidawake-idle-selftest && /tmp/lidawake-idle-selftest
//
// MUTATION-CHECKED — each of these, made on purpose, fails at least one check
// (tools/idlewatcher-mutations.sh runs them all):
//   - `nil` readings treated as "nothing"          → "stub never stops", "… unreadable alone"
//   - `>=` window → `>`                             → "stops at exactly 30 min"
//   - median → mean                                 → "E5 replay", "two spikes in ten"
//   - minimumSamples ignored                        → "one sample is not sustained"
//   - note() allowed to move backwards              → "presence cannot move the last moment back"
//   - ties broken by later Signal                   → "tie goes to presence"
//   - switching modes touching the helper           → "switch: helper untouched"
//   - program windows never decaying                → "a program that stopped lets go"
//   - audio matched on any holder                   → "Music's own assertion is not sound", "caffeinate …"
//   - video excluding own pid only                  → "another account's lidawake is not video"
//   - Apple's .app bundles counted as work          → "Siri AI is macOS's own"
//   - an orphaned job treated as macOS's own        → "a nohup job is work"
//   - the agent-loop sentence dropped from a tooltip → "both tooltips say where an agent in a loop belongs"

import Foundation

var failures = 0
func expect(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { print("  PASS  \(label)") }
    else { print("  FAIL  \(label)  \(detail())"); failures += 1 }
}

// The test's own numbers — not the app's.
let T: Thresholds = {
    var t = Thresholds()
    t.quietWindow = 1800; t.medianSamples = 10; t.minimumSamples = 3
    t.programCores = 0.5; t.gpuPercent = 50; t.networkKBps = 30
    return t
}()
let tick: TimeInterval = 30
let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
func P(_ name: String, _ pid: Int32 = 100) -> Program { Program(name: name, pid: pid) }

/// Everything readable, nothing happening, last input at `lastInput`.
func quiet(now: Date, lastInput: Date = t0) -> Readings {
    var r = Readings()
    r.presenceAge = now.timeIntervalSince(lastInput)
    r.audioHeld = false; r.videoHolders = []; r.programCores = [:]
    r.gpuPercent = 5; r.networkKBps = 7
    return r
}

/// Run `policy` from t0 in 30 s ticks, feeding `readings(now)`, until it stops
/// or `limit` seconds pass. Returns the time it stopped, or nil.
func run(_ policy: inout QuietPolicy, limit: TimeInterval, _ readings: (Date) -> Readings) -> TimeInterval? {
    var s: TimeInterval = 0
    while s <= limit {
        s += tick
        let now = at(s)
        policy.observe(readings(now), at: now)
        if policy.shouldStop(at: now) { return s }
    }
    return nil
}

// E5's sixty network samples (research/e5-floor.log, 2026-09-06): the run the
// old rule read as BUSY on its 30-minute mean, on five spikes.
let e5KBps: [Double] = [5.9,7.2,1.7,7.8,2.5,12.1,5.4,10.5,5.6,7.0,1282.3,7.7,6.6,8.8,3.8,53.5,1.7,7.7,14.1,12.5,
                        157.4,6.0,7.4,9.7,3.3,20.3,3.5,12.0,7.6,12.6,12.4,11.1,10.5,5.7,7.6,6.6,9.5,10.5,3.1,18.9,
                        3.8,13.8,2.6,3.2,1.6,2.8,2.3,7.8,1.8,3.8,2.0,2.7,3.9,5.6,1.2,2.5,1.2,4.1,1.7,2.7]

// What the assertion table actually held in E10 and E10b, as (pid, process, TRUE type, name).
func row(_ pid: Int32, _ process: String, _ type: String, _ name: String) -> AssertionRow {
    AssertionRow(pid: pid, process: process, trueType: type, name: name)
}
let SYS = "PreventUserIdleSystemSleep", DISP = "PreventUserIdleDisplaySleep"
let baseline: [AssertionRow] = [   // lid shut, nothing playing — every one of these was seen
    row(376, "powerd", SYS, "Powerd - Prevent sleep while display is on"),
    row(417, "bluetoothd", SYS, "com.apple.BTStack"),
    row(440, "runningboardd", SYS, "osservice<com.apple.dataaccess.dataaccessd>440-1786-12274:com.apple.CFNetwork.StorageDB"),
    row(901, "AddressBookSourceSync", SYS, "Address Book Source Sync"),
    row(612, "sharingd", SYS, "Handoff"),
    row(376, "powerd", "InternalPreventDisplaySleep", "com.apple.powermanagement.delayDisplayOff"),
    row(520, "mds_stores", "BackgroundTask", "com.apple.metadata.mds_stores.power"),
    row(435, "WindowServer", "UserIsActive", "com.apple.iohideventsystem.queue.tickle … product:MX KEYS S eventType:3"),
]
let me: Int32 = 2250

@main struct SelfTest {
    static func main() {
        print("the window: median")
        var w = MedianWindow(capacity: 10)
        expect("empty has no median", w.median == nil)
        w.add(3); expect("one sample: itself", w.median == 3)
        w.add(9); expect("two samples: the mean of both", w.median == 6)
        w.add(1); expect("three: the middle one", w.median == 3)
        for _ in 0..<20 { w.add(100) }
        expect("rolls: capacity holds", w.count == 10 && w.median == 100)
        var z = MedianWindow(capacity: 3); z.add(0); z.add(0)
        expect("not full → not allZero-prunable yet", !z.isFull && z.allZero)
        z.add(0); expect("full of zeros", z.isFull && z.allZero)
        var spikes = MedianWindow(capacity: 10)
        for v in [1.0, 1300, 2, 3, 160, 2, 1, 2, 3, 2] { spikes.add(v) }
        expect("two spikes in ten do not move the median", !spikes.sustained(over: 30, minimum: 3), "median \(spikes.median ?? -1)")
        var one = MedianWindow(capacity: 10); one.add(500)
        expect("one sample is not sustained", !one.sustained(over: 30, minimum: 3))
        var six = MedianWindow(capacity: 10)
        for v in [40.0, 40, 40, 40, 40, 40, 1, 1, 1, 1] { six.add(v) }
        expect("six of ten over is sustained", six.sustained(over: 30, minimum: 3))

        print("the rule: nothing happening")
        var p = QuietPolicy(thresholds: T, start: t0)
        expect("starting is activity", p.quietAge(at: t0) == 0 && p.lastActivity.signal == .presence)
        var stopped = run(&p, limit: 3600) { now in quiet(now: now) }
        expect("stops at exactly 30 min", stopped == 1800, "stopped at \(stopped ?? -1)")
        expect("last activity is the click", p.lastActivity == Activity(.presence, at: t0))
        p = QuietPolicy(thresholds: T, start: t0)
        _ = run(&p, limit: 1770) { now in quiet(now: now) }
        expect("29.5 min is not 30", !p.shouldStop(at: at(1770)))

        print("the rule: nothing readable")
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { _ in Readings() }
        expect("stub never stops", stopped == nil && p.quietAge(at: at(7200)) == 0)
        expect("and says why", !p.lastActivity.readable && p.lastActivity.description.hasSuffix("could not be checked"))
        for (label, blank) in [("presence", { (r: inout Readings) in r.presenceAge = nil }),
                               ("sound", { r in r.audioHeld = nil }), ("video", { r in r.videoHolders = nil }),
                               ("programs", { r in r.programCores = nil }), ("the graphics chip", { r in r.gpuPercent = nil }),
                               ("the network", { r in r.networkKBps = nil })] as [(String, (inout Readings) -> Void)] {
            p = QuietPolicy(thresholds: T, start: t0)
            stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); blank(&r); return r }
            expect("\(label) unreadable alone holds everything", stopped == nil && !p.lastActivity.readable)
        }

        print("presence")
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in quiet(now: now, lastInput: now <= at(600) ? now : at(600)) }
        expect("typing until 10 min → off at 40", stopped == 2400, "stopped at \(stopped ?? -1)")
        expect("names you", p.lastActivity.description == "you using the Mac" && p.lastActivity.at == at(600))
        p = QuietPolicy(thresholds: T, start: t0)
        p.observe(quiet(now: at(30), lastInput: at(-5000)), at: at(30))
        expect("presence cannot move the last moment back", p.lastActivity.at == t0)

        print("sound and video")
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); r.audioHeld = now > at(300) && now <= at(900); return r }
        expect("audio until 15 min → off at 45", stopped == 2700, "stopped at \(stopped ?? -1)")
        expect("names the sound, at the last held sample", p.lastActivity.description == "sound playing" && p.lastActivity.at == at(900))
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); r.videoHolders = now <= at(1200) ? ["QuickTime Player"] : []; return r }
        expect("video until 20 min → off at 50", stopped == 3000, "stopped at \(stopped ?? -1)")
        expect("names the player", p.lastActivity.description == "video playing in QuickTime Player")

        // THE MEDIAN'S LAG. A load signal is "sustained" while the median of the
        // last ten samples is over the threshold, so after the load ENDS it stays
        // sustained until more than half the window is below: the fifth under-
        // sample if the midpoint of (over, under) is already below the threshold,
        // the sixth if not. Bounded by half the window — 2.5 min — and in the safe
        // direction. Spec §11.2 says so; these pin it.
        print("your programs")
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); r.programCores = now <= at(1800) ? [P("Ollama"): 0.9, P("Slack", 7): 0.1] : [:]; return r }
        expect("a busy program until 30 min → off at 60 + 4 ticks ((0.9+0)/2 < 0.5)", stopped == 3600 + 4 * tick, "stopped at \(stopped ?? -1)")
        expect("names the program", p.lastActivity.description == "Ollama working")
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); r.programCores = now == at(600) ? [P("Finder"): 3.0] : [:]; return r }
        expect("a single 30 s spike is not work", stopped == 1800, "stopped at \(stopped ?? -1)")
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in
            var r = quiet(now: now)
            if now <= at(300) { r.programCores = [P("clang"): 1.0] }           // a build, 5 min
            else if now <= at(600) { r.programCores = [:] }                    // gone
            else { r.programCores = [P("Slack", 7): 0.05] }                    // something else, idle
            return r
        }
        expect("a program that stopped lets go: off at 35 + 5 ticks ((1.0+0)/2 ≥ 0.5)", stopped == 2100 + 5 * tick, "stopped at \(stopped ?? -1)")
        expect("…and is still the last thing named, at the last sustained tick", p.lastActivity.description == "clang working" && p.lastActivity.at == at(300 + 5 * tick), "at \(p.lastActivity.at.timeIntervalSince(t0)) \(p.lastActivity.description)")
        // Two helpers of one app are two processes: 0.3 + 0.3 is not one at 0.6.
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); r.programCores = [P("Firefox", 11): 0.3, P("Firefox", 12): 0.3]; return r }
        expect("two helpers at 0.3 each are not one program at 0.6", stopped == 1800, "stopped at \(stopped ?? -1)")
        // E11's floor: the busiest third-party process all night held 0.24.
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); r.programCores = [P("Firefox", 11): 0.24, P("Firefox", 12): 0.13]; return r }
        expect("E11's floor (0.24) is quiet", stopped == 1800, "stopped at \(stopped ?? -1)")

        print("the graphics chip, the network")
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); r.gpuPercent = now <= at(900) ? 98 : 6; return r }
        expect("GPU at 98 until 15 min → off at 45 + 5 ticks ((98+6)/2 ≥ 50)", stopped == 2700 + 5 * tick && p.lastActivity.description == "the graphics chip busy", "stopped at \(stopped ?? -1)")
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); r.gpuPercent = 39; return r }
        expect("E10's highest lit-monitor floor (39 %) is quiet", stopped == 1800, "stopped at \(stopped ?? -1)")
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); r.networkKBps = now <= at(1200) ? 42 : 7; return r }
        expect("the 42 KB/s download until 20 min → off at 50 + 4 ticks", stopped == 3000 + 4 * tick && p.lastActivity.signal == .network, "stopped at \(stopped ?? -1)")
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); r.networkKBps = 18.2; return r }
        expect("E11's highest idle median (18.2 KB/s) is quiet", stopped == 1800, "stopped at \(stopped ?? -1)")
        // The lag never exceeds half the window, whatever the numbers.
        var worst: TimeInterval = 0
        for (over, under) in [(50.0, 49.9), (100.0, 49.9), (50.0, 0.0), (50.1, 0.0)] {
            p = QuietPolicy(thresholds: T, start: t0)
            let s = run(&p, limit: 7200) { now in var r = quiet(now: now); r.gpuPercent = now <= at(600) ? over : under; return r }
            worst = max(worst, (s ?? 0) - 600 - 1800)
        }
        expect("the lag after a load ends is at most half the window", worst <= Double(T.medianSamples / 2) * tick, "worst \(worst)s")

        print("E5 replay — the run the old rule got wrong")
        p = QuietPolicy(thresholds: T, start: t0)
        var i = 0
        stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); r.networkKBps = e5KBps[i % 60]; i += 1; return r }
        expect("E5's five network spikes read quiet: off at 30", stopped == 1800, "stopped at \(stopped ?? -1)")
        expect("the mean would have said busy (31 KB/s)", e5KBps.reduce(0, +) / 60 > 30)

        print("ties")
        p = QuietPolicy(thresholds: T, start: t0)
        var r = quiet(now: at(30), lastInput: at(30)); r.audioHeld = true
        p.observe(r, at: at(30))
        expect("tie goes to presence", p.lastActivity.signal == .presence)

        print("sound, from the table E10 saw")
        expect("nothing playing: seven holders of that type, no sound", !AssertionRule.audioHeld(baseline))
        for name in ["com.apple.audio.BuiltInSpeakerDevice.context.preventuseridlesleep",                       // built-in
                     "com.apple.audio.10AC6A43-0000-0000-1B23-0104B53C2278.context.preventuseridlesleep",       // the monitor
                     "com.apple.audio.CC-22-FE-35-D1-B3:output.context.preventuseridlesleep",                   // AirPods
                     "com.apple.audio.eeb801de-9bb7-4a36-8f2b-c2762bced248-8152828513541-Audio.context.preventuseridlesleep"] {  // AirPlay
            expect("coreaudiod, \(name.dropFirst(16).prefix(14))… is sound", AssertionRule.audioHeld(baseline + [row(388, "coreaudiod", SYS, name)]))
        }
        expect("Music's own assertion is not sound", !AssertionRule.audioHeld(baseline + [row(700, "Music", SYS, "com.apple.Music.playback")]))
        expect("Comet's \"Playing audio\" is not sound either", !AssertionRule.audioHeld(baseline + [row(710, "Comet", SYS, "Playing audio")]))
        expect("caffeinate is not sound", !AssertionRule.audioHeld(baseline + [row(720, "caffeinate", SYS, "caffeinate command-line tool")]))
        expect("lidawake's own two are not sound", !AssertionRule.audioHeld(baseline + [row(me, "lidawake", SYS, "it.zayco.lidawake: keep awake while armed"), row(me, "lidawake", SYS, "lidawake is keeping this Mac awake")]))
        expect("coreaudiod holding some OTHER type is not sound", !AssertionRule.audioHeld(baseline + [row(388, "coreaudiod", "BackgroundTask", "x")]))

        print("video, from the table E10 saw")
        expect("nothing playing: no video — powerd's delayDisplayOff has its own type", AssertionRule.videoHolders(baseline, ownPid: me).isEmpty)
        expect("QuickTime is video", AssertionRule.videoHolders(baseline + [row(800, "QuickTime Player", DISP, "com.apple.coremedia.iq.ca.client-1")], ownPid: me) == ["QuickTime Player"])
        // Firefox declares NoDisplaySleepAssertion; the reader hands the rule the TRUE type.
        expect("Firefox's lock, by its true type, is video", AssertionRule.videoHolders(baseline + [row(810, "firefox", DISP, "video-playing")], ownPid: me) == ["firefox"])
        expect("…and by its declared type it would not be — which is why the reader passes the true one", AssertionRule.videoHolders(baseline + [row(810, "firefox", "NoDisplaySleepAssertion", "video-playing")], ownPid: me).isEmpty)
        expect("caffeinate -d is video: declared intent", AssertionRule.videoHolders(baseline + [row(720, "caffeinate", DISP, "caffeinate command-line tool")], ownPid: me) == ["caffeinate"])
        expect("our own screen assertion is not video", AssertionRule.videoHolders(baseline + [row(me, "lidawake", DISP, "it.zayco.lidawake: keep the screen on while armed")], ownPid: me).isEmpty)
        expect("another account's lidawake is not video", AssertionRule.videoHolders(baseline + [row(930, "lidawake", DISP, "it.zayco.lidawake: keep the screen on while armed")], ownPid: me).isEmpty)
        expect("…even renamed, by its assertion name", AssertionRule.videoHolders(baseline + [row(930, "lidawake-test", DISP, "it.zayco.lidawake: keep the screen on while armed")], ownPid: me).isEmpty)
        expect("two players, each named once", AssertionRule.videoHolders([row(1, "A", DISP, "x"), row(2, "B", DISP, "y"), row(3, "A", DISP, "z")], ownPid: me) == ["A", "B"])

        print("whose CPU is it — the processes E10 and E11 met")
        let macOS = [("/System/Library/PrivateFrameworks/MediaAnalysis.framework/Versions/A/mediaanalysisd", "mediaanalysisd"),
                     ("/usr/libexec/spotlightknowledged.updater", "Spotlight's updater"),
                     ("/System/Library/Frameworks/Contacts.framework/Support/contactsd", "contactsd"),
                     ("/System/Library/PrivateFrameworks/CloudKitDaemon.framework/Support/cloudd", "cloudd"),
                     ("/System/Applications/Siri AI.app/Contents/MacOS/Siri AI", "Siri AI"),
                     ("/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/XPCServices/XProtectPluginService.xpc/Contents/MacOS/XProtectPluginService", "XProtect"),
                     ("/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder", "Finder"),
                     ("/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app/Contents/MacOS/Safari", "Safari"),
                     ("/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent", "Safari's page process"),
                     ("/System/Applications/QuickTime Player.app/Contents/MacOS/QuickTime Player", "QuickTime Player")]
        for (path, label) in macOS { expect("\(label) is macOS's own", !WorkRule.isWork(path: path, ppid: 1)) }
        let yours: [(String, Int32, String)] = [
            ("/Applications/Firefox.app/Contents/MacOS/gpu-helper.app/Contents/MacOS/Firefox GPU Helper", 2093, "a third-party app's helper"),
            ("/Applications/Ollama.app/Contents/MacOS/Ollama", 1, "a third-party app, started by launchd"),
            ("/Applications/Xcode.app/Contents/MacOS/Xcode", 1, "Xcode — Apple's, but in /Applications"),
            ("/bin/zsh", 2880, "a terminal's shell"),
            ("/usr/bin/python3", 4183, "python3 from a terminal"),
            ("/opt/homebrew/bin/ffmpeg", 1, "a nohup job, re-parented to launchd"),
            ("/usr/bin/rsync", 1, "an orphaned rsync"),
            ("/Users/someone/.local/bin/claude", 1, "an agent left running"),
            ("/usr/libexec/something", 4000, "anything a terminal started, wherever it lives"),
            ("", 1, "a process whose path cannot be read")]
        for (path, ppid, label) in yours { expect("\(label) is work", WorkRule.isWork(path: path, ppid: ppid)) }
        expect("a helper is called by its app", WorkRule.displayName(path: "/Applications/Firefox.app/Contents/MacOS/gpu-helper.app/Contents/MacOS/Firefox GPU Helper") == "Firefox")
        expect("an app by its name", WorkRule.displayName(path: "/Applications/Ollama.app/Contents/MacOS/Ollama") == "Ollama")
        expect("a tool by its executable", WorkRule.displayName(path: "/opt/homebrew/bin/ffmpeg") == "ffmpeg")
        expect("a tool by the name the system gives it, when it has one", WorkRule.displayName(path: "/usr/local/lib/tool/real-binary", processName: "tool") == "tool")
        expect("a version number is not a name: …/claude/versions/2.1.286 is claude", WorkRule.displayName(path: "/Users/someone/.local/share/claude/versions/2.1.286", processName: "2.1.286") == "claude")
        expect("…and with nothing better above it, the number stands", WorkRule.displayName(path: "/1/2.0", processName: "2.0") == "2.0")
        expect("an app's helper is still called by the app, whatever it was started as", WorkRule.displayName(path: "/Applications/Firefox.app/Contents/MacOS/plugin-container.app/Contents/MacOS/plugin-container", processName: "plugin-container") == "Firefox")

        print("modes")
        typealias M = ModeTransition
        expect("off, click until-off → arm", M.clicked(.untilOff, while: .off) == M(mode: .untilOff, helper: .arm, detector: .none))
        expect("off, click until-quiet → arm + start", M.clicked(.untilQuiet, while: .off) == M(mode: .untilQuiet, helper: .arm, detector: .start))
        expect("until-off, click it → off", M.clicked(.untilOff, while: .untilOff) == M(mode: .off, helper: .disarm, detector: .none))
        expect("until-quiet, click it → off + stop", M.clicked(.untilQuiet, while: .untilQuiet) == M(mode: .off, helper: .disarm, detector: .stop))
        expect("switch: helper untouched, detector starts", M.clicked(.untilQuiet, while: .untilOff) == M(mode: .untilQuiet, helper: .none, detector: .start))
        expect("switch back: helper untouched, detector stops", M.clicked(.untilOff, while: .untilQuiet) == M(mode: .untilOff, helper: .none, detector: .stop))

        print("the status line and the tooltips")
        expect("off", StatusLine.text(mode: .off, quietAge: nil, quietMinutes: 30) == "Off \u{2014} your Mac will sleep normally")
        expect("until I turn it off", StatusLine.text(mode: .untilOff, quietAge: nil, quietMinutes: 30) == "On \u{2014} you can close the lid")
        expect("quiet, active now", StatusLine.text(mode: .untilQuiet, quietAge: 59, quietMinutes: 30) == "On \u{2014} stops after 30 min of quiet (active now)")
        expect("quiet, 12 min", StatusLine.text(mode: .untilQuiet, quietAge: 12 * 60 + 59, quietMinutes: 30) == "On \u{2014} stops after 30 min of quiet (quiet for 12 min)")
        expect("quiet, detector not running reads active", StatusLine.text(mode: .untilQuiet, quietAge: nil, quietMinutes: 30).hasSuffix("(active now)"))
        expect("the minute count is derived", StatusLine.text(mode: .untilQuiet, quietAge: nil, quietMinutes: 2).contains("after 2 min"))
        let tipOff = ArmMode.untilOff.toolTip(quietMinutes: 30), tipQuiet = ArmMode.untilQuiet.toolTip(quietMinutes: 30)
        expect("both tooltips say where an agent in a loop belongs",
               tipOff.contains("an AI agent running in a loop belongs here")
               && tipQuiet.contains("An AI agent running in a loop looks quiet") && tipQuiet.contains("\u{201C}Keep awake until I turn it off\u{201D}"))
        expect("the quiet tooltip names what counts, and derives its minutes",
               ["you using the Mac", "sound or video", "one of your programs", "the graphics chip", "network traffic"].allSatisfy { tipQuiet.contains($0) }
               && ArmMode.untilQuiet.toolTip(quietMinutes: 2).contains("2 minutes"))
        expect("the other one names the guards that still stop it", tipOff.contains("too hot") && tipOff.contains("battery"))

        print("the message")
        let last = Activity(.video, at: at(600), detail: "QuickTime Player")
        let body = QuietReport.body(minutes: 30, last: last, session: "2 h 10 min · stayed cool")
        expect("body names the thing and the time", body.hasPrefix("Nothing had been happening for 30 minutes. The last thing it saw was video playing in QuickTime Player, at \(QuietReport.time(at(600))).") && body.hasSuffix(" Awake 2 h 10 min · stayed cool."))
        expect("no session line lid-open", !QuietReport.body(minutes: 30, last: last, session: nil).contains("Awake"))
        expect("one minute, singular", QuietReport.body(minutes: 1, last: last, session: nil).hasPrefix("Nothing had been happening for 1 minute."))
        expect("menu line", QuietReport.menuLine(last: last, session: nil) == "lidawake turned itself off \u{2014} last: video playing in QuickTime Player at \(QuietReport.time(at(600)))")
        expect("every signal has its own words", Set(Signal.allCases.map { Activity($0, at: t0).description }).count == Signal.allCases.count)

        print("the hook, and the numbers the app ships")
        expect("default tick 30 s", IdleWatcher.interval(for: IdleWatcher.defaultWindow) == 30)
        expect("120 s window → 2 s tick", IdleWatcher.interval(for: 120) == 2)
        expect("never under a second", IdleWatcher.interval(for: 10) == 1)
        expect("only the window scales", IdleWatcher.thresholds(for: 120).quietWindow == 120 && IdleWatcher.thresholds(for: 120).medianSamples == Thresholds.measured.medianSamples)
        // Pinned on purpose: these are decisions (spec §11.3, 2026-10-04), and a
        // change to one of them should have to change this line too.
        let m = Thresholds.measured
        expect("ships 30 min, 0.5 cores, 50 %, 30 KB/s, median of ten", m.quietWindow == 1800 && m.programCores == 0.5 && m.gpuPercent == 50 && m.networkKBps == 30 && m.medianSamples == 10 && m.minimumSamples == 3)

        print(failures == 0 ? "\nall quiet-rule checks passed" : "\n\(failures) FAILURES")
        exit(failures == 0 ? 0 : 1)
    }
}
