import SwiftUI

struct EventDetailView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.self) private var environment
    @State private var sheet: EventSheet?
    @State private var reserving = false
    @State private var errorText: String?
    let eventID: String

    var body: some View {
        Group {
            if let event = store.events.first(where: { $0.id == eventID }) {
                details(event)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            if store.isPreview {
                                ShareLink(item: event.shareText, subject: Text(event.title)) {
                                    Label("Share event", systemImage: "square.and.arrow.up")
                                }
                            } else {
                                ShareLink(item: store.eventURL(event.id), subject: Text(event.title), message: Text(event.shareText)) {
                                    Label("Share event", systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                        if store.isAdmin {
                            ToolbarItem(placement: .primaryAction) {
                                Menu {
                                    Button { sheet = .checkIn } label: { Label("Check in members", systemImage: "qrcode.viewfinder") }
                                    Button { sheet = .edit } label: { Label("Edit event", systemImage: "pencil") }
                                } label: {
                                    Label("Manage event", systemImage: "ellipsis.circle")
                                }
                            }
                        }
                    }
                    .sheet(item: $sheet) { route in
                        switch route {
                        case .edit:
                            if store.isAdmin { EventEditorView(event: event) }
                        case .calendar:
                            EventCalendarEditor(title: event.title, start: event.startsAt, end: event.endsAt,
                                                location: event.location, notes: event.summary, url: store.isPreview ? nil : store.eventURL(event.id)) { sheet = nil }
                        case .ticket:
                            EventTicketView(event: event)
                        case .checkIn:
                            if store.isAdmin { EventCheckInView(event: event) }
                        }
                    }
            } else {
                ContentUnavailableView("Event unavailable", systemImage: "calendar.badge.exclamationmark",
                                       description: Text("This event may have been removed from the club calendar."))
            }
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn’t RSVP", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func details(_ event: ClubEvent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !typeSize.isAccessibilitySize, let artwork = event.bundledArtwork {
                    Rectangle()
                        .fill(store.club.accent.opacity(0.2))
                        .frame(height: 178)
                        .overlay { Image(artwork).resizable().scaledToFill() }
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text([store.club.name, event.category].filter { !$0.isEmpty }.joined(separator: "  ·  ").uppercased())
                        .font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(Color.primary.opacity(0.68))
                    Text(event.title)
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                }

                if typeSize.isAccessibilitySize, hasTicket(for: event) || event.endsAt > .now {
                    ticketAction(event)
                }

                VStack(alignment: .leading, spacing: 16) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.startsAt.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                                .font(.headline)
                            Text(event.timeRange).font(.subheadline).foregroundStyle(Color.primary.opacity(0.68))
                        }
                    } icon: { Image(systemName: "calendar").foregroundStyle(store.club.accent) }
                    Divider()
                    Label {
                        Text(event.location).font(.headline)
                    } icon: { Image(systemName: "mappin.and.ellipse").foregroundStyle(store.club.accent) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17))
                Button { sheet = .calendar } label: {
                    Label("Add to Calendar", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
                .tint(Color.primary)
                if !event.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About this event").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                        Text(event.summary).font(.body).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !typeSize.isAccessibilitySize, hasTicket(for: event) || event.endsAt > .now {
                ticketAction(event)
                    .frame(maxWidth: 700)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
            }
        }
    }

    private func hasTicket(for event: ClubEvent) -> Bool {
        store.tickets.contains { $0.eventID == event.id }
    }

    private var ticketLabelColor: Color {
        let background = store.club.accent.resolve(in: environment)
        // Black and white have equal WCAG contrast at a relative luminance of about 0.179.
        let luminance = 0.2126 * background.linearRed + 0.7152 * background.linearGreen + 0.0722 * background.linearBlue
        return luminance > 0.179 ? .black : .white
    }

    private func ticketAction(_ event: ClubEvent) -> some View {
        Group {
            if hasTicket(for: event) {
                Button { sheet = .ticket } label: {
                    Label("View ticket", systemImage: "ticket")
                        .foregroundStyle(ticketLabelColor).frame(maxWidth: .infinity)
                }
            } else {
                Button { Task { await rsvp(to: event) } } label: {
                    Group {
                        if reserving { ProgressView().tint(ticketLabelColor) }
                        else { Label("RSVP", systemImage: "ticket").foregroundStyle(ticketLabelColor) }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(reserving)
            }
        }
        .font(.headline)
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
    }

    @MainActor private func rsvp(to event: ClubEvent) async {
        guard !reserving else { return }
        reserving = true
        defer { reserving = false }
        do {
            try await store.setRSVP(eventID: event.id, attending: true)
            sheet = .ticket
        } catch {
            errorText = error.localizedDescription
        }
    }

    private enum EventSheet: String, Identifiable {
        case edit, calendar, ticket, checkIn
        var id: Self { self }
    }
}

extension ClubEvent {
    // The demonstration photo is associated with the seeded coffee gathering.
    var bundledArtwork: String? {
        id == "a1000000-0000-4000-8000-000000000001" ? "Gathering" : nil
    }

    var shareText: String {
        [title, startsAt.formatted(date: .complete, time: .omitted), timeRange, location, summary]
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    var timeRange: String {
        let sameDay = Calendar.current.isDate(startsAt, inSameDayAs: endsAt)
        let start = startsAt.formatted(date: .omitted, time: .shortened)
        let end = endsAt.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened)
        return "\(start) – \(end)"
    }
}
