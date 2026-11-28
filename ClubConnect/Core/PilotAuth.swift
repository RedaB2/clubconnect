import CryptoKit
import Foundation
import Security

@MainActor
final class PilotAuth {
    private var session: Session?
    private var refreshTask: Task<String, Error>?
    private var generation = UUID()

    init() {
        if let bytes = try? Keychain.read() {
            session = try? JSONDecoder().decode(Session.self, from: bytes)
            if session == nil { try? Keychain.remove() }
        }
    }

    var hasSession: Bool { session != nil }

    var isAlumniAccount: Bool {
        session.map { !$0.email.hasSuffix("@usc.edu") } ?? false
    }

    static func normalizedEmail(_ raw: String) -> String? {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Match the single-mailbox syntax accepted by the signup service.
        let pattern = #"^[-a-z0-9_+']+(\.[-a-z0-9_+']+)*@[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?(\.[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?)+$"#
        guard email.utf8.count <= 254,
              let at = email.firstIndex(of: "@"), email[..<at].utf8.count <= 64,
              email.range(of: pattern, options: .regularExpression) == email.startIndex..<email.endIndex else { return nil }
        return email
    }

    private static let redirect = "clubconnect://auth/callback"

    func requestCode(email raw: String) async throws {
        guard let email = Self.normalizedEmail(raw) else { throw ClubFailure("Enter a valid email address.") }
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        let verifier = bytes.map { String(format: "%02x", $0) }.joined()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        // Save before sending so a verification link can resume after an app restart.
        let pending = PendingSignIn(email: email, verifier: verifier, createdAt: .now)
        let previous = try Keychain.read(suffix: ".pkce")
        let pendingData = try JSONEncoder().encode(pending)
        try Keychain.save(pendingData, suffix: ".pkce")
        do {
            _ = try await request(path: "otp", query: ["redirect_to": Self.redirect], body: [
                "email": email, "code_challenge": challenge, "code_challenge_method": "s256"
            ])
        } catch let response as AuthResponseError where (400..<500).contains(response.status) {
            // A refused resend (e.g. rate-limit) must not invalidate the previous email on this device.
            if (try? Keychain.read(suffix: ".pkce")) == pendingData {
                if let previous { try Keychain.save(previous, suffix: ".pkce") }
                else { try Keychain.remove(suffix: ".pkce") }
            }
            throw response
        }
    }

    func verifyCode(email raw: String, code: String) async throws {
        guard let email = Self.normalizedEmail(raw), code.count == 6,
              code.utf8.allSatisfy({ (48...57).contains($0) }) else { throw ClubFailure("Enter the six-digit code from your sign-in email.") }
        let attempt = beginSessionChange()
        let reply = try await request(path: "verify", query: [:], body: ["type": "email", "email": email, "token": code])
        try persist(reply, for: attempt, expectedEmail: email)
        try? Keychain.remove(suffix: ".pkce")
    }

    func verifyEmailLink(_ url: URL) async throws {
        guard url.scheme == "clubconnect", url.host == "auth", url.path == "/callback",
              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty, let bytes = try Keychain.read(suffix: ".pkce"),
              let pending = try? JSONDecoder().decode(PendingSignIn.self, from: bytes),
              Date().timeIntervalSince(pending.createdAt) < 15 * 60 else {
            throw ClubFailure("Open the latest sign-in email on the device where you requested it, or request a new email.")
        }
        let attempt = beginSessionChange()
        let reply = try await request(path: "token", query: ["grant_type": "pkce"], body: [
            "auth_code": code, "code_verifier": pending.verifier
        ])
        try persist(reply, for: attempt, expectedEmail: pending.email)
        try? Keychain.remove(suffix: ".pkce")
    }

    func accessToken() async throws -> String {
        guard let session else { throw ClubFailure("Sign in to continue.") }
        guard session.expiresAt.timeIntervalSinceNow < 60 else { return session.accessToken }
        if let refreshTask { return try await refreshTask.value }

        let attempt = generation
        let task = Task {
            defer { if generation == attempt { refreshTask = nil } }
            do {
                let reply = try await request(path: "token", query: ["grant_type": "refresh_token"],
                                              body: ["refresh_token": session.refreshToken])
                return try persist(reply, for: attempt, expectedEmail: session.email).accessToken
            } catch let failure as AuthResponseError where failure.sessionHasEnded {
                if generation == attempt {
                    try Keychain.remove()
                    self.session = nil
                }
                throw ClubFailure("Your session has ended. Sign in again to continue.")
            }
        }
        refreshTask = task
        return try await task.value
    }

