// The readers behind "Keep awake until it goes quiet": seven signals, read from
// the system once a tick — and the keep-awake list twice more in between. The
// rule that uses them, and the classification rules they feed, are in
// IdleWatcher.swift — this file is only the reading.
//
// WHAT IS READ, AND WHAT IS THROWN AWAY. Said out loud because none of it asks
// permission: no entitlement, no prompt, nothing in System Settings, and no
// way for a user to see that it happens (spec §7.11).
//
//   input      CGEventSource: seconds since the last hardware input. One
//              number. Not which key, not which app, not which device.
//   sound,     IOPMCopyAssertionsByProcess: the power-assertion table. macOS
//   video and  hands over the WHOLE table — every asserting process, in every
//   requests   account, its name and its reason. Three facts are kept: whether
//              coreaudiod holds a system-sleep assertion; the names of
//              processes holding a display-sleep one (to say "video playing in
//              ‹app›"); and who, among the user's programs, is asking the Mac
//              to stay awake. For that last one the holder's path, parent and
//              account are looked up — for any account, which macOS allows —
//              and A HOLDER IN ANOTHER USER'S ACCOUNT IS COUNTED BUT NEVER
//              NAMED: its name is dropped in the rule, before anything is kept,
//              shown or logged. (Root's are named: a system-wide daemon is
//              nobody's private app.) Everything else is discarded here, on
//              the spot.
//   programs   libproc: CPU time, parent pid and executable path of this
//              user's own processes. Kept: a name and a number for those using
//              real CPU. Other users' and root's processes cannot be read.
//   graphics   IOKit registry: the GPU's utilisation, one percentage.
//   network    getifaddrs: bytes in and out, summed over interfaces. A total —
//              not which host, not which process.
//
// Nothing is stored between ticks but the counters needed to take a
// difference, nothing is written to disk, and nothing leaves the Mac.
//
// EVERY READER RETURNS nil WHEN IT CANNOT READ, never a zero. The policy
// counts nil as activity: stopping someone's work is worse than running
// longer. All of it was verified on macOS 27.0.1 from a Standard account
// (spec §11.6); two of the calls are not public API and are marked.

import Foundation
import CoreGraphics
import IOKit
import IOKit.pwr_mgt
import Darwin

final class SystemActivitySource: ActivitySource {

    /// Below this a process is not reported at all: a twentieth of a core cannot
    /// move a median toward the half-core threshold, and reporting every idle
    /// process would have the policy keep a window for each.
    static let reportFloor = 0.05

    private struct ProcessTime { let cpu: UInt64; let ppid: Int32; let path: String; let name: String }

    private var lastProcesses: [Int32: UInt64] = [:]
    private var lastProcessesAt: Date?
    private var lastNetBytes: UInt64?
    private var lastNetAt: Date?
    private let machToNanoseconds: Double

    init() {
        // proc_pid_rusage reports CPU time in Mach absolute-time units, which
        // are not nanoseconds on Apple silicon (125/3 on an M5). Unscaled, every
        // per-process figure is off by the same factor of ~42.
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        machToNanoseconds = tb.denom == 0 ? 1 : Double(tb.numer) / Double(tb.denom)
    }

    func prime() {
        let now = Date()
        if let p = Self.processTimes() { lastProcesses = p.mapValues { $0.cpu }; lastProcessesAt = now }
        else { lastProcesses = [:]; lastProcessesAt = nil }
        lastNetBytes = Self.netBytes()
        lastNetAt = now
    }

    func read() -> Readings {
        var r = Readings()
        r.presenceAge = Self.presenceAge()
        if let rows = Self.assertionRows() {
            r.audioHeld = AssertionRule.audioHeld(rows)
            r.videoHolders = AssertionRule.videoHolders(rows, ownPid: getpid())
            r.requestHolders = Self.requestHolders(rows)
        }
        r.programCores = programCores()
        r.gpuPercent = Self.gpuPercent()
        r.networkKBps = networkKBps()
        return r
    }

    func readRequests() -> [String]? {
        Self.assertionRows().map(Self.requestHolders)
    }

    private static func requestHolders(_ rows: [AssertionRow]) -> [String] {
        AssertionRule.requestHolders(rows, ownPid: getpid(), ownUid: getuid(), lookup: processFacts)
    }

    // MARK: - Presence

