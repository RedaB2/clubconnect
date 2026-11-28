import SwiftUI

struct MyProfileView: View {
    @Environment(\.brandTheme) private var theme
    @Environment(ClubStore.self) private var store
    @State private var editing = false
    @State private var redeeming = false
    @State private var confirmingDeletion = false
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            MemberProfile(member: store.me) {
                if !store.me.hasCompleteAcademicProfile() {
                    Section {
                        Button("Complete graduation details") { editing = true }
                    }.listRowBackground(theme.surface)
                }
                Section {
                    if !store.isPreview && !store.isAlumniAccount && !store.hasOrganizerRole {
                        Button { redeeming = true } label: {
                            Label("Redeem organizer invitation", systemImage: "envelope.badge.person.crop")
                        }
                    }
                    Button {
                        perform { try await store.leaveSession() }
                    } label: {
                        Label(store.isPreview ? (store.hasCampusSession ? "Return to my clubs" : "Leave sample community") : "Sign out", systemImage: "rectangle.portrait.and.arrow.right")
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
                }.listRowBackground(theme.surface)
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
    @Environment(\.brandTheme) private var theme
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
                }.listRowBackground(theme.surface)
            }
            .brandListBackground()
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
    @Environment(\.brandTheme) private var theme
    let member: Member
    @ViewBuilder var footer: () -> Footer

    init(member: Member, @ViewBuilder footer: @escaping () -> Footer) {
        self.member = member
        self.footer = footer
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    MemberPortrait(name: member.name, imageData: member.photoData, diameter: 85)
                    VStack(spacing: 5) {
                        Text(member.name)
                            .font(.system(.largeTitle, design: .serif, weight: .medium))
                            .foregroundStyle(theme.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(member.effectiveKind()?.communityTitle ?? "Graduation term needed")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(theme.ink.opacity(0.76))
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 12)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(colors: [theme.wash, theme.surface], startPoint: .top, endPoint: .bottom))
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(.init(top: 4, leading: 0, bottom: 6, trailing: 0))
            if !member.bio.isEmpty {
                Section("About") { Text(member.bio).textSelection(.enabled) }.listRowBackground(theme.surface)
            }
            if let graduation = member.graduationLabel {
                Section("Education") {
                    LabeledContent("Graduation", value: graduation)
                    if member.effectiveKind() == .student, let standing = member.classStanding {
                        LabeledContent("Class standing", value: standing.title)
                    }
                }.listRowBackground(theme.surface)
            }
            if !member.major.isEmpty {
                Section("Major") { Label(member.major, systemImage: "graduationcap").labelStyle(CommunityFieldLabelStyle()) }.listRowBackground(theme.surface)
            }
            if !member.interests.isEmpty {
                Section("Interests") {
                    ForEach(Array(member.interests.enumerated()), id: \.offset) { _, interest in
                        Text(interest)
                    }
                }.listRowBackground(theme.surface)
            }
            if !member.experience.isEmpty {
                Section("Experience") { Text(member.experience).textSelection(.enabled) }.listRowBackground(theme.surface)
            }
            footer()
        }
        .listStyle(.insetGrouped)
        .brandListBackground()
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

struct ProfileEditor: View {
    @Environment(\.brandTheme) private var theme
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
                }.listRowBackground(theme.surface)
                Section("Profile") {
                    TextField("Name", text: $draft.name).textContentType(.name)
                    TextField("Major", text: $draft.major)
                    TextField("About you", text: $draft.bio, axis: .vertical)
                        .lineLimit(2...6)
                }.listRowBackground(theme.surface)
                GraduationFields(term: $draft.graduationTerm, year: $draft.graduationYear, standing: $draft.classStanding, alumniOnly: store.isAlumniAccount)
                Section {
                    TextField("Interests", text: $interests, axis: .vertical)
                        .lineLimit(1...4)
                } footer: {
                    Text("Separate your interests with commas.")
                }.listRowBackground(theme.surface)
                Section("Experience") {
                    TextField("Work, projects, or campus involvement", text: $draft.experience, axis: .vertical)
                        .lineLimit(3...8)
                }.listRowBackground(theme.surface)
            }
            .brandListBackground()
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(saving || loadingImage || draft.name.communityTrimmed.isEmpty ||
                                  !draft.hasCompleteAcademicProfile() || (store.isAlumniAccount && draft.effectiveKind() != .alumni) || !GraduationTerm.validYears.contains(draft.graduationYear ?? 0))
                }
            }
            .interactiveDismissDisabled(saving)
            .alert("Couldn’t save profile", isPresented: Binding(
                get: { problem != nil }, set: { if !$0 { problem = nil } }
            )) { Button("OK") {} } message: { Text(problem ?? "") }
        }
    }

    private func save() {
        guard !saving, let kind = draft.effectiveKind(), draft.hasCompleteAcademicProfile(),
              !store.isAlumniAccount || kind == .alumni,
              GraduationTerm.validYears.contains(draft.graduationYear ?? 0) else { return }
        var update = draft
        update.kind = kind
        if kind == .alumni { update.classStanding = nil }
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
                if store.phase == .alumniClubs {
                    try await store.saveAlumniProfile(update)
                } else {
                    try await store.saveProfile(update)
                }
                dismiss()
            } catch { problem = error.localizedDescription }
            saving = false
        }
    }
}

struct GraduationFields: View {
    @Environment(\.brandTheme) private var theme
    @Binding var term: GraduationTerm?
    @Binding var year: Int?
    @Binding var standing: ClassStanding?
    var alumniOnly = false

    private var kind: MemberKind? {
        guard let term, let year, GraduationTerm.validYears.contains(year) else { return nil }
        return term.kind(year: year)
    }

    var body: some View {
        Section {
            Picker("Graduation term", selection: $term) {
                Text("Choose term").tag(nil as GraduationTerm?)
                ForEach(GraduationTerm.allCases, id: \.self) { term in
                    Text(term.title).tag(Optional(term))
                }
            }
            LabeledContent("Graduation year") {
                TextField("YYYY", value: $year, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Graduation year")
                    .accessibilityIdentifier("graduation-year-input")
            }
            if let kind {
                LabeledContent("Membership", value: kind.communityTitle)
                if kind == .student && !alumniOnly {
                    Picker("Class standing", selection: $standing) {
                        Text("Choose standing").tag(nil as ClassStanding?)
                        ForEach(ClassStanding.allCases, id: \.self) { standing in
                            Text(standing.title).tag(Optional(standing))
                        }
                    }
                }
            }
        } header: {
            Text("Graduation")
        } footer: {
            if let year, !GraduationTerm.validYears.contains(year) {
                Text("Enter a year from \(GraduationTerm.validYears.lowerBound.formatted(.number.grouping(.never))) through \(GraduationTerm.validYears.upperBound.formatted(.number.grouping(.never))).")
            } else if alumniOnly {
                Text("Choose a graduation term that has already ended.")
            } else {
                Text(GraduationTerm.cutoffDescription)
            }
        }.listRowBackground(theme.surface)
    }
}
