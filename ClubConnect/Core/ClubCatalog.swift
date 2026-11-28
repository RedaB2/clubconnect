import Foundation

struct ClubListing: Identifiable, Codable, Hashable {
    var club: Club
    var joined: Bool
    var isAdmin: Bool
    var canJoin: Bool
    var pendingRequestCount: Int? = nil
    var id: String { club.id }
}

struct SampleClubs: Codable {
    var memberships: [String: CommunityState]
    var alumniApplications: [String: [AlumniApplication]]? = nil
    var activeID: String
    var otherOrganizers: [String: Set<String>] = [:]

    static let film = Club(id: "campus-cinema", name: "Campus Cinema", fullName: "Campus Cinema Society",
                           about: "Student screenings and conversations about film.", accentHex: "#395E72")
    var catalog: [ClubListing] {
        var entries = memberships.values.map { state in
            let queue = alumniApplications?[state.club.id] ?? (state.club.id == CommunityState.pilot.id ? [.sample()] : [])
            return ClubListing(club: state.club, joined: true, isAdmin: state.isAdmin, canJoin: true,
                               pendingRequestCount: state.isAdmin ? queue.filter { $0.status == .pending }.count : nil)
        }
        if memberships[Self.film.id] == nil {
            entries.append(.init(club: Self.film, joined: false, isAdmin: false, canJoin: true))
        }
        return entries.sorted { $0.club.name < $1.club.name }
    }
}
