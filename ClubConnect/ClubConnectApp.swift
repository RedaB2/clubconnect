import SwiftUI

@main
struct ClubConnectApp: App {
    @State private var store = ClubStore()

    init() {
        let defaults = UserDefaults.standard
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ClubConnectResetIntroduction") {
            defaults.set(false, forKey: introductionCompletedKey)
            defaults.removeObject(forKey: "clubconnect.incoming-link")
            return
        }
        if arguments.contains("-ClubConnectFreshDemo") {
            defaults.set(true, forKey: introductionCompletedKey)
            return
        }
        #endif
        // Previous builds saved the active club even after the member signed out.
        if defaults.object(forKey: introductionCompletedKey) == nil,
           defaults.string(forKey: "clubconnect.active-club") != nil {
            defaults.set(true, forKey: introductionCompletedKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environment(store)
                .brandScope()
        }
    }
}

private let introductionCompletedKey = "clubconnect.introduction-completed"

private enum Destination: Hashable { case events, people, club, messages, profile }

private struct Invitation: Equatable {
    var event: String?
    var clubID: String
    var sample: Bool
    var alumni: Bool
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
        alumni = url.host == "join" && !sample && components.queryItems?.contains(.init(name: "alumni", value: "1")) == true
    }

    var savedLink: String {
        if let event { return "clubconnect://event/\(event)?club=\(clubID)" + (sample ? "&sample=1" : "") }
        return "clubconnect://join/\(clubID)" + (alumni ? "?alumni=1" : sample ? "?sample=1" : "")
    }
}

private struct EventLink: Identifiable { let id: String }

