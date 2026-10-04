// "Keep awake until it goes quiet" — the rule, and the timer that runs it.
//
// THE RULE (attended-mac-spec.md §11.2): lidawake turns itself off 30 minutes
// after the last thing it could see. Every signal reports the time it last saw
// activity; the verdict is `now − max(lastActivity) ≥ 30 min`, checked every
// 30 s. Nothing learns, nothing adapts, every number is fixed, and the message
// that turns lidawake off names the last thing seen and when.
//
// Seven signals, of two kinds:
//   declared — input age, sound, video, and a keep-awake request from one of
//              your programs: read as they are, instantaneous.
//   load     — a program's CPU, the graphics chip, the network: bursty, so each
//              is the MEDIAN of the trailing ten samples (five minutes) against
//              a fixed threshold. The median's only job is spike immunity; the
//              30-minute rule is the debounce, so the window is short on
//              purpose — a long one keeps reading "active" for most of half an
//              hour after a download ends, and only then do the 30 minutes
//              start, which nobody can predict from "30 minutes of quiet".
//
// A SIGNAL THAT CANNOT BE READ COUNTS AS ACTIVITY NOW. Each reader returns an
// optional; nil means "could not read", never "nothing". Stopping someone's
// work is worse than running longer, and this is testable without hardware.
//
// THERE IS NO SYSTEM-WIDE CPU SIGNAL, and that is the history of this file.
// T2.5's detector counted system-wide CPU and network on a 30-minute mean and
// was stopped in 1.4.9: in the target configuration it read BUSY permanently
// (spec §7.20). A system-wide total cannot tell the user's work from macOS's
// housekeeping (§7.21) — on an idle night `mediaanalysisd` alone ran at two
// cores for 79 % of the samples (E11, §11.6.4). The rebuild kept one
// system-wide number as a backstop at 4 cores; the same night it read "busy"
// for an hour and a half, and it was dropped (2026-10-04). CPU is counted per
// process, for the user's own programs only — see `WorkRule`.
//
// AN AGENT IN A LOOP is seen by what it asks for, not by what it uses. Between
// its checks it uses nothing, and every load signal reads quiet. But Claude
// Code, in a terminal, asks macOS to stay awake for each turn it works — a
// `caffeinate` child, from the turn's first second until about 30 s after its
// last (E13a, spec §11.6.5) — and holds nothing while it waits. (Headless,
// `claude -p`, it asks for nothing at all: E13b, §11.6.6.) So a request held by one of the
// user's programs is a signal (2026-10-04): each check resets the 30 minutes,
// and a loop that waits less than that stays on. The whole request can be as
// short as 31 s, which a 30 s tick sees once at best, so the keep-awake list
// alone is read three times a tick — every 10 s. A loop that waits LONGER than
// the window is still stopped, unless it asks for the wait itself; the menu
// says so (ArmMode.swift). The rest of what is not seen is spec §11.4.
//
// This file has no system calls in it: the policy, the classification rules
// and the sentences, all testable without a machine. The readers are in
// ActivitySignals.swift.

import Foundation

/// The seven things the detector can see. The order is the tie-break when two
/// signals share the same last moment — presence first, so "you using the Mac"
/// is what gets named when it and "network traffic" are both now; and what a
/// program ASKED for before what it used, so an agent is named by its request.
enum Signal: Int, CaseIterable, Comparable {
    case presence, audio, video, request, program, graphics, network
    static func < (a: Signal, b: Signal) -> Bool { a.rawValue < b.rawValue }
}

/// One moment of activity, and how to say it.
struct Activity: Equatable {
    let signal: Signal
    let at: Date
    /// The app or process name, for video, request and program — the part of
    /// the sentence that names something. Nil for the rest.
    let detail: String?
    /// False when the signal counted because it could NOT be read. While that
    /// lasts it is always "now" and nothing stops. But one failed read followed
    /// by good ones is a moment like any other, and can be the last one — so
    /// its words have to stand in the stop message too.
    let readable: Bool