    func signOut() async throws {
        // Rotating refresh tokens are single-use. Finish any pending rotation before revocation.
        let token = try? await accessToken()
        _ = beginSessionChange()
        try Keychain.remove()
        try? Keychain.remove(suffix: ".pkce")
        session = nil
        if let token {
            // Device sign-out is immediate, including offline. Revoke this session on the server when reachable.
            _ = try? await request(path: "logout", query: ["scope": "local"], bearer: token)
        }
    }

    private func beginSessionChange() -> UUID {
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        return generation
    }

    @discardableResult
    private func persist(_ reply: Data, for attempt: UUID, expectedEmail: String) throws -> Session {
        guard generation == attempt else { throw CancellationError() }
        let response = try JSONDecoder().decode(TokenResponse.self, from: reply)
        guard !response.access_token.isEmpty, !response.refresh_token.isEmpty, response.expires_in > 0 else {
            throw ClubFailure("The sign-in service returned an incomplete session. Try again.")
        }
        guard let email = Self.normalizedEmail(response.user.email), email == expectedEmail,
              response.user.email_confirmed_at != nil, response.user.app_metadata.provider == "email" else {
            throw ClubFailure("Verify the same email address you used to sign in.")
        }
        let updated = Session(accessToken: response.access_token, refreshToken: response.refresh_token,
                              expiresAt: Date().addingTimeInterval(response.expires_in), email: email)
        try Keychain.save(JSONEncoder().encode(updated))
        session = updated
        return updated
    }

    private func request(path: String, query: [String: String], body: [String: String]? = nil,
                         bearer: String? = nil) async throws -> Data {
        let url = PilotConfiguration.url.appending(path: "auth/v1").appending(path: path)
            .appending(queryItems: query.map { URLQueryItem(name: $0.key, value: $0.value) })
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(PilotConfiguration.key, forHTTPHeaderField: "apikey")
        if let bearer { request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let details = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw AuthResponseError(status: http.statusCode, code: details?.error_code ?? details?.error)
        }
        return data
    }

    private struct Session: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
        let email: String

        // Retain the existing Keychain format across the alumni rollout.
        enum CodingKeys: String, CodingKey {
            case accessToken, refreshToken, expiresAt
            case email = "uscEmail"
        }
    }

    private struct PendingSignIn: Codable {
        let email: String
        let verifier: String
        let createdAt: Date
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: TimeInterval
        let user: AuthUser

        struct AuthUser: Decodable {
            let email: String
            let email_confirmed_at: String?
            let app_metadata: Provider
            struct Provider: Decodable { let provider: String }
        }
    }

    private struct ErrorBody: Decodable {
        var error_code: String?
        var error: String?
    }

    private struct AuthResponseError: LocalizedError {
        let status: Int
        let code: String?

        var sessionHasEnded: Bool {
            ["refresh_token_not_found", "refresh_token_already_used", "session_not_found",
             "session_expired", "user_not_found", "user_banned", "invalid_grant"].contains(code ?? "")
        }

        var errorDescription: String? {
            if code == "email_address_not_authorized" { return "The pilot’s email service cannot deliver to this address yet. Contact your club organizer." }
            if code == "otp_expired" || code == "flow_state_not_found" { return "This sign-in has expired. Request a new email and use the latest one." }
            if status == 429 { return "Too many sign-in attempts. Try again in a moment." }
            if status >= 500 { return "The sign-in service is temporarily unavailable. Try again shortly." }
            return "Club Connect couldn’t verify your sign-in. Try signing in again."
        }
    }

    private enum Keychain {
        static func query(suffix: String) -> [String: Any] {
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "ClubConnect") + ".session",
             kSecAttrAccount as String: (PilotConfiguration.url.host() ?? "pilot") + suffix]
        }

        static func read(suffix: String = "") throws -> Data? {
            var lookup = query(suffix: suffix)
            lookup[kSecReturnData as String] = true
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(lookup as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            try check(status)
            return result as? Data
        }

        static func save(_ bytes: Data, suffix: String = "") throws {
            let query = query(suffix: suffix)
            let attributes: [String: Any] = [kSecValueData as String: bytes,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                let item = query.merging(attributes) { _, new in new }
                try check(SecItemAdd(item as CFDictionary, nil))
            } else {
                try check(status)
            }
        }

        static func remove(suffix: String = "") throws {
            let status = SecItemDelete(query(suffix: suffix) as CFDictionary)
            if status != errSecItemNotFound { try check(status) }
        }

        static func check(_ status: OSStatus) throws {
            guard status == errSecSuccess else { throw ClubFailure("Unlock your device to access the saved sign-in.") }
        }
    }
}
