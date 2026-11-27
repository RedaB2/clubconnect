import AuthenticationServices
import Foundation
import Observation

@MainActor @Observable
final class ClubStore {
    enum Phase { case loading, welcome, enrollment, community, reconnect }
    private(set) var phase = Phase.loading
    private(set) var isPreview = false
    private var state = CommunityState.sample()
    var notice: String?
    var showAccountDeleted = false
    var suggestedName = ""
    private let auth = PilotAuth()
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard
    private let demoKey = "clubconnect.sample.v1"
    private let modeKey = "clubconnect.mode"

    var club: Club { state.club }
    var members: [Member] { state.members }
    var me: Member { members.first { $0.id == state.myID } ?? Member(id: state.myID, name: "Member", kind: .student) }
    var isAdmin: Bool { state.isAdmin }
    var events: [ClubEvent] { state.events }
    var tickets: [EventTicket] { state.tickets }
    var walletAvailable: Bool { phase == .community && !isPreview }
    var inviteURL: URL { PilotConfiguration.invitePage.appending(queryItems: [.init(name: "club", value: club.id)]) }
    func eventURL(_ id: String) -> URL {
        let items = [URLQueryItem(name: "event", value: id)] + (isPreview ? [.init(name: "sample", value: "1")] : [])
        return inviteURL.appending(queryItems: items)
    }

