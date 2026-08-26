// Policy checks for ActivityWindow, driven by the real measurements taken on
// 2026-08-27 (18-core M5 Pro). No machine required — this is the decision only.
//   swiftc -parse-as-library Sources/App/IdleWatcher.swift tools/idlewatcher-selftest.swift -o /tmp/iwt && /tmp/iwt

import Foundation

var failures = 0
func expect(_ label: String, _ got: Bool, _ want: Bool) {
    if got == want { print("  PASS  \(label): quiet=\(got)") }
    else { print("  FAIL  \(label): quiet=\(got), expected \(want)"); failures += 1 }
}

/// A full window of one workload.
func window(cores: Double, kbps: Double, capacity: Int = 60) -> ActivityWindow {
    var w = ActivityWindow(capacity: capacity)
    for _ in 0..<capacity { w.add(cores: cores, kbps: kbps) }
    return w
}

@main struct T {
    static func main() {
        // Capacity the shipping build actually uses, not a guess.
        let cap = Int(IdleWatcher.defaultWindow / min(30, max(1, IdleWatcher.defaultWindow / 12)))
        print("window \(Int(IdleWatcher.defaultWindow / 60)) min, \(cap) samples\n")

        print("measured workloads")
        // Idle floor: 0.5–1.1 cores, 0–11 KB/s. Must sleep.
        var idle = ActivityWindow(capacity: cap)
        let floorCores = [1.12, 0.80, 0.52, 0.90, 0.57, 0.58, 0.58, 0.51]
        let floorKBps  = [11.0, 8.0, 0.0, 11.0, 0.0, 1.0, 7.0, 1.0]
        for i in 0..<cap { idle.add(cores: floorCores[i % 8], kbps: floorKBps[i % 8]) }
        expect("idle floor (real samples) sleeps", idle.isQuiet, true)

        // Compile: ~8 cores, ~3 KB/s. Must NOT sleep.
        expect("compile, 8 cores pegged", window(cores: 8.0, kbps: 3.0, capacity: cap).isQuiet, false)

        // Download: 0.8 cores — INSIDE the idle band — but 42 KB/s. Must NOT sleep.
        // This is the case a CPU-only rule would have killed.
        expect("download (CPU looks idle, network does not)",
               window(cores: 0.8, kbps: 42.0, capacity: cap).isQuiet, false)

        print("edges")
        // A single busy core must survive, even on an 18-core machine where it is
        // only 5.5% of capacity.
        expect("one busy core + idle floor", window(cores: 1.6, kbps: 5.0, capacity: cap).isQuiet, false)
        // A slow transfer must survive.
        expect("slow 20 KB/s transfer", window(cores: 0.6, kbps: 20.0, capacity: cap).isQuiet, false)

        print("bias toward not sleeping")
        // Never fire on a partial window — 29 minutes of quiet is not 30.
        var partial = ActivityWindow(capacity: cap)
        for _ in 0..<(cap - 1) { partial.add(cores: 0.1, kbps: 0.0) }
        expect("29 of 30 minutes quiet", partial.isQuiet, false)
        expect("empty window", ActivityWindow(capacity: cap).isQuiet, false)

        // Averaging must keep a finished burst suppressing sleep for a while.
        var burst = ActivityWindow(capacity: cap)
        for _ in 0..<10 { burst.add(cores: 8.0, kbps: 3.0) }     // 5 min of build
        for _ in 0..<50 { burst.add(cores: 0.5, kbps: 2.0) }     // then 25 min quiet
        expect("build ended 25 min ago still suppresses", burst.isQuiet, false)

        // ...but it must eventually let go, or the feature never fires.
        var settled = ActivityWindow(capacity: cap)
        for _ in 0..<10 { settled.add(cores: 8.0, kbps: 3.0) }
        for _ in 0..<60 { settled.add(cores: 0.5, kbps: 2.0) }   // burst rolled out
        expect("once the burst rolls out of the window", settled.isQuiet, true)

        // reset() must not leave a stale verdict behind.
        var r = window(cores: 0.1, kbps: 0.0, capacity: cap)
        r.reset()
        expect("after reset", r.isQuiet, false)

        print(failures == 0 ? "\nall \(11) policy checks passed" : "\n\(failures) FAILURES")
        exit(failures == 0 ? 0 : 1)
    }
}