    init(_ signal: Signal, at: Date, detail: String? = nil, readable: Bool = true) {
        self.signal = signal; self.at = at; self.detail = detail; self.readable = readable
    }
    static func unreadable(_ signal: Signal, at: Date) -> Activity {
        Activity(signal, at: at, readable: false)
    }

    /// "you using the Mac", "video playing in QuickTime Player", "Ollama working"…
    /// The customer's words (positioning principle 4), never a counter's name.
    var description: String {
        guard readable else { return "a moment when \(subject) could not be checked" }
        switch signal {
        case .presence: return "you using the Mac"
        case .audio:    return "sound playing"
        case .video:    return detail.map { "video playing in \($0)" } ?? "video playing"
        case .request:  return "\(detail ?? "one of your programs") asking the Mac to stay awake"
        case .program:  return detail.map { "\($0) working" } ?? "one of your programs working"
        case .graphics: return "the graphics chip busy"
        case .network:  return "network traffic"
        }
    }

    private var subject: String {
        switch signal {
        case .presence: return "input"
        case .audio:    return "sound"
        case .video:    return "video"
        case .request:  return "keep-awake requests"
        case .program:  return "your programs"
        case .graphics: return "the graphics chip"
        case .network:  return "the network"
        }
    }
}

/// One of the user's processes. The name is the one the message uses — the
/// app's, not the helper's (see `WorkRule.displayName`) — so two helpers of one
/// app are two programs with one name, each with its own median.
struct Program: Hashable {
    let name: String
    let pid: Int32
}

/// One tick's readings. EVERY field is optional, and nil means the reader
/// could not read — which the policy counts as activity now. A reader that can
/// read and sees nothing returns a value: false, [], [:], 0.
struct Readings {
    var presenceAge: TimeInterval? = nil         // seconds since the last hardware input event
    var audioHeld: Bool? = nil                   // coreaudiod holds its assertion
    var videoHolders: [String]? = nil            // names holding a display-sleep assertion, lidawake excluded
    var requestHolders: [String]? = nil          // who is asking the Mac to stay awake (AssertionRule.requestHolders)
    var programCores: [Program: Double]? = nil   // this tick's core-equivalents per WORK process
    var gpuPercent: Double? = nil                // IOAccelerator Device Utilization %
    var networkKBps: Double? = nil               // non-loopback bytes, both directions
    init() {}
}

/// Every number the rule uses, in one place. All measured on macOS 27.0.1
/// (spec §11.6); none is a guess, and the selftest passes its own.
struct Thresholds {
    /// The product rule itself. Not a setting.
    var quietWindow: TimeInterval = 30 * 60
    /// Five minutes at the 30 s tick.
    var medianSamples = 10
    /// A "median" of one or two samples is a spike with a majority.
    var minimumSamples = 3
    /// One of your programs at half a core, sustained. E11: across an idle
    /// night the highest five-minute median of any third-party process was
    /// 0.24; a single busy thread is 1.0. Twice the margin on both sides.
    var programCores = 0.5
    /// E5c: 98 % under local inference. E10: at most 39 % with a monitor lit,
    /// 0 with it asleep, 12 with no display at all. One contaminant is known
    /// and accepted — macOS's media analysis uses the GPU (§11.4).
    var gpuPercent = 50.0
    /// E11: an idle night's five-minute median peaked at 18.2 KB/s on
    /// background sync; 15, the old number, was crossed three times.
    var networkKBps = 30.0

    static let measured = Thresholds()
}

/// The trailing median of one load signal. Spike-immune by construction: of ten
/// samples, four can be anything and the median does not move.
struct MedianWindow {
    let capacity: Int
    private(set) var values: [Double] = []

    init(capacity: Int) { self.capacity = max(1, capacity) }

