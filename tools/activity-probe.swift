// What quiet mode would see, and when it would stop — the app's own readers and
// the app's own rule, run standalone in a terminal. No helper, no menu, nothing
// is turned on or off: it only reads and prints.
//
//   swiftc -O -parse-as-library Sources/App/IdleWatcher.swift Sources/App/ActivitySignals.swift \
//       tools/activity-probe.swift -o /tmp/lidawake-activity-probe
//   /tmp/lidawake-activity-probe                      # the real 30 min window, 30 s ticks
//   LIDAWAKE_IDLE_SECONDS=120 /tmp/lidawake-activity-probe    # a 2-minute window, 2 s ticks
//   /tmp/lidawake-activity-probe 90 > probe.log       # stop after 90 ticks whatever happens
//
// Same code path as the app (the same thresholds, the same LIDAWAKE_IDLE_SECONDS
// hook), so what it prints is what the app would decide. It is the instrument
// for the acceptance runs of spec §11.7 — E9, E4, and E13, the agent in a loop:
// start it, start the loop, walk away, and read which signal moved at each poll
// and when the rule would have turned lidawake off.
//
// It keeps going after "WOULD TURN OFF" so a run shows what happened next; the
// app turns off once and stops looking.

import Foundation

@main struct ActivityProbe {
    static func main() {
        let limit = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) : nil
        let source = SystemActivitySource()
        let thresholds = IdleWatcher.thresholds
        let interval = IdleWatcher.sampleInterval
        let time = DateFormatter(); time.dateFormat = "HH:mm:ss"

        print("lidawake activity probe — window \(Int(thresholds.quietWindow)) s, a tick every \(Int(interval)) s, median of \(thresholds.medianSamples)")
        print("  counts: one of your programs ≥ \(thresholds.programCores) cores · graphics ≥ \(Int(thresholds.gpuPercent)) % · network ≥ \(Int(thresholds.networkKBps)) KB/s · sound · video · input")
        print("  a reading shown as ?? could not be read, and counts as activity\n")

        source.prime()
        var policy = QuietPolicy(thresholds: thresholds, start: Date())
        var announced = false
        var n = 0
        while limit == nil || n < limit! {
            Thread.sleep(forTimeInterval: interval)
            n += 1
            let now = Date()
            let r = source.read()
            policy.observe(r, at: now)

            let input = r.presenceAge.map { String(format: "%6.0f s", $0) } ?? "      ??"
            let sound = r.audioHeld.map { $0 ? "YES" : " no" } ?? " ??"
            let video = r.videoHolders.map { $0.isEmpty ? "no" : $0.joined(separator: ",") } ?? "??"
            let gpu = r.gpuPercent.map { String(format: "%3.0f %%", $0) } ?? "   ??"
            let net = r.networkKBps.map { String(format: "%7.1f", $0) } ?? "     ??"
            let top = r.programCores.map { cores -> String in
                let busiest = cores.sorted { $0.value > $1.value }.prefix(3)
                return busiest.isEmpty ? "-" : busiest.map { String(format: "%@ %.2f", $0.key.name, $0.value) }.joined(separator: ", ")
            } ?? "??"
            let last = policy.lastActivity
            print("\(time.string(from: now))  input \(input)  sound \(sound)  video \(video)  gpu \(gpu)  net \(net) KB/s  programs: \(top)")
            print(String(format: "          quiet for %4.0f s — last: %@ at %@", policy.quietAge(at: now), last.description, time.string(from: last.at)))
            if policy.shouldStop(at: now) && !announced {
                announced = true
                print("          >>> WOULD TURN OFF NOW — \(QuietReport.body(minutes: max(1, Int(thresholds.quietWindow / 60)), last: last, session: nil))")
            }
            if !policy.shouldStop(at: now) { announced = false }
            fflush(stdout)
        }
    }
}
