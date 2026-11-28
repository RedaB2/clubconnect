import SwiftUI

struct WelcomeView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.brandTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 43
    @State private var entry: AccountEntry?
    let sampleInvitation: Bool
    var alumniInvitation = false
    var invitedClubName: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Image("ClubMark").resizable().frame(width: 30, height: 30).accessibilityHidden(true)
                        Text("Club Connect").font(.headline)
                        Spacer()
                        Button { entry = .returning } label: {
                            Text("Sign in").padding(.horizontal, 3)
                        }.buttonStyle(.bordered)
                            .frame(minHeight: 44)
                            .buttonBorderShape(.capsule)
                            .accessibilityIdentifier("returning-sign-in")
                    }
                    .padding(.horizontal, 22).padding(.vertical, 14)

                    Image("CampusWelcome")
                        .resizable().scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: typeSize.isAccessibilitySize ? 155 : 265)
                        .clipped().accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(invitedClubName.map { "Join " + $0 } ?? "Find your people at USC.")
                            .font(.system(size: headlineSize, weight: .semibold, design: .serif))
                            .tracking(-0.9).fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("Meet the students and alumni in your clubs, and see what’s coming up on campus.")
                            .font(.body).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24).padding(.top, 27)

                    VStack(spacing: 8) {
                        AccountAction("Join with USC email", systemImage: "arrow.right") { entry = .campus }
                            .accessibilityIdentifier("usc-sign-in")
                        Button("Join as an alum") { entry = .alumni }
                            .font(.headline).frame(minHeight: 44).accessibilityIdentifier("alumni-sign-up")
                        #if DEBUG
                        Button(sampleInvitation ? "Open sample invitation" : "Explore the sample community") {
                            store.openSample()
                        }
                        .frame(minHeight: 44).accessibilityIdentifier("explore-demo")
                        #endif
                    }.padding(24)
                }.frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
            }
            .background(theme.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $entry) { kind in
                EmailEntryView(kind: kind, clubName: invitedClubName)
            }
            .onChange(of: alumniInvitation, initial: true) { _, invited in
                if invited { entry = .alumni }
            }
        }
    }
}

enum AccountEntry: Hashable {
    case campus, returning, alumni
}

struct AccountAction: View {
    @Environment(\.brandTheme) private var theme
    let title: String
    let systemImage: String?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).fontWeight(.semibold)
                if let systemImage { Image(systemName: systemImage).imageScale(.small).accessibilityHidden(true) }
            }.frame(maxWidth: .infinity, minHeight: 29)
                .foregroundStyle(BrandTheme.label(on: theme.accent))
        }
        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
    }
}

private struct EmailEntryView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.brandTheme) private var theme
    let kind: AccountEntry
    let clubName: String?
    @State private var email = ""
    @State private var code = ""
    @State private var awaitingVerification = false
    @State private var busy = false
    @State private var problem: String?
    @State private var sentAt: Date?
    @FocusState private var focused: Field?

    private enum Field { case email, code }

    private var normalized: String? {
        guard let address = PilotAuth.normalizedEmail(email) else { return nil }
        switch kind {
        case .campus: return address.hasSuffix("@usc.edu") ? address : nil
        case .alumni: return address.hasSuffix("@usc.edu") ? nil : address
        case .returning: return address
        }
    }

    private var title: String {
        if awaitingVerification { return "Check your email" }
        switch kind {
        case .campus: return "Verify your USC email"
        case .returning: return "Welcome back"
        case .alumni: return "Reconnect with your club"
        }
    }

    private var instruction: String {
        if awaitingVerification { return "Open the link on this device, or enter the six-digit code from the same email." }
        switch kind {
        case .campus: return "Use your USC address to join your campus community."
        case .returning: return "Use the email address you signed up with."
        case .alumni:
            if let clubName { return "Verify your personal email to create an alumni profile and request to join " + clubName + "." }
            return "Verify your personal email to create an alumni profile and find your former USC club."
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: awaitingVerification ? "envelope.open" : kind == .alumni ? "envelope.badge.person.crop" : "envelope")
                    .font(.title2).foregroundStyle(theme.accent).padding(14)
                    .background(theme.wash, in: RoundedRectangle(cornerRadius: 15))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.system(.largeTitle, design: .serif, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    if awaitingVerification { Text(email).font(.headline).textSelection(.enabled) }
                    Text(instruction).foregroundStyle(.secondary)
                }
                if awaitingVerification { codeEntry } else { emailEntry }
                if busy { ProgressView("Contacting Club Connect…") }
                if let problem { Text(problem).font(.callout).foregroundStyle(.primary).accessibilityLabel("Sign-in error. " + problem) }
            }
            .padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.canvas)
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle("Club Connect").navigationBarTitleDisplayMode(.inline)
    }

    private var emailEntry: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kind == .campus ? "USC email address" : kind == .alumni ? "Personal email address" : "Email address").font(.headline)
            TextField(kind == .campus ? "name@usc.edu" : "Your email address", text: $email)
                .keyboardType(.emailAddress).textContentType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder).controlSize(.large)
                .focused($focused, equals: .email).submitLabel(.go)
                .onSubmit { send() }.disabled(busy)
                .accessibilityIdentifier("account-email")
            AccountAction("Email me a sign-in link") { send() }.disabled(normalized == nil || busy)
            if normalized != nil {
                Button("I already have a code") {
                    email = normalized ?? email
                    awaitingVerification = true
                    focused = .code
                    problem = nil
                }.frame(minHeight: 44).disabled(busy)
            }
        }
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Verification code").font(.headline)
            TextField("Six-digit code", text: $code)
                .textContentType(.oneTimeCode).keyboardType(.numberPad)
                .font(.title2.monospacedDigit()).textFieldStyle(.roundedBorder)
                .focused($focused, equals: .code).disabled(busy)
                .onChange(of: code) { _, value in
                    let digits = String(value.filter { "0123456789".contains($0) }.prefix(6))
                    if digits != value { code = digits }
                }
                .accessibilityIdentifier("account-otp")
            AccountAction("Verify email") { verify() }.disabled(code.count != 6 || busy)
            TimelineView(.periodic(from: .now, by: 1)) { tick in
                let seconds = max(0, Int(ceil(60 - tick.date.timeIntervalSince(sentAt ?? .distantPast))))
                Button(seconds > 0 ? "Resend in \(seconds)s" : "Resend email") { send() }
                    .frame(minHeight: 44).disabled(seconds > 0 || busy)
            }
            Button("Use a different address") {
                awaitingVerification = false
                code = ""
                problem = nil
                focused = .email
            }.frame(minHeight: 44).disabled(busy)
        }
    }

    private func send() {
        guard !busy, let normalized else { return }
        busy = true
        problem = nil
        focused = nil
        Task {
            defer { busy = false }
            do {
                try await store.requestCode(email: normalized)
                email = normalized
                code = ""
                sentAt = .now
                awaitingVerification = true
            } catch { problem = error.localizedDescription }
        }
    }

    private func verify() {
        guard !busy, code.count == 6 else { return }
        busy = true
        problem = nil
        focused = nil
        Task {
            defer { busy = false }
            do { try await store.verifyCode(email: email, code: code) }
            catch { problem = error.localizedDescription }
        }
    }
}