private struct AppRoot: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = Destination.events
    @State private var showingLaunch = true
    @AppStorage(introductionCompletedKey) private var didFinishIntroduction = false
    // Email verification may relaunch the app. Persist only the validated club/event route.
    @AppStorage("clubconnect.incoming-link") private var pendingLink = ""
    private var route: Invitation? { URL(string: pendingLink).flatMap(Invitation.init) }
    @State private var awaitingFirstMembership = false
    @State private var linkedEvent: EventLink?
    @State private var linkedClubID: String?
    @State private var eventsListID = UUID()
    @State private var switchCommunity = false
    @State private var joinInvitation: ClubListing?
    @State private var alumniRequestTarget: ClubListing?
    @State private var linkedApplicationID: String?
    @State private var presentedApplicationLink: String?

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .loading: ProgressView("Opening Club Connect…")
        case .welcome:
            if !didFinishIntroduction && route == nil {
                FirstRunIntroduction { didFinishIntroduction = true }
            } else {
                WelcomeView(sampleInvitation: route?.sample == true, alumniInvitation: route?.alumni == true,
                            invitedClubName: route.flatMap { link in
                                store.catalog.first { $0.id == link.clubID }?.club.name ?? (link.clubID == "menasa" ? "MENASA" : nil)
                            })
            }
        case .enrollment: EnrollmentView()
        case .alumniClubs: AlumniMembershipView(linkedClub: $linkedApplicationID)
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

    var body: some View {
        ZStack {
            content
            if showingLaunch { LaunchAppearance { showingLaunch = false } }
        }
        .task {
            if route != nil { didFinishIntroduction = true }
            await store.start()
            followLink()
        }
        .onChange(of: store.phase) { _, phase in
            if phase == .enrollment || phase == .alumniClubs || phase == .community || phase == .reconnect {
                didFinishIntroduction = true
            }
            if phase == .enrollment || phase == .alumniClubs { awaitingFirstMembership = true }
            if phase == .welcome { awaitingFirstMembership = false; linkedApplicationID = nil }
            if phase != .community {
                tab = .events; linkedEvent = nil; linkedClubID = nil; alumniRequestTarget = nil; joinInvitation = nil
            } else if awaitingFirstMembership {
                awaitingFirstMembership = false
                if route == nil {
                    linkedClubID = store.club.id
                    tab = .club
                }
            }
            followLink()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, store.phase == .community { Task { await store.refresh() } }
        }
        .onOpenURL { url in
            if url.scheme == "clubconnect", url.host == "auth", url.path == "/callback" {
                didFinishIntroduction = true
                showingLaunch = false
                Task {
                    do { try await store.verifyEmailLink(url) }
                    catch { store.notice = error.localizedDescription }
                }
                return
            }
            guard let link = Invitation(url) else { return }
            didFinishIntroduction = true
            showingLaunch = false
            pendingLink = link.savedLink
            presentedApplicationLink = nil
            Task {
                if store.phase == .alumniClubs && !store.catalog.contains(where: { $0.id == link.clubID }) {
                    await store.loadMembership()
                } else if store.phase == .community {
                    await store.refresh()
                }
                followLink()
            }
        }
        .sheet(item: $linkedEvent) { item in
            NavigationStack {
                EventDetailView(eventID: item.id)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { linkedEvent = nil } } }
            }
            .brandScope(store.club)
        }
        .confirmationDialog("Open the shared community?", isPresented: $switchCommunity, titleVisibility: .visible) {
            Button(store.isPreview ? "Leave sample and sign in" : "Open sample community") {
                Task {
                    if store.isPreview { try? await store.leaveSession() }
                    else { store.openSample(); followLink() }
                }
            }
            Button("Cancel", role: .cancel) { pendingLink = "" }
        }
        .sheet(item: $alumniRequestTarget) { target in
            AlumniApplicationSheet(club: target.club) {}
        }
        .alert("Join " + (joinInvitation?.club.name ?? "club") + "?", isPresented: Binding(
            get: { joinInvitation != nil }, set: { if !$0 { joinInvitation = nil } }
        ), presenting: joinInvitation) { listing in
            Button("Join club") {
                Task {
                    do { try await store.joinAdditionalClub(listing.id); followLink() }
                    catch { pendingLink = ""; store.notice = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) { pendingLink = "" }
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
                Tab("Events", systemImage: "calendar", value: .events) { clubEvents }
                Tab("People", systemImage: "person.2", value: .people) { clubPeople }
                Tab("Clubs", systemImage: "building.columns", value: .club) { campusClubs }
                Tab("Messages", systemImage: "bubble.left.and.bubble.right", value: .messages) { clubMessages }
                Tab("Profile", systemImage: "person.crop.circle", value: .profile) { MyProfileView() }
            }.tabViewStyle(.sidebarAdaptable)
        } else {
            TabView(selection: $tab) {
                clubEvents.tabItem { Label("Events", systemImage: "calendar") }.tag(Destination.events)
                clubPeople.tabItem { Label("People", systemImage: "person.2") }.tag(Destination.people)
                campusClubs.tabItem { Label("Clubs", systemImage: "building.columns") }.tag(Destination.club)
                clubMessages.tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }.tag(Destination.messages)
                MyProfileView().tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(Destination.profile)
            }
        }
    }

    private var clubEvents: some View { EventsView().brandScope(store.club).id(store.club.id).id(eventsListID) }
    private var clubPeople: some View { PeopleView().brandScope(store.club).id(store.club.id) }
    private var clubMessages: some View { MessagesView().brandScope(store.club).id(store.club.id) }
    private var campusClubs: some View {
        ClubView(invitedClub: $linkedClubID) {
            eventsListID = UUID()
            tab = .events
        }
    }

    private func followLink() {
        guard let route else { return }
        if store.phase == .alumniClubs, !route.sample {
            if store.catalog.contains(where: { $0.id == route.clubID }) {
                store.enrollmentClubID = route.clubID
                if presentedApplicationLink != route.savedLink {
                    linkedApplicationID = route.clubID
                    presentedApplicationLink = route.savedLink
                }
            } else {
                pendingLink = ""
                store.notice = "This club is unavailable."
            }
            // A club link selects a club to apply to. It is never a membership credential.
            if route.event == nil { pendingLink = "" }
            return
        }
        if store.phase == .enrollment, !store.completingProfile,
           store.catalog.contains(where: { $0.id == route.clubID && ($0.canJoin || store.isAlumniAccount) }) {
            store.enrollmentClubID = route.clubID
        }
        guard store.phase == .community else { return }
        if route.sample != store.isPreview {
            switchCommunity = true
            return
        }
        if route.clubID != store.club.id {
            guard let target = store.catalog.first(where: { $0.id == route.clubID }) else {
                pendingLink = ""
                store.notice = "This club is unavailable."
                return
            }
            if !target.joined {
                if store.isAlumniAccount {
                    pendingLink = ""
                    alumniRequestTarget = target
                } else if target.canJoin {
                    joinInvitation = target
                } else {
                    pendingLink = ""
                    store.notice = "This club is unavailable."
                }
                return
            }
            Task {
                do { try await store.selectClub(target.id); followLink() }
                catch { pendingLink = ""; store.notice = error.localizedDescription }
            }
            return
        }
        pendingLink = ""
        if let id = route.event {
            tab = .events
            linkedEvent = EventLink(id: id)
        } else {
            linkedClubID = route.clubID
            tab = .club
        }
    }
}
