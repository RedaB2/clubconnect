import SwiftUI

struct MessageMemberButton: View {
    let member: Member
    var body: some View {
        NavigationLink { MessageThreadView(member: member) } label: { Label("Message", systemImage: "bubble.left") }
    }
}

struct MessagesView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.brandTheme) private var theme
    @Environment(\.scenePhase) private var scene
    @Environment(\.horizontalSizeClass) private var width
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var threads: [InboxConversation] = []
    @State private var queue: [DirectMessage] = []
    @State private var older = false
    @State private var loading = true
    @State private var working = false
    @State private var needsRefresh = false
    @State private var problem: String?
    @State private var compose = false
    @State private var query = ""
    @State private var selectedID: String?
    @State private var compactColumn = NavigationSplitViewColumn.sidebar

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            List(selection: $selectedID) {
                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.circle")
                        Button("Try again") { Task { await reload() } }
                    }
                    .listRowBackground(theme.surface)
                }
                let conversations = rows
                let search = query.communityTrimmed
                let members = Dictionary(uniqueKeysWithValues: store.members.map { ($0.id, $0) })
                let filtered = conversations.filter { row in
                    search.isEmpty || members[row.peer]?.name.localizedStandardContains(search) == true
                        || row.latest.body.localizedStandardContains(search)
                }
                if !filtered.isEmpty {
                    Section {
                        ForEach(filtered) { row in
                            let member = members[row.peer] ?? Member(id: row.peer, name: "Club member", kind: .student)
                            NavigationLink(value: row.peer) {
                                ConversationRow(member: member, thread: row, mine: row.latest.sender == store.me.id)
                            }
                            .listRowBackground(selectedID == row.peer ? theme.wash : theme.surface)
                            .accessibilityIdentifier("conversation-" + row.peer)
                        }
                    } header: {
                        Text(search.isEmpty ? "Conversations" : "Matching conversations")
                            .font(.system(.title3, design: .serif, weight: .semibold)).foregroundStyle(theme.ink).textCase(nil)
                    }
                } else if loading {
                    ProgressView("Loading messages").listRowBackground(Color.clear)
                } else if problem == nil {
                    if !search.isEmpty {
                        ContentUnavailableView.search(text: search).listRowBackground(Color.clear)
                    } else {
                        ContentUnavailableView("No messages yet", systemImage: "bubble.left.and.bubble.right",
                            description: Text("Choose a club member to start a conversation."))
                            .listRowBackground(Color.clear)
                    }
                }
                if older {
                    Button("Earlier conversations") { Task { await loadOlder() } }
                        .listRowBackground(theme.surface)
                        .disabled(working)
                }
                if !loading && search.isEmpty && conversations.count < 3 {
                    let peers = Set(conversations.map(\.peer))
                    let others = store.members.filter { $0.id != store.me.id && !peers.contains($0.id) }
                        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    if !others.isEmpty { contactShortcuts(Array(others.prefix(3))) }
                }
            }
            .listStyle(.insetGrouped)
            .brandListBackground()
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ActiveClubMenu() }
                ToolbarItem(placement: .primaryAction) {
                    Button("New message", systemImage: "square.and.pencil") { compose = true }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or latest message")
            .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 520)
            .refreshable { await reload() }
        } detail: {
            if let selectedID {
                let member = store.members.first { $0.id == selectedID }
                    ?? Member(id: selectedID, name: "Club member", kind: .student)
                MessageThreadView(member: member) {
                    if width == .regular { await reload() }
                }
                .id(selectedID)
            } else {
                ContentUnavailableView("Your conversations", systemImage: "bubble.left.and.bubble.right",
                    description: Text("Select a conversation or write to a club member."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.canvas)
            }
        }
        .task(id: "\(store.club.id)/\(store.me.id)/\(scene == .active)/\(showsInboxOnly)") {
            guard scene == .active && showsInboxOnly else { return }
            await MessageLiveUpdates(store: store).listen {
                await reload()
                return problem == nil && queue.isEmpty
            }
        }
        .sheet(isPresented: $compose) {
            RecipientPicker { member in
                compose = false
                select(member)
            }
        }
    }

    private var showsInboxOnly: Bool {
        selectedID == nil || (width == .compact && compactColumn == .sidebar)
    }

    private func select(_ member: Member) {
        selectedID = member.id
        compactColumn = .detail
    }

    private func contactShortcuts(_ members: [Member]) -> some View {
        Section {
            if typeSize.isAccessibilitySize {
                ForEach(members) { member in
                    Button { select(member) } label: { DirectoryPersonRow(member: member) }
                        .listRowBackground(theme.surface)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(members) { member in
                        Button { select(member) } label: {
                            VStack(spacing: 7) {
                                MemberPortrait(name: member.name, imageData: member.photoData, diameter: 52)
                                Text(member.name)
                                    .font(.footnote.weight(.medium)).multilineTextAlignment(.center)
                                    .foregroundStyle(theme.ink).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Message " + member.name)
                    }
                }
                .padding(.vertical, 7)
                .listRowBackground(theme.surface)
            }
        } header: {
            Text("Start a conversation").font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(theme.ink).textCase(nil)
        }
    }

    private var rows: [InboxConversation] {
        var combined = Dictionary(uniqueKeysWithValues: threads.map { ($0.peer, $0) })
        for msg in queue where combined[msg.recipient].map({ $0.latest.sentAt < msg.sentAt }) ?? true {
            combined[msg.recipient] = InboxConversation(peer: msg.recipient, latest: msg, unread: combined[msg.recipient]?.unread ?? 0)
        }
        return combined.values.sorted { $0.latest.sentAt > $1.latest.sentAt }
    }

    private func reload() async {
        if working { needsRefresh = true; return }
        working = true
        defer { loading = false; finishLoading() }
        let mailbox = MessageMailbox(store)
        do {
            queue = try mailbox.pending()
            var deliveryProblem: String?
            do { try await mailbox.deliverPending() }
            catch is CancellationError { return }
            catch { deliveryProblem = error.localizedDescription }
            queue = try mailbox.pending()
            let fresh = try await mailbox.inbox()
            let knownMembers = Set(store.members.map(\.id))
            if fresh.contains(where: { !knownMembers.contains($0.peer) }) {
                // A newly enrolled member can message us while the directory is already open.
                await store.refresh()
            }
            try Task.checkCancellation()
            if threads.count <= 40 { threads = fresh; older = fresh.count == 40 }
            else {
                let changed = Set(fresh.map(\.peer))
                threads = fresh + threads.filter { !changed.contains($0.peer) }
            }
            problem = deliveryProblem
        } catch is CancellationError { return }
        catch { if !Task.isCancelled { problem = error.localizedDescription } }
    }

    private func finishLoading() {
        working = false
        if needsRefresh {
            needsRefresh = false
            Task { await reload() }
        }
    }

    private func loadOlder() async {
        guard !working, let cursor = threads.last?.latest.id else { return }
        working = true
        defer { finishLoading() }
        do {
            let page = try await MessageMailbox(store).inbox(before: cursor)
            let known = Set(threads.map(\.peer))
            threads.append(contentsOf: page.filter { !known.contains($0.peer) })
            older = page.count == 40
        } catch { problem = error.localizedDescription }
    }
}

private struct ConversationRow: View {
    @Environment(\.brandTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    let member: Member
    let thread: InboxConversation
    let mine: Bool

    private var timestamp: String {
        let date = thread.latest.sentAt
        if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            MemberPortrait(name: member.name, imageData: member.photoData, diameter: 52)
            VStack(alignment: .leading, spacing: 5) {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 7))
                layout {
                    Text(member.name).font(.headline).foregroundStyle(theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(timestamp).font(.caption).foregroundStyle(theme.ink.opacity(0.72))
                }
                Text((mine ? "You: " : "") + thread.latest.body)
                    .font(.subheadline)
                    .foregroundStyle(theme.ink.opacity(thread.unread > 0 ? 0.94 : 0.76))
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                if thread.unread > 0 {
                    HStack(spacing: 5) {
                        Circle().fill(theme.accent).frame(width: 6, height: 6)
                        Text("\(thread.unread) unread").font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                    }
                }
            }
        }
        .padding(.vertical, 7)
    }
}

private struct RecipientPicker: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.brandTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let select: (Member) -> Void

    var body: some View {
        NavigationStack {
            let search = query.communityTrimmed
            let members = store.members
                .filter { $0.id != store.me.id && (search.isEmpty || $0.name.localizedStandardContains(search) || $0.major.localizedStandardContains(search)) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            List {
                if members.isEmpty {
                    if search.isEmpty {
                        ContentUnavailableView("No other members yet", systemImage: "person.2",
                            description: Text("You can message other people once they join \(store.club.name)."))
                            .listRowBackground(Color.clear)
                    } else {
                        ContentUnavailableView.search(text: search).listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(members) { member in
                            Button { select(member) } label: { DirectoryPersonRow(member: member) }
                                .accessibilityLabel(member.name)
                                .listRowBackground(theme.surface)
                        }
                    } header: {
                        SocialSectionHeading(title: "\(store.club.name) members", count: members.count)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .brandListBackground()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or major")
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
