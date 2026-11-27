import SwiftUI

struct EventsView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.brandTheme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selection: String?
    @State private var path: [String] = []
    @State private var filter: EventFilter = .upcoming
    @State private var creating = false

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    eventList
                        .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 540)
                } detail: {
                    if let selection {
                        EventDetailView(eventID: selection)
                            .id(selection)
                    } else {
                        ContentUnavailableView("Select an event", systemImage: "calendar")
                    }
                }
            } else {
                NavigationStack(path: $path) {
                    eventList
                        .navigationDestination(for: String.self) { id in
                            EventDetailView(eventID: id)
                        }
                }
            }
        }
        .sheet(isPresented: $creating) {
            EventEditorView(event: nil) { id in
                filter = .upcoming
                showEvent(id)
            }
        }
    }

    private var eventList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if typeSize.isAccessibilitySize {
                    filterPicker.pickerStyle(.menu).accessibilityIdentifier("event-filter-menu")
                } else {
                    filterPicker.pickerStyle(.segmented)
                }

                let events = filteredEvents
                if events.isEmpty {
                    ContentUnavailableView(filter.emptyTitle, systemImage: filter.emptyImage, description: Text(filter.emptyDescription))
                        .padding(.vertical, 44)
                } else if filter == .upcoming, let nextEvent = events.first {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Up next").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        Button { showEvent(nextEvent.id) } label: {
                            FeaturedEventCard(event: nextEvent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("event-\(nextEvent.id)")
                    }
                    if events.count > 1 {
                        eventRows(Array(events.dropFirst()), title: "More events")
                    }
                } else {
                    eventRows(events, title: filter.rawValue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 740)
            .frame(maxWidth: .infinity)
        }
        .background(theme.canvas)
        .refreshable { await store.refresh() }
        .navigationTitle("Events")
        .toolbar { ToolbarItem(placement: .topBarLeading) { ActiveClubMenu() } }
        .toolbar {
            if store.isAdmin {
                ToolbarItem(placement: createPlacement) {
                    Button { creating = true } label: {
                        Label("Create event", systemImage: "plus")
                    }
                }
            }
        }
    }

    private var createPlacement: ToolbarItemPlacement {
        if #available(iOS 27, *) { return .topBarPinnedTrailing }
        return .primaryAction
    }

    private var filterPicker: some View {
        Picker("Show events", selection: $filter) {
            ForEach(EventFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
    }

    private var filteredEvents: [ClubEvent] {
        let today = Date()
        switch filter {
        case .upcoming:
            return store.upcomingEvents(at: today)
        case .past:
            return store.events.filter { $0.endsAt <= today }.sorted { $0.startsAt > $1.startsAt }
        case .going:
            let registeredIDs = Set(store.tickets.map(\.eventID))
            return store.events.filter { registeredIDs.contains($0.id) }.sorted { lhs, rhs in
                if (lhs.endsAt <= today) != (rhs.endsAt <= today) { return lhs.endsAt > today }
                return lhs.startsAt < rhs.startsAt
            }
        }
    }

    private func eventRows(_ events: [ClubEvent], title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(events) { event in
                    if event.id != events.first?.id { Divider().padding(.leading, 76) }
                    Button { showEvent(event.id) } label: {
                        EventListRow(event: event)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("event-\(event.id)")
                }
            }
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func showEvent(_ id: String) {
        if sizeClass == .regular {
            selection = id
        } else {
            path.append(id)
        }
    }
}

private enum EventFilter: String, CaseIterable {
    case upcoming = "Upcoming"
    case going = "My events"
    case past = "Past"

    var emptyTitle: String {
        switch self {
        case .upcoming: "No upcoming events"
        case .going: "Your events will appear here"
        case .past: "No past events"
        }
    }

    var emptyDescription: String {
        switch self {
        case .upcoming: "Check back for the next club gathering."
        case .going: "RSVP to an event to find it here with your ticket."
        case .past: "Club gatherings appear here after they end."
        }
    }

    var emptyImage: String { self == .going ? "ticket" : "calendar" }
}

private struct FeaturedEventCard: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.brandTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    let event: ClubEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !typeSize.isAccessibilitySize {
                ZStack(alignment: .topLeading) {
                    if let artwork = event.bundledArtwork {
                        Rectangle().fill(theme.wash)
                            .overlay { Image(artwork).resizable().scaledToFill() }
                            .clipped()
                    } else {
                        LinearGradient(colors: [theme.wash, theme.accent.opacity(0.22)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                            .overlay { ClubBadge(club: store.club, side: 76) }
                    }
                    EventDateTile(date: event.startsAt, onImage: true).padding(14)
                }
                .frame(height: 176)
            }

            VStack(alignment: .leading, spacing: 7) {
                if typeSize.isAccessibilitySize {
                    Text(event.startsAt.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.subheadline.weight(.semibold))
                } else if !event.category.isEmpty {
                    Text(event.category.uppercased())
                        .font(.caption2.weight(.bold)).tracking(1.2)
                        .foregroundStyle(theme.accent)
                }
                Text(event.title)
                    .font(.system(.title, design: .serif, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Label(event.location, systemImage: "mappin")
                    .font(.subheadline).foregroundStyle(Color.primary.opacity(0.68))
            }
            .padding(18)
        }
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

private struct EventListRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let event: ClubEvent

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title).font(.headline)
            Text(event.location).font(.subheadline).foregroundStyle(Color.primary.opacity(0.68))
            Text(event.startsAt.formatted(date: .omitted, time: .shortened))
                .font(.caption).foregroundStyle(Color.primary.opacity(0.68))
        }
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.startsAt.formatted(.dateTime.month(.wide).day())).font(.subheadline.bold())
                    summary
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 14) {
                    EventDateTile(date: event.startsAt)
                    summary
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct EventDateTile: View {
    @Environment(\.brandTheme) private var theme
    let date: Date
    var onImage = false
    @ScaledMetric(relativeTo: .body) private var minWidth: CGFloat = 48

    var body: some View {
        VStack(spacing: 1) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.caption2.weight(.bold))
            Text(date.formatted(.dateTime.day()))
                .font(.system(.title3, design: .rounded, weight: .bold))
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 5)
        .frame(minWidth: minWidth)
        .foregroundStyle(onImage ? theme.ink : theme.accent)
        .background(onImage ? theme.surface : theme.wash, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }
}
