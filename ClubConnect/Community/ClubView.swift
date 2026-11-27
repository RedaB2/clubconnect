import SwiftUI

struct ActiveClubMenu: View {
    @Environment(ClubStore.self) private var store
    var body: some View {
        Menu {
            ForEach(store.catalog.filter(\.joined)) { entry in
                Button {
                    Task { do { try await store.selectClub(entry.id) } catch { store.notice = error.localizedDescription } }
                } label: {
                    if entry.id == store.club.id { Label(entry.club.name, systemImage: "checkmark") }
                    else { Text(entry.club.name) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(store.club.name).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }.frame(maxWidth: 150)
        }
        .accessibilityLabel("Switch club, " + store.club.name)
    }
}

private enum ClubRoute: Hashable {
    case club(String)
    case event(club: String, event: String)

    var clubID: String {
        switch self {
        case .club(let id), .event(let id, _): id
        }
    }
}

struct ClubView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.brandTheme) private var theme
    @Binding var invitedClub: String?
    let onShowEvents: () -> Void
    @State private var query = ""
    @State private var path: [ClubRoute] = []
    @State private var creating = false
    @State private var joining: ClubListing?
    @State private var busy = false

    init(invitedClub: Binding<String?>, onShowEvents: @escaping () -> Void) {
        _invitedClub = invitedClub
        self.onShowEvents = onShowEvents
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                let matches = store.catalog.filter { query.isEmpty || $0.club.name.localizedStandardContains(query) || $0.club.fullName.localizedStandardContains(query) }
                let memberships = matches.filter(\.joined)
                let available = matches.filter { !$0.joined && $0.canJoin }
                if memberships.isEmpty && available.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                }
                if !memberships.isEmpty {
                    Section("My clubs") {
                        ForEach(memberships) { entry in
                            Button {
                                perform {
                                    try await store.selectClub(entry.id)
                                    path = [.club(entry.id)]
                                }
                            } label: { clubRow(entry, joined: true) }
                            .accessibilityIdentifier("select-club-" + entry.id)
                        }
                    }
                }
                if !available.isEmpty {
                    Section("Discover clubs") {
                        ForEach(available) { entry in
                            Button { joining = entry } label: { clubRow(entry, joined: false) }
                                .accessibilityIdentifier("discover-club-" + entry.id)
                        }
                    }
                }
                if !store.isPreview {
                    Section {
                        Button("Explore the sample community") { store.openSample() }
                    }
                }
            }
            .disabled(busy)
            .navigationTitle("Campus clubs")
            .brandListBackground()
            .searchable(text: $query, prompt: "Find a club")
            .refreshable { await store.refresh() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { creating = true } label: { Label("Create a club", systemImage: "plus") }
                }
            }
            .navigationDestination(for: ClubRoute.self) { route in
                if route.clubID == store.club.id {
                    switch route {
                    case .club(let id):
                        CurrentClubView(onShowEvents: onShowEvents) { eventID in path.append(.event(club: id, event: eventID)) }
                            .id(id)
                            .brandScope(store.club)
                    case .event(_, let eventID):
                        EventDetailView(eventID: eventID)
                            .brandScope(store.club)
                    }
                }
            }
            .sheet(isPresented: $creating) { CreateClubView { path = [.club(store.club.id)] } }
            .sheet(item: $joining) { entry in
                NavigationStack {
                    List {
                        Section { ClubIdentity(club: entry.club) }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                        if !entry.club.about.isEmpty { Section("About") { Text(entry.club.about) } }
                        Button("Join " + entry.club.name) {
                            perform {
                                try await store.joinAdditionalClub(entry.id)
                                joining = nil
                                path = [.club(entry.id)]
                            }
                        }.disabled(busy)
                    }
                    .navigationTitle("Join club").navigationBarTitleDisplayMode(.inline)
                    .brandListBackground()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { joining = nil } } }
                }
                .brandScope(entry.club)
            }
        }
        .onChange(of: invitedClub, initial: true) { _, _ in openInvitation() }
        .onChange(of: store.club.id, initial: true) { _, clubID in
            if invitedClub == clubID {
                openInvitation()
            } else if let route = path.first, route.clubID != clubID {
                // A switch from another tab discards the previous club’s pushed event.
                path = [.club(clubID)]
            }
        }
    }

    private func openInvitation() {
        guard let invitedClub, invitedClub == store.club.id else { return }
        path = [.club(invitedClub)]
        self.invitedClub = nil
    }

    private func clubRow(_ entry: ClubListing, joined: Bool) -> some View {
        HStack(spacing: 12) {
            ClubBadge(club: entry.club, side: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.club.name).font(.headline).foregroundStyle(theme.ink)
                if joined { Text(entry.isAdmin ? "Organizer" : "Member").font(.subheadline).foregroundStyle(theme.ink.opacity(0.74)) }
                else if entry.club.fullName != entry.club.name { Text(entry.club.fullName).font(.subheadline).foregroundStyle(theme.ink.opacity(0.74)) }
            }
            Spacer()
            if entry.id == store.club.id { Image(systemName: "checkmark.circle.fill").accessibilityLabel("Active club") }
            else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true) }
        }.frame(minHeight: 44)
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await action() }
            catch { store.notice = error.localizedDescription }
        }
    }
}

