// Client-side toast queue ported from @wildwood/core/src/notifications.
// MainActor + @Observable: SwiftUI views observe the queue directly.

import Foundation
import Observation

public enum NotificationType: String, Codable, Sendable {
    case info = "Info"
    case success = "Success"
    case warning = "Warning"
    case error = "Error"
}

public enum NotificationActionStyle: String, Codable, Sendable {
    case primary = "Primary"
    case secondary = "Secondary"
    case success = "Success"
    case danger = "Danger"
    case warning = "Warning"
    case info = "Info"
    case light = "Light"
    case dark = "Dark"
}

public enum NotificationPosition: String, Codable, Sendable {
    case topLeft = "TopLeft"
    case topRight = "TopRight"
    case topCenter = "TopCenter"
    case bottomLeft = "BottomLeft"
    case bottomRight = "BottomRight"
    case bottomCenter = "BottomCenter"
}

public struct NotificationAction: Sendable, Equatable, Identifiable {
    public var id: String
    public var text: String
    public var style: NotificationActionStyle
    public var dismissOnClick: Bool

    public init(id: String, text: String, style: NotificationActionStyle = .primary, dismissOnClick: Bool = true) {
        self.id = id
        self.text = text
        self.style = style
        self.dismissOnClick = dismissOnClick
    }
}

public struct ToastNotification: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var message: String
    public var type: NotificationType
    public var timestamp: Date
    public var isVisible: Bool
    public var isDismissible: Bool
    /// Auto-dismiss delay in milliseconds; 0 means sticky.
    public var duration: Int
    public var actions: [NotificationAction]

    public init(
        id: String,
        title: String = "",
        message: String,
        type: NotificationType = .info,
        timestamp: Date = Date(),
        isVisible: Bool = true,
        isDismissible: Bool = true,
        duration: Int = 5000,
        actions: [NotificationAction] = []
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.type = type
        self.timestamp = timestamp
        self.isVisible = isVisible
        self.isDismissible = isDismissible
        self.duration = duration
        self.actions = actions
    }
}

@MainActor
@Observable
public final class NotificationService {
    public private(set) var toasts: [ToastNotification] = []
    public var defaultPosition: NotificationPosition = .topRight
    public var defaultDurationMs = 5000

    @ObservationIgnored private var nextId = 1
    @ObservationIgnored private var dismissTasks: [String: Task<Void, Never>] = [:]

    public init() {}

    @discardableResult
    public func show(
        _ message: String,
        type: NotificationType = .info,
        title: String? = nil,
        durationMs: Int? = nil
    ) -> String {
        let id = String(nextId)
        nextId += 1
        let duration = durationMs ?? defaultDurationMs

        toasts.append(
            ToastNotification(id: id, title: title ?? "", message: message, type: type, duration: duration)
        )

        if duration > 0 {
            dismissTasks[id] = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(duration))
                guard !Task.isCancelled else { return }
                self?.dismiss(id)
            }
        }

        return id
    }

    @discardableResult
    public func success(_ message: String, title: String? = nil) -> String {
        show(message, type: .success, title: title)
    }

    /// Errors don't auto-dismiss.
    @discardableResult
    public func error(_ message: String, title: String? = nil) -> String {
        show(message, type: .error, title: title, durationMs: 0)
    }

    @discardableResult
    public func warning(_ message: String, title: String? = nil) -> String {
        show(message, type: .warning, title: title)
    }

    @discardableResult
    public func info(_ message: String, title: String? = nil) -> String {
        show(message, type: .info, title: title)
    }

    public func dismiss(_ id: String) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
        toasts.removeAll { $0.id == id }
    }

    public func clear() {
        for task in dismissTasks.values {
            task.cancel()
        }
        dismissTasks.removeAll()
        toasts.removeAll()
    }
}