    /// Seconds since the last HARDWARE input event. `.hidSystemState`, not
    /// `.combinedSessionState`: the combined state also counts events software
    /// posts into the session, and ran a second behind in the one phase where
    /// the two differed (E10). It is elapsed time, not a flag, so none of the
    /// three ways the `UserIsActive` assertion can be misread apply (§7.15).
    static func presenceAge() -> TimeInterval? {
        guard let any = CGEventType(rawValue: ~0) else { return nil }   // kCGAnyInputEventType
        let s = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: any)
        return s.isFinite && s >= 0 ? s : nil
    }

    // MARK: - Sound, video and keep-awake requests

    /// The assertion table, reduced to four fields per row. nil unless the call
    /// SUCCEEDS: a powerd that cannot be reached answers `kIOReturnNotFound`
    /// with no dictionary (E12), which read as "nothing is held" would sleep
    /// someone's music. The return code is the test, not the dictionary.
    static func assertionRows() -> [AssertionRow]? {
        var byPid: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byPid) == kIOReturnSuccess,
              let table = byPid?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return nil }
        var rows: [AssertionRow] = []
        for (pid, assertions) in table {
            for a in assertions {
                let declared = a[kIOPMAssertionTypeKey] as? String ?? ""
                rows.append(AssertionRow(pid: pid.int32Value,
                                         process: a["Process Name"] as? String ?? "",
                                         // The true type, falling back to the declared one. See AssertionRow.
                                         trueType: a["AssertionTrueType"] as? String ?? declared,
                                         name: a[kIOPMAssertionNameKey] as? String ?? ""))
            }
        }
        return rows
    }

    /// Path, parent, account and name of ONE process — any process. `sysctl`
    /// and `proc_pidpath` answer for root's and other accounts' too (verified
    /// from a Standard account, macOS 27.0.1), which the CPU reader's calls
    /// below do not; that is why a request can be attributed across accounts
    /// and CPU cannot. nil when there is no such process any more. The account
    /// is the REAL uid — whose session it is, not what it is allowed to do.
    static func processFacts(_ pid: Int32) -> ProcessFacts? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        var path = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &path, UInt32(path.count))
        let file = n > 0 ? String(cString: path) : ""
        let comm = withUnsafeBytes(of: &info.kp_proc.p_comm) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return ProcessFacts(path: file, ppid: info.kp_eproc.e_ppid, uid: info.kp_eproc.e_pcred.p_ruid,
                            name: WorkRule.wholeName(comm: comm, path: file))
    }

    // MARK: - Your programs

    /// Core-equivalents used since the last tick by each of the user's WORK
    /// processes (WorkRule). nil if the process list cannot be read at all;
    /// empty on the first tick, when there is nothing to take a difference from.
    private func programCores() -> [Program: Double]? {
        guard let now = Self.processTimes() else {
            lastProcesses = [:]; lastProcessesAt = nil
            return nil
        }
        let at = Date()
        defer { lastProcesses = now.mapValues { $0.cpu }; lastProcessesAt = at }
        guard let before = lastProcessesAt else { return [:] }
        let dt = at.timeIntervalSince(before)
        guard dt > 0 else { return [:] }

        var out: [Program: Double] = [:]
        let me = getpid()
        for (pid, p) in now where pid != me {
            guard let was = lastProcesses[pid], p.cpu >= was else { continue }   // new, or the pid was reused
            guard WorkRule.isWork(path: p.path, ppid: p.ppid) else { continue }
            let cores = Double(p.cpu - was) * machToNanoseconds / (dt * 1e9)
            if cores >= Self.reportFloor {
                out[Program(name: WorkRule.displayName(path: p.path, processName: p.name), pid: pid)] = cores
            }
        }
        return out
    }

    /// CPU time, parent and path of every process this user may read. Root's
    /// and other accounts' processes are refused (errno 1) and simply absent —
    /// that is the limit named in spec §11.4, not an error. nil only if the
    /// list itself cannot be had, or nothing in it could be read.
    private static func processTimes() -> [Int32: ProcessTime]? {
        var bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return nil }
        var pids = [Int32](repeating: 0, count: Int(bytes) / MemoryLayout<Int32>.size + 64)
        bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard bytes > 0 else { return nil }

        var out: [Int32: ProcessTime] = [:]
        var path = [CChar](repeating: 0, count: 4096)
        for pid in pids.prefix(Int(bytes) / MemoryLayout<Int32>.size) where pid > 0 {
            var usage = rusage_info_v4()
            let rc = withUnsafeMutablePointer(to: &usage) { p in
                p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard rc == 0 else { continue }
            var info = proc_bsdinfo()
            let got = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
            let n = proc_pidpath(pid, &path, UInt32(path.count))
            // Own time plus REAPED CHILDREN's: a build spawns compilers that
            // live for seconds each, and the tool that reaps them is the one
            // process alive across two ticks.
            let cpu = usage.ri_user_time &+ usage.ri_system_time
                &+ usage.ri_child_user_time &+ usage.ri_child_system_time
            // The name it was started as (see WorkRule.displayName), read as the
            // C string it is from the fixed-size field.
            let name = got > 0 ? withUnsafeBytes(of: &info.pbi_name) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            } : ""
            out[pid] = ProcessTime(cpu: cpu,
                                   ppid: got > 0 ? Int32(bitPattern: info.pbi_ppid) : -1,
                                   path: n > 0 ? String(cString: path) : "",
                                   name: name)
        }
        return out.isEmpty ? nil : out
    }

    // MARK: - Graphics

    /// The GPU's "Device Utilization %". NOT a public API: the key lives in the
    /// registry entry of the IOAccelerator driver and Apple documents none of
    /// it. If the driver, the dictionary or the key is gone this returns nil,
    /// which the policy reads as activity — the feature then never fires, which
    /// is the safe way for an undocumented read to break, and E9 would show it.
    static func gpuPercent() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString,
                                                        kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
            IOObjectRelease(service)
            if let n = stats?["Device Utilization %"] as? NSNumber { return n.doubleValue }
            service = IOIteratorNext(iterator)
        }
        return nil
    }

    // MARK: - Network

    /// KB/s across every real interface since the last tick. nil if the
    /// counters cannot be read, or went BACKWARDS — an interface that left took
    /// its bytes with it, and a difference across that is not a small number,
    /// it is no number.
    private func networkKBps() -> Double? {
        guard let bytes = Self.netBytes() else { lastNetBytes = nil; lastNetAt = nil; return nil }
        let at = Date()
        defer { lastNetBytes = bytes; lastNetAt = at }
        guard let before = lastNetBytes, let was = lastNetAt else { return 0 }   // first read: nothing to compare
        let dt = at.timeIntervalSince(was)
        guard dt > 0 else { return 0 }
        guard bytes >= before else { return nil }
        return Double(bytes - before) / dt / 1024.0
    }

    /// Bytes in+out across every real interface. Loopback excluded — a Mac
    /// talking to itself is not a transfer worth staying awake for.
    private static func netBytes() -> UInt64? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
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
