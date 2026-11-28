import Foundation

struct AlumniApplication: Identifiable, Codable, Equatable {
    enum Status: String, Codable { case pending, approved, declined, withdrawn }
    let id: UUID
    let clubID: String
    let name: String
    let email: String
    let graduationTerm: GraduationTerm
    let graduationYear: Int
    let note: String
    var status: Status
    let submittedAt: Date
    var decidedAt: Date?

    static func sample() -> Self {
        Self(id: UUID(uuidString: "2A0F8120-FD89-4B1D-A065-7F372BC1E13C")!, clubID: "menasa",
             name: "Samira Khalil", email: "samira@example.invalid", graduationTerm: .spring, graduationYear: 2021,
             note: "I served on the cultural events committee.", status: .pending, submittedAt: .now)
    }
}

struct AlumniWorkspace: Decodable {
    let profile: Member?
    let applications: [AlumniApplication]
    let catalog: [ClubListing]
}

extension ClubStore {
    static func alumniDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    func saveAlumniProfile(name: String, graduationTerm: GraduationTerm, graduationYear: Int) async throws {
        struct Details: Encodable { let name: String; let graduationTerm: GraduationTerm; let graduationYear: Int }
        try await savePersonalProfile(Details(name: name, graduationTerm: graduationTerm, graduationYear: graduationYear))
    }

    func saveAlumniProfile(_ member: Member) async throws {
        struct FullProfile: Encodable {
            let member: Member
            enum CodingKeys: String, CodingKey { case photoData }

            func encode(to encoder: Encoder) throws {
                try member.encode(to: encoder)
                if member.photoData == nil {
                    var fields = encoder.container(keyedBy: CodingKeys.self)
                    try fields.encodeNil(forKey: .photoData)
                }
            }
        }
        try await savePersonalProfile(FullProfile(member: member))
    }

    private func savePersonalProfile<Details: Encodable>(_ details: Details) async throws {
        guard isAlumniAccount, !isPreview else { throw ClubFailure("Sign in with your personal email.") }
        _ = try await rpc("save_alumni_profile", body: JSONEncoder().encode(["entry": details]))
        switch phase {
        case .enrollment: await loadMembership()
        case .community: await refresh()
        default: try await reloadCatalog()
        }
    }

    func requestMembership(clubID: String, note: String = "") async throws {
        guard isAlumniAccount, !isPreview else { throw ClubFailure("An alumni profile is required.") }
        _ = try await rpc("request_alumni_membership", body: JSONEncoder().encode(["c": clubID, "note": note]))
        try await reloadCatalog()
    }

    func withdrawMembershipRequest(clubID: String) async throws {
        guard isAlumniAccount, !isPreview else { throw ClubFailure("An alumni profile is required.") }
        _ = try await rpc("withdraw_alumni_request", body: JSONEncoder().encode(["c": clubID]))
        try await reloadCatalog()
    }

    func reviewAlumniApplications() async throws -> [AlumniApplication] {
        guard phase == .community, isAdmin else { throw ClubFailure("Organizer access required.") }
        if isPreview { return sampleApplicationsForReview() }
        let data = try await rpc("review_alumni_applications", body: JSONEncoder().encode(["c": club.id]))
        return try Self.alumniDecoder().decode([AlumniApplication].self, from: data)
    }

    func decideAlumniApplication(_ id: UUID, approve: Bool) async throws {
        guard phase == .community, isAdmin else { throw ClubFailure("Organizer access required.") }
        if isPreview { try decideSampleApplication(id, approve: approve); return }
        struct Decision: Encodable { let c: String; let application_id: UUID; let approve: Bool }
        let target = club.id
        _ = try await rpc("decide_alumni_application", body: JSONEncoder().encode(Decision(c: target, application_id: id, approve: approve)))
        if target == club.id { await refresh() }
    }
}
