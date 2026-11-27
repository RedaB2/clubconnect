import SwiftUI

struct MyProfileView: View {
    @Environment(ClubStore.self) private var store
    @State private var editing = false
    @State private var redeeming = false
    @State private var confirmingDeletion = false
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            MemberProfile(member: store.me) {
                Section {
                    if !store.isPreview && !store.isAdmin {
                        Button { redeeming = true } label: {
                            Label("Redeem organizer invitation", systemImage: "envelope.badge.person.crop")
                        }
                    }
                    Button {
                        perform { try await store.leaveSession() }
                    } label: {
                        Label(store.isPreview ? "Leave sample community" : "Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    if !store.isPreview {
                        Button("Delete account", role: .destructive) { confirmingDeletion = true }
                            .confirmationDialog("Permanently delete your account?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                                Button("Delete my account", role: .destructive) {
                                    perform { try await store.deleteAccount() }
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("This permanently removes your Club Connect profile and event registrations.")
                            }
                    }
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editing = true }
                        .accessibilityLabel("Edit profile")
                }
            }
            .disabled(busy)
            .sheet(isPresented: $editing) { ProfileEditor(member: store.me) }
            .sheet(isPresented: $redeeming) { OrganizerInvitationView() }
            .alert("Couldn’t update account", isPresented: Binding(
                get: { problem != nil }, set: { if !$0 { problem = nil } }
            )) { Button("OK") {} } message: { Text(problem ?? "") }
        }
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await action() }
            catch { problem = error.localizedDescription }
        }
    }
}

private struct OrganizerInvitationView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var submitting = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Invitation code", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Use the one-time code provided by your club to manage events and club settings.")
                }
            }
            .navigationTitle("Organizer invitation")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(submitting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(submitting) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Redeem") {
                        guard !submitting else { return }
                        submitting = true
                        Task {
                            defer { submitting = false }
                            do {
                                try await store.claimOrganizer(code.communityTrimmed)
                                dismiss()
                            } catch { problem = error.localizedDescription }
                        }
                    }
                    .disabled(submitting || code.communityTrimmed.isEmpty)
                }
            }
            .alert("Couldn’t redeem invitation", isPresented: Binding(
                get: { problem != nil }, set: { if !$0 { problem = nil } }
            )) { Button("OK") {} } message: { Text(problem ?? "") }
        }
    }
}

struct MemberProfile<Footer: View>: View {
    let member: Member
    @ViewBuilder var footer: () -> Footer

    init(member: Member, @ViewBuilder footer: @escaping () -> Footer) {
        self.member = member
        self.footer = footer
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    MemberPortrait(name: member.name, imageData: member.photoData, diameter: 85)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(member.name)
                            .font(.system(.largeTitle, design: .serif, weight: .medium))
                            .accessibilityAddTraits(.isHeader)
                        Text(member.kind.communityTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(.init(top: 4, leading: 0, bottom: 6, trailing: 0))
            if !member.bio.isEmpty {
                Section("About") { Text(member.bio).textSelection(.enabled) }
            }
            if !member.major.isEmpty {
                Section("Major") { Label(member.major, systemImage: "graduationcap").labelStyle(CommunityFieldLabelStyle()) }
            }
            if !member.interests.isEmpty {
                Section("Interests") {
                    ForEach(Array(member.interests.enumerated()), id: \.offset) { _, interest in
                        Text(interest)
                    }
                }
            }
            if !member.experience.isEmpty {
                Section("Experience") { Text(member.experience).textSelection(.enabled) }
            }
            footer()
        }
        .listStyle(.insetGrouped)
    }
}

extension MemberProfile where Footer == EmptyView {
    init(member: Member) { self.init(member: member) { EmptyView() } }
}

private struct CommunityFieldLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon.foregroundStyle(.tint)
            configuration.title
        }
    }
}

private struct ProfileEditor: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Member
    @State private var interests: String
    @State private var loadingImage = false
    @State private var saving = false
    @State private var problem: String?

    init(member: Member) {
        _draft = State(initialValue: member)
        _interests = State(initialValue: member.interests.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AdaptivePhotoRow {
                        MemberPortrait(name: draft.name, imageData: draft.photoData, diameter: 72)
                        CommunityPhotoPicker(label: "Choose photo", removalLabel: "Remove photo", data: $draft.photoData, isLoading: $loadingImage)
                    }
                    .padding(.vertical, 5)
                }
                Section("Profile") {
                    TextField("Name", text: $draft.name).textContentType(.name)
                    Picker("Membership", selection: $draft.kind) {
                        Text("Student").tag(MemberKind.student)
                        Text("Alumni").tag(MemberKind.alumni)
                    }
                    TextField("Major", text: $draft.major)
                    TextField("About you", text: $draft.bio, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    TextField("Interests", text: $interests, axis: .vertical)
                        .lineLimit(1...4)
                } footer: {
                    Text("Separate your interests with commas.")
                }
                Section("Experience") {
                    TextField("Work, projects, or campus involvement", text: $draft.experience, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(saving || loadingImage || draft.name.communityTrimmed.isEmpty)
                }
            }
            .interactiveDismissDisabled(saving)
            .alert("Couldn’t save profile", isPresented: Binding(
                get: { problem != nil }, set: { if !$0 { problem = nil } }
            )) { Button("OK") {} } message: { Text(problem ?? "") }
        }
    }

    private func save() {
        guard !saving else { return }
        var update = draft
        update.name = draft.name.communityTrimmed
        update.major = draft.major.communityTrimmed
        update.bio = draft.bio.communityTrimmed
        update.experience = draft.experience.communityTrimmed
        var seen = Set<String>()
        update.interests = interests.split(separator: ",").map { String($0).communityTrimmed }.filter { interest in
            !interest.isEmpty && seen.insert(interest.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted
        }
        saving = true
        Task {
            do {
                try await store.saveProfile(update)
                dismiss()
            } catch { problem = error.localizedDescription }
            saving = false
        }
    }
}
