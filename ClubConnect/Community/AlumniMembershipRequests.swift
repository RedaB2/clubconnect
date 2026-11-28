import SwiftUI

extension AlumniApplication {
    var statusTitle: String {
        switch status {
        case .pending: "Pending review"
        case .approved: "Approved"
        case .declined: "Declined"
        case .withdrawn: "Withdrawn"
        }
    }
}

struct AlumniApplicationSheet: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let club: Club
    let onSubmitted: () -> Void
    @State private var note = ""
    @State private var busy = false
    @State private var problem: String?
    @State private var confirmingWithdrawal = false

    private var request: AlumniApplication? {
        store.alumniApplications.filter { $0.clubID == club.id }.max { $0.submittedAt < $1.submittedAt }
    }

    var body: some View {
        NavigationStack {
            let open = store.catalog.first { $0.id == club.id }?.canJoin == true
            let canApply = open && request?.status != .pending && request?.status != .approved
            let theme = BrandTheme(club: club)
            Form {
                Section {
                    HStack(spacing: 12) {
                        ClubBadge(club: club, side: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(club.name).font(.title3.weight(.semibold))
                            if club.fullName != club.name { Text(club.fullName).font(.subheadline).foregroundStyle(.secondary) }
                        }
                    }.padding(.vertical, 4)
                    if !club.about.isEmpty { Text(club.about) }
                }.listRowBackground(theme.surface)
                if let request {
                    Section {
                        LabeledContent("Status", value: request.statusTitle)
                        LabeledContent("Sent", value: request.submittedAt.formatted(date: .abbreviated, time: .omitted))
                        if !request.note.isEmpty { Text(request.note) }
                        if request.status == .pending {
                            Button("Withdraw request", role: .destructive) { confirmingWithdrawal = true }
                        }
                    } header: { Text("Your request") } footer: {
                        if request.status == .pending { Text("An organizer will review your request. You can check its status in Clubs.") }
                        if request.status == .declined && open {
                            Text("You can apply again and include any additional information for the organizers.")
                        }
                    }.listRowBackground(theme.surface)
                }
                if canApply {
                    Section {
                        TextField("For example, I organized movie nights in 2018.", text: $note, axis: .vertical)
                            .lineLimit(2...5).accessibilityLabel("Note to organizers")
                    } header: { Text("Note to organizers (optional)") } footer: {
                        Text(note.count > 300 ? "Shorten your note to 300 characters." : "Only this club’s organizers can review your name, verified email address, graduation term, and note.")
                    }.listRowBackground(theme.surface)
                    Button { perform { try await store.requestMembership(clubID: club.id, note: note.communityTrimmed) } } label: {
                        Label("Request to join", systemImage: "person.badge.plus")
                    }.disabled(note.count > 300).listRowBackground(theme.surface)
                }
                if !open && request?.status != .approved {
                    Text("This club is closed to new requests.").listRowBackground(theme.surface)
                }
                if let problem { Text(problem).listRowBackground(theme.surface) }
            }.brandListBackground()
            .scrollDismissesKeyboard(.interactively)
            .disabled(busy)
            .navigationTitle("Club membership").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(busy) } }
            .confirmationDialog("Withdraw your request to join " + club.name + "?", isPresented: $confirmingWithdrawal, titleVisibility: .visible) {
                Button("Withdraw request", role: .destructive) { perform { try await store.withdrawMembershipRequest(clubID: club.id) } }
                Button("Keep request", role: .cancel) {}
            }
        }
        .brandScope(club)
        .interactiveDismissDisabled(busy)
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await action(); onSubmitted(); dismiss() }
            catch { problem = error.localizedDescription }
        }
    }
}

struct AlumniReviewQueue: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.brandTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let club: Club
    @State private var requests: [AlumniApplication] = []
    @State private var loaded = false
    @State private var busy = false
    @State private var problem: String?
    @State private var decision: Decision?

    private struct Decision {
        let request: AlumniApplication
        let approve: Bool
    }

    var body: some View {
        NavigationStack {
            List {
                let pending = requests.filter { $0.status == .pending }
                let history = requests.filter { $0.status != .pending }
                Section {
                    if !loaded && problem == nil {
                        ProgressView("Loading requests")
                    } else if pending.isEmpty && loaded {
                        Label("No pending requests", systemImage: "checkmark.circle").foregroundStyle(theme.ink)
                    }
                    ForEach(pending) { row($0) }
                } header: { Text(club.name) }
                .listRowBackground(theme.surface)
                if !history.isEmpty {
                    Section("History") { ForEach(history) { row($0) } }.listRowBackground(theme.surface)
                }
                if let problem {
                    Section { Text(problem); Button("Try again") { Task { await load() } } }.listRowBackground(theme.surface)
                }
            }
            .brandListBackground()
            .refreshable { await load() }.task { await load() }
            .navigationTitle("Membership requests")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(busy) } }
            .alert(decision?.approve == true ? "Approve membership?" : "Decline request?",
                   isPresented: Binding(get: { decision != nil }, set: { if !$0 { decision = nil } }), presenting: decision) { choice in
                Button(choice.approve ? "Approve" : "Decline", role: choice.approve ? nil : .destructive) {
                    Task { await decide(choice) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { choice in
                Text(choice.approve ? "\(choice.request.name) will be able to see \(club.name)’s members, messages they participate in, and events." : "\(choice.request.name) will see your decision and can apply again with more information.")
            }
            .onChange(of: store.club.id) { _, id in if id != club.id { dismiss() } }
            .onChange(of: store.isAdmin) { _, canManage in if !canManage { dismiss() } }
        }
    }

    private func row(_ request: AlumniApplication) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(request.name).font(.headline).foregroundStyle(theme.ink)
            Text(request.email).font(.subheadline).textSelection(.enabled)
            Text("\(request.graduationTerm.title) \(String(request.graduationYear)) graduate · \(request.submittedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption).foregroundStyle(.secondary)
            if !request.note.isEmpty { Text(request.note).font(.body).textSelection(.enabled) }
            if request.status == .pending {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { actions(request) }
                    VStack(alignment: .leading) { actions(request) }
                }
                .buttonStyle(.borderless)
                .disabled(busy)
            } else {
                Text(request.statusTitle).font(.subheadline.weight(.medium))
            }
        }.padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func actions(_ request: AlumniApplication) -> some View {
        Button { decision = Decision(request: request, approve: true) } label: {
            Label("Approve", systemImage: "checkmark").frame(minHeight: 44)
        }
        Button(role: .destructive) { decision = Decision(request: request, approve: false) } label: {
            Label("Decline", systemImage: "xmark").frame(minHeight: 44)
        }
    }

    private func load() async {
        guard store.club.id == club.id, store.isAdmin, !busy else { return }
        busy = true
        defer { busy = false }
        do { requests = try await store.reviewAlumniApplications(); loaded = true; problem = nil }
        catch { if !Task.isCancelled { problem = error.localizedDescription } }
    }

    private func decide(_ choice: Decision) async {
        guard store.club.id == club.id, store.isAdmin, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await store.decideAlumniApplication(choice.request.id, approve: choice.approve)
            requests = try await store.reviewAlumniApplications()
            problem = nil
        } catch { problem = error.localizedDescription }
    }
}
