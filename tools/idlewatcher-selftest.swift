// The quiet rule, tested without a machine: QuietPolicy, the median windows,
// the mode transitions, the status line and the stop message. Every threshold
// is passed in explicitly, so nothing here depends on the placeholders in
// IdleWatcher.swift that E10/E11 will replace.
//
//   swiftc -O -parse-as-library Sources/App/IdleWatcher.swift Sources/App/ArmMode.swift \
//       tools/idlewatcher-selftest.swift -o /tmp/lidawake-idle-selftest && /tmp/lidawake-idle-selftest
//
// MUTATION-CHECKED — each of these, made on purpose, fails at least one check:
//   - `nil` readings treated as "nothing"         → "stub never stops", "one unreadable signal"
//   - `>=` window → `>`                            → "stops at exactly 30 min"
//   - median → mean                                → "E5 replay", "two spikes in ten"
//   - minimumSamples ignored                       → "one sample is not sustained"
//   - note() allowed to move backwards             → "presence cannot move the last moment back"
//   - ties broken by later Signal                  → "tie goes to presence"
//   - switching modes touching the helper          → "switch: helper untouched"
//   - program windows never decaying               → "a program that stopped lets go"

import Foundation

var failures = 0
func expect(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { print("  PASS  \(label)") }
    else { print("  FAIL  \(label)  \(detail())"); failures += 1 }
}

// The test's own numbers — not IdleWatcher's placeholders.
let T: Thresholds = {
    var t = Thresholds()
    t.quietWindow = 1800; t.medianSamples = 10; t.minimumSamples = 3
    t.programCores = 0.5; t.processorCores = 4.0; t.gpuPercent = 50; t.networkKBps = 15
    return t
}()
let tick: TimeInterval = 30
let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

