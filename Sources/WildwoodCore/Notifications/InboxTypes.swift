// Notification inbox models ported from @wildwood/core/src/notifications/inboxTypes.ts.
// Distinct from the transient toast queue in NotificationService.swift.

import Foundation

/// Status values for a persisted inbox notification. String constants (not an enum)
/// to match the API payload verbatim and mirror the JS union 'Unread' | 'Read' | 'Dismissed'.
public enum AppNotificationStatus {
    public static let unread = "Unread"
    public static let read = "Read"
    public static let dismissed = "Dismissed"
}

/// A persisted in-app notification (inbox item) returned by api/notifications.
public struct AppNotification: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var type: String
    public var title: String?
    public var message: String
    /// Optional deep-link navigated to on click.
    public var link: String?
    public var appId: String?
    public var eventType: String?
    public var userId: String
    public var status: String
    /// ISO 8601 date string, mirroring the JS payload.
    public var createdAt: String

    /// True when this notification has not yet been read.
    public var isUnread: Bool { status == AppNotificationStatus.unread }

    public init(
        id: String,
        type: String = "",
        title: String? = nil,
        message: String,
        link: String? = nil,
        appId: String? = nil,
        eventType: String? = nil,
        userId: String = "",
        status: String = AppNotificationStatus.unread,
        createdAt: String = ""
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.message = message
        self.link = link
        self.appId = appId
        self.eventType = eventType
        self.userId = userId
        self.status = status
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title)
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link)
        appId = try c.decodeIfPresent(String.self, forKey: .appId)
        eventType = try c.decodeIfPresent(String.self, forKey: .eventType)
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? AppNotificationStatus.unread
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

/// Per-app delivery-channel preferences (opt-outs) for the authenticated user.
public struct UserNotificationPreference: Codable, Sendable, Equatable {
    public var appId: String
    public var emailEnabled: Bool
    public var smsEnabled: Bool
    public var pushEnabled: Bool
    /// Browser (Web Notifications API) channel — web-only; retained for cross-stack model parity.
    public var browserEnabled: Bool
    /// Opaque server-owned JSON blob of per-event opt-outs.
    public var eventOptOutsJson: String?

    public init(
        appId: String,
        emailEnabled: Bool = true,
        smsEnabled: Bool = false,
        pushEnabled: Bool = false,
        browserEnabled: Bool = false,
        eventOptOutsJson: String? = nil
    ) {
        self.appId = appId
        self.emailEnabled = emailEnabled
        self.smsEnabled = smsEnabled
        self.pushEnabled = pushEnabled
        self.browserEnabled = browserEnabled
        self.eventOptOutsJson = eventOptOutsJson
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appId = try c.decodeIfPresent(String.self, forKey: .appId) ?? ""
        emailEnabled = try c.decodeIfPresent(Bool.self, forKey: .emailEnabled) ?? true
        smsEnabled = try c.decodeIfPresent(Bool.self, forKey: .smsEnabled) ?? false
        pushEnabled = try c.decodeIfPresent(Bool.self, forKey: .pushEnabled) ?? false
        browserEnabled = try c.decodeIfPresent(Bool.self, forKey: .browserEnabled) ?? false
        eventOptOutsJson = try c.decodeIfPresent(String.self, forKey: .eventOptOutsJson)
    }

    /// Safe defaults (email on, all else off), returned when the API denies access (401/403)
    /// so callers get a usable object rather than nil/stale values.
    public static func createDefault(appId: String) -> UserNotificationPreference {
        UserNotificationPreference(appId: appId)
    }
}

/// Response shape for the mark-all-read endpoint.
public struct MarkAllReadResponse: Codable, Sendable, Equatable {
    public var markedAsRead: Int

    public init(markedAsRead: Int = 0) {
        self.markedAsRead = markedAsRead
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        markedAsRead = try c.decodeIfPresent(Int.self, forKey: .markedAsRead) ?? 0
    }
}