    mutating func add(_ v: Double) {
        values.append(v)
        if values.count > capacity { values.removeFirst() }
    }

    var count: Int { values.count }
    var isFull: Bool { values.count >= capacity }
    var allZero: Bool { values.allSatisfy { $0 == 0 } }

    var median: Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted(), n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// At or over `threshold`, once at least `minimum` samples are in.
    func sustained(over threshold: Double, minimum: Int) -> Bool {
        guard count >= minimum, let m = median else { return false }
        return m >= threshold
    }
}

/// The decision, with no sampling in it, so it can be tested without a machine.
struct QuietPolicy {
    let thresholds: Thresholds

    /// The last moment each signal saw activity. Never empty: starting the
    /// detector is itself activity — the user just clicked.
    private(set) var last: [Signal: Activity] = [:]

    /// Who is asking the Mac to stay awake as of the last look at the list —
    /// nil when nobody is, or when the list could not be read. For the status
    /// line: a program that holds a request for ever keeps quiet mode on for
    /// ever, and this is how that explains itself.
    private(set) var heldBy: String?

    private var graphics: MedianWindow
    private var network: MedianWindow
    private var programs: [Program: MedianWindow] = [:]

    init(thresholds: Thresholds, start: Date) {
        self.thresholds = thresholds
        graphics = MedianWindow(capacity: thresholds.medianSamples)
        network  = MedianWindow(capacity: thresholds.medianSamples)
        last[.presence] = Activity(.presence, at: start)
    }

    mutating func observe(_ r: Readings, at now: Date) {
        // Declared signals: as they are.
        if let age = r.presenceAge { note(Activity(.presence, at: now.addingTimeInterval(-max(0, age)))) }
        else { note(.unreadable(.presence, at: now)) }

        if let held = r.audioHeld { if held { note(Activity(.audio, at: now)) } }
        else { note(.unreadable(.audio, at: now)) }

        if let holders = r.videoHolders { if let h = holders.first { note(Activity(.video, at: now, detail: h)) } }
        else { note(.unreadable(.video, at: now)) }

        observeRequests(r.requestHolders, at: now)

        // Your programs: one median per process. A process that was seen before
        // and is absent this tick reads as 0, so it decays; a window that has
        // filled with zeros is forgotten.
        if let cores = r.programCores {
            for (program, c) in cores {
                programs[program, default: MedianWindow(capacity: thresholds.medianSamples)].add(c)
            }
            for program in programs.keys where cores[program] == nil { programs[program]?.add(0) }
            var busiest: (name: String, median: Double)? = nil
            for (program, w) in programs where w.sustained(over: thresholds.programCores, minimum: thresholds.minimumSamples) {
                if let m = w.median, busiest == nil || m > busiest!.median { busiest = (program.name, m) }
            }
            if let busiest { note(Activity(.program, at: now, detail: busiest.name)) }
            programs = programs.filter { !($0.value.isFull && $0.value.allZero) }
        } else {
            note(.unreadable(.program, at: now))
        }

        // The two system-wide load signals.
        var a: Activity?
        (graphics, a) = load(graphics, r.gpuPercent,  .graphics, thresholds.gpuPercent,  now); if let a { note(a) }
        (network,  a) = load(network,  r.networkKBps, .network,  thresholds.networkKBps, now); if let a { note(a) }
    }

    /// The keep-awake list by itself. The full tick calls it with the rest; the
    /// watcher also calls it between ticks, because a request can come and go
    /// inside one (see the header). Seeing it more often can only add activity.
    mutating func observeRequests(_ holders: [String]?, at now: Date) {
        heldBy = holders?.first
        if let holders { if let h = holders.first { note(Activity(.request, at: now, detail: h)) } }
        else { note(.unreadable(.request, at: now)) }
    }

