import SwiftUI

struct WelcomeView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.brandTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var signingIn = false
    let sampleInvitation: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Image("ClubMark").resizable().frame(width: 34, height: 34).accessibilityHidden(true)
                    Text("Club Connect").font(.headline).foregroundStyle(theme.ink)
                }
                Image("Gathering")
                    .resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: typeSize.isAccessibilitySize ? 150 : 236)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 9) {
                    Text("Your campus community")
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Discover USC clubs, meet students and alumni, and keep your event tickets together.")
                        .foregroundStyle(.secondary)
                }
                Button { signingIn = true } label: {
                    Text("Continue with USC email").font(.headline)
                        .foregroundStyle(BrandTheme.label(on: theme.accent))
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("usc-sign-in")
                #if DEBUG
                Button { store.openSample() } label: {
                    Text(sampleInvitation ? "Open sample invitation" : "Explore the sample community")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("explore-demo")
                #endif
            }
            .padding(24).frame(maxWidth: 580)
            .frame(maxWidth: .infinity)
        }
        .background(theme.canvas)
        .sheet(isPresented: $signingIn) { USCSignInView() }
    }
}

private struct USCSignInView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var sent = false
    @State private var busy = false
    @State private var problem: String?
    @State private var sentAt: Date?

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section {
                        Text("Open the sign-in link sent to **\(email)** on this device.")
                        DisclosureGroup("Enter a verification code") {
                            TextField("Six-digit code", text: $code)
                                .textContentType(.oneTimeCode).keyboardType(.numberPad)
                                .onChange(of: code) { _, updated in
                                    code = String(updated.filter { "0123456789".contains($0) }.prefix(6))
                                }
                            Button("Verify email") { verify() }.disabled(code.count != 6)
                        }
                    }
                    Section {
                        TimelineView(.periodic(from: .now, by: 1)) { tick in
                            let seconds = max(0, Int(ceil(60 - tick.date.timeIntervalSince(sentAt ?? .distantPast))))
                            Button(seconds > 0 ? "Resend in \(seconds)s" : "Resend email") { send() }
                                .disabled(seconds > 0)
                        }
                        Button("Use a different address") {
                            sent = false
                            code = ""
                            problem = nil
                        }
                    }
                } else {
                    Section {
                        TextField("name@usc.edu", text: $email)
                            .keyboardType(.emailAddress).textContentType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onSubmit { if PilotAuth.normalizedEmail(email) != nil { send() } }
                    } header: { Text("USC email address") } footer: {
                        Text("We’ll send a sign-in link to verify your USC email.")
                    }
                    Button("Email me a sign-in link") { send() }
                        .disabled(PilotAuth.normalizedEmail(email) == nil)
                }
                if busy { ProgressView("Contacting Club Connect…") }
                if let problem { Text(problem).foregroundStyle(.secondary).accessibilityLabel("Sign-in error. " + problem) }
            }
            .disabled(busy)
            .brandListBackground()
            .navigationTitle(sent ? "Check your email" : "Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func send() {
        guard !busy, let normalized = PilotAuth.normalizedEmail(email) else { return }
        busy = true
        problem = nil
        Task {
            defer { busy = false }
            do {
                try await store.requestCode(email: normalized)
                email = normalized
                code = ""
                sentAt = .now
                sent = true
            } catch { problem = error.localizedDescription }
        }
    }

    private func verify() {
        guard !busy else { return }
        busy = true
        problem = nil
        Task {
            defer { busy = false }
            do { try await store.verifyCode(email: email, code: code) }
            catch { problem = error.localizedDescription }
        }
    }
}

struct EnrollmentView: View {
    @Environment(ClubStore.self) private var store
    @State private var name = ""
    @State private var newClubName = ""
    @State private var createClub = false
    @State private var term: GraduationTerm?
    @State private var year: Int?
    @State private var standing: ClassStanding?
    @State private var saving = false
    @State private var problem: String?

    private var canContinue: Bool {
        guard !saving, !name.communityTrimmed.isEmpty, let term, let year,
              GraduationTerm.validYears.contains(year), term.kind(year: year) == .alumni || standing != nil else { return false }
        if store.completingProfile { return true }
        if createClub { return !newClubName.communityTrimmed.isEmpty }
        return store.catalog.contains { $0.club.id == store.enrollmentClubID && $0.canJoin }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Your name", text: $name).textContentType(.name).textInputAutocapitalization(.words)
                }
                GraduationFields(term: $term, year: $year, standing: $standing)
                if !store.completingProfile {
                    Section("Your first club") {
                        Picker("Club", selection: Binding(get: { createClub ? "create:" : store.enrollmentClubID }, set: { selected in
                            createClub = selected == "create:"
                            if !createClub { store.enrollmentClubID = selected }
                        })) {
                            ForEach(store.catalog.filter(\.canJoin), id: \.club.id) { listing in
                                Text(listing.club.name).tag(listing.club.id)
                            }
                            Text("Create a club").tag("create:")
                        }
                        if createClub { TextField("Club name", text: $newClubName).textInputAutocapitalization(.words) }
                    }
                }
                Section {
                    Button(store.completingProfile ? "Save profile" : createClub ? "Create club" : "Join club") { submit() }
                        .disabled(!canContinue)
                    if saving { ProgressView() }
                    if let problem { Text(problem).font(.footnote).foregroundStyle(.secondary) }
                } footer: { Text("Your name and profile details are visible to members of the clubs you join.") }
            }
            .brandListBackground()
            .disabled(saving)
            .navigationTitle(store.completingProfile ? "Complete your profile" : "Join Club Connect")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Sign out") { Task { do { try await store.leaveSession() } catch { problem = error.localizedDescription } } }
                    .disabled(saving)
            } }
            .onAppear {
                if store.completingProfile {
                    name = store.me.name
                    term = store.me.graduationTerm
                    year = store.me.graduationYear
                    standing = store.me.classStanding
                } else if let first = store.catalog.first(where: \.canJoin) {
                    if !store.catalog.contains(where: { $0.canJoin && $0.club.id == store.enrollmentClubID }) {
                        store.enrollmentClubID = first.club.id
                    }
                } else { createClub = true }
            }
        }
    }

    private func submit() {
        guard canContinue, let term, let year else { return }
        saving = true
        problem = nil
        let standing = term.kind(year: year) == .student ? standing : nil
        Task {
            defer { saving = false }
            do {
                if createClub && !store.completingProfile {
                    try await store.createFirstClub(newClubName.communityTrimmed, name: name.communityTrimmed, graduationTerm: term, graduationYear: year, classStanding: standing)
                } else {
                    try await store.join(name: name.communityTrimmed, graduationTerm: term, graduationYear: year, classStanding: standing)
                }
            } catch { problem = error.localizedDescription }
        }
    }
}
