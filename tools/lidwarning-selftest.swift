// Headless self-test for the lid warning's volume handling (WarningVolume).
// Compiles with the REAL source against a fake output device, so it tests the
// shipping rules and never touches the Mac's actual volume. Dev-only; NOT part of
// the app build.
//
//   swiftc -O -parse-as-library Sources/App/WarningVolume.swift \
//       tools/lidwarning-selftest.swift -o /tmp/lidawake-lidwarning-selftest \
//       && /tmp/lidawake-lidwarning-selftest
//
// Each rule in WarningVolume.swift exists because the obvious version leaves the
// Mac louder than the user set it, or overrides a level they chose — and neither
// failure makes a sound anyone would notice as a bug. Hence a test, not a hope.
//
// The crash case re-runs this binary as a child whose fake device SIGKILLs the
// process the instant the volume changes — the worst moment, mid-raise: no
// restore, no flush, no exit handlers. The parent then checks the record is
// there to repair from. That is rule 1's actual claim, and only a real process
// death tests it; dying after the raise returned would pass even with the record
// written too late.

import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { print("  PASS  \(label)") }
    else { print("  FAIL  \(label) \(detail())"); failures += 1 }
}

/// An output device table. `quantum` rounds every set down to a step, the way a
/// device with coarse volume steps reports back something other than what it
/// was asked for.
final class FakeDevices: VolumeControl {
    struct Dev { var volume: Float32; var muted = false; var settable = true }
    var devs: [String: Dev]
    var current: String?
    var quantum: Float32?
    var dieOnSet = false

    init(_ devs: [String: Dev], current: String?) { self.devs = devs; self.current = current }

    func defaultUID() -> String? { current }
    func volume(uid: String) -> Float32? { devs[uid]?.volume }
    func isMuted(uid: String) -> Bool { devs[uid]?.muted ?? false }
    func canSetVolume(uid: String) -> Bool { devs[uid]?.settable ?? false }
    func setVolume(uid: String, _ value: Float32) -> Bool {
        guard devs[uid]?.settable == true else { return false }
        var v = value
        if let q = quantum { v = (value / q).rounded(.down) * q }
        devs[uid]!.volume = v
        if dieOnSet { kill(getpid(), SIGKILL) }
        return true
    }
}

let SPEAKERS = "BuiltInSpeakerDevice"
let HEADPHONES = "BuiltInHeadphoneOutputDevice"

/// In-memory defaults for the in-process cases. A real suite cannot be cleaned
/// up after: cfprefsd writes an emptied domain back to ~/Library/Preferences
/// about ten seconds later, whatever the process deleted or flushed — a per-run
/// suite left two files behind every run.
final class MemoryDefaults: UserDefaults {
    private var store: [String: Any] = [:]
    init() { super.init(suiteName: nil)! }
    override func object(forKey key: String) -> Any? { store[key] }
    override func dictionary(forKey key: String) -> [String: Any]? { store[key] as? [String: Any] }
    override func set(_ value: Any?, forKey key: String) { store[key] = value }
    override func removeObject(forKey key: String) { store[key] = nil }
}
func freshDefaults() -> UserDefaults { MemoryDefaults() }

/// The crash case needs the real thing — surviving a process death through
/// cfprefsd is what it tests — so it gets one fixed domain, reused by every run.
/// It leaves one empty ~/Library/Preferences/it.zayco.lidawake.selftest.plist.
let CRASH_SUITE = "it.zayco.lidawake.selftest"