    /// One load signal's step: the window with this sample added, and the
    /// activity it implies — unreadable, sustained, or none. Returns rather than
    /// mutates in place, so `observe` never overlaps its own access to `self`.
    private func load(_ w: MedianWindow, _ value: Double?, _ signal: Signal,
                      _ threshold: Double, _ now: Date) -> (MedianWindow, Activity?) {
        guard let value else { return (w, .unreadable(signal, at: now)) }
        var w = w
        w.add(value)
        let active = w.sustained(over: threshold, minimum: thresholds.minimumSamples)
        return (w, active ? Activity(signal, at: now) : nil)
    }

    /// Only ever forward. Presence reports an absolute moment, which can be
    /// earlier than the click that started the detector; the later one stands.
    private mutating func note(_ a: Activity) {
        if let old = last[a.signal], old.at > a.at { return }
        last[a.signal] = a
    }

    /// The most recent activity across every signal. Ties go to the signal
    /// earlier in `Signal`'s order.
    var lastActivity: Activity {
        last.values.max { a, b in (a.at, b.signal) < (b.at, a.signal) }!
    }

    func quietAge(at now: Date) -> TimeInterval { max(0, now.timeIntervalSince(lastActivity.at)) }
    func shouldStop(at now: Date) -> Bool { quietAge(at: now) >= thresholds.quietWindow }
}

// MARK: - The classification rules

/// One row of the power-assertion table, reduced to what the rules read.
/// `trueType` is `AssertionTrueType`, NOT `AssertType`: the declared type is
/// whatever name the holder created the assertion under, and browsers create
/// their video lock under the legacy `NoDisplaySleepAssertion`. Matching the
/// declared type scored Firefox 0 of 9 while it held its lock 9 of 9 (E10).
struct AssertionRow {
    let pid: Int32
    let process: String
    let trueType: String
    let name: String
}

/// What the request rule needs to know about a process: where it runs from,
/// who started it, and whose it is. `name` is what the system calls it.
struct ProcessFacts {
    let path: String
    let ppid: Int32
    let uid: UInt32
    let name: String
}

/// Sound, video and keep-awake requests, as other software declares them
/// (spec §11.3, §11.3.1, §11.3.3).
enum AssertionRule {
    static let systemSleep  = "PreventUserIdleSystemSleep"
    static let displaySleep = "PreventUserIdleDisplaySleep"
    /// The two ways of asking that the Mac itself stay awake: `caffeinate -i`
    /// and `-s`. Legacy names (`NoIdleSleepAssertion`) arrive as the first, by
    /// true type. A display request is not here — that is video's.
    static let requestTypes: Set<String> = [systemSleep, "PreventSystemSleep"]
    static let caffeinate = "/usr/bin/caffeinate"
    /// What a holder in another PERSON's account is called, everywhere. On a
    /// shared Mac one person does not get to read in a menu which programs
    /// another is running (product owner, 2026-10-04), so the name is dropped
    /// HERE — it never reaches the policy, the status line, the notice or the
    /// log. Root is not a person: a root daemon is nobody's private app, and
    /// its name is the only clue when something keeps quiet mode on for ever,
    /// so root's holders are named.
    static let otherAccount = "a program in another account"
    /// How WakeAssertionManager names both of ours.
    static let ownPrefix = "it.zayco.lidawake"

    /// Sound: `coreaudiod`, and only `coreaudiod`, holding a system-sleep
    /// assertion. It takes one for an open output device whatever the app and
    /// whatever the device — speakers, a monitor, AirPods, AirPlay (E10) — and
    /// lets go within seconds of a pause. Matching the HOLDER excludes every
    /// other holder of that type in one test: powerd, bluetoothd, caffeinate,
    /// a player's own, and lidawake's. That type is far too busy to read any
    /// other way — in half an hour with nothing playing, seven different
    /// daemons held it (E10).
    static func audioHeld(_ rows: [AssertionRow]) -> Bool {
        rows.contains { $0.process == "coreaudiod" && $0.trueType == systemSleep }
    }

