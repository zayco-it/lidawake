// "Keep awake until it goes quiet" — the rule, and the timer that runs it.
//
// THE RULE (attended-mac-spec.md §11.2): lidawake turns itself off 30 minutes
// after the last thing it could see. Every signal reports the time it last saw
// activity; the verdict is `now − max(lastActivity) ≥ 30 min`, checked every
// 30 s. Nothing learns, nothing adapts, every number is fixed, and the message
// that turns lidawake off names the last thing seen and when.
//
// Two kinds of signal:
//   declared — input age, sound, video: read as they are, instantaneous.
//   load     — a program's CPU, the processor, the graphics chip, the network:
//              bursty, so each is the MEDIAN of the trailing ten samples (five
//              minutes) against a fixed threshold. The median's only job is
//              spike immunity; the 30-minute rule is the debounce, so the
//              window is short on purpose — a long one keeps reading "active"
//              for most of half an hour after a download ends, and only then
//              do the 30 minutes start, which nobody can predict from "30
//              minutes of quiet".
//
// A SIGNAL THAT CANNOT BE READ COUNTS AS ACTIVITY NOW. Each reader returns an
// optional; nil means "could not read", never "nothing". Stopping someone's
// work is worse than running longer, and this is testable without hardware.
//
// THRESHOLDS ARE PLACEHOLDERS until E10 and E11 (spec §11.6) have run on
// macOS 27 — see `Thresholds`. The selftest passes its own, so nothing there
// depends on them.
//
// READERS ARE STUBBED. `StubActivitySource` reads nothing, so every signal is
// unreadable, quiet mode never fires, and the menu shows "(active now)". The
// real readers are spec §11.8 step 3 (`ActivitySignals.swift`), after the
// measurements. Until then the mode is plumbing, and safe plumbing.
//
// What was here before — T2.5's two counters, system-wide CPU and network on a
// 30-minute mean — was stopped in 1.4.9: measured in the target configuration
// it read BUSY permanently (spec §7.20), because a system-wide total cannot
// tell the user's work from macOS's housekeeping (§7.21). The per-program
// signal below exists to fix exactly that, by attributing CPU to processes.

import Foundation

/// The seven things the detector can see. The order is the tie-break when two
/// signals share the same last moment — presence first, so "you using the Mac"
/// is what gets named when it and "the processor busy" are both now.
enum Signal: Int, CaseIterable, Comparable {
    case presence, audio, video, program, processor, graphics, network
    static func < (a: Signal, b: Signal) -> Bool { a.rawValue < b.rawValue }
}

/// One moment of activity, and how to say it.
struct Activity: Equatable {
    let signal: Signal
    let at: Date
    /// The process name, for video and program — the part of the sentence that
    /// names something. Nil for the rest.
    let detail: String?
    /// False when the signal counted because it could NOT be read. Such an
    /// activity is always "now", so it never reaches the stop message; it shows
    /// only in the log line under the test hook.
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
        guard readable else { return "\(subject) could not be checked" }
        switch signal {
        case .presence:  return "you using the Mac"
        case .audio:     return "sound playing"
        case .video:     return detail.map { "video playing in \($0)" } ?? "video playing"
        case .program:   return detail.map { "\($0) working" } ?? "one of your programs working"
        case .processor: return "the processor busy"
        case .graphics:  return "the graphics chip busy"
        case .network:   return "network traffic"
        }
    }

    private var subject: String {
        switch signal {
        case .presence:  return "input"
        case .audio:     return "sound"
        case .video:     return "video"
        case .program:   return "your programs"
        case .processor: return "the processor"
        case .graphics:  return "the graphics chip"
        case .network:   return "the network"
        }
    }
}

/// One tick's readings. EVERY field is optional, and nil means the reader
/// could not read — which the policy counts as activity now. A reader that can
/// read and sees nothing returns a value: false, [], [:], 0.
struct Readings {
    var presenceAge: TimeInterval? = nil        // seconds since the last input event
    var audioHeld: Bool? = nil                  // coreaudiod holds its assertion
    var videoHolders: [String]? = nil           // names holding PreventUserIdleDisplaySleep, lidawake excluded
    var programCores: [String: Double]? = nil   // this tick's core-equivalents per WORK process, by name
    var totalCores: Double? = nil               // system-wide core-equivalents
    var gpuPercent: Double? = nil               // IOAccelerator Device Utilization %
    var networkKBps: Double? = nil              // non-loopback bytes, both directions
    init() {}
}

