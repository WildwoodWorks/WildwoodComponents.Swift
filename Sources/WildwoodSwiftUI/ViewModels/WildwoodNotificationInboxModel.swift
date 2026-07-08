// Backend-connected notification inbox state — the SwiftUI analog of
// react-shared's useNotificationInbox hook. Wraps WildwoodCore's
// NotificationInboxService: the unread count and the full list are refreshed
// together on an interval (the backend has no SSE) plus per-item read/delete
// actions. Distinct from WildwoodNotificationModel/NotificationService (the
// transient in-memory toast queue).
//
// Retain-on-nil: a transient service failure returns nil, so we keep the
// last-good list/count rather than clobbering it (the service already returns a
// safe empty array / 0 for a legitimate 401/403 deny).

import Foundation
import Observation
import WildwoodCore

@MainActor
@Observable
public final class WildwoodNotificationInboxModel {
    @ObservationIgnored private let client: WildwoodClient

    public private(set) var notifications: [AppNotification] = []
    public private(set) var unreadCount = 0
    public private(set) var isLoading = true
    public var errorMessage: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    public init(client: WildwoodClient) {
        self.client = client
    }

    // MARK: - Polling lifecycle

    /// Kick off an immediate refresh and then poll list + count together on an
    /// interval so the bell badge and the list never drift apart. Cancels any
    /// existing poll first, so repeated calls are safe. `pollIntervalSeconds <= 0`
    /// performs a single refresh with no recurring poll.
    public func start(pollIntervalSeconds: Int = 45) {
        stop()
        isLoading = true
        pollTask = Task { [weak self] in
            await self?.refresh()
            guard pollIntervalSeconds > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollIntervalSeconds))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Loads

    /// Refetch the full list and the unread count in parallel. nil results are a
    /// transient failure — retain the last-good value instead of clearing it.
    public func refresh() async {
        let service = client.notificationInbox
        async let listResult = service.list()
        async let countResult = service.getUnreadCount()
        let (list, count) = await (listResult, countResult)
        if let list { notifications = list }
        if let count { unreadCount = count }
        errorMessage = nil
        isLoading = false
    }

    // MARK: - Item actions (each refreshes so badge + list stay in sync)

    @discardableResult
    public func markRead(id: String) async -> Bool {
        let ok = await client.notificationInbox.markRead(id: id)
        if ok { await refresh() }
        return ok
    }

    @discardableResult
    public func markAllRead() async -> Int {
        let count = await client.notificationInbox.markAllRead()
        await refresh()
        return count
    }

    @discardableResult
    public func remove(id: String) async -> Bool {
        let ok = await client.notificationInbox.remove(id: id)
        if ok { await refresh() }
        return ok
    }
}
