import SwiftUI

struct MessageThreadView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.scenePhase) private var scene
    let member: Member
    @State private var messages: [DirectMessage] = []
    @State private var queue: [DirectMessage] = []
    @State private var draft = ""
    @State private var older = false
    @State private var loading = true
    @State private var updating = false
    @State private var needsRefresh = false
    @State private var problem: String?
    @State private var scrollTarget: String?
    @FocusState private var composing: Bool

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 9) {
                    if older { Button("Load earlier messages") { Task { await loadOlder() } }.padding(8) }
                    if loading && rows.isEmpty { ProgressView().accessibilityLabel("Loading conversation") }
                    else if rows.isEmpty && problem == nil {
                        ContentUnavailableView("Start the conversation", systemImage: "bubble.left",
                            description: Text("Send a private message to \(member.name)."))
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, message in
                        if index == 0 || !Calendar.current.isDate(message.sentAt, inSameDayAs: rows[index-1].sentAt) {
                            Text(message.sentAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.vertical, 5)
                        }
                        bubble(message).id(message.id)
                    }
                }.padding(.horizontal).padding(.vertical, 10)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scrollTarget) { _, id in
                if let id { reader.scrollTo(id, anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                if let problem {
                    HStack {
                        Text(problem).font(.footnote)
                        Spacer()
                        Button("Retry") { Task { await refresh() } }
                    }
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message", text: $draft, axis: .vertical)
                        .lineLimit(1...5).textFieldStyle(.roundedBorder).focused($composing)
                        .accessibilityLabel("Message to \(member.name)")
                    Button { Task { await send() } } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Send message")
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.unicodeScalars.count > 4000)
                }
                if draft.unicodeScalars.count > 4000 { Text("Messages can contain up to 4,000 characters.").font(.caption) }
            }.padding(.horizontal).padding(.vertical, 8).background(.bar)
        }
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(store.club.id)/\(store.me.id)/\(member.id)/\(scene == .active)") {
            guard scene == .active else { return }
            await MessageLiveUpdates(store: store).listen {
                await refresh()
                return problem == nil && queue.isEmpty
            }
        }
    }

    private var rows: [DirectMessage] {
        let confirmed = Set(messages.map(\.id))
        return messages + queue.filter { !confirmed.contains($0.id) }
    }

    private func bubble(_ message: DirectMessage) -> some View {
        let mine = message.sender == store.me.id
        let waiting = queue.contains { $0.id == message.id }
        return HStack {
            if mine { Spacer(minLength: 35) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                Text(message.body).textSelection(.enabled)
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background(mine ? store.club.brandColor.opacity(0.16) : Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 16))
                HStack(spacing: 5) {
                    Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                    if waiting { Text("Queued") }
                    else if mine && message.id == messages.last?.id { Text(message.readAt == nil ? "Sent" : "Read") }
                }.font(.caption2).foregroundStyle(.secondary)
            }
            if !mine { Spacer(minLength: 35) }
        }
            .contextMenu {
                if waiting && !updating && problem != nil {
                    Button("Remove from outbox", role: .destructive) {
                        do {
                            let mailbox = MessageMailbox(store)
                            try mailbox.removeFromOutbox(message.id)
                            queue = try mailbox.pending(member.id)
                        } catch { problem = error.localizedDescription }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(mine ? "You" : member.name), \(message.body), \(message.sentAt.formatted()), \(waiting ? "Queued" : "")")
    }

    private func send() async {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let mailbox = MessageMailbox(store)
            try mailbox.enqueue(draft, to: member.id)
            draft = ""
            queue = try mailbox.pending(member.id)
            scrollTarget = queue.last?.id
            await refresh()
        } catch { problem = error.localizedDescription }
    }

    private func refresh() async {
        if updating { needsRefresh = true; return }
        updating = true
        defer { loading = false; finishLoading() }
        let mailbox = MessageMailbox(store)
        do {
            queue = try mailbox.pending(member.id)
            var deliveryProblem: String?
            do { try await mailbox.deliverPending(to: member.id) }
            catch is CancellationError { return }
            catch { deliveryProblem = error.localizedDescription }
            let page = try await mailbox.history(member.id)
            try Task.checkCancellation()
            let originalLast = messages.last?.id
            let pageIDs = Set(page.map(\.id))
            if messages.count >= 40, messages.contains(where: { pageIDs.contains($0.id) }) {
                messages = messages.filter { !pageIDs.contains($0.id) } + page
            } else {
                messages = page
                older = page.count == 40
            }
            queue = try mailbox.pending(member.id)
            if let last = page.last, originalLast != last.id { scrollTarget = last.id }
            if let last = page.last(where: { $0.recipient == mailbox.me && $0.readAt == nil }) {
                try await mailbox.markRead(member.id, through: last)
            }
            problem = deliveryProblem
        } catch is CancellationError { return }
        catch { if !Task.isCancelled { problem = error.localizedDescription } }
    }

    private func finishLoading() {
        updating = false
        if needsRefresh {
            needsRefresh = false
            Task { await refresh() }
        }
    }

    private func loadOlder() async {
        guard !updating, let first = messages.first else { return }
        updating = true
        defer { finishLoading() }
        do {
            let page = try await MessageMailbox(store).history(member.id, cursor: first.id)
            messages.insert(contentsOf: page, at: 0)
            older = page.count == 40
            scrollTarget = first.id
        } catch { problem = error.localizedDescription }
    }
}
