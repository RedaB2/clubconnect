import AuthenticationServices
import SwiftUI

@main
struct ClubConnectApp: App {
    @State private var store = ClubStore()

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environment(store)
                .tint(store.club.accent)
        }
    }
}

private enum Destination: Hashable { case events, people, club, profile }

private struct Invitation: Equatable {
    var event: String?
    var sample: Bool
    init?(_ url: URL) {
        guard url.scheme == "clubconnect", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let path = url.lastPathComponent
        switch url.host {
        case "join" where path == "menasa": event = nil
        case "event":
            guard let uuid = UUID(uuidString: path) else { return nil }
            event = uuid.uuidString.lowercased()
        default: return nil
        }
        sample = components.queryItems?.contains(.init(name: "sample", value: "1")) ?? false
    }
}

private struct EventLink: Identifiable { let id: String }

private struct AppRoot: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var tab = Destination.events
    @State private var route: Invitation?
    @State private var linkedEvent: EventLink?
    @State private var switchCommunity = false

    var body: some View {
        Group {
            switch store.phase {
            case .loading: ProgressView("Opening Club Connect…")
            case .welcome: WelcomeView(sampleInvitation: route?.sample == true)
            case .enrollment: EnrollmentView()
            case .community: tabs
            case .reconnect:
                ContentUnavailableView {
                    Label("Couldn’t load your club", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Try again") { Task { await store.loadMembership() } }
                    Button("Sign out") { Task { try? await store.leaveSession() } }
                }
            }
        }
        .task { await store.start(); followLink() }
        .onChange(of: store.phase) { _, phase in
            if phase != .community { tab = .events; linkedEvent = nil }
            followLink()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, store.phase == .community { Task { await store.refresh() } }
        }
        .onOpenURL { url in
            guard let link = Invitation(url) else { return }
            route = link
            Task { await store.refresh(); followLink() }
        }
        .sheet(item: $linkedEvent) { item in
            NavigationStack {
                EventDetailView(eventID: item.id)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { linkedEvent = nil } } }
            }
        }
        .confirmationDialog("Open the shared community?", isPresented: $switchCommunity, titleVisibility: .visible) {
            Button(store.isPreview ? "Leave sample and sign in" : "Open sample community") {
                Task {
                    if store.isPreview { try? await store.leaveSession() }
                    else { store.openSample(); followLink() }
                }
            }
            Button("Cancel", role: .cancel) { route = nil }
        }
        .alert("Club Connect", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("OK") { store.notice = nil }
        } message: { Text(store.notice ?? "") }
        .alert("Account deleted", isPresented: Binding(get: { store.showAccountDeleted }, set: { store.showAccountDeleted = $0 })) {
            Button("Apple’s instructions") { openURL(URL(string: "https://support.apple.com/en-us/102571")!) }
            Button("Done", role: .cancel) {}
        } message: {
            Text("Your Club Connect profile and registrations have been deleted. You can also remove Club Connect from Sign in with Apple in Settings.")
        }
    }

    @ViewBuilder private var tabs: some View {
        if #available(iOS 18, *) {
            TabView(selection: $tab) {
                Tab("Events", systemImage: "calendar", value: .events) { EventsView() }
                Tab("People", systemImage: "person.2", value: .people) { PeopleView() }
                Tab("Club", systemImage: "building.columns", value: .club) { ClubView() }
                Tab("Profile", systemImage: "person.crop.circle", value: .profile) { MyProfileView() }
            }.tabViewStyle(.sidebarAdaptable)
        } else {
            TabView(selection: $tab) {
                EventsView().tabItem { Label("Events", systemImage: "calendar") }.tag(Destination.events)
                PeopleView().tabItem { Label("People", systemImage: "person.2") }.tag(Destination.people)
                ClubView().tabItem { Label("Club", systemImage: "building.columns") }.tag(Destination.club)
                MyProfileView().tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(Destination.profile)
            }
        }
    }

    private func followLink() {
        guard let route, store.phase == .community else { return }
        if route.sample != store.isPreview {
            switchCommunity = true
            return
        }
        self.route = nil
        if let id = route.event {
            tab = .events
            linkedEvent = EventLink(id: id)
        } else {
            tab = .club
        }
    }
}

private struct WelcomeView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var nonce: String?
    @State private var busy = false
    let sampleInvitation: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image("ClubMark").resizable().frame(width: 34, height: 34).accessibilityHidden(true)
                    Text("Club Connect").font(.headline)
                }
                .padding(.top, 10)
                Image("Gathering")
                    .resizable().scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: typeSize.isAccessibilitySize ? 152 : 244)
                    .clipped().clipShape(RoundedRectangle(cornerRadius: 22))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Welcome to MENASA")
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Middle Eastern and North African Association")
                        .font(.headline).foregroundStyle(store.club.accent)
                    Text("See what’s happening on campus, meet students and alumni, and keep your event tickets together.")
                        .font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 8) {
                    SignInWithAppleButton(.continue) { request in
                        let raw = PilotAuth.nonce()
                        nonce = raw
                        request.requestedScopes = [.fullName]
                        request.nonce = PilotAuth.hash(raw)
                    } onCompletion: { result in
                        defer { nonce = nil }
                        do {
                            let authorization = try result.get()
                            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                                  let raw = nonce else { throw ClubFailure("Please try signing in again.") }
                            busy = true
                            Task {
                                defer { busy = false }
                                do { try await store.signIn(credential, rawNonce: raw) }
                                catch { store.notice = error.localizedDescription }
                            }
                        } catch let error as ASAuthorizationError where error.code == .canceled {
                            return
                        } catch { store.notice = error.localizedDescription }
                    }
                    .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .accessibilityLabel("Continue with Apple")
                    Button { store.openSample() } label: {
                        Text(sampleInvitation ? "Open sample invitation" : "Explore the sample community")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("explore-demo")
                    if busy { ProgressView() }
                }.disabled(busy)
            }
            .padding(24).frame(maxWidth: 580)
            .frame(maxWidth: .infinity)
        }.background(Color(uiColor: .systemBackground))
    }
}

private struct EnrollmentView: View {
    @Environment(ClubStore.self) private var store
    @State private var name = ""
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $name).textContentType(.name).textInputAutocapitalization(.words)
                } footer: { Text("Your name and the profile details you add will be visible to other MENASA members.") }
                Button("Join MENASA") {
                    saving = true
                    Task {
                        defer { saving = false }
                        do { try await store.join(name: name.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        catch { store.notice = error.localizedDescription }
                    }
                }.disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("Join MENASA")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { Task { try? await store.leaveSession() } }.disabled(saving) } }
            .onAppear { if name.isEmpty { name = store.suggestedName } }
        }
    }
}
