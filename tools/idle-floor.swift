// Measure this Mac's idle floor against the shipping thresholds.
//
// Run it in the TARGET configuration — on AC, external display attached, lid
// about to be closed, and NO development tooling running — then walk away. The
// numbers are only meaningful if nobody is touching the machine: a driven Mac
// reads ~0.96 cores where the same Mac left alone reads ~0.27.
//
//   swiftc -parse-as-library Sources/App/IdleWatcher.swift tools/idle-floor.swift -o /tmp/idle-floor
//   /tmp/idle-floor            # 30 min, the real window
//   LIDAWAKE_IDLE_SECONDS=120 /tmp/idle-floor   # 2 min, for a quick look
//
// Same code path as the app, so the verdict is directly comparable.

import Foundation

@main struct IdleFloor {
    static func main() {
        let interval = IdleWatcher.sampleInterval
        let cap = Int(IdleWatcher.window / interval)
        print("lidawake idle-floor probe")
        print("  window \(Int(IdleWatcher.window))s, sampling every \(Int(interval))s, \(cap) samples")
        print("  thresholds: cores < \(ActivityWindow.busyCores), network < \(ActivityWindow.busyKBps) KB/s")
        print("  walk away now — anything you do to this Mac is what it measures\n")

        var w = ActivityWindow(capacity: cap)
        var c0 = IdleWatcher.cpuTicks(), n0 = IdleWatcher.netBytes()
        for i in 1...cap {
            Thread.sleep(forTimeInterval: interval)
            let c1 = IdleWatcher.cpuTicks(), n1 = IdleWatcher.netBytes()
            let dT = c1.total - c0.total, dB = c1.busy - c0.busy
            let cores = dT > 0 ? (dB / dT) * Double(ProcessInfo.processInfo.processorCount) : 0
            let kbps = n1 >= n0 ? Double(n1 - n0) / interval / 1024.0 : 0
            c0 = c1; n0 = n1
            w.add(cores: cores, kbps: kbps)
            print(String(format: "  %2d/%d  cores=%5.2f%@  net=%7.1f KB/s%@",
                         i, cap, cores, cores < ActivityWindow.busyCores ? "     " : " OVER",
                         kbps, kbps < ActivityWindow.busyKBps ? "" : " OVER"))
        }
        print(String(format: "\n  average  cores=%.2f (limit %.1f, %.1fx margin)   net=%.1f KB/s (limit %.1f)",
                     w.averageCores, ActivityWindow.busyCores,
                     w.averageCores > 0 ? ActivityWindow.busyCores / w.averageCores : 0,
                     w.averageKBps, ActivityWindow.busyKBps))
        print("  verdict: \(w.isQuiet ? "QUIET — lidawake would let this Mac sleep" : "BUSY — lidawake would keep it awake")")
    }
}