    /// One of lidawake's own. Own pid is NOT enough — a second account can run
    /// its own lidawake, which holds both of ours while it is on (measured, two
    /// accounts on one Mac) — so they are known by process and by name too.
    static func isOurs(_ r: AssertionRow, ownPid: Int32) -> Bool {
        r.pid == ownPid || r.process == "lidawake" || r.name.hasPrefix(ownPrefix)
    }

    /// Video: a display-sleep assertion from anything that is not lidawake.
    /// powerd's `delayDisplayOff` has a true type of its own and never matches.
    static func videoHolders(_ rows: [AssertionRow], ownPid: Int32) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for r in rows where r.trueType == displaySleep && !isOurs(r, ownPid: ownPid) {
            if seen.insert(r.process).inserted { out.append(r.process) }
        }
        return out
    }

    /// A keep-awake request: a system-sleep assertion held by one of the user's
    /// PROGRAMS — the same test as for CPU (`WorkRule`), so macOS's own holders
    /// of this very busy type (bluetoothd, runningboardd, AddressBookSourceSync,
    /// coreaudiod, powerd…) are out without a list, and lidawake's own are out
    /// the way they are for video. Across an idle night nothing passed (E11);
    /// an agent's every turn does (E13a).
    ///
    /// `caffeinate` is named by whoever started it — "claude", not "caffeinate"
    /// — because that is who asked. Left running with no parent, it is itself.
    ///
    /// Holders in other accounts COUNT — an agent in one account and lidawake
    /// in another is a real arrangement — but another user's are never named:
    /// see `otherAccount`. Root's are named like the user's own.
    ///
    /// `lookup` answers for a pid, or nil if the process is gone — and then so
    /// is its request. A process that exists but whose path cannot be read has
    /// an empty path, which `WorkRule` counts as work: unreadable is activity.
    /// The user's own names come first, in a stable order.
    static func requestHolders(_ rows: [AssertionRow], ownPid: Int32, ownUid: UInt32,
                               lookup: (Int32) -> ProcessFacts?) -> [String] {
        var mine = Set<String>(), other = false, looked = Set<Int32>()
        for r in rows where requestTypes.contains(r.trueType) && !isOurs(r, ownPid: ownPid) {
            guard looked.insert(r.pid).inserted, let p = lookup(r.pid) else { continue }
            guard WorkRule.isWork(path: p.path, ppid: p.ppid) else { continue }
            guard p.uid == ownUid || p.uid == 0 else { other = true; continue }
            var who = (path: p.path, name: p.name.isEmpty ? r.process : p.name)
            if p.path == caffeinate, p.ppid > 1, let parent = lookup(p.ppid) { who = (parent.path, parent.name) }
            mine.insert(WorkRule.displayName(path: who.path, processName: who.name))
        }
        return mine.sorted() + (other ? [otherAccount] : [])
    }
}

/// Whose CPU is it? (spec §11.3.2)
///
/// A process is the user's WORK unless it is one of macOS's own: started by
/// launchd from a system location. That one test separates `mediaanalysisd`,
/// Spotlight, iCloud sync and the rest — two cores for most of an idle night —
/// from anything the user opened or started, without a list of names.
///
/// Stated as what is excluded, deliberately. The first wording included "inside
/// a .app, or not started by launchd", and two things in it were wrong: Apple
/// ships background agents AS .app bundles (`Siri AI` held half a core and was
/// named as the user's work), and a job left running with `nohup` is
/// re-parented to launchd the moment its terminal closes, so it matched
/// neither test and would have been slept.
enum WorkRule {
    /// Where macOS keeps its own. `/usr/bin` and `/bin` are NOT here: those are
    /// tools people run (python3, rsync, a shell), not agents.
    static let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/"]

    static func isWork(path: String, ppid: Int32) -> Bool {
        if ppid != 1 { return true }          // something other than launchd started it
        return !systemPrefixes.contains { path.hasPrefix($0) }
    }

