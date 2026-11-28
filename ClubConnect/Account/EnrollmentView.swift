import SwiftUI

struct EnrollmentView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.brandTheme) private var theme

    @State private var name = ""
    @State private var newClubName = ""
    @State private var creating = false
    @State private var term: GraduationTerm?
    @State private var year: Int?
    @State private var standing: ClassStanding?
    @State private var choosingClub = false
    @State private var saving = false
    @State private var problem: String?

    private var availableClubs: [ClubListing] {
        store.catalog.filter { !$0.joined && $0.canJoin }
    }

    private var memberKind: MemberKind? {
        guard let term, let year, GraduationTerm.validYears.contains(year) else { return nil }
        return term.kind(year: year)
    }

    private var profileIsReady: Bool {
        guard !name.communityTrimmed.isEmpty, name.communityTrimmed.count <= 100, let memberKind else { return false }
        if store.isAlumniAccount { return memberKind == .alumni }
        return memberKind == .alumni || standing != nil
    }

    private var selectedClub: ClubListing? {
        availableClubs.first { $0.id == store.enrollmentClubID }
    }

    var body: some View {
        NavigationStack {
            profile
                .navigationTitle(store.isAlumniAccount ? "Your alumni profile" : "Your profile")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NonmemberAccountMenu { problem = $0 }.disabled(saving)
                    }
                }
                .navigationDestination(isPresented: $choosingClub) { clubSelection }
                .onAppear { prepare() }
        }
    }

    private var profile: some View {
        Form {
            Section {
                TextField("Your name", text: $name)
                    .textContentType(.name).textInputAutocapitalization(.words)
                    .accessibilityIdentifier("onboarding-name")
            } header: { Text("Name") } footer: {
                Text(store.isAlumniAccount ? "Club organizers see your name when you request to join." : "This is how other club members will see you.")
            }.listRowBackground(theme.surface)
            Section {
                Picker("Graduation term", selection: $term) {
                    Text("Choose term").tag(nil as GraduationTerm?)
                    ForEach(GraduationTerm.allCases, id: \.self) { value in Text(value.title).tag(Optional(value)) }
                }
                .accessibilityIdentifier("graduation-term-picker")
                LabeledContent("Graduation year") {
                    TextField("YYYY", value: $year, format: .number.grouping(.never))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        .accessibilityLabel("Graduation year").accessibilityIdentifier("graduation-year-input")
                }
                if memberKind == .student && !store.isAlumniAccount {
                    Picker("Class standing", selection: $standing) {
                        Text("Choose standing").tag(nil as ClassStanding?)
                        ForEach(ClassStanding.allCases, id: \.self) { value in Text(value.title).tag(Optional(value)) }
                    }.accessibilityIdentifier("standing-picker")
                }
            } header: { Text("Graduation") } footer: {
                if let year, !GraduationTerm.validYears.contains(year) {
                    Text("Enter a year between \(GraduationTerm.validYears.lowerBound.formatted(.number.grouping(.never))) and \(GraduationTerm.validYears.upperBound.formatted(.number.grouping(.never))).")
                } else if store.isAlumniAccount {
                    Text("Choose a graduation term that has already ended. You can then request to join your former club.")
                } else if let memberKind {
                    Text(memberKind == .student ? "You’ll appear in the student directory." : "You’ll appear in the alumni directory.")
                } else {
                    Text("Your graduation term determines whether you appear as a student or an alum.")
                }
            }.listRowBackground(theme.surface)
            Section {
                AccountAction(profileActionTitle, systemImage: store.completingProfile ? nil : "arrow.right") {
                    if store.completingProfile || store.isAlumniAccount {
                        submit()
                    } else {
                        problem = nil
                        choosingClub = true
                    }
                }
                .disabled(!profileIsReady || saving)
                .accessibilityIdentifier("onboarding-continue")
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            status
        }
        .scrollDismissesKeyboard(.interactively)
        .brandListBackground().disabled(saving)
    }

    private var profileActionTitle: String {
        if store.completingProfile { return "Save profile" }
        return store.isAlumniAccount ? "Save alumni profile" : "Choose your first club"
    }

    private var clubSelection: some View {
        Form {
            Section {
                ForEach(availableClubs) { entry in
                    Button {
                        store.enrollmentClubID = entry.id
                        creating = false
                    } label: {
                        HStack(spacing: 12) {
                            CommunityMark(logoData: entry.club.logoData, side: 42)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.club.name).font(.headline).foregroundStyle(.primary)
                                if entry.club.fullName != entry.club.name {
                                    Text(entry.club.fullName).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if !creating, entry.id == selectedClub?.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent).accessibilityHidden(true)
                            }
                        }.padding(.vertical, 3)
                    }
                    .accessibilityAddTraits(!creating && entry.id == selectedClub?.id ? .isSelected : [])
                }
            } footer: { Text("Your profile will be visible to the members of the club you join.") }
            .listRowBackground(theme.surface)
            Section {
                if creating {
                    TextField("Club name", text: $newClubName).textInputAutocapitalization(.words)
                } else {
                    Button("Create a club", systemImage: "plus") { creating = true }
                }
            }.listRowBackground(theme.surface)
            Section {
                AccountAction(creating ? "Create club" : selectedClub.map { "Join " + $0.club.name } ?? "Join club") { submit() }
                    .disabled(saving || (creating ? newClubName.communityTrimmed.isEmpty || newClubName.communityTrimmed.count > 60 : selectedClub == nil))
                    .accessibilityIdentifier("onboarding-join")
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            status
        }
        .brandListBackground().disabled(saving)
        .navigationTitle("Your first club")
        .navigationBarBackButtonHidden(saving)
    }

    @ViewBuilder private var status: some View {
        if saving { Section { ProgressView("Saving your profile…") }.listRowBackground(theme.surface) }
        if let problem { Section { Text(problem).foregroundStyle(.primary).accessibilityLabel("Profile error. " + problem) }.listRowBackground(theme.surface) }
    }

    private func prepare() {
        if store.completingProfile, name.isEmpty {
            name = store.me.name
            term = store.me.graduationTerm
            year = store.me.graduationYear
            standing = store.me.classStanding
        }
        if !store.isAlumniAccount, !store.completingProfile, selectedClub == nil {
            if let first = availableClubs.first { store.enrollmentClubID = first.id }
            else { creating = true }
        }
    }

    private func submit() {
        guard !saving, profileIsReady, let term, let year else { return }
        saving = true
        problem = nil
        let name = name.communityTrimmed
        let standing = memberKind == .student ? standing : nil
        Task {
            defer { saving = false }
            do {
                if store.isAlumniAccount && !store.completingProfile {
                    try await store.saveAlumniProfile(name: name, graduationTerm: term, graduationYear: year)
                } else if creating && !store.completingProfile {
                    try await store.createFirstClub(newClubName.communityTrimmed, name: name,
                        graduationTerm: term, graduationYear: year, classStanding: standing)
                } else {
                    try await store.join(name: name, graduationTerm: term, graduationYear: year, classStanding: standing)
                }
            } catch { problem = error.localizedDescription }
        }
    }
}
