// Entitlement brain — decides whether the app's core "keep awake" is unlocked.
// Three ways to be entitled: a valid paid license, grandfathered (an existing free
// 1.0.x user), or an active 14-day trial. Everything here works offline; only
// activating/validating a key touches the network. Light enforcement: we trust the
// local cache and don't fight a determined user.

import AppKit
import IOKit

enum Entitlement: Equatable {
    case licensed
    case grandfathered
    case trial(daysLeft: Int)
    case expired

    /// Is the core feature unlocked?
    var unlocked: Bool {
        switch self {
        case .licensed, .grandfathered, .trial: return true
        case .expired: return false
        }
    }
}

final class LicenseController {
    static let trialLength = 14   // days

    private let provider: LicenseProvider
    private let defaults: UserDefaults

    private enum K {
        static let grandfathered = "lic.grandfathered"
        static let trialStart    = "lic.trialStart"
        static let record        = "lic.record"
        static let deviceUID     = "lic.deviceUID"
        static let evaluated     = "lic.evaluated"
    }

    init(provider: LicenseProvider, defaults: UserDefaults = .standard) {
        self.provider = provider
        self.defaults = defaults
    }

    // MARK: First-run decision (grandfather vs. trial), made once and sticky.

    /// On the first launch of the licensing build, decide whether this is an existing
    /// 1.0.x user (→ grandfathered, free forever) or brand new (→ start the 14-day
    /// trial). `usedBefore` is any pre-license signal (e.g. seenWelcome, or the helper
    /// already approved). Safe to call every launch; only acts the first time.
    func bootstrap(usedBefore: Bool) {
        guard !defaults.bool(forKey: K.evaluated) else { return }
        if usedBefore {
            defaults.set(true, forKey: K.grandfathered)
        } else {
            defaults.set(Date(), forKey: K.trialStart)
        }
        defaults.set(true, forKey: K.evaluated)
    }

    // MARK: Status

    var status: Entitlement {
        if defaults.bool(forKey: K.grandfathered) { return .grandfathered }
        if let rec = record, isRecordValid(rec) { return .licensed }
        if let start = defaults.object(forKey: K.trialStart) as? Date {
            let days = trialDaysLeft(from: start)
            return days > 0 ? .trial(daysLeft: days) : .expired
        }
        return .expired   // shouldn't happen — bootstrap always sets one of the above
    }

    var isEntitled: Bool { status.unlocked }

    private func trialDaysLeft(from start: Date) -> Int {
        let length = Self.trialLengthOverride ?? Self.trialLength
        let end = Calendar.current.date(byAdding: .day, value: length, to: start) ?? start
        let secs = end.timeIntervalSinceNow
        return secs <= 0 ? 0 : Int(ceil(secs / 86_400))
    }

    // Test hook: LIDAWAKE_TRIAL_DAYS overrides the trial length (e.g. 0 = expired now,
    // so we can exercise the paywall without waiting two weeks).
    private static var trialLengthOverride: Int? {
        ProcessInfo.processInfo.environment["LIDAWAKE_TRIAL_DAYS"].flatMap { Int($0) }
    }

    // MARK: Cached license record

    private var record: LicenseRecord? {
        get {
            guard let data = defaults.data(forKey: K.record) else { return nil }
            return try? JSONDecoder().decode(LicenseRecord.self, from: data)
        }
        set {
            if let v = newValue, let data = try? JSONEncoder().encode(v) {
                defaults.set(data, forKey: K.record)
            } else {
                defaults.removeObject(forKey: K.record)
            }
        }
    }

    private func isRecordValid(_ rec: LicenseRecord) -> Bool {
        if let exp = rec.expiresAt, exp < Date() { return false }
        return true
    }

    // MARK: Actions

    var buyURL: URL { provider.buyURL }
    func openBuyPage() { NSWorkspace.shared.open(provider.buyURL) }

    /// Activate a key the user typed. On success caches the record → status flips to
    /// `.licensed`. Completion is delivered on the main queue.
    func activate(key: String, completion: @escaping (Result<Void, LicenseError>) -> Void) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { completion(.failure(.invalidKey)); return }
        provider.activate(key: key, deviceUID: deviceUID,
                          deviceName: Host.current().localizedName ?? "Mac") { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let rec): self?.record = rec; completion(.success(()))
                case .failure(let e):   completion(.failure(e))
                }
            }
        }
    }

    /// Occasionally re-confirm a cached license when online. Network failures are
    /// ignored (we stay entitled offline). A hard "invalid" (revoked / refunded)
    /// clears the cache so the app falls back to trial/expired.
    func revalidateIfNeeded() {
        guard let rec = record, Date().timeIntervalSince(rec.lastValidated) > 7 * 86_400 else { return }
        provider.validate(rec) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let fresh):                       self?.record = fresh
                case .failure(.invalidKey), .failure(.expired): self?.record = nil
                case .failure:                                  break   // offline — keep trusting cache
                }
            }
        }
    }

    /// Stable identifier for THIS Mac, used as the Freemius activation id. We use the
    /// hardware platform UUID so a reinstall / wipe / prefs reset reuses the SAME
    /// activation slot (one physical Mac = one seat) instead of burning a new one.
    /// Falls back to a stored random UUID on the rare chance the hardware UUID is
    /// unavailable. IOPlatformUUID is a per-machine id, NOT the serial number, and it
    /// never leaves the activation call.
    private var deviceUID: String {
        let raw: String
        if let hw = Self.hardwareUUID() {
            raw = hw
        } else if let id = defaults.string(forKey: K.deviceUID) {
            raw = id
        } else {
            let id = UUID().uuidString
            defaults.set(id, forKey: K.deviceUID)
            raw = id
        }
        // Freemius wants a stable 32-char id (a UUID with the dashes removed).
        return raw.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private static func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let prop = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString,
                                                   kCFAllocatorDefault, 0)
        return prop?.takeRetainedValue() as? String
    }
}