    /// `sysctl` hands back a process's name in a 16-byte field, so a longer one
    /// arrives cut short — "AddressBookSourc". When the executable's own file
    /// name starts with exactly those 16, that is the whole of it.
    static func wholeName(comm: String, path: String) -> String {
        guard comm.utf8.count == 16, let leaf = path.split(separator: "/").last.map(String.init),
              leaf.hasPrefix(comm) else { return comm }
        return leaf
    }

    /// The name the message uses: the outermost `.app` the executable lives in
    /// — "Firefox", not "Firefox GPU Helper" — and otherwise the process's own
    /// name. Unless that name is a version number: Claude Code runs from
    /// `…/claude/versions/2.1.286` and is called exactly that by the system
    /// (measured), and "2.1.286 working" tells nobody anything. Then it is the
    /// nearest folder above with a real name — "claude".
    static func displayName(path: String, processName: String = "") -> String {
        let parts = path.split(separator: "/").map(String.init)
        if let app = parts.first(where: { $0.hasSuffix(".app") }) { return String(app.dropLast(4)) }
        let leaf = processName.isEmpty ? (parts.last ?? path) : processName
        if leaf.contains(where: \.isLetter) { return leaf }
        let generic: Set<String> = ["versions", "version", "releases", "current", "bin"]
        let named = parts.dropLast().reversed().first { $0.contains(where: \.isLetter) && !generic.contains($0.lowercased()) }
        return named ?? leaf
    }
}

// MARK: - Sources and sentences

/// Where a tick's readings come from. The real one is `SystemActivitySource`
/// (ActivitySignals.swift); the stub is what the policy runs on in tests.
protocol ActivitySource: AnyObject {
    /// Take the baselines the load signals measure against. Called at start.
    func prime()
    func read() -> Readings
    /// The keep-awake list alone, for the looks between two ticks. nil if it
    /// could not be read.
    func readRequests() -> [String]?
}

/// Reads nothing: every signal unreadable, so the policy can never stop.
final class StubActivitySource: ActivitySource {
    init() {}
    func prime() {}
    func read() -> Readings { Readings() }
    func readRequests() -> [String]? { nil }
}

/// The sentences the stop produces, composed here so the selftest reads the
/// same words the user does.
enum QuietReport {
    static func body(minutes: Int, last: Activity, session: String?) -> String {
        var s = "Nothing had been happening for \(minutes) minute\(minutes == 1 ? "" : "s"). "
            + "The last thing it saw was \(last.description), at \(time(last.at))."
        if let session { s += " Awake \(session)." }
        return s
    }

    /// Shorter, for the menu carrier beside the on/off state.
    static func menuLine(last: Activity, session: String?) -> String {
        var s = "lidawake turned itself off \u{2014} last: \(last.description) at \(time(last.at))"
        if let session { s += " \u{2014} \(session)" }
        return s
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: d)
    }
}

/// Runs the policy on a timer while quiet mode is on, and reports once.
final class IdleWatcher {

    /// 30 minutes: the product rule. A build that pauses to link, a download
    /// stalling on a slow server, a render between frames — all look quiet
    /// briefly, and none should cost the user their work.
    static let defaultWindow: TimeInterval = 30 * 60

    /// Test hook, same pattern as LIDAWAKE_TRIAL_DAYS in LicenseController:
    /// LIDAWAKE_IDLE_SECONDS shortens the window so the whole path can be
    /// exercised on real hardware in minutes. Ignored unless set, so a shipped
    /// build always uses the 30 minutes above. It rewrites the minute count in
    /// the user-facing message too, because that number is derived (spec §9).
    static var window: TimeInterval {
        if let raw = ProcessInfo.processInfo.environment["LIDAWAKE_IDLE_SECONDS"],
           let v = TimeInterval(raw), v > 0 { return v }
        return defaultWindow
    }

