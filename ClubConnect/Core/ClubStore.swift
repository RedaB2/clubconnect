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
    private(set) var catalog: [ClubListing] = []
    var enrollmentClubID = "menasa"
    private(set) var completingProfile = false
    private(set) var viewingAsMember = false
    private var sampleClubs: SampleClubs?
    private let auth = PilotAuth()
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard
    private let demoKey = "clubconnect.sample.v1"
    private var campusAccountID: String?
    var sampleOwnerID: String { campusAccountID ?? "demo-organizer" }
    private var libraryKey: String { "clubconnect.sample.clubs.v2." + sampleOwnerID }
    private let modeKey = "clubconnect.mode"
    private let activeKey = "clubconnect.active-club"

    var enrollmentClubName: String { catalog.first { $0.id == enrollmentClubID }?.club.name ?? "MENASA" }
    var hasOrganizerRole: Bool { state.isAdmin }
    var hasCampusSession: Bool { auth.hasSession }
    var club: Club { state.club }
    var members: [Member] { state.members }
    var me: Member { members.first { $0.id == state.myID } ?? Member(id: state.myID, name: "Member", kind: .student) }
    var isAdmin: Bool { hasOrganizerRole && !viewingAsMember }
    var events: [ClubEvent] { state.events }
    var tickets: [EventTicket] { state.tickets }
    var walletAvailable: Bool { phase == .community && auth.hasSession }
    var inviteURL: URL { PilotConfiguration.invitePage.appending(queryItems: [.init(name: "club", value: club.id)]) }
    func eventURL(_ id: String) -> URL {
        let items = [URLQueryItem(name: "event", value: id)] + (isPreview ? [.init(name: "sample", value: "1")] : [])
        return inviteURL.appending(queryItems: items)
    }

    func start() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ClubConnectFreshDemo") {
            defaults.removeObject(forKey: demoKey)
            defaults.removeObject(forKey: libraryKey)
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("clubconnect.member-view.demo-organizer.") {
                defaults.removeObject(forKey: key)
            }
            defaults.removeObject(forKey: modeKey)
            phase = .welcome
            return
        }
        #endif
        #if DEBUG
        if defaults.string(forKey: modeKey) == "sample", !auth.hasSession { openSample(); return }
        #endif
        guard auth.hasSession else { phase = .welcome; return }
        await loadMembership()
        if phase == .community, defaults.string(forKey: modeKey) == "sample" { openSample() }
    }

    func openSample() {
        #if !DEBUG
        guard auth.hasSession, phase == .community else { return }
        #endif
        let saved = defaults.data(forKey: libraryKey).flatMap { try? JSONDecoder().decode(SampleClubs.self, from: $0) }
        let old = (campusAccountID == nil ? defaults.data(forKey: demoKey) : nil).flatMap { try? JSONDecoder().decode(CommunityState.self, from: $0) }
        let pilot = old ?? .sample()
        let library = saved ?? SampleClubs(memberships: [pilot.club.id: pilot], activeID: pilot.club.id)
        sampleClubs = library
        defaults.set("sample", forKey: modeKey)
        isPreview = true
        catalog = library.catalog
        activate(library.memberships[library.activeID] ?? pilot)
        phase = .community
    }

    func requestCode(email: String) async throws { try await auth.requestCode(email: email) }

    func verifyCode(email: String, code: String) async throws {
        try await auth.verifyCode(email: email, code: code)
        await enterVerifiedSession()
    }

    func verifyEmailLink(_ url: URL) async throws {
        try await auth.verifyEmailLink(url)
        await enterVerifiedSession()
    }

    private func enterVerifiedSession() async {
        isPreview = false
        defaults.removeObject(forKey: modeKey)
        await loadMembership()
    }

    func loadMembership() async {
        phase = .loading
        do {
            try await reloadCatalog()
            let joined = catalog.filter(\.joined)
            let remembered = defaults.string(forKey: activeKey)
            guard let selected = joined.first(where: { $0.id == remembered }) ?? joined.first else {
                if !catalog.contains(where: { $0.id == enrollmentClubID }) { enrollmentClubID = catalog.first?.id ?? "menasa" }
                completingProfile = false
                phase = .enrollment
                return
            }
            try await loadClub(selected.id)
            completingProfile = !me.hasCompleteAcademicProfile()
            enrollmentClubID = selected.id
            suggestedName = me.name
            phase = completingProfile ? .enrollment : .community
        } catch {
            phase = auth.hasSession ? .reconnect : .welcome
            notice = error.localizedDescription
        }
    }

    private struct Enrollment: Encodable {
        let c: String
        let display_name: String
        let graduation_term: GraduationTerm
        let graduation_year: Int
        let class_standing: ClassStanding?
    }

    func join(name: String, graduationTerm: GraduationTerm, graduationYear: Int, classStanding: ClassStanding?) async throws {
        let body = Enrollment(c: enrollmentClubID, display_name: name, graduation_term: graduationTerm,
                              graduation_year: graduationYear, class_standing: classStanding)
        try await readLiveState("enroll_student", body: encode(body))
        finishEnrollment()
    }

    func createFirstClub(_ title: String, name: String, graduationTerm: GraduationTerm, graduationYear: Int, classStanding: ClassStanding?) async throws {
        struct Details: Encodable {
            let name: String; let graduationTerm: GraduationTerm; let graduationYear: Int; let classStanding: ClassStanding?
        }
        struct Creation: Encodable { let c: String; let title: String; let first_profile: Details }
        let detail = Details(name: name, graduationTerm: graduationTerm, graduationYear: graduationYear, classStanding: classStanding)
        let body = Creation(c: creationID(for: title), title: title, first_profile: detail)
        try await readLiveState("create_campus_club", body: encode(body))
        finishEnrollment()
    }

    private func finishEnrollment() {
        pendingCreation = nil
        completingProfile = false
        phase = .community
    }

    private func reloadCatalog() async throws {
        let data = try await rpc("club_catalog", body: Data("{}".utf8))
        catalog = try JSONDecoder().decode([ClubListing].self, from: data)
    }

    private func loadClub(_ id: String) async throws {
        try await readLiveState("snapshot", body: encode(["c": id]))
    }

    private func activate(_ fresh: CommunityState) {
        state = fresh
        let id = fresh.club.id
        if !isPreview { campusAccountID = fresh.myID }
        viewingAsMember = defaults.bool(forKey: roleViewKey)
        if !isPreview { defaults.set(id, forKey: activeKey) }
        let entry = ClubListing(club: fresh.club, joined: true, isAdmin: fresh.isAdmin, canJoin: true)
        if let index = catalog.firstIndex(where: { $0.id == id }) { catalog[index] = entry }
        else { catalog.append(entry) }
    }

    private var roleViewKey: String { "clubconnect.member-view." + (isPreview ? sampleOwnerID + ".sample" : state.myID) + "." + state.club.id }
    func setMemberView(_ value: Bool) {
        viewingAsMember = value && hasOrganizerRole
        defaults.set(viewingAsMember, forKey: roleViewKey)
    }

    func selectClub(_ id: String) async throws {
        try await serialized {
            if self.state.club.id == id { return }
            guard self.catalog.contains(where: { $0.id == id && $0.joined }) else { throw ClubFailure("Join this club first.") }
            if self.isPreview {
                guard let next = self.sampleClubs?.memberships[id] else { throw ClubFailure("Club unavailable.") }
                try self.persist(next)
            } else { try await self.loadClub(id) }
        }
    }

    func joinAdditionalClub(_ id: String) async throws {
        try await serialized {
            if self.isPreview {
                guard let entry = self.catalog.first(where: { $0.id == id }) else { throw ClubFailure("Club unavailable.") }
                if let existing = self.sampleClubs?.memberships[id] { try self.persist(existing); return }
                let organizer = CommunityState.sample().members.first { $0.id == "demo-omar" }
                let next = CommunityState(club: entry.club, members: [self.me] + [organizer].compactMap { $0 },
                                          events: [], tickets: [], myID: self.me.id, isAdmin: false)
                try self.persist(next)
            } else { try await self.readLiveState("join_additional", body: self.encode(["c":id])) }
        }
    }

    private var pendingCreation: (name: String, id: String)?
    private func creationID(for name: String) -> String {
        if let pendingCreation, pendingCreation.name == name { return pendingCreation.id }
        let id = UUID().uuidString.lowercased()
        pendingCreation = (name,id)
        return id
    }

    func createClub(name: String) async throws {
        try await serialized {
            let id = self.creationID(for: name)
            if self.isPreview {
                let club = Club(id: id, name: name, fullName: name, about: "", accentHex: "#974A30")
                try self.persist(CommunityState(club: club, members: [self.me], events: [], tickets: [], myID: self.me.id, isAdmin: true))
            } else { try await self.readLiveState("create_campus_club", body: self.encode(["c":id, "title":name])) }
            self.pendingCreation = nil
        }
    }

    func stepDown(successor: String?) async throws {
        try await serialized {
            guard self.hasOrganizerRole else { throw ClubFailure("Organizer access required.") }
            if self.isPreview {
                let prior = self.sampleClubs?.otherOrganizers[self.club.id] ?? []
                if let successor, self.members.contains(where: { $0.id == successor && $0.id != self.me.id }) {
                    self.sampleClubs?.otherOrganizers[self.club.id, default: []].insert(successor)
                } else if prior.isEmpty {
                    throw ClubFailure("Choose another member to take over. You can use member view at any time.")
                }
                var sample = self.state
                sample.isAdmin = false
                try self.persist(sample)
            } else {
                var body = ["c": self.club.id]
                body["successor"] = successor
                try await self.readLiveState("step_down", body: self.encode(body))
            }
            self.setMemberView(false)
        }
    }

    func authToken() async throws -> String { try await auth.accessToken() }
    func rpc(_ name: String, body: Data) async throws -> Data {
        try await request("rest/v1/rpc/" + name, body: body)
    }

    func refresh() async {
        guard phase == .community, !isPreview else { return }
        do {
            try await serialized {
                guard self.phase == .community, !self.isPreview else { return }
                try await self.reloadCatalog()
                try await self.loadClub(self.club.id)
            }
        } catch {
            if !auth.hasSession { reset() }
            notice = error.localizedDescription
        }
    }

    func leaveSession() async throws {
        try await serialized {
            if self.isPreview && self.auth.hasSession {
                self.isPreview = false
                self.defaults.removeObject(forKey: self.modeKey)
                await self.loadMembership()
            } else {
                if !self.isPreview { try await self.auth.signOut() }
                self.reset()
            }
        }
    }

    private func reset() {
        defaults.removeObject(forKey: modeKey)
        isPreview = false
        state = .sample()
        campusAccountID = nil
        sampleClubs = nil
        suggestedName = ""
        enrollmentClubID = "menasa"
        completingProfile = false
        pendingCreation = nil
        catalog = []
        viewingAsMember = false
        phase = .welcome
    }

    func deleteAccount() async throws {
        try await serialized {
            guard !self.isPreview else { throw ClubFailure("Sign in to manage your account.") }
            _ = try await self.request("rest/v1/rpc/delete_account", body: Data("{}".utf8))
            MessageMailbox.clearAccount(self.me.id)
            self.defaults.removeObject(forKey: self.libraryKey)
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
            let data = try await self.request("rest/v1/rpc/check_in", body: try self.encode(["c": self.club.id, "eid": eventID, "ticket_code": code]))
            let name = try JSONDecoder().decode(String.self, from: data)
            // A successful check-in is final even if the follow-up refresh is offline.
            if let index = self.state.tickets.firstIndex(where: { $0.eventID == eventID && $0.code == code.uppercased() }) {
                self.state.tickets[index].checkedIn = true
            }
            return name
        }
    }

    func walletPass(eventID: String) async throws -> Data {
        guard walletAvailable else { throw ClubFailure("Verify your USC email to add a pass to Wallet.") }
        if isPreview {
            guard let ticket = tickets.first(where: { $0.eventID == eventID }) else { throw ClubFailure("RSVP to this event first.") }
            struct SamplePass: Encodable { let sample: Bool; let eventID: String; let sampleTicketID: String }
            return try await request("functions/v1/event-pass", body: encode(SamplePass(sample: true, eventID: eventID, sampleTicketID: ticket.id)))
        }
        return try await request("functions/v1/event-pass", body: encode(["eventID": eventID, "clubID": club.id]))
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
        let target = club.id
        try await serialized {
            guard self.phase == .community, self.club.id == target else { throw ClubFailure("Open your club to continue.") }
            if self.isPreview {
                var sample = self.state
                try sampleChange(&sample)
                try self.persist(sample)
            } else {
                let data = try self.encode(body)
                guard var parameters = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClubFailure("Couldn’t prepare this request.") }
                parameters["c"] = target
                try await self.readLiveState(endpoint, body: JSONSerialization.data(withJSONObject: parameters))
            }
        }
    }

    private func persist(_ sample: CommunityState) throws {
        guard var library = sampleClubs else { throw ClubFailure("Open the sample community first.") }
        library.memberships[sample.club.id] = sample
        library.activeID = sample.club.id
        if let profile = sample.members.first(where: { $0.id == sample.myID }) {
            for id in Array(library.memberships.keys) where id != sample.club.id {
                if let index = library.memberships[id]?.members.firstIndex(where: { $0.id == profile.id }) {
                    library.memberships[id]?.members[index] = profile
                }
            }
        }
        defaults.set(try JSONEncoder().encode(library), forKey: libraryKey)
        sampleClubs = library
        catalog = library.catalog
        activate(sample)
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
        activate(fresh)
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
            if let problem = try? JSONDecoder().decode(ServerError.self, from: data) {
                if problem.code == "28000" {
                    // A previously accepted campus identity can lose eligibility.
                    // Clear the roster and credentials immediately on that response.
                    try? await auth.signOut()
                    reset()
                }
                throw problem
            }
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
