// Licensing backend — kept provider-agnostic so the store can be swapped without
// touching the app's entitlement logic (LicenseController). Freemius is the live
// provider; a Mock provider backs local UI testing.
//
// Freemius's client license API authenticates by the license KEY itself (+ the
// public product id) — the app sends no pk_/sk_ key at all. Contract confirmed against
// freemius.com/help/documentation/saas/integrating-license-key-activation/.

import Foundation

/// A license activated on THIS device. Codable so we can cache it and keep working
/// offline after one successful online activation/validation (light enforcement).
/// Mirrors Freemius's "store the uuid, install_id, install_api_token, license_key".
struct LicenseRecord: Codable, Equatable {
    var key: String            // the license key the user entered
    var uid: String            // this device's stable 32-char Freemius id
    var installId: String      // Freemius "install" id = this device's activation
    var installToken: String   // per-install bearer token (to update the Install)
    var planName: String?
    var expiresAt: Date?       // nil = lifetime / one-off (our plan)
    var lastValidated: Date    // last time we confirmed it online
}

enum LicenseError: Error {
    case invalidKey             // unknown / wrong-product / cancelled key
    case noActivationsLeft      // all seats (3) already used
    case expired                // license lapsed
    case offline                // couldn't reach the server
    case server(String)         // server said no, with a reason

    var message: String {
        switch self {
        case .invalidKey:        return "That license key wasn\u{2019}t recognized. Check for typos and try again."
        case .noActivationsLeft: return "This license is already active on the maximum number of Macs. Deactivate it on another Mac first."
        case .expired:           return "This license has expired."
        case .offline:           return "Couldn\u{2019}t reach the licensing server. Check your internet connection and try again."
        case .server(let m):     return m
        }
    }
}

/// The store backend. Swap the implementation to migrate providers; the rest of the
/// app only ever talks to this protocol. Completions may arrive on any queue —
/// LicenseController hops back to main.
protocol LicenseProvider {
    var displayName: String { get }
    var buyURL: URL { get }

    func activate(key: String, deviceUID: String, deviceName: String,
                  completion: @escaping (Result<LicenseRecord, LicenseError>) -> Void)
    func validate(_ record: LicenseRecord,
                  completion: @escaping (Result<LicenseRecord, LicenseError>) -> Void)
    func deactivate(_ record: LicenseRecord,
                    completion: @escaping (Result<Void, LicenseError>) -> Void)
}

// MARK: - Freemius (live provider)

/// Talks to Freemius's REST license API. Only the public product id is embedded; the
/// license key is the credential. Happy path follows the official docs; the exact
/// error CODES are best-effort and get confirmed on the sandbox live-test.
final class FreemiusProvider: LicenseProvider {
    let productID: String
    let checkoutURL: URL
    private let base = "https://api.freemius.com/v1"
    private let session = URLSession(configuration: .ephemeral)

    init(productID: String, checkoutURL: URL) {
        self.productID = productID
        self.checkoutURL = checkoutURL
    }

    var displayName: String { "Freemius" }
    var buyURL: URL { checkoutURL }