    /// 30 s normally — sixty ticks across the window. Under the hook, window/60,
    /// never under a second.
    static var sampleInterval: TimeInterval { interval(for: window) }
    static func interval(for window: TimeInterval) -> TimeInterval { max(1, window / 60) }

    /// The keep-awake list is looked at this many times per tick: every 10 s at
    /// the 30 s tick. An agent's request for a short turn lasts 31–36 s in all
    /// (E13a) — one sighting at best on the tick alone, three or more this way.
    /// Nothing else is read faster: the load signals' medians are counted in
    /// ticks, and their five minutes stay five minutes.
    static let requestReadsPerTick = 3
    static var requestInterval: TimeInterval { requestInterval(for: window) }
    static func requestInterval(for window: TimeInterval) -> TimeInterval {
        interval(for: window) / TimeInterval(requestReadsPerTick)
    }

    /// The measured thresholds with the window applied. Only the window scales;
    /// the median stays ten ticks, so under the hook it is ten shortened ticks.
    static var thresholds: Thresholds { thresholds(for: window) }
    static func thresholds(for window: TimeInterval) -> Thresholds {
        var t = Thresholds.measured
        t.quietWindow = window
        return t
    }

    /// Called on the main thread, once per session, with the last activity seen.
    var onIdle: ((Activity) -> Void)?

    private let source: ActivitySource
    private var timer: Timer?
    private var policy: QuietPolicy?
    private var fired = false
    private var looks = 0

    init(source: ActivitySource = StubActivitySource()) { self.source = source }

    var isRunning: Bool { timer != nil }
    /// For the status line. Nil when the detector is not running.
    var quietAge: TimeInterval? { policy?.quietAge(at: Date()) }
    var lastActivity: Activity? { policy?.lastActivity }
    /// Who is asking the Mac to stay awake right now, if anyone (≤ 10 s old).
    var heldBy: String? { policy?.heldBy }

    func start() {
        guard timer == nil else { return }
        begin(at: Date())
        NSLog("[lidawake] quiet watch started — window \(Int(Self.window))s, sampling every \(Int(Self.sampleInterval))s, keep-awake requests every \(String(format: "%.3g", Self.requestInterval))s")
        let t = Timer(timeInterval: Self.requestInterval, repeats: true) { [weak self] _ in self?.look(at: Date()) }
        // .common so menu tracking and modal panels don't stall sampling — the
        // same reason the heartbeat uses it.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        if timer != nil { NSLog("[lidawake] quiet watch stopped") }
        timer?.invalidate(); timer = nil
        policy = nil; fired = false
    }

    /// start() without the timer — the selftest drives `look(at:)` itself.
    func begin(at now: Date) {
        source.prime()
        policy = QuietPolicy(thresholds: Self.thresholds, start: now)
        fired = false; looks = 0
    }

    /// One firing of the timer. Every third is the tick: everything is read and
    /// the verdict taken. The two between read the keep-awake list only.
    func look(at now: Date) {
        looks += 1
        if looks % Self.requestReadsPerTick == 0 { tick(at: now) }
        else if !fired { policy?.observeRequests(source.readRequests(), at: now) }
    }

    private func tick(at now: Date) {
        guard !fired, var p = policy else { return }
        p.observe(source.read(), at: now)
        policy = p
        let last = p.lastActivity
        // Per-tick diagnostics, only under the test hook. Without these, "still
        // active" and "the timer never ran" are indistinguishable from outside.
        if ProcessInfo.processInfo.environment["LIDAWAKE_IDLE_SECONDS"] != nil {
            NSLog("[lidawake] quiet for \(Int(p.quietAge(at: now)))s — last: \(last.description)")
        }
        guard p.shouldStop(at: now) else { return }
        fired = true
        NSLog("[lidawake] nothing happening for \(Int(Self.window / 60)) min — last: \(last.description) — turning off")
        onIdle?(last)
    }
}