@main struct LidWarningSelfTest {
    static func main() {
        // Child mode for the crash case: die mid-raise.
        let args = CommandLine.arguments
        if args.count == 3, args[1] == "--die-mid-raise" {
            let fake = FakeDevices([SPEAKERS: .init(volume: 0.10)], current: SPEAKERS)
            fake.dieOnSet = true
            let v = WarningVolume(device: fake, defaults: UserDefaults(suiteName: args[2])!)
            _ = v.raiseIfLow(uid: SPEAKERS)
            exit(3)   // never raised: the parent reads this as a failure, not a crash
        }

        print("raiseTarget — when to raise, and to what")
        let M = WarningVolume.minimum
        check("the minimum is 60%", M == 0.60)
        let targets: [(Float32?, Bool, Bool, Float32?, String)] = [
            (0.10,   false, true,  M,   "10% → raised to 60%"),
            (0.31,   false, true,  M,   "31% → raised (measured: missed with a TV on)"),
            (0.5999, false, true,  M,   "just under 60% → raised"),
            (0.60,   false, true,  nil, "exactly 60% is not below 60% → played as is"),
            (0.90,   false, true,  nil, "90% → played as is"),
            (0.10,   true,  true,  nil, "muted → never raised"),
            (0.0,    false, true,  nil, "exactly 0 counts as muted → never raised"),
            (0.10,   false, false, nil, "no settable volume (HDMI, some USB) → left alone"),
            (nil,    false, true,  nil, "volume unreadable → left alone"),
        ]
        for (vol, muted, settable, want, why) in targets {
            let got = WarningVolume.raiseTarget(volume: vol, muted: muted, settable: settable)
            check(why, got == want, "got \(String(describing: got)), want \(String(describing: want))")
        }

        print("shouldRestore — rule 4")
        check("still exactly ours → restore", WarningVolume.shouldRestore(current: 0.5, weSet: 0.5))
        check("within 0.0005 → restore", WarningVolume.shouldRestore(current: 0.5005, weSet: 0.5))
        check("one ⌥⇧ volume-key step away (1/64) → user's, leave it",
              !WarningVolume.shouldRestore(current: 0.5 - 1.0 / 64, weSet: 0.5))
        check("device gone → nothing to restore", !WarningVolume.shouldRestore(current: nil, weSet: 0.5))

        print("flow — the round trip")
        do {
            let fake = FakeDevices([SPEAKERS: .init(volume: 0.10)], current: SPEAKERS)
            let v = WarningVolume(device: fake, defaults: freshDefaults())
            check("low volume is raised", v.raiseIfLow(uid: SPEAKERS))
            check("device now at 60%", fake.devs[SPEAKERS]!.volume == M)
            check("record holds the user's original", v.pending?.original == 0.10)
            check("restore reports .restored", v.restore() == .restored)
            check("device back at the user's 10%", fake.devs[SPEAKERS]!.volume == 0.10)
            check("record cleared", v.pending == nil)
            check("a second restore is a no-op", v.restore() == .nothingPending)
        }

        print("flow — nothing to do")
        do {
            let fake = FakeDevices([SPEAKERS: .init(volume: 0.10, muted: true)], current: SPEAKERS)
            let v = WarningVolume(device: fake, defaults: freshDefaults())
            check("muted: not raised", !v.raiseIfLow(uid: SPEAKERS))
            check("muted: volume untouched", fake.devs[SPEAKERS]!.volume == 0.10)
            check("muted: still muted", fake.devs[SPEAKERS]!.muted)
            check("muted: no record written", v.pending == nil)

            fake.devs[SPEAKERS] = .init(volume: 0)
            check("zero: not raised", !v.raiseIfLow(uid: SPEAKERS))
            check("zero: still zero", fake.devs[SPEAKERS]!.volume == 0)

            fake.devs[SPEAKERS] = .init(volume: 0.75)
            check("already loud enough: not raised", !v.raiseIfLow(uid: SPEAKERS))
            check("already loud enough: no record", v.pending == nil)
        }

        print("rule 3 — no raise over an outstanding raise")
        do {
            let fake = FakeDevices([SPEAKERS: .init(volume: 0.10)], current: SPEAKERS)
            let v = WarningVolume(device: fake, defaults: freshDefaults())
            _ = v.raiseIfLow(uid: SPEAKERS)
            fake.devs[SPEAKERS]!.volume = 0.20   // as if something lowered it again mid-warning
            check("second raise refused", !v.raiseIfLow(uid: SPEAKERS))
            check("record still holds the FIRST original, not ours", v.pending?.original == 0.10)
        }

        print("rule 4 — compare against what the device reported")
        do {
            let fake = FakeDevices([SPEAKERS: .init(volume: 0.10)], current: SPEAKERS)
            fake.quantum = 0.07                  // 0.60 is stored as 0.56
            let v = WarningVolume(device: fake, defaults: freshDefaults())
            _ = v.raiseIfLow(uid: SPEAKERS)
            let reported = fake.devs[SPEAKERS]!.volume
            check("device rounded the raise (\(reported))", reported != M)
            check("record holds the reported level, not the requested 60%",
                  v.pending?.setTo == reported)
            check("so the restore still happens", v.restore() == .restored)
            check("user's level back", abs(fake.devs[SPEAKERS]!.volume - 0.07) < 0.0001,
                  "got \(fake.devs[SPEAKERS]!.volume) — 0.10 rounded down to the device's step")

            fake.quantum = nil
            fake.devs[SPEAKERS] = .init(volume: 0.10)
            _ = v.raiseIfLow(uid: SPEAKERS)
            fake.devs[SPEAKERS]!.volume = 0.75   // the user turned it up during the warning
            check("user changed it → .userChanged", v.restore() == .userChanged)
            check("their 75% stands", fake.devs[SPEAKERS]!.volume == 0.75)
            check("record cleared anyway", v.pending == nil)
        }

        print("rule 2 — the device we raised, by UID")
        do {
            let fake = FakeDevices([SPEAKERS: .init(volume: 0.10),
                                    HEADPHONES: .init(volume: 0.30)], current: SPEAKERS)
            let v = WarningVolume(device: fake, defaults: freshDefaults())
            _ = v.raiseIfLow(uid: SPEAKERS)
            fake.current = HEADPHONES            // user switched output mid-warning
            check("restore after a switch → .restored", v.restore() == .restored)
            check("the speakers we raised are back at 10%", fake.devs[SPEAKERS]!.volume == 0.10)
            check("the headphones were never touched", fake.devs[HEADPHONES]!.volume == 0.30)

            _ = v.raiseIfLow(uid: SPEAKERS)
            fake.devs[SPEAKERS] = nil            // unplugged mid-warning
            check("device gone → .deviceGone", v.restore() == .deviceGone)
            check("headphones still untouched", fake.devs[HEADPHONES]!.volume == 0.30)
            check("record cleared", v.pending == nil)
        }

        print("rule 1 — the record survives a process death mid-raise")
        do {
            let suite = CRASH_SUITE
            UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite)
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = ["--die-mid-raise", suite]
            do { try child.run() } catch { check("child launched", false, "\(error)") }
            child.waitUntilExit()
            check("child died by SIGKILL inside the raise, as intended",
                  child.terminationReason == .uncaughtSignal && child.terminationStatus == SIGKILL,
                  "reason \(child.terminationReason.rawValue), status \(child.terminationStatus)")
            // A fresh instance, as the next launch would have. The device is where
            // the dead process left it: raised.
            let fake = FakeDevices([SPEAKERS: .init(volume: WarningVolume.minimum)], current: SPEAKERS)
            let next = WarningVolume(device: fake, defaults: UserDefaults(suiteName: suite)!)
            check("next launch finds the record", next.pending != nil)
            check("…with the user's original in it", next.pending?.original == 0.10)
            check("…and the requested level, since it died before the read-back",
                  next.pending?.setTo == WarningVolume.minimum)
            check("repair restores", next.restore() == .restored)
            check("user's 10% is back", fake.devs[SPEAKERS]!.volume == 0.10)
        }

        UserDefaults(suiteName: CRASH_SUITE)!.removePersistentDomain(forName: CRASH_SUITE)
        print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