private struct CreateClubView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var saving = false
    @State private var problem: String?
    var onCreated: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Club name", text: $name).textInputAutocapitalization(.words) }
                footer: { Text("You’ll be the first organizer. You can set your club’s logo, colors, and description next.") }
                if let problem { Text(problem).foregroundStyle(.red) }
            }
            .brandListBackground()
            .navigationTitle("Create a club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        saving = true
                        Task {
                            defer { saving = false }
                            do { try await store.createClub(name: name.communityTrimmed); dismiss(); onCreated() }
                            catch { problem = error.localizedDescription }
                        }
                    }.disabled(saving || !(1...60).contains(name.communityTrimmed.count))
                }
            }
        }.interactiveDismissDisabled(saving)
    }
}

private struct CurrentClubView: View {
    @Environment(ClubStore.self) private var store
    @State private var editing = false
    @State private var steppingDown = false
    @State private var creatingEvent = false
    var onShowEvents: () -> Void
    var openEvent: (String) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { clock in
            clubPage(at: clock.date)
        }
        .navigationTitle(store.club.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.isAdmin {
                ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true }.accessibilityLabel("Edit club") }
            }
        }
        .sheet(isPresented: $editing) { ClubEditor(club: store.club) }
        .sheet(isPresented: $steppingDown) { StepDownView() }
        .sheet(isPresented: $creatingEvent) { EventEditorView(event: nil, onSave: openEvent) }
    }

    private func clubPage(at now: Date) -> some View {
        let upcoming = store.upcomingEvents(at: now)
        return List {
            Section { ClubIdentity(club: store.club) }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("Upcoming events") {
                if upcoming.isEmpty {
                    Text("No upcoming events")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("club-events-empty")
                } else {
                    ForEach(upcoming.prefix(3)) { event in
                        NavigationLink(value: ClubRoute.event(club: store.club.id, event: event.id)) {
                            ClubEventRow(event: event)
                        }
                        .accessibilityIdentifier("club-event-" + event.id)
                    }
                    if upcoming.count > 3 {
                        Button("See all upcoming events", action: onShowEvents)
                            .accessibilityIdentifier("club-all-upcoming")
                    }
                }
                if store.isAdmin {
                    Button { creatingEvent = true } label: { Label("Create event", systemImage: "calendar.badge.plus") }
                        .accessibilityIdentifier("club-create-event")
                }
            }

            if store.hasOrganizerRole {
                Section {
                    Toggle("View as a member", isOn: Binding(get: { store.viewingAsMember }, set: { store.setMemberView($0) }))
                        .accessibilityIdentifier("member-view-toggle")
                    if !store.viewingAsMember {
                        Button("Step down as organizer") { steppingDown = true }
                    }
                } header: { Text("Your role") } footer: {
                    Text("Member view hides the organizer tools for this club. You can switch back here.")
                }
            }
            if !store.club.about.isEmpty { Section("About the club") { Text(store.club.about).textSelection(.enabled) } }
            Section("Community") {
                LabeledContent("Students", value: String(store.members.filter { $0.effectiveKind() == .student }.count))
                LabeledContent("Alumni", value: String(store.members.filter { $0.effectiveKind() == .alumni }.count))
                if !store.isPreview || store.club.id == "menasa" {
                    ShareLink(item: store.inviteURL, subject: Text("Join " + store.club.name), message: Text("Meet us on Club Connect.")) {
                        Label("Invite a friend", systemImage: "person.badge.plus")
                    }.accessibilityIdentifier("share-club-invite")
                }
            }
        }
        .brandListBackground()
        .refreshable { await store.refresh() }
    }
}

private struct ClubEventRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.brandTheme) private var theme
    let event: ClubEvent

    var body: some View {
        HStack(spacing: 12) {
            if !typeSize.isAccessibilitySize {
                EventDateTile(date: event.startsAt)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.headline).foregroundStyle(theme.ink)
                Text(event.location).font(.subheadline).foregroundStyle(theme.ink.opacity(0.76))
                Text(event.startsAt.formatted(date: typeSize.isAccessibilitySize ? .abbreviated : .omitted, time: .shortened))
                    .font(.caption).foregroundStyle(theme.ink.opacity(0.76))
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

private struct StepDownView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var successor: String?
    @State private var confirming = false
    @State private var saving = false
    @State private var problem: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Hand off to", selection: $successor) {
                        Text("An existing organizer").tag(nil as String?)
                        ForEach(store.members.filter { $0.id != store.me.id }) { m in Text(m.name).tag(Optional(m.id)) }
                    }
                } footer: { Text("You’ll stay a member. If you’re the last organizer, choose another member to take over.") }
                if let problem { Text(problem).foregroundStyle(.red) }
                Button("Step down", role: .destructive) { confirming = true }.disabled(saving)
            }
            .brandListBackground()
            .navigationTitle("Organizer handoff").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) } }
            .confirmationDialog("Give up your organizer role in " + store.club.name + "?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Step down", role: .destructive) {
                    saving = true
                    Task {
                        defer { saving = false }
                        do { try await store.stepDown(successor: successor); dismiss() }
                        catch { problem = error.localizedDescription }
                    }
                }
                Button("Keep role", role: .cancel) {}
            }
        }
    }
}

