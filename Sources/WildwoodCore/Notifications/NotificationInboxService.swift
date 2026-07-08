// Notification inbox service ported from @wildwood/core/src/notifications/notificationInboxService.ts.
//
// Mirrors the JS transient-retain contract via optional returns: a transient failure
// (5xx/network) returns nil so callers retain their last-good data, while a genuine
// 401/403 deny returns a safe empty/default value. Distinct from NotificationService
// (the transient in-memory toast queue).
//
// PARITY: endpoint paths are passed as double-quoted string literals to the HTTP verb
// methods so the Sync parity script can extract them.

import Foundation

public final class NotificationInboxService: Sendable {
    private let http: WildwoodHttpClient
    private let defaultAppId: String

    public init(http: WildwoodHttpClient, defaultAppId: String) {
        self.http = http
        self.defaultAppId = defaultAppId
    }

    private static func isAuthDeny(_ error: WildwoodError) -> Bool {
        error.status == 401 || error.status == 403
    }

    /// List inbox notifications. Returns an empty array on an auth deny (401/403) and
    /// nil on a transient failure so callers retain the last-good list.
    public func list() async -> [AppNotification]? {
        do {
            let result: [AppNotification] = try await http.get("api/notifications")
            return result
        } catch let error as WildwoodError {
            return Self.isAuthDeny(error) ? [] : nil
        } catch {
            return nil
        }
    }

    /// Unread count. Returns 0 on an auth deny and nil on a transient failure so callers
    /// keep the last known badge count.
    public func getUnreadCount() async -> Int? {
        do {
            // Read the raw body and coerce tolerantly (raw number, text/plain number, or empty → 0),
            // mirroring @wildwood/core's Number() coercion with a 0 fallback, so a 204/empty or an
            // unexpectedly-wrapped body doesn't throw and leave the badge stale.
            let data = try await http.getData("api/notifications/count")
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return 0 }
            if let n = Int(text) { return n }
            if let d = Double(text) { return Int(d) }
            return 0
        } catch let error as WildwoodError {
            return Self.isAuthDeny(error) ? 0 : nil
        } catch {
            return nil
        }
    }

    /// Mark a single notification read. Returns whether the request succeeded.
    public func markRead(id: String) async -> Bool {
        do {
            let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            try await http.putVoid("api/notifications/\(encodedId)/read", body: EmptyBody())
            return true
        } catch {
            return false
        }
    }

    /// Mark all notifications read. Returns the number marked (0 on failure).
    public func markAllRead() async -> Int {
        do {
            let response: MarkAllReadResponse = try await http.put("api/notifications/read-all", body: EmptyBody())
            return response.markedAsRead
        } catch {
            return 0
        }
    }

    /// Delete/dismiss a single notification. Returns whether the request succeeded.
    public func remove(id: String) async -> Bool {
        do {
            let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            try await http.deleteVoid("api/notifications/\(encodedId)")
            return true
        } catch {
            return false
        }
    }

    /// Get per-app delivery preferences. Returns safe defaults on an auth deny and nil on a
    /// transient failure so callers retain previously-loaded preferences.
    public func getPreferences(appId: String? = nil) async -> UserNotificationPreference? {
        let targetAppId = appId ?? defaultAppId
        do {
            let encodedAppId = targetAppId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? targetAppId
            let pref: UserNotificationPreference = try await http.get("api/notifications/preferences?appId=\(encodedAppId)")
            return pref
        } catch let error as WildwoodError {
            return Self.isAuthDeny(error) ? .createDefault(appId: targetAppId) : nil
        } catch {
            return nil
        }
    }

    /// Persist delivery preferences. Returns the saved record, or nil on failure.
    public func updatePreferences(_ pref: UserNotificationPreference) async -> UserNotificationPreference? {
        do {
            let saved: UserNotificationPreference = try await http.put("api/notifications/preferences", body: pref)
            return saved
        } catch {
            return nil
        }
    }
}