    func start() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ClubConnectFreshDemo") {
            defaults.removeObject(forKey: demoKey)
            defaults.removeObject(forKey: modeKey)
            phase = .welcome
            return
        }
        #endif
        if defaults.string(forKey: modeKey) == "sample" { openSample(); return }
        guard auth.hasSession else { phase = .welcome; return }
        await loadMembership()
    }

    func openSample() {
        if let data = defaults.data(forKey: demoKey), let saved = try? JSONDecoder().decode(CommunityState.self, from: data) {
            state = saved
        } else {
            state = .sample()
        }
        defaults.set("sample", forKey: modeKey)
        isPreview = true
        phase = .community
    }

    func signIn(_ credential: ASAuthorizationAppleIDCredential, rawNonce: String) async throws {
        try await auth.signIn(credential: credential, rawNonce: rawNonce)
        if let name = credential.fullName { suggestedName = PersonNameComponentsFormatter().string(from: name) }
        isPreview = false
        defaults.removeObject(forKey: modeKey)
        await loadMembership()
    }

    func loadMembership() async {
        phase = .loading
        do {
            try await readLiveState("snapshot", body: Data("{}".utf8))
            phase = .community
        } catch let error as ServerError where error.code == "42501" {
            phase = .enrollment
        } catch {
            if auth.hasSession { phase = .reconnect } else { phase = .welcome }
            notice = error.localizedDescription
        }
    }

    func join(name: String) async throws {
        try await readLiveState("join_club", body: try encode(["display_name": name]))
        phase = .community
    }

    func refresh() async {
        guard phase == .community, !isPreview else { return }
        do {
            try await serialized {
                guard self.phase == .community, !self.isPreview else { return }
                try await self.readLiveState("snapshot", body: Data("{}".utf8))
            }
        } catch {
            if !auth.hasSession { phase = .welcome }
            notice = error.localizedDescription
        }
    }

    func leaveSession() async throws {
        try await serialized {
            if !self.isPreview { try await self.auth.signOut() }
            self.reset()
        }
    }

    private func reset() {
        defaults.removeObject(forKey: modeKey)
        isPreview = false
        state = .sample()
        suggestedName = ""
        phase = .welcome
    }

    func deleteAccount() async throws {
        try await serialized {
            guard !self.isPreview else { throw ClubFailure("Sign in to manage your account.") }
            _ = try await self.request("rest/v1/rpc/delete_account", body: Data("{}".utf8))
            try await self.auth.signOut()
            self.reset()
            self.showAccountDeleted = true
        }
    }

    func claimOrganizer(_ invitation: String) async throws {
        try await change("claim_organizer", ["invite": invitation]) { _ in throw ClubFailure("Sign in to redeem an invitation.") }
    }

    func saveProfile(_ member: Member) async throws {
        guard member.id == state.myID else { throw ClubFailure("You can edit your own profile.") }
        try await change("save_profile", ["entry": member]) { sample in
            guard let index = sample.members.firstIndex(where: { $0.id == member.id }) else { throw ClubFailure("Profile unavailable.") }
            sample.members[index] = member
        }
    }

    func saveClub(_ club: Club) async throws {
        guard isAdmin else { throw ClubFailure("Organizer access required.") }
        try await change("save_club", ["entry": club]) { $0.club = club }
    }

    func saveEvent(_ event: ClubEvent) async throws {
        guard isAdmin else { throw ClubFailure("Organizer access required.") }
        try await change("save_event", ["entry": event]) { sample in
            sample.events.removeAll { $0.id == event.id }
            sample.events.append(event)
            sample.events.sort { $0.startsAt < $1.startsAt }
        }
    }

    func setRSVP(eventID: String, attending: Bool) async throws {
        struct RSVP: Encodable { let eid: String; let attending: Bool }
        try await change("set_rsvp", RSVP(eid: eventID, attending: attending)) { sample in
            guard let event = sample.events.first(where: { $0.id == eventID }), event.endsAt > .now else { throw ClubFailure("This event is closed.") }
            if let ticket = sample.tickets.first(where: { $0.eventID == eventID }) {
                if attending { return }
                if ticket.checkedIn { throw ClubFailure("This ticket has already been checked in.") }
                sample.tickets.removeAll { $0.id == ticket.id }
            } else if attending {
                let id = UUID().uuidString
                sample.tickets.append(EventTicket(id: id, eventID: eventID, code: String(id.prefix(8)), checkedIn: false))
            }
        }
    }

    func checkIn(eventID: String, code: String) async throws -> String {
        guard isAdmin else { throw ClubFailure("Organizer access required.") }
        return try await serialized {
            if self.isPreview {
                guard let i = self.state.tickets.firstIndex(where: { $0.eventID == eventID && $0.code == code.uppercased() }) else {
                    throw ClubFailure("No matching ticket for this event.")
                }
                guard !self.state.tickets[i].checkedIn else { throw ClubFailure("This ticket has already been checked in.") }
                var sample = self.state
                sample.tickets[i].checkedIn = true
                try self.persist(sample)
                return self.me.name
            }
            let data = try await self.request("rest/v1/rpc/check_in", body: try self.encode(["eid": eventID, "ticket_code": code]))
            let name = try JSONDecoder().decode(String.self, from: data)
            // A successful check-in is final even if the follow-up refresh is offline.
            if let index = self.state.tickets.firstIndex(where: { $0.eventID == eventID && $0.code == code.uppercased() }) {
                self.state.tickets[index].checkedIn = true
            }
            return name
        }
    }

    func walletPass(eventID: String) async throws -> Data {
        guard walletAvailable else { throw ClubFailure("Wallet passes are available for live events.") }
        return try await request("functions/v1/event-pass", body: try encode(["eventID": eventID]))
    }

    private func serialized<T>(_ work: @escaping @MainActor () async throws -> T) async throws -> T {
        let earlier = pending
        let task = Task { @MainActor in
            await earlier?.value
            return try await work()
        }
        pending = Task { _ = await task.result }
        return try await task.value
    }

    private func change<Body: Encodable>(_ endpoint: String, _ body: Body,
                                          sampleChange: @escaping (inout CommunityState) throws -> Void) async throws {
        try await serialized {
            guard self.phase == .community else { throw ClubFailure("Open your club to continue.") }
            if self.isPreview {
                var sample = self.state
                try sampleChange(&sample)
                try self.persist(sample)
            } else {
                try await self.readLiveState(endpoint, body: try self.encode(body))
            }
        }
    }

    private func persist(_ sample: CommunityState) throws {
        defaults.set(try JSONEncoder().encode(sample), forKey: demoKey)
        state = sample
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func readLiveState(_ endpoint: String, body: Data) async throws {
        let data = try await request("rest/v1/rpc/" + endpoint, body: body)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            for fractional in [true, false] {
                if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: fractional).parse(raw) { return date }
            }
            throw ClubFailure("The event date could not be read.")
        }
        let fresh = try decoder.decode(CommunityState.self, from: data)
        guard fresh.members.contains(where: { $0.id == fresh.myID }) else { throw ClubFailure("Your membership could not be loaded.") }
        state = fresh
    }

    private func request(_ path: String, body: Data) async throws -> Data {
        let token = try await auth.accessToken()
        var request = URLRequest(url: PilotConfiguration.url.appending(path: path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(PilotConfiguration.key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            if let problem = try? JSONDecoder().decode(ServerError.self, from: data) { throw problem }
            throw ClubFailure("Club Connect couldn’t complete this request. Please try again.")
        }
        return data
    }

    private struct ServerError: Decodable, LocalizedError {
        let code: String?
        let message: String?
        let error: String?
        var errorDescription: String? {
            if code == "23514" { return "One of the fields is too long or outside its allowed range. Shorten it and try again." }
            return message ?? error ?? "Club Connect couldn’t complete this request."
        }
    }
}
