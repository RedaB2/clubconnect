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
    @State private var threads: [InboxConversation] = []
    @State private var queue: [DirectMessage] = []
    @State private var older = false
    @State private var loading = true
    @State private var working = false
    @State private var needsRefresh = false
    @State private var problem: String?
    @State private var compose = false
    @State private var query = ""
    @State private var path: [Member] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let problem {
                    Section { Label(problem, systemImage: "exclamationmark.circle")
                        Button("Try again") { Task { await reload() } } }
                }
                ForEach(rows) { row in
                    let member = store.members.first(where: { $0.id == row.peer })
                        ?? Member(id: row.peer, name: "Club member", kind: .student)
                    NavigationLink(value: member) {
                        HStack(spacing: 12) {
                            MemberPortrait(name: member.name, imageData: member.photoData, diameter: 46)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(member.name).font(.headline)
                                    Spacer()
                                    Text(row.latest.sentAt, format: .relative(presentation: .numeric))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text((row.latest.sender == store.me.id ? "You: " : "") + row.latest.body)
                                    .font(.subheadline).foregroundStyle(row.unread > 0 ? .primary : .secondary).lineLimit(2)
                                if row.unread > 0 {
                                    Text("\(row.unread) unread").font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                }
                if older { Button("Earlier conversations") { Task { await loadOlder() } } }
            }
            .listStyle(.plain)
            .brandListBackground()
            .overlay {
                if loading && rows.isEmpty { ProgressView("Loading messages") }
                else if rows.isEmpty && problem == nil {
                    ContentUnavailableView {
                        Label("No messages yet", systemImage: "bubble.left.and.bubble.right")
                    } description: { Text("Start a conversation with another member of \(store.club.name).") } actions: {
                        Button("New message") { compose = true }
                    }
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ActiveClubMenu() }
                ToolbarItem(placement: .primaryAction) {
                    Button("New message", systemImage: "square.and.pencil") { compose = true }
                }
            }
            .refreshable { await reload() }
            .task(id: "\(store.club.id)/\(store.me.id)/\(scene == .active)/\(path.isEmpty)") {
                guard scene == .active, path.isEmpty else { return }
                await MessageLiveUpdates(store: store).listen {
                    await reload()
                    return problem == nil && queue.isEmpty
                }
            }
            .navigationDestination(for: Member.self) { member in MessageThreadView(member: member) }
            .sheet(isPresented: $compose) {
                NavigationStack {
                    List(recipients) { member in
                        Button {
                            compose = false
                            path.append(member)
                        } label: {
                            HStack(spacing: 12) {
                                MemberPortrait(name: member.name, imageData: member.photoData, diameter: 38)
                                Text(member.name).foregroundStyle(.primary)
                            }
                        }
                    }
                    .brandListBackground()
                    .overlay { if recipients.isEmpty { ContentUnavailableView.search(text: query) } }
                    .searchable(text: $query, prompt: "Search members")
                    .navigationTitle("New message")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { compose = false } } }
                }
                .onDisappear { query = "" }
            }
        }
    }

    private var recipients: [Member] {
        store.members.filter { $0.id != store.me.id && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
