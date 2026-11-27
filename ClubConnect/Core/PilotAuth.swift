import AuthenticationServices
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
        }
    }

    var hasSession: Bool { session != nil }

    static func nonce() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ raw: String) -> String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func signIn(credential: ASAuthorizationAppleIDCredential, rawNonce: String) async throws {
        guard !rawNonce.isEmpty, let data = credential.identityToken,
              let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            throw ClubFailure("Apple didn’t return a sign-in credential. Please try again.")
        }
        let attempt = beginSessionChange()
        let reply = try await request(path: "token", query: ["grant_type": "id_token"],
                                      body: ["provider": "apple", "id_token": token, "nonce": rawNonce])
        try persist(reply, for: attempt)
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
                return try persist(reply, for: attempt).accessToken
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
    private func persist(_ reply: Data, for attempt: UUID) throws -> Session {
        guard generation == attempt else { throw CancellationError() }
        let response = try JSONDecoder().decode(TokenResponse.self, from: reply)
        guard !response.access_token.isEmpty, !response.refresh_token.isEmpty, response.expires_in > 0 else {
            throw ClubFailure("The sign-in service returned an incomplete session. Try again.")
        }
        let updated = Session(accessToken: response.access_token, refreshToken: response.refresh_token,
                              expiresAt: Date().addingTimeInterval(response.expires_in))
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
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: TimeInterval
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
            if status == 429 { return "Too many sign-in attempts. Try again in a moment." }
            if status >= 500 { return "The sign-in service is temporarily unavailable. Try again shortly." }
            return "Club Connect couldn’t verify your sign-in. Try signing in again."
        }
    }

    private enum Keychain {
        static var query: [String: Any] {
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "ClubConnect") + ".session",
             kSecAttrAccount as String: PilotConfiguration.url.host() ?? "pilot"]
        }

        static func read() throws -> Data? {
            var lookup = query
            lookup[kSecReturnData as String] = true
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(lookup as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            try check(status)
            return result as? Data
        }

        static func save(_ bytes: Data) throws {
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

        static func remove() throws {
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecItemNotFound { try check(status) }
        }

        static func check(_ status: OSStatus) throws {
            guard status == errSecSuccess else { throw ClubFailure("Unlock your device to access the saved sign-in.") }
        }
    }
}
