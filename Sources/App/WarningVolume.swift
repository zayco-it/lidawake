// The volume handling behind the lid warning: raise a low volume so the warning
// is heard, then put the user's level back. Kept free of CoreAudio and AppKit so
// tools/lidwarning-selftest.swift can drive it against a fake device — it is the
// one part of the warning that can go wrong silently and leave the Mac louder
// than the user set it.
//
// The four rules, each of which exists because the obvious version is wrong:
//
//   1. The restore record is written BEFORE the raise and persisted, so a crash
//      between raise and restore is repaired on the next launch.
//   2. The device is addressed by UID, never as "whatever is default now". If the
//      user switched output in between, the device we raised is the one restored,
//      and the new one is never touched.
//   3. No raise while one is outstanding. A second raise would read OUR level as
//      the user's original, and the restore would then put the warning level back
//      as if it were theirs.
//   4. Restore only if the volume is still what we set — compared against what
//      the device REPORTED after the raise, not what we asked for, because a
//      device may round the value it is given. If the user changed it themselves,
//      their value stands.
//
// Mute is never written anywhere in this app. That, not a check, is what keeps
// "never unmute" true.

import Foundation

/// What the volume handling needs from an output device. Every call names the
/// device by UID; `volume` is nil when the device is gone or cannot be read.
protocol VolumeControl {
    func defaultUID() -> String?
    func volume(uid: String) -> Float32?
    func isMuted(uid: String) -> Bool
    func canSetVolume(uid: String) -> Bool
    func setVolume(uid: String, _ value: Float32) -> Bool
}

struct WarningVolume {

    /// The least the warning plays at. Below it the volume is raised TO it for the
    /// sound and put back after; at or above it, left alone. One number, not a
    /// threshold and a separate target: anything below the level that is loud
    /// enough is, by definition, too quiet.
    ///
    /// Measured 2026-09-27, Hero through a closed lid on the built-in speakers: at
    /// 50% it was "about right, maybe slightly too quiet for a noisy room"; at 31%,
    /// with a TV on, it was heard only because the listener was waiting for it.
    /// The first version raised only below 25%, so 31% — an ordinary setting —
    /// played unraised and would have been missed.
    static let minimum: Float32 = 0.60
    /// How close a read-back must be to count as "still what we set". A volume key
    /// moves the level by 1/16, or 1/64 with Option-Shift — both far outside this.
    static let sameWithin: Float32 = 0.001

    static let pendingKey = "warningVolumePendingRestore"

    let device: VolumeControl
    let defaults: UserDefaults

    /// The level to raise to, or nil to leave the volume alone. A muted device is
    /// never raised, and a volume of exactly 0 counts as muted: someone who pulled
    /// the slider all the way down meant silence.
    static func raiseTarget(volume: Float32?, muted: Bool, settable: Bool) -> Float32? {
        guard settable, !muted, let v = volume, v > 0, v < minimum else { return nil }
        return minimum
    }

    /// Rule 4. `current` is nil when the device is gone or unreadable.
    static func shouldRestore(current: Float32?, weSet: Float32) -> Bool {
        guard let current else { return false }
        return abs(current - weSet) <= sameWithin
    }

    /// Raise `uid` for the warning if it is low. True if it was raised.
    @discardableResult
    func raiseIfLow(uid: String) -> Bool {
        guard pending == nil else { return false }                       // rule 3
        let original = device.volume(uid: uid)
        guard let target = Self.raiseTarget(volume: original,
                                            muted: device.isMuted(uid: uid),
                                            settable: device.canSetVolume(uid: uid)),
              let original else { return false }
        save(Pending(uid: uid, original: original, setTo: target))       // rule 1
        guard device.setVolume(uid: uid, target) else { clear(); return false }
        if let reported = device.volume(uid: uid) {                      // rule 4
            save(Pending(uid: uid, original: original, setTo: reported))
        }
        return true
    }

    enum Restore: Equatable {
        case nothingPending
        case restored
        case deviceGone      // unplugged, or unreadable: nothing of ours to put back
        case userChanged     // the level is no longer ours — theirs stands
        case setFailed
    }

    /// Put the user's level back if it is still ours to put back, and forget the
    /// record either way. The one path out for the sound finishing, a quit, and
    /// the next launch after a crash.
    @discardableResult
    func restore() -> Restore {
        guard let p = pending else { return .nothingPending }
        defer { clear() }
        guard let current = device.volume(uid: p.uid) else { return .deviceGone }   // rule 2
        guard Self.shouldRestore(current: current, weSet: p.setTo) else { return .userChanged }
        return device.setVolume(uid: p.uid, p.original) ? .restored : .setFailed
    }

    // MARK: - The persisted record

    struct Pending: Equatable {
        let uid: String
        let original: Float32
        let setTo: Float32
    }

    var pending: Pending? {
        guard let d = defaults.dictionary(forKey: Self.pendingKey),
              let uid = d["uid"] as? String,
              let original = (d["original"] as? NSNumber)?.floatValue,
              let setTo = (d["setTo"] as? NSNumber)?.floatValue else { return nil }
        return Pending(uid: uid, original: original, setTo: setTo)
    }

    private func save(_ p: Pending) {
        defaults.set(["uid": p.uid, "original": p.original, "setTo": p.setTo],
                     forKey: Self.pendingKey)
    }

    private func clear() {
        defaults.removeObject(forKey: Self.pendingKey)
    }
}
