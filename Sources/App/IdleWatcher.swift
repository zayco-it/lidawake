// T2.5 — the one rule: lid closed and nothing happening → let the Mac sleep.
//
// ONE RULE, TWO COUNTERS. That is not a contradiction. The rule the user sees is
// "nothing is happening"; establishing it takes two counters because the two
// things lidawake publicly exists for are DISJOINT in every single counter.
// Measured on an 18-core M5 Pro, 2026-08-27:
//
//   workload                    CPU (core-equivalents)   network
//   idle, display on, apps open        0.5 – 1.1          0 – 11 KB/s
//   compile, 8 cores pegged            ~8.0               ~3 KB/s
//   download over Wi-Fi                0.8                42 KB/s
//
// A real download sits INSIDE the idle band on CPU. A compile is invisible to
// the network. Either counter alone sleeps through one of the two cases the
// site promises in writing, so both are required. There is no third counter and
// no tuning surface: the two numbers below are the whole policy.
//
// Also ruled out, with evidence:
//   - System power assertions ("would macOS sleep?"). Pegging 8 cores produced
//     ZERO new assertions. macOS would happily sleep a compiling Mac — that is
//     what `caffeinate` exists to prevent — so asking macOS defeats the product.
//   - Disk I/O. Reads 0 KB/s under pure CPU load; sleeps through a compile.
//   - HID idle time. Measures the wrong thing entirely: an overnight render has
//     hours of it and must never be slept.
//   - Load average. A 1-minute EMA — 8 pegged cores moved it 2.18 → 2.73 in six
//     seconds. Far too slow to be trusted.
//
// EVERY THRESHOLD IS BIASED TOWARD NOT SLEEPING. Sleeping early kills someone's
// build and loses hours of their work; sleeping late costs a little power. The
// failure mode of a threshold that is too low is "we never auto-sleep", which is
// exactly today's behaviour and harms nobody.

import Foundation
import Darwin

/// The rolling window and the decision, with no sampling in it, so the policy
/// can be tested without a machine to measure.
struct ActivityWindow {

    /// Busy above one core's worth of sustained work. Expressed in cores rather
    /// than percent so it means the same thing on an 8-core Air and an 18-core
    /// Pro — a single busy core is 12.5% on one and 5.5% on the other, and a
    /// percentage threshold would protect the Air and abandon the Pro.
    static let busyCores = 1.0

    /// Deliberately low. The slowest download worth keeping a Mac awake for is
    /// far below the 42 KB/s measured above, and the idle floor averaged ~5 KB/s.
    /// Setting this high enough to guarantee sleep on a chatty machine would
    /// start killing slow transfers, which is the one thing this must not do.
    static let busyKBps = 15.0

    let capacity: Int
    private var cores: [Double] = []
    private var kbps: [Double] = []

    init(capacity: Int) { self.capacity = capacity }

    mutating func add(cores c: Double, kbps k: Double) {
        cores.append(c); kbps.append(k)
        if cores.count > capacity { cores.removeFirst(); kbps.removeFirst() }
    }

    mutating func reset() { cores.removeAll(); kbps.removeAll() }

    var isFull: Bool { cores.count >= capacity }
    var count: Int { cores.count }
    var averageCores: Double { cores.isEmpty ? 0 : cores.reduce(0, +) / Double(cores.count) }
    var averageKBps: Double { kbps.isEmpty ? 0 : kbps.reduce(0, +) / Double(kbps.count) }

    /// Averaged over the whole window, NOT "every sample was quiet".
    ///
    /// Continuous-quiet was tried on paper and fails: the measured idle floor
    /// spikes over one core roughly one sample in eight, which would reset the
    /// timer forever and the feature would never fire. Averaging also biases the
    /// right way on its own — a burst of real work keeps the average up long
    /// after it ends, so we wait longer rather than pouncing the moment a build
    /// stops.
    var isQuiet: Bool {
        guard isFull, !cores.isEmpty else { return false }
        return averageCores < Self.busyCores && averageKBps < Self.busyKBps
    }
}

/// Samples the machine while the lid is shut and reports when it has had nothing
/// to do for the whole window.
final class IdleWatcher {

    /// 30 minutes, not 5. A build that pauses to link, a download stalling on a
    /// slow server, a render between frames — all of them look idle briefly, and
    /// none of them should cost the user their work.
    static let defaultWindow: TimeInterval = 30 * 60

