import Foundation
import Realtime

@MainActor
struct MessageLiveUpdates {
    let store: ClubStore

    func listen(_ reconcile: @escaping @MainActor () async -> Bool) async {
        let member = store.me.id
        let club = store.club.id
        _ = await reconcile()
        guard !store.isPreview else { return }

        func isCurrent() -> Bool {
            !Task.isCancelled && !store.isPreview && store.phase == .community
                && store.me.id == member && store.club.id == club
        }

        var backoff = 2
        while isCurrent() {
            let connected = await subscribe(member: member, club: club, reconcile: reconcile)
            guard isCurrent() else { return }
            if connected { backoff = 2 }
            do { try await Task.sleep(for: .seconds(backoff)) } catch { return }
            guard isCurrent() else { return }
            _ = await reconcile()
            backoff = min(backoff * 2, 60)
        }
    }

    private func subscribe(member: String, club: String, reconcile: @escaping @MainActor () async -> Bool) async -> Bool {
        let options = RealtimeClientOptions(
            headers: ["apikey": PilotConfiguration.key],
            maxRetryAttempts: 1,
            accessToken: { try await store.authToken() },
            handleAppLifecycle: false
        )
        let client = RealtimeClientV2(url: PilotConfiguration.url.appending(path: "realtime/v1"), options: options)
        let channel = client.channel("mail:\(member.lowercased()):\(club)") { $0.isPrivate = true }
        // Keep one pending refresh, even when read receipts or multiple inserts arrive during a fetch.
        let (events, wake) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let onChange = channel.onBroadcast(event: "changed") { _ in wake.yield() }
        let onChannel = channel.onStatusChange { _ in wake.yield() }
        let onConnection = client.onStatusChange { _ in wake.yield() }
        var retry: Task<Void, Never>?
        defer {
            retry?.cancel()
            onChange.cancel()
            onChannel.cancel()
            onConnection.cancel()
            wake.finish()
            client.disconnect()
        }

        do {
            await client.setAuth(try await store.authToken())
            try Task.checkCancellation()
            try await channel.subscribeWithError()
        } catch { return false }

        // Catch up after joining. WebSocket events contain no conversation data.
        wake.yield()
        var delay = 2
        for await _ in events {
            guard !Task.isCancelled, client.status == .connected, channel.status == .subscribed,
                  store.club.id == club, store.me.id == member, !store.isPreview else { break }
            retry?.cancel()
            if await reconcile() {
                delay = 2
            } else {
                // Retry the durable outbox / RPC after a temporary HTTP failure while the socket is up.
                let seconds = delay
                retry = Task {
                    do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                    wake.yield()
                }
                delay = min(delay * 2, 60)
            }
        }
        return true
    }
}