/// Everything readable, nothing happening, last input at `lastInput`.
func quiet(now: Date, lastInput: Date = t0) -> Readings {
    var r = Readings()
    r.presenceAge = now.timeIntervalSince(lastInput)
    r.audioHeld = false; r.videoHolders = []; r.programCores = [:]
    r.totalCores = 0.3; r.gpuPercent = 5; r.networkKBps = 2
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

// E5's sixty samples (research/e5-floor.log, 2026-09-06): the run the old
// two-counter rule read as BUSY on its 30-minute mean. Cores, then KB/s.
let e5Cores: [Double] = [1.48,1.30,1.30,1.25,1.30,1.30,1.29,1.30,1.28,1.29,1.44,1.83,2.50,1.86,0.86,0.38,1.12,1.26,1.45,1.30,
                         1.74,1.36,1.62,1.08,0.33,1.02,0.24,0.22,0.88,1.20,1.29,1.24,1.28,1.17,1.17,1.24,1.36,1.27,1.20,1.19,
                         1.24,2.29,2.32,2.27,2.27,2.25,2.28,2.31,2.28,2.26,2.28,2.26,2.30,2.30,2.27,2.29,2.31,2.29,2.26,2.26]
let e5KBps: [Double]  = [5.9,7.2,1.7,7.8,2.5,12.1,5.4,10.5,5.6,7.0,1282.3,7.7,6.6,8.8,3.8,53.5,1.7,7.7,14.1,12.5,
                         157.4,6.0,7.4,9.7,3.3,20.3,3.5,12.0,7.6,12.6,12.4,11.1,10.5,5.7,7.6,6.6,9.5,10.5,3.1,18.9,
                         3.8,13.8,2.6,3.2,1.6,2.8,2.3,7.8,1.8,3.8,2.0,2.7,3.9,5.6,1.2,2.5,1.2,4.1,1.7,2.7]

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
        expect("two spikes in ten do not move the median", !spikes.sustained(over: 15, minimum: 3), "median \(spikes.median ?? -1)")
        var one = MedianWindow(capacity: 10); one.add(500)
        expect("one sample is not sustained", !one.sustained(over: 15, minimum: 3))
        var six = MedianWindow(capacity: 10)
        for v in [20.0, 20, 20, 20, 20, 20, 1, 1, 1, 1] { six.add(v) }
        expect("six of ten over is sustained", six.sustained(over: 15, minimum: 3))

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
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); r.gpuPercent = nil; return r }
        expect("one unreadable signal holds everything", stopped == nil && p.lastActivity.signal == .graphics)
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); r.presenceAge = nil; return r }
        expect("presence unreadable alone holds everything", stopped == nil && p.lastActivity.signal == .presence && !p.lastActivity.readable)

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
        stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); r.programCores = now <= at(1800) ? ["Ollama": 0.9, "Slack": 0.1] : [:]; return r }
        expect("a busy program until 30 min → off at 60 + 4 ticks ((0.9+0)/2 < 0.5)", stopped == 3600 + 4 * tick, "stopped at \(stopped ?? -1)")
        expect("names the program", p.lastActivity.description == "Ollama working")
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); r.programCores = now == at(600) ? ["Finder": 3.0] : [:]; return r }
        expect("a single 30 s spike is not work", stopped == 1800, "stopped at \(stopped ?? -1)")
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in
            var r = quiet(now: now)
            if now <= at(300) { r.programCores = ["clang": 1.0] }        // a build, 5 min
            else if now <= at(600) { r.programCores = [:] }              // gone
            else { r.programCores = ["Slack": 0.05] }                   // something else, idle
            return r
        }
        expect("a program that stopped lets go: off at 35 + 5 ticks ((1.0+0)/2 ≥ 0.5)", stopped == 2100 + 5 * tick, "stopped at \(stopped ?? -1)")
        expect("…and is still the last thing named, at the last sustained tick", p.lastActivity.description == "clang working" && p.lastActivity.at == at(300 + 5 * tick), "at \(p.lastActivity.at.timeIntervalSince(t0)) \(p.lastActivity.description)")

        print("the processor, the graphics chip, the network")
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); r.totalCores = now <= at(600) ? 6.0 : 1.3; return r }
        expect("6 cores until 10 min → off at 40 + 4 ticks; 1.3 never counts", stopped == 2400 + 4 * tick && p.lastActivity.signal == .processor, "stopped at \(stopped ?? -1)")
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); r.gpuPercent = now <= at(900) ? 98 : 6; return r }
        expect("GPU at 98 until 15 min → off at 45 + 5 ticks ((98+6)/2 ≥ 50)", stopped == 2700 + 5 * tick && p.lastActivity.description == "the graphics chip busy", "stopped at \(stopped ?? -1)")
        p = QuietPolicy(thresholds: T, start: t0)
        stopped = run(&p, limit: 7200) { now in var r = quiet(now: now); r.networkKBps = now <= at(1200) ? 20 : 3; return r }
        expect("a slow 20 KB/s transfer until 20 min → off at 50 + 4 ticks", stopped == 3000 + 4 * tick && p.lastActivity.signal == .network, "stopped at \(stopped ?? -1)")
        // The lag never exceeds half the window, whatever the numbers.
        var worst: TimeInterval = 0
        for (over, under) in [(4.0, 3.99), (100.0, 3.99), (4.0, 0.0), (4.01, 0.0)] {
            p = QuietPolicy(thresholds: T, start: t0)
            let s = run(&p, limit: 7200) { now in var r = quiet(now: now); r.totalCores = now <= at(600) ? over : under; return r }
            worst = max(worst, (s ?? 0) - 600 - 1800)
        }
        expect("the lag after a load ends is at most half the window", worst <= Double(T.medianSamples / 2) * tick, "worst \(worst)s")

        print("E5 replay — the run the old rule got wrong")
        p = QuietPolicy(thresholds: T, start: t0)
        var i = 0
        stopped = run(&p, limit: 7200) { now in
            var r = quiet(now: now)
            r.totalCores = e5Cores[i % 60]; r.networkKBps = e5KBps[i % 60]; i += 1
            return r
        }
        expect("E5's floor and its five spikes read quiet: off at 30", stopped == 1800, "stopped at \(stopped ?? -1)")
        expect("the mean would have said busy (31 KB/s)", e5KBps.reduce(0, +) / 60 > 15)

        print("ties")
        p = QuietPolicy(thresholds: T, start: t0)
        var r = quiet(now: at(30), lastInput: at(30)); r.audioHeld = true
        p.observe(r, at: at(30))
        expect("tie goes to presence", p.lastActivity.signal == .presence)

        print("modes")
        typealias M = ModeTransition
        expect("off, click until-off → arm", M.clicked(.untilOff, while: .off) == M(mode: .untilOff, helper: .arm, detector: .none))
        expect("off, click until-quiet → arm + start", M.clicked(.untilQuiet, while: .off) == M(mode: .untilQuiet, helper: .arm, detector: .start))
        expect("until-off, click it → off", M.clicked(.untilOff, while: .untilOff) == M(mode: .off, helper: .disarm, detector: .none))
        expect("until-quiet, click it → off + stop", M.clicked(.untilQuiet, while: .untilQuiet) == M(mode: .off, helper: .disarm, detector: .stop))
        expect("switch: helper untouched, detector starts", M.clicked(.untilQuiet, while: .untilOff) == M(mode: .untilQuiet, helper: .none, detector: .start))
        expect("switch back: helper untouched, detector stops", M.clicked(.untilOff, while: .untilQuiet) == M(mode: .untilOff, helper: .none, detector: .stop))

        print("the status line")
        expect("off", StatusLine.text(mode: .off, quietAge: nil, quietMinutes: 30) == "Off \u{2014} your Mac will sleep normally")
        expect("until I turn it off", StatusLine.text(mode: .untilOff, quietAge: nil, quietMinutes: 30) == "On \u{2014} you can close the lid")
        expect("quiet, active now", StatusLine.text(mode: .untilQuiet, quietAge: 59, quietMinutes: 30) == "On \u{2014} stops after 30 min of quiet (active now)")
        expect("quiet, 12 min", StatusLine.text(mode: .untilQuiet, quietAge: 12 * 60 + 59, quietMinutes: 30) == "On \u{2014} stops after 30 min of quiet (quiet for 12 min)")
        expect("quiet, detector not running reads active", StatusLine.text(mode: .untilQuiet, quietAge: nil, quietMinutes: 30).hasSuffix("(active now)"))
        expect("the minute count is derived", StatusLine.text(mode: .untilQuiet, quietAge: nil, quietMinutes: 2).contains("after 2 min"))

        print("the message")
        let last = Activity(.video, at: at(600), detail: "QuickTime Player")
        let body = QuietReport.body(minutes: 30, last: last, session: "2 h 10 min · stayed cool")
        expect("body names the thing and the time", body.hasPrefix("Nothing had been happening for 30 minutes. The last thing it saw was video playing in QuickTime Player, at \(QuietReport.time(at(600))).") && body.hasSuffix(" Awake 2 h 10 min · stayed cool."))
        expect("no session line lid-open", !QuietReport.body(minutes: 30, last: last, session: nil).contains("Awake"))
        expect("one minute, singular", QuietReport.body(minutes: 1, last: last, session: nil).hasPrefix("Nothing had been happening for 1 minute."))
        expect("menu line", QuietReport.menuLine(last: last, session: nil) == "lidawake turned itself off \u{2014} last: video playing in QuickTime Player at \(QuietReport.time(at(600)))")

        print("the hook")
        expect("default tick 30 s", IdleWatcher.interval(for: IdleWatcher.defaultWindow) == 30)
        expect("120 s window → 2 s tick", IdleWatcher.interval(for: 120) == 2)
        expect("never under a second", IdleWatcher.interval(for: 10) == 1)
        expect("only the window scales", IdleWatcher.thresholds(for: 120).quietWindow == 120 && IdleWatcher.thresholds(for: 120).medianSamples == Thresholds.placeholder.medianSamples)

        print(failures == 0 ? "\nall quiet-rule checks passed" : "\n\(failures) FAILURES")
        exit(failures == 0 ? 0 : 1)
    }
}