/// Every number the rule uses, in one place.
///
/// PLACEHOLDERS: `programCores` is set from E11 and `gpuPercent` from E10
/// phase E before release (spec §11.6); the values here are the provisional
/// ones from spec §11.3 and nothing in the selftest depends on them.
/// `processorCores` and `networkKBps` are decided; `quietWindow` is the product
/// rule itself.
struct Thresholds {
    var quietWindow: TimeInterval = 30 * 60
    var medianSamples = 10        // five minutes at the 30 s tick
    var minimumSamples = 3        // a "median" of one or two samples is a spike with a majority
    var programCores = 0.5        // PLACEHOLDER — E11
    var processorCores = 4.0      // the backstop for what attribution cannot read
    var gpuPercent = 50.0         // PLACEHOLDER — E10 phase E (the load side is measured: 98 % under inference, E5c)
    var networkKBps = 15.0
    static let placeholder = Thresholds()
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

    private var processor: MedianWindow
    private var graphics: MedianWindow
    private var network: MedianWindow
    private var programs: [String: MedianWindow] = [:]

    init(thresholds: Thresholds, start: Date) {
        self.thresholds = thresholds
        processor = MedianWindow(capacity: thresholds.medianSamples)
        graphics  = MedianWindow(capacity: thresholds.medianSamples)
        network   = MedianWindow(capacity: thresholds.medianSamples)
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

        // Your programs: one median per process, by name. A process that was
        // seen before and is absent this tick reads as 0, so it decays; a window
        // that has filled with zeros is forgotten.
        if let cores = r.programCores {
            for (name, c) in cores {
                programs[name, default: MedianWindow(capacity: thresholds.medianSamples)].add(c)
            }
            for name in programs.keys where cores[name] == nil { programs[name]?.add(0) }
            var busiest: (name: String, median: Double)? = nil
            for (name, w) in programs where w.sustained(over: thresholds.programCores, minimum: thresholds.minimumSamples) {
                if let m = w.median, busiest == nil || m > busiest!.median { busiest = (name, m) }
            }
            if let busiest { note(Activity(.program, at: now, detail: busiest.name)) }
            programs = programs.filter { !($0.value.isFull && $0.value.allZero) }
        } else {
            note(.unreadable(.program, at: now))
        }

        // The three system-wide load signals.
        var a: Activity?
        (processor, a) = load(processor, r.totalCores,  .processor, thresholds.processorCores, now); if let a { note(a) }
        (graphics,  a) = load(graphics,  r.gpuPercent,  .graphics,  thresholds.gpuPercent,     now); if let a { note(a) }
        (network,   a) = load(network,   r.networkKBps, .network,   thresholds.networkKBps,    now); if let a { note(a) }
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

/// Where a tick's readings come from. The real readers arrive with spec §11.8
/// step 3; until then the stub below is the only source.
protocol ActivitySource {
    func read() -> Readings
}

/// Reads nothing: every signal unreadable, so quiet mode can never fire. The
/// safe intermediate state while the readers wait on E10 and E11.
struct StubActivitySource: ActivitySource {
    func read() -> Readings { Readings() }
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

    /// The placeholders with the window applied. Only the window scales; the
    /// median stays ten ticks, so under the hook it is ten shortened ticks.
    static var thresholds: Thresholds { thresholds(for: window) }
    static func thresholds(for window: TimeInterval) -> Thresholds {
        var t = Thresholds.placeholder
        t.quietWindow = window
        return t
    }

    /// Called on the main thread, once per session, with the last activity seen.
    var onIdle: ((Activity) -> Void)?

    private let source: ActivitySource
    private var timer: Timer?
    private var policy: QuietPolicy?
    private var fired = false

    init(source: ActivitySource = StubActivitySource()) { self.source = source }

    var isRunning: Bool { timer != nil }
    /// For the status line. Nil when the detector is not running.
    var quietAge: TimeInterval? { policy?.quietAge(at: Date()) }
    var lastActivity: Activity? { policy?.lastActivity }

    func start() {
        guard timer == nil else { return }
        policy = QuietPolicy(thresholds: Self.thresholds, start: Date())
        fired = false
        NSLog("[lidawake] quiet watch started — window \(Int(Self.window))s, sampling every \(Int(Self.sampleInterval))s")
        let t = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in self?.tick() }
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

    private func tick() {
        guard !fired, var p = policy else { return }
        let now = Date()
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
