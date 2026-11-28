import SwiftUI

struct AlumniMembershipView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.brandTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Binding var linkedClub: String?
    @State private var search = ""
    @State private var selectedClub: Club?
    @State private var editingProfile = false
    @State private var problem: String?

    private var matchingClubs: [ClubListing] {
        let query = search.communityTrimmed
        return store.catalog.filter { entry in
            !entry.joined && (query.isEmpty || entry.club.name.localizedCaseInsensitiveContains(query) ||
                              entry.club.fullName.localizedCaseInsensitiveContains(query))
        }.sorted { lhs, rhs in
            if lhs.id == rhs.id { return false }
            if lhs.id == store.enrollmentClubID { return true }
            if rhs.id == store.enrollmentClubID { return false }
            return lhs.club.name.localizedStandardCompare(rhs.club.name) == .orderedAscending
        }
    }

    private var requests: [String: AlumniApplication] {
        Dictionary(grouping: store.alumniApplications, by: \.clubID)
            .compactMapValues { $0.max { $0.submittedAt < $1.submittedAt } }
    }

    var body: some View {
        NavigationStack {
            List {
                if search.communityTrimmed.isEmpty {
                    Section {
                        Text("Find a club you belonged to at USC. An organizer reviews your request before you can see its members and events.")
                            .font(.body).foregroundStyle(theme.ink)
                    }.listRowBackground(theme.surface)
                }

                let latest = requests
                let requested = matchingClubs.filter { latest[$0.id] != nil }
                if !requested.isEmpty {
                    Section("Your requests") {
                        ForEach(requested) { entry in row(entry, application: latest[entry.id]) }
                    }.listRowBackground(theme.surface)
                }

                let available = matchingClubs.filter { latest[$0.id] == nil }
                if !available.isEmpty {
                    Section("Find your club") {
                        ForEach(available) { entry in row(entry, application: nil) }
                    }.listRowBackground(theme.surface)
                }

                if available.isEmpty && requested.isEmpty {
                    Section {
                        if search.communityTrimmed.isEmpty {
                            ContentUnavailableView("No clubs available", systemImage: "building.columns", description: Text("Pull down to refresh the club directory."))
                        } else {
                            ContentUnavailableView.search(text: search)
                        }
                    }.listRowBackground(theme.surface)
                }
                if let problem { Text(problem).listRowBackground(theme.surface) }
            }
            .navigationTitle("Alumni clubs")
            .brandListBackground()
            .searchable(text: $search, prompt: "Search USC clubs")
            .refreshable { await store.loadMembership() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.loadMembership() } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NonmemberAccountMenu(editProfile: { editingProfile = true }) { problem = $0 }
                }
            }
            .sheet(item: $selectedClub) { club in
                AlumniApplicationSheet(club: club) { selectedClub = nil }
            }
            .sheet(isPresented: $editingProfile) {
                if let profile = store.alumniProfile { ProfileEditor(member: profile) }
            }
            .onChange(of: linkedClub, initial: true) { _, identifier in
                guard let identifier else { return }
                linkedClub = nil
                guard let target = store.catalog.first(where: { $0.id == identifier }) else { return }
                selectedClub = target.club
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && selectedClub == nil && !editingProfile {
                    Task { await store.loadMembership() }
                }
            }
        }
    }

    private func row(_ entry: ClubListing, application: AlumniApplication?) -> some View {
        Button {
            selectedClub = entry.club
        } label: {
            HStack(spacing: 12) {
                CommunityMark(logoData: entry.club.logoData, side: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.club.name).font(.headline).foregroundStyle(theme.ink)
                    if let application {
                        Text(statusDescription(application)).font(.subheadline).foregroundStyle(theme.ink.opacity(0.78))
                    } else if entry.club.fullName != entry.club.name {
                        Text(entry.club.fullName).font(.subheadline).foregroundStyle(theme.ink.opacity(0.78))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary).accessibilityHidden(true)
            }.padding(.vertical, 4)
        }
        .accessibilityIdentifier("alumni-club-" + entry.id)
    }

    private func statusDescription(_ request: AlumniApplication) -> String {
        switch request.status {
        case .pending: return "Pending organizer review"
        case .approved: return "Approved"
        case .declined: return "Declined · You can request again"
        case .withdrawn: return "Withdrawn · You can request again"
        }
    }
}

struct NonmemberAccountMenu: View {
    @Environment(ClubStore.self) private var store
    @State private var confirmingDeletion = false
    var editProfile: (() -> Void)?
    let onError: (String) -> Void

    var body: some View {
        Menu("Account", systemImage: "person.crop.circle") {
            if let editProfile {
                Button("Edit alumni profile", systemImage: "person.text.rectangle", action: editProfile)
            }
            Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") {
                Task {
                    do { try await store.leaveSession() }
                    catch { onError(error.localizedDescription) }
                }
            }
            Button("Delete account", systemImage: "trash", role: .destructive) { confirmingDeletion = true }
        }
        .confirmationDialog("Permanently delete your account?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Delete my account", role: .destructive) {
                Task {
                    do { try await store.deleteAccount() }
                    catch { onError(error.localizedDescription) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your profile and club requests will be deleted. This can’t be undone.")
        }
    }
}
