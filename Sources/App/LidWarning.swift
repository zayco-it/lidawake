// The audible warning: lidawake is on, the lid is shut, and the Mac is on
// battery — the state that leaves a laptop awake in a bag. Two ways in: the lid
// closing while on battery, and the power going to battery while the lid is
// already shut (a laptop pulled off its dock), which used to get no warning at
// all. On AC it stays quiet: a shut lid there is usually deliberate.
//
// NOT covered: unplugging a monitor that does not charge, on battery, lid shut.
// There is no power change, and the display list is frozen in that state. The
// one registry reading that does see the monitor leave (an external framebuffer's
// DisplayAttributes) also drops when the monitor is switched off at its button or
// moved to another input — measured 2026-09-27 — so a trigger on it would sound
// for those too. It was not built.
//
// THIS IS THE FIRST SOUND LIDAWAKE HAS EVER MADE. Everything else it says is
// silent, and the morning summary stays that way (Notifier.deliver): that
// reports hours that already happened, while this goes off at the one moment the
// user can still do something about it.
//
// The app plays the sound itself instead of giving the notification one. A
// notification sound plays at the ALERT volume, a separate slider no public API
// sets, so WarningVolume would be turning the wrong knob; it is silenced by Focus;
// and it has no "finished" callback to restore on. NSSound plays through the
// output device at that device's volume, stays silent on a muted device with no
// code here, and says when it is done. That the speakers keep playing with the
// lid shut was measured in E0e (research log, 2026-09-06): the built-in speakers
// stayed the output across a lid close. That run had an external display
// attached; the no-display case is the TESTING.md §11 lid test.
//
// The notification is still posted, silently, so the warning is waiting in
// Notification Center when the user comes back.
//
// Only people who turned on "Keep going on battery power" can ever hear this:
// with it off, going to battery turns lidawake off instead.

import AppKit
import AudioToolbox
import CoreAudio

final class LidWarning: NSObject, NSSoundDelegate {

    /// Chosen by measurement across the fourteen sounds in /System/Library/Sounds,
    /// 2026-09-27: the loudest by RMS, about 4 dB above the next, and pitched in
    /// the middle of the range (~540 Hz) instead of the thin top end most alert
    /// sounds sit in. It has to carry through a closed lid.
    static let soundName = "Hero"

    /// Fixed, so a second warning replaces the first in Notification Center
    /// instead of stacking beside it.
    private static let notificationID = "lidawake.lid-closed-on-battery"

    /// Test hook, same pattern as LIDAWAKE_IDLE_SECONDS: hold the raised volume
    /// this many seconds instead of until the sound ends, so the crash, device
    /// switch and changed-volume cases in TESTING.md fit in a window a person can
    /// act in. A one-second sound is not one. Ignored unless set, so a shipped
    /// build restores the moment the sound ends.
    private static let testHold: TimeInterval? = {
        guard let raw = ProcessInfo.processInfo.environment["LIDAWAKE_WARNING_HOLD_SECONDS"],
              let v = TimeInterval(raw), v > 0 else { return nil }
        return v
    }()

    private let notifier: Notifier
    private let volume = WarningVolume(device: CoreAudioVolume(), defaults: .standard)
    /// The sound while it plays, and the in-flight guard: from the raise until the
    /// restore, a second trigger — a lid bounced shut twice — neither raises nor
    /// plays again. WarningVolume refuses an outstanding raise as well; this also
    /// stops the sounds stacking.
    private var sounding: NSSound?
    private var fallback: DispatchWorkItem?

    /// Called with the sound's length just before it plays. Quiet mode listens
    /// for sound, and this one is ours: without the notice it reads the warning
    /// as "sound playing" and says so in the note it leaves (IdleWatcher).
    var onSound: ((TimeInterval) -> Void)?

    init(notifier: Notifier) {
        self.notifier = notifier
    }