    // POST /v1/products/{pid}/licenses/activate.json  { uid, license_key, title }
    func activate(key: String, deviceUID: String, deviceName: String,
                  completion: @escaping (Result<LicenseRecord, LicenseError>) -> Void) {
        guard let url = URL(string: "\(base)/products/\(productID)/licenses/activate.json") else {
            completion(.failure(.server("Bad URL."))); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "uid": deviceUID, "license_key": key, "title": deviceName,
        ])
        send(req) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let json):
                guard let installId = json["install_id"].map({ "\($0)" }),
                      let token = json["install_api_token"] as? String else {
                    completion(.failure(.server("Unexpected activation response."))); return
                }
                completion(.success(LicenseRecord(
                    key: key, uid: deviceUID, installId: installId, installToken: token,
                    planName: json["license_plan_name"] as? String,
                    expiresAt: Self.parseExpiration(json["expiration"]),
                    lastValidated: Date())))
            }
        }
    }

    // GET /v1/products/{pid}/installs/{install_id}/license.json?uid=&license_key=
    func validate(_ record: LicenseRecord,
                  completion: @escaping (Result<LicenseRecord, LicenseError>) -> Void) {
        let uid = Self.encode(record.uid), key = Self.encode(record.key)
        guard let url = URL(string: "\(base)/products/\(productID)/installs/\(record.installId)/license.json?uid=\(uid)&license_key=\(key)") else {
            completion(.failure(.server("Bad URL."))); return
        }
        send(URLRequest(url: url)) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let json):
                if (json["is_cancelled"] as? Bool) == true {   // revoked / refunded
                    completion(.failure(.invalidKey)); return
                }
                var fresh = record
                fresh.expiresAt = Self.parseExpiration(json["expiration"])
                fresh.lastValidated = Date()
                completion(.success(fresh))
            }
        }
    }

    // POST /v1/products/{pid}/licenses/deactivate.json  { uid, install_id, license_key }
    func deactivate(_ record: LicenseRecord,
                    completion: @escaping (Result<Void, LicenseError>) -> Void) {
        guard let url = URL(string: "\(base)/products/\(productID)/licenses/deactivate.json") else {
            completion(.failure(.server("Bad URL."))); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "uid": record.uid, "install_id": record.installId, "license_key": record.key,
        ])
        send(req) { completion($0.map { _ in () }) }
    }

    // Freemius sends expiration as "Y-m-d H:i:s" (UTC), or null for lifetime licenses.
    private static func parseExpiration(_ value: Any?) -> Date? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }

    private static func encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private func send(_ req: URLRequest,
                      _ done: @escaping (Result<[String: Any], LicenseError>) -> Void) {
        session.dataTask(with: req) { data, _, err in
            if err != nil { done(.failure(.offline)); return }
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                done(.failure(.server("Unexpected response from the licensing server."))); return
            }
            if let error = obj["error"] as? [String: Any] { done(.failure(Self.mapError(error))); return }
            done(.success(obj))
        }.resume()
    }

    // Best-effort mapping of Freemius error codes → our cases. Confirmed/refined on the
    // sandbox live-test (bad key, exhausted activations).
    private static func mapError(_ error: [String: Any]) -> LicenseError {
        let code = (error["code"] as? String) ?? ""
        let msg  = (error["message"] as? String) ?? "Licensing error."
        if code.contains("activation") || code.contains("exceeded") || code.contains("quota") {
            return .noActivationsLeft
        }
        if code.contains("license") || code.contains("not_found") || code.contains("empty") || code.contains("invalid") {
            return .invalidKey
        }
        return .server(msg)
    }
}

// MARK: - Mock (local UI testing only)

/// Used only when LIDAWAKE_MOCK_LICENSE=1 — exercises the activation UI with no live
/// product. Accepts "LIDA-TEST" as a valid key; anything else fails.
final class MockProvider: LicenseProvider {
    var displayName: String { "Mock" }
    var buyURL: URL { URL(string: "https://zayco.it/lidawake")! }

    func activate(key: String, deviceUID: String, deviceName: String,
                  completion: @escaping (Result<LicenseRecord, LicenseError>) -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
            if key.uppercased() == "LIDA-TEST" {
                completion(.success(LicenseRecord(
                    key: key, uid: deviceUID, installId: "mock-install", installToken: "mock-token",
                    planName: "Pro", expiresAt: nil, lastValidated: Date())))
            } else {
                completion(.failure(.invalidKey))
            }
        }
    }

    func validate(_ record: LicenseRecord,
                  completion: @escaping (Result<LicenseRecord, LicenseError>) -> Void) {
        var r = record; r.lastValidated = Date(); completion(.success(r))
    }

    func deactivate(_ record: LicenseRecord,
                    completion: @escaping (Result<Void, LicenseError>) -> Void) {
        completion(.success(()))
    }
}

// MARK: - Config

enum LicenseConfig {
    // Public Freemius identifiers (safe to embed). Product 33405, plan 54847
    // ("Pro", 3-activation license). The REST license API authenticates by the license
    // key itself + product id — no public/secret key is ever sent from the app.
    static let productID = "33405"
    static let checkoutURL = URL(string: "https://checkout.freemius.com/app/33405/plan/54847/licenses/3/")!

    static func makeProvider() -> LicenseProvider {
        if ProcessInfo.processInfo.environment["LIDAWAKE_MOCK_LICENSE"] == "1" {
            return MockProvider()
        }
        return FreemiusProvider(productID: productID, checkoutURL: checkoutURL)
    }
}