struct ClubBadge: View {
    let club: Club
    let side: CGFloat

    var body: some View {
        ZStack {
            if let bytes = club.logoData, let image = UIImage(data: bytes) {
                Color.white
                Image(uiImage: image).resizable().scaledToFit().padding(side * 0.08)
            } else {
                club.brandColor
                let words = club.name.split(whereSeparator: \.isWhitespace)
                Text(words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased())
                    .font(.system(size: side * 0.42, weight: .semibold, design: .serif))
                    .foregroundStyle(BrandTheme.label(on: club.brandColor))
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: side * 0.24))
        .accessibilityHidden(true)
    }
}

private struct ClubIdentity: View {
    @Environment(\.brandTheme) private var theme
    let club: Club

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ClubBadge(club: club, side: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(club.name)
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if !club.fullName.isEmpty && club.name != club.fullName {
                    Text(club.fullName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(alignment: .topTrailing) {
            ZStack {
                ClubPattern(rotation: 0).stroke(club.brandColor.opacity(0.32), lineWidth: 1.3)
                ClubPattern(rotation: .pi / 4).stroke(club.secondaryBrandColor.opacity(0.55), lineWidth: 1.3)
            }
            .frame(width: 190, height: 120)
            .accessibilityHidden(true)
        }
        .background(club.brandColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 19))
    }
}

private struct ClubPattern: Shape {
    let rotation: Double

    func path(in rect: CGRect) -> Path {
        var result = Path()
        let spacing = rect.width / 3
        for row in -1...1 {
            for column in 0...3 {
                let center = CGPoint(x: CGFloat(column) * spacing + spacing / 2,
                                     y: CGFloat(row) * spacing + spacing / 3)
                for vertex in 0..<4 {
                    let angle = rotation + Double(vertex) * .pi / 2
                    let point = CGPoint(x: center.x + cos(angle) * spacing * 0.52,
                                        y: center.y + sin(angle) * spacing * 0.52)
                    if vertex == 0 { result.move(to: point) } else { result.addLine(to: point) }
                }
                result.closeSubpath()
            }
        }
        return result
    }
}

private struct ClubEditor: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Club
    @State private var loadingImage = false
    @State private var saving = false
    @State private var problem: String?

    init(club: Club) { _draft = State(initialValue: club) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    AdaptivePhotoRow {
                        ClubBadge(club: draft, side: 60)
                        CommunityPhotoPicker(label: "Choose logo", removalLabel: "Remove logo", data: $draft.logoData, isLoading: $loadingImage, preservesTransparency: true)
                    }
                    .padding(.vertical, 4)
                    LabeledContent("Short name") {
                        TextField("Short name", text: $draft.name)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                    }
                    TextField("Full name", text: $draft.fullName, axis: .vertical)
                        .textInputAutocapitalization(.words)
                }
                Section("Club palette") {
                    palettePicker("Primary color", hex: draft.accentHex, color: draft.brandColor) { draft.accentHex = $0 }
                    palettePicker("Secondary color", hex: draft.effectiveSecondaryHex, color: draft.secondaryBrandColor) { draft.secondaryHex = $0 }
                }
                Section("About the club") {
                    TextField("Describe your club", text: $draft.about, axis: .vertical)
                        .lineLimit(3...10)
                }
                Section("Preview") {
                    ClubIdentity(club: draft)
                        .listRowInsets(EdgeInsets())
                }
            }
            .brandListBackground()
            .navigationTitle("Edit club")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(saving || loadingImage || draft.name.communityTrimmed.isEmpty || draft.fullName.communityTrimmed.isEmpty)
                }
            }
            .interactiveDismissDisabled(saving)
            .alert("Couldn’t save club", isPresented: Binding(
                get: { problem != nil }, set: { if !$0 { problem = nil } }
            )) { Button("OK") {} } message: { Text(problem ?? "") }
        }
    }

    private func palettePicker(_ label: String, hex: String, color: Color,
                               setHex: @escaping (String) -> Void) -> some View {
        ColorPicker(selection: Binding(get: { color }, set: { selected in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard UIColor(selected).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
            let rgb = [red, green, blue].map { Int((min(1, max(0, $0)) * 255).rounded()) }
            setHex(String(format: "#%02X%02X%02X", rgb[0], rgb[1], rgb[2]))
        }), supportsOpacity: false) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                Text(hex.uppercased()).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        guard !saving else { return }
        var update = draft
        update.name = draft.name.communityTrimmed
        update.fullName = draft.fullName.communityTrimmed
        update.about = draft.about.communityTrimmed
        saving = true
        Task {
            do {
                try await store.saveClub(update)
                dismiss()
            } catch { problem = error.localizedDescription }
            saving = false
        }
    }
}
