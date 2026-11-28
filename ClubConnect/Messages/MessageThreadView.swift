import SwiftUI

struct MessageThreadView: View {
    @Environment(\.brandTheme) private var theme
    @Environment(ClubStore.self) private var store
    @Environment(\.scenePhase) private var scene
    @Environment(\.horizontalSizeClass) private var width
    @Environment(\.dynamicTypeSize) private var typeSize
    let member: Member
    var refreshInbox: (() async -> Void)? = nil
    @State private var showingProfile = false
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
                let transcript = rows
                LazyVStack(spacing: 12) {
                    if older { Button("Load earlier messages") { Task { await loadOlder() } }.padding(8) }
                    if loading && transcript.isEmpty { ProgressView().accessibilityLabel("Loading conversation") }
                    else if transcript.isEmpty && problem == nil {
                        ContentUnavailableView {
                            MemberPortrait(name: member.name, imageData: member.photoData, diameter: 72)
                            Text("Start the conversation")
                        } description: {
                            Text("Send a private message to \(member.name).")
                        }
                    }
                    ForEach(Array(transcript.enumerated()), id: \.element.id) { index, message in
                        if index == 0 || !Calendar.current.isDate(message.sentAt, inSameDayAs: transcript[index - 1].sentAt) {
                            dayDivider(message.sentAt)
                        }
                        bubble(message).id(message.id)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 18)
                .frame(maxWidth: 710)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.canvas)
            .onChange(of: scrollTarget) { _, id in
                if let id { reader.scrollTo(id, anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationTitle(member.name)
        .modifier(ThreadClubSubtitle(clubName: store.club.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(width == .compact ? .hidden : .automatic, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingProfile = true } label: {
                    MemberPortrait(name: member.name, imageData: member.photoData, diameter: 32)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("View profile of " + member.name)
            }
        }
        .sheet(isPresented: $showingProfile) {
            NavigationStack {
                MemberProfile(member: store.members.first { $0.id == member.id } ?? member)
                    .navigationTitle("Member profile").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingProfile = false } } }
            }
        }
        .task(id: "\(store.club.id)/\(store.me.id)/\(member.id)/\(scene == .active)") {
            guard scene == .active else { return }
            await MessageLiveUpdates(store: store).listen {
                await refresh()
                await refreshInbox?()
                return problem == nil && queue.isEmpty
            }
        }
    }

    private var rows: [DirectMessage] {
        let confirmed = Set(messages.map(\.id))
        return messages + queue.filter { !confirmed.contains($0.id) }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.unicodeScalars.count <= 4000
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let problem {
                HStack {
                    Text(problem).font(.footnote)
                    Spacer()
                    Button("Retry") { Task { await refresh() } }
                }
            }
            HStack(alignment: .bottom, spacing: 3) {
                TextField("Message", text: $draft, prompt: Text("Message").foregroundStyle(theme.ink.opacity(0.63)), axis: .vertical)
                    .lineLimit(1...5).textFieldStyle(.plain).focused($composing)
                    .foregroundStyle(theme.ink)
                    .padding(.leading, 16).padding(.vertical, 12)
                    .accessibilityLabel("Message to \(member.name)")
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(canSend ? BrandTheme.label(on: theme.accent) : theme.ink.opacity(0.5))
                        .frame(width: 34, height: 34)
                        .background(canSend ? theme.accent : theme.wash, in: Circle())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send message")
                .disabled(!canSend)
            }
            .padding(2)
            .background(theme.surface, in: .rect(cornerRadius: 25))
            .overlay {
                RoundedRectangle(cornerRadius: 25).strokeBorder(theme.ink.opacity(0.2), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            if draft.unicodeScalars.count > 4000 { Text("Messages can contain up to 4,000 characters.").font(.caption) }
        }
        .frame(maxWidth: 710)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(theme.canvas)
    }

    private func dayDivider(_ date: Date) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(theme.ink.opacity(0.16)).frame(height: 1)
            Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                .font(.caption.weight(.semibold)).foregroundStyle(theme.ink.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Rectangle().fill(theme.ink.opacity(0.16)).frame(height: 1)
        }
        .padding(.vertical, 4)
        .accessibilityAddTraits(.isHeader)
    }

    private func bubble(_ message: DirectMessage) -> some View {
        let mine = message.sender == store.me.id
        let waiting = queue.contains { $0.id == message.id }
        let status = waiting ? "Queued" : (mine && message.id == messages.last?.id ? (message.readAt == nil ? "Sent" : "Read") : "")
        let bubbleShape = UnevenRoundedRectangle(topLeadingRadius: 19, bottomLeadingRadius: mine ? 19 : 5,
            bottomTrailingRadius: mine ? 5 : 19, topTrailingRadius: 19)
        let margin: CGFloat = typeSize.isAccessibilitySize ? 12 : 46
        return HStack {
            if mine { Spacer(minLength: margin) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                Text(message.body).textSelection(.enabled)
                    .foregroundStyle(mine ? BrandTheme.label(on: theme.accent) : theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(mine ? theme.accent : theme.surface, in: bubbleShape)
                HStack(spacing: 5) {
                    Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                    if !status.isEmpty { Text(status) }
                }.font(.caption).foregroundStyle(theme.ink.opacity(0.73))
            }
            if !mine { Spacer(minLength: margin) }
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
            .accessibilityLabel("\(mine ? "You" : member.name), \(message.body), \(message.sentAt.formatted()), \(status)")
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
            await refreshInbox?()
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


private struct ThreadClubSubtitle: ViewModifier {
    let clubName: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) { content.navigationSubtitle(Text(clubName)) }
        else { content }
    }
}
