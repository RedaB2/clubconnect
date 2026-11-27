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

private enum Destination: Hashable { case events, people, club, messages, profile }

private struct Invitation: Equatable {
    var event: String?
    var clubID: String
    var sample: Bool
    init?(_ url: URL) {
        guard url.scheme == "clubconnect", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let path = url.lastPathComponent
        switch url.host {
        case "join": clubID = path; event = nil
        case "event":
            guard let uuid = UUID(uuidString: path) else { return nil }
            event = uuid.uuidString.lowercased()
            clubID = components.queryItems?.first(where: { $0.name == "club" })?.value ?? "menasa"
        default: return nil
        }
        guard clubID == "menasa" || UUID(uuidString: clubID) != nil else { return nil }
        clubID = clubID.lowercased()
        sample = components.queryItems?.contains(.init(name: "sample", value: "1")) ?? false
    }
}

private struct EventLink: Identifiable { let id: String }

private struct AppRoot: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = Destination.events
    @State private var route: Invitation?
    @State private var linkedEvent: EventLink?
    @State private var switchCommunity = false
    @State private var joinInvitation: ClubListing?

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
            if url.scheme == "clubconnect", url.host == "auth", url.path == "/callback" {
                Task {
                    do { try await store.verifyEmailLink(url) }
                    catch { store.notice = error.localizedDescription }
                }
                return
            }
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
        .alert("Join " + (joinInvitation?.club.name ?? "club") + "?", isPresented: Binding(
            get: { joinInvitation != nil }, set: { if !$0 { joinInvitation = nil } }
        ), presenting: joinInvitation) { listing in
            Button("Join club") {
                Task {
                    do { try await store.joinAdditionalClub(listing.id); followLink() }
                    catch { route = nil; store.notice = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) { route = nil }
        } message: { _ in Text("Joining makes your profile visible to the other members.") }
        .alert("Club Connect", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("OK") { store.notice = nil }
        } message: { Text(store.notice ?? "") }
        .alert("Account deleted", isPresented: Binding(get: { store.showAccountDeleted }, set: { store.showAccountDeleted = $0 })) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("Your Club Connect profile and registrations have been deleted.")
        }
    }

    @ViewBuilder private var tabs: some View {
        if #available(iOS 18, *) {
            TabView(selection: $tab) {
                Tab("Events", systemImage: "calendar", value: .events) { EventsView().id(store.club.id) }
                Tab("People", systemImage: "person.2", value: .people) { PeopleView().id(store.club.id) }
                Tab("Clubs", systemImage: "building.columns", value: .club) { ClubView() }
                Tab("Messages", systemImage: "bubble.left.and.bubble.right", value: .messages) { MessagesView().id(store.club.id) }
                Tab("Profile", systemImage: "person.crop.circle", value: .profile) { MyProfileView() }
            }.tabViewStyle(.sidebarAdaptable)
        } else {
            TabView(selection: $tab) {
                EventsView().id(store.club.id).tabItem { Label("Events", systemImage: "calendar") }.tag(Destination.events)
                PeopleView().id(store.club.id).tabItem { Label("People", systemImage: "person.2") }.tag(Destination.people)
                ClubView().tabItem { Label("Clubs", systemImage: "building.columns") }.tag(Destination.club)
                MessagesView().id(store.club.id).tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }.tag(Destination.messages)
                MyProfileView().tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(Destination.profile)
            }
        }
    }

    private func followLink() {
        guard let route else { return }
        if store.phase == .enrollment, !store.completingProfile,
           store.catalog.contains(where: { $0.id == route.clubID && $0.canJoin }) {
            store.enrollmentClubID = route.clubID
        }
        guard store.phase == .community else { return }
        if route.sample != store.isPreview {
            switchCommunity = true
            return
        }
        if route.clubID != store.club.id {
            guard let target = store.catalog.first(where: { $0.id == route.clubID }) else {
                self.route = nil
                store.notice = "This club is unavailable."
                return
            }
            if !target.joined {
                joinInvitation = target
                return
            }
            Task {
                do { try await store.selectClub(target.id); followLink() }
                catch { self.route = nil; store.notice = error.localizedDescription }
            }
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