    /// `audible` is false with an external display attached: a lid shut on a desk
    /// with a monitor is someone still working, and gets the notification alone.
    func warn(audible: Bool) {
        notifier.postNow(title: "lidawake is still on",
                         body: "Your Mac is on battery with the lid closed. lidawake will keep it awake until the battery reaches \(Settings.batteryFloorPercent)%.",
                         identifier: Self.notificationID)
        guard audible else { return }
        guard sounding == nil else {
            NSLog("[lidawake] lid warning already sounding — not stacking another")
            return
        }
        guard let sound = NSSound(named: Self.soundName) else {
            NSLog("[lidawake] lid warning: system sound \(Self.soundName) is missing — notification only")
            return
        }
        // Play on the device whose volume was just checked, named by UID, so a
        // default that changes in between cannot send the sound somewhere else.
        // Always assigned: NSSound(named:) hands back a cached instance, and a
        // UID left over from a previous warning must not survive into this one.
        let uid = volume.device.defaultUID()
        if let uid, volume.raiseIfLow(uid: uid) {
            // Format arguments, not interpolation: NSLog's first argument IS the
            // format, and a literal "%" in it reads a vararg that was never passed.
            NSLog("[lidawake] lid warning: volume was below %ld%% — raised to it for the warning",
                  Int((WarningVolume.minimum * 100).rounded()))
        }
        sound.playbackDeviceIdentifier = uid
        sound.delegate = self
        sounding = sound
        // Normally the delegate ends the warning. The timer is for when it never
        // does — the device unplugged mid-sound — so the volume is not left up.
        let work = DispatchWorkItem { [weak self] in self?.finish() }
        fallback = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (Self.testHold ?? sound.duration + 3),
                                      execute: work)
        onSound?(Self.testHold ?? sound.duration)
        if !sound.play() {
            NSLog("[lidawake] lid warning: the sound would not play")
            finish()
        }
    }

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        guard Self.testHold == nil else { return }   // the hook holds until its timer
        finish()
    }

    /// End the warning and put the volume back. Idempotent, and synchronous, so it
    /// is also the quit path. Does nothing unless THIS process has a warning in
    /// progress: a duplicate copy quitting at launch must not restore — and clear
    /// the record of — a raise made by the copy that is still running.
    func finish() {
        guard let s = sounding else { return }
        fallback?.cancel()
        fallback = nil
        s.delegate = nil
        s.stop()
        sounding = nil
        let result = volume.restore()
        if result != .nothingPending { NSLog("[lidawake] lid warning volume: \(result)") }
    }

    /// A warning that was sounding when lidawake last died left the volume raised.
    /// Called once at launch, before anything could start a new one.
    static func repairAfterCrash() {
        let v = WarningVolume(device: CoreAudioVolume(), defaults: .standard)
        guard v.pending != nil else { return }
        NSLog("[lidawake] a lid warning was cut off last run — volume: \(v.restore())")
    }
}

/// The real output device, through CoreAudio. Reading and setting the volume need
/// no special rights — checked from a Standard account.
struct CoreAudioVolume: VolumeControl {

    func defaultUID() -> String? {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice,
                                   kAudioObjectPropertyScopeGlobal)
        var dev = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                         0, nil, &size, &dev) == noErr,
              dev != kAudioObjectUnknown else { return nil }
        address = Self.address(kAudioDevicePropertyDeviceUID, kAudioObjectPropertyScopeGlobal)
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &address, 0, nil, &size, &uid) == noErr,
              let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    func volume(uid: String) -> Float32? {
        guard let dev = device(uid) else { return nil }
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        guard AudioObjectHasProperty(dev, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(dev, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    /// Unreadable counts as not muted. The cost of being wrong is a raise on a
    /// muted device, which is inaudible and put back afterwards.
    func isMuted(uid: String) -> Bool {
        guard let dev = device(uid) else { return false }
        var address = Self.address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(dev, &address) else { return false }
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &address, 0, nil, &size, &muted) == noErr && muted != 0
    }

    func canSetVolume(uid: String) -> Bool {
        guard let dev = device(uid) else { return false }
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var settable = DarwinBoolean(false)
        return AudioObjectHasProperty(dev, &address)
            && AudioObjectIsPropertySettable(dev, &address, &settable) == noErr
            && settable.boolValue
    }

    func setVolume(uid: String, _ value: Float32) -> Bool {
        guard let dev = device(uid) else { return false }
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var v = value
        return AudioObjectSetPropertyData(dev, &address, 0, nil,
                                          UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }

    /// nil once the device is gone — unplugged, or a Bluetooth device that dropped.
    private func device(_ uid: String) -> AudioObjectID? {
        var address = Self.address(kAudioHardwarePropertyTranslateUIDToDevice,
                                   kAudioObjectPropertyScopeGlobal)
        var cfUID = uid as CFString
        var dev = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &cfUID) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<CFString>.size), $0, &size, &dev)
        }
        return status == noErr && dev != kAudioObjectUnknown ? dev : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