    /// Test hook, same pattern as LIDAWAKE_TRIAL_DAYS in LicenseController:
    /// LIDAWAKE_IDLE_SECONDS shortens the window so the whole path can be
    /// exercised on real hardware in a minute instead of half an hour. Ignored
    /// unless set, so a shipped build always uses the 30 minutes above.
    static var window: TimeInterval {
        if let raw = ProcessInfo.processInfo.environment["LIDAWAKE_IDLE_SECONDS"],
           let v = TimeInterval(raw), v > 0 { return v }
        return defaultWindow
    }

    /// 30 s normally — 60 samples across the window, which is what the policy
    /// was tuned and tested against. When the hook shortens the window, fall to
    /// whatever gives 12 samples so the averaging still has something to average.
    static var sampleInterval: TimeInterval { min(30, max(1, window / 12)) }

    var onIdle: (() -> Void)?   // called on the main thread, once per session

    private var timer: Timer?
    private var win = ActivityWindow(capacity: Int(window / sampleInterval))
    private var lastCPU: (busy: Double, total: Double)?
    private var lastNetBytes: UInt64?
    private var fired = false

    func start() {
        guard timer == nil else { return }
        win.reset()
        lastCPU = Self.cpuTicks()
        lastNetBytes = Self.netBytes()
        fired = false
        NSLog("[lidawake] idle watch started — window \(Int(Self.window))s, sampling every \(Int(Self.sampleInterval))s")
        let t = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in self?.tick() }
        // .common so menu tracking and modal panels don't stall sampling — the
        // same reason the heartbeat uses it.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        if timer != nil { NSLog("[lidawake] idle watch stopped") }
        timer?.invalidate(); timer = nil
        win.reset(); lastCPU = nil; lastNetBytes = nil; fired = false
    }

    private func tick() {
        guard !fired else { return }
        guard let prevCPU = lastCPU, let prevNet = lastNetBytes else { return }
        let nowCPU = Self.cpuTicks(), nowNet = Self.netBytes()
        lastCPU = nowCPU; lastNetBytes = nowNet

        let dTotal = nowCPU.total - prevCPU.total
        let dBusy  = nowCPU.busy  - prevCPU.busy
        guard dTotal > 0 else { return }   // counters wrapped or no time passed
        let cores = (dBusy / dTotal) * Double(ProcessInfo.processInfo.processorCount)

        // Unsigned subtraction underflows if an interface resets its counters.
        // Treat that as "unknown", not as zero traffic — zero would look quiet.
        guard nowNet >= prevNet else { return }
        let kbps = Double(nowNet - prevNet) / Self.sampleInterval / 1024.0

        win.add(cores: cores, kbps: kbps)

        // Per-sample diagnostics, only when the test hook is set. Without these,
        // "the average stayed above the threshold" and "the timer never ran" are
        // indistinguishable from outside — both look like nothing happening.
        // Off in shipped builds: two lines a minute, forever, for a decision
        // that is taken at most once every 30 minutes.
        if ProcessInfo.processInfo.environment["LIDAWAKE_IDLE_SECONDS"] != nil {
            NSLog(String(format: "[lidawake] idle sample cores=%.2f kbps=%.1f  avg cores=%.2f kbps=%.1f  %d/%d  quiet=%@",
                         cores, kbps, win.averageCores, win.averageKBps,
                         win.count, win.capacity, win.isQuiet ? "YES" : "no"))
        }

        guard win.isQuiet else { return }
        fired = true
        NSLog("[lidawake] nothing happening for \(Int(Self.window / 60)) min — restoring normal sleep")
        onIdle?()
    }

    // MARK: - Sampling

    /// System-wide CPU ticks since boot: (busy, total).
    static func cpuTicks() -> (busy: Double, total: Double) {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, 0) }
        let user = Double(info.cpu_ticks.0), sys = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2), nice = Double(info.cpu_ticks.3)
        return (user + sys + nice, user + sys + nice + idle)
    }

    /// Bytes in+out across every real interface. Loopback excluded — a Mac
    /// talking to itself is not a transfer worth staying awake for.
    static func netBytes() -> UInt64 {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return 0 }
        defer { freeifaddrs(addrs) }
        var total: UInt64 = 0
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard ifa.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            guard let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            total += UInt64(data.pointee.ifi_ibytes) + UInt64(data.pointee.ifi_obytes)
        }
        return total
    }
}
