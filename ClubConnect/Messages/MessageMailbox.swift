import CryptoKit
import Foundation

struct DirectMessage: Codable, Identifiable, Hashable {
    let id: String
    let sender: String
    let recipient: String
    let body: String
    let sentAt: Date
    var readAt: Date?
}

struct InboxConversation: Codable, Identifiable {
    let peer: String
    let latest: DirectMessage
    let unread: Int
    var id: String { peer }
}

// Persist before sending. The caller reuses the message UUID until Postgres confirms it,
// including when the app exits after the write but before receiving the HTTP response.
@MainActor
struct MessageMailbox {
    let store: ClubStore
    let club: String
    let me: String
    let sample: Bool
    private let location: URL

    private struct Stored: Codable {
        var outgoing: [DirectMessage] = []
        var sampleHistory: [DirectMessage] = []
    }

    init(_ store: ClubStore) {
        self.store = store
        club = store.club.id
        me = store.me.id
        sample = store.isPreview
        let folder = Self.accountLocation(sample ? store.sampleOwnerID : me, sample: sample)
        location = folder.appending(path: Self.key(club) + ".json")
    }

    private func checkScope() throws {
        try Task.checkCancellation()
        guard club == store.club.id, me == store.me.id, sample == store.isPreview, store.phase == .community else {
            throw CancellationError()
        }
    }

    private func load() throws -> Stored {
        do {
            return try JSONDecoder().decode(Stored.self, from: Data(contentsOf: location))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            var empty = Stored()
            if sample, let peer = store.members.first(where: { $0.id == "demo-yasmin" && $0.id != me }) {
                empty.sampleHistory = [DirectMessage(id: "e624c0f0-c8e3-4ab3-80ee-c27dace7f066", sender: peer.id, recipient: me,
                    body: "Welcome! If you’re curious about working in tech after graduation, I’d be happy to chat.",
                    sentAt: Date(timeIntervalSince1970: 1_795_737_600), readAt: nil)]
            }
            return empty
        }
    }

    private func save(_ state: Stored) throws {
        let directory = location.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var settings = URLResourceValues()
        settings.isExcludedFromBackup = true
        try folder.setResourceValues(settings)
        try JSONEncoder().encode(state).write(to: location, options: [.atomic, .completeFileProtection])
    }

    private static func key(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func accountLocation(_ id: String, sample: Bool) -> URL {
        URL.applicationSupportDirectory.appending(path: "ClubConnectMessages")
            .appending(path: key((sample ? "sample/" : "live/") + id))
    }

    #if DEBUG
    static func resetSampleForTesting(_ id: String) {
        try? FileManager.default.removeItem(at: accountLocation(id, sample: true))
    }
    #endif

    static func clearAccount(_ id: String) {
        try? FileManager.default.removeItem(at: accountLocation(id, sample: false))
        try? FileManager.default.removeItem(at: accountLocation(id, sample: true))
    }

    private func call<T: Decodable>(_ name: String, _ fields: [String: String], as: T.Type) async throws -> T {
        try checkScope()
        var body = fields
        body["c"] = club
        let data = try await store.rpc(name, body: JSONEncoder().encode(body))
        try checkScope()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let raw = try d.singleValueContainer().decode(String.self)
            for fractional in [true, false] {
                if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: fractional).parse(raw) { return date }
            }
            throw ClubFailure("A message timestamp could not be read.")
        }
        return try decoder.decode(T.self, from: data)
    }

    func pending(_ peer: String? = nil) throws -> [DirectMessage] {
        try load().outgoing.filter { peer == nil || $0.recipient == peer }
    }

    func enqueue(_ text: String, to peer: String) throws {
        try checkScope()
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.unicodeScalars.count <= 4000 else { throw ClubFailure("Enter a message of up to 4,000 characters.") }
        guard peer != me, store.members.contains(where: { $0.id == peer }) else { throw ClubFailure("Choose another member of this club.") }
        let message = DirectMessage(id: UUID().uuidString.lowercased(), sender: me, recipient: peer, body: body, sentAt: .now)
        var state = try load()
        if sample { state.sampleHistory.append(message) }
        else { state.outgoing.append(message) }
        try save(state)
    }

    func removeFromOutbox(_ id: String) throws {
        try checkScope()
        var state = try load()
        state.outgoing.removeAll { $0.id == id }
        try save(state)
    }

    func deliverPending(to peer: String? = nil) async throws {
        var failedPeers = Set<String>()
        var firstError: Error?
        for queued in try pending(peer) where !failedPeers.contains(queued.recipient) {
            do {
                let _: DirectMessage = try await call("send_message",
                    ["peer": queued.recipient, "message_id": queued.id, "content": queued.body], as: DirectMessage.self)
                try removeFromOutbox(queued.id)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Preserve delivery order within a thread without blocking unrelated recipients.
                failedPeers.insert(queued.recipient)
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    func inbox(before cursor: String? = nil) async throws -> [InboxConversation] {
        try checkScope()
        if sample {
            let messages = try load().sampleHistory.sorted { $0.sentAt > $1.sentAt }
            let grouped = Dictionary(grouping: messages) { $0.sender == me ? $0.recipient : $0.sender }
            let rows = grouped.compactMap { peer, entries -> InboxConversation? in
                guard let newest = entries.first else { return nil }
                return InboxConversation(peer: peer, latest: newest, unread: entries.filter { $0.recipient == me && $0.readAt == nil }.count)
            }.sorted { $0.latest.sentAt > $1.latest.sentAt }
            let offset = cursor.flatMap { id in rows.firstIndex { $0.latest.id == id } }.map { $0 + 1 } ?? 0
            return Array(rows.dropFirst(offset).prefix(40))
        }
        return try await call("message_inbox", cursor.map { ["cursor_id": $0] } ?? [:], as: [InboxConversation].self)
    }

    func history(_ peer: String, cursor: String? = nil) async throws -> [DirectMessage] {
        try checkScope()
        if sample {
            let messages = try load().sampleHistory.filter { $0.sender == peer || $0.recipient == peer }.sorted { $0.sentAt < $1.sentAt }
            let end = cursor.flatMap { id in messages.firstIndex { $0.id == id } } ?? messages.endIndex
            return Array(messages[..<end].suffix(40))
        }
        var params = ["peer": peer]
        params["cursor_id"] = cursor
        return try await call("message_history", params, as: [DirectMessage].self)
    }

    func markRead(_ peer: String, through message: DirectMessage) async throws {
        try checkScope()
        if sample {
            var state = try load()
            for i in state.sampleHistory.indices where state.sampleHistory[i].sender == peer && state.sampleHistory[i].readAt == nil && state.sampleHistory[i].sentAt <= message.sentAt {
                state.sampleHistory[i].readAt = .now
            }
            try save(state)
        } else {
            _ = try await store.rpc("read_messages", body: JSONEncoder().encode(["c": club, "peer": peer, "through_id": message.id]))
        }
    }
}
