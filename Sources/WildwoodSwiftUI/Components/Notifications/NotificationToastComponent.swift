#if os(iOS)
// Toast overlay rendering the client-side notification queue.
// Parity with NotificationToastComponent in the React Native package.

import SwiftUI
import WildwoodCore

public struct NotificationToastComponent: View {
    @Environment(\.wildwoodClient) private var client

    private let position: NotificationPosition?
    private let onAction: ((String, NotificationAction) -> Void)?

    public init(position: NotificationPosition? = nil, onAction: ((String, NotificationAction) -> Void)? = nil) {
        self.position = position
        self.onAction = onAction
    }

    public var body: some View {
        if let notifications = requireClient(client, component: "NotificationToastComponent")?.notifications {
            let resolved = position ?? notifications.defaultPosition
            VStack(spacing: 8) {
                if isBottom(resolved) { Spacer() }
                ForEach(notifications.toasts) { toast in
                    ToastView(toast: toast, onAction: onAction) {
                        notifications.dismiss(toast.id)
                    }
                    .transition(.move(edge: isBottom(resolved) ? .bottom : .top).combined(with: .opacity))
                }
                if !isBottom(resolved) { Spacer() }
            }
            .padding()
            .animation(.snappy, value: notifications.toasts)
            .allowsHitTesting(!notifications.toasts.isEmpty)
        }
    }

    private func isBottom(_ position: NotificationPosition) -> Bool {
        position == .bottomLeft || position == .bottomRight || position == .bottomCenter
    }
}

private struct ToastView: View {
    @Environment(\.wildwoodTheme) private var theme

    let toast: ToastNotification
    let onAction: ((String, NotificationAction) -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    if !toast.title.isEmpty {
                        Text(toast.title)
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(toast.message)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if toast.isDismissible {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss notification")
                }
            }
            if !toast.actions.isEmpty {
                HStack {
                    ForEach(toast.actions) { action in
                        Button(action.text) {
                            onAction?(toast.id, action)
                            if action.dismissOnClick {
                                onDismiss()
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(iconColor.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch toast.type {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch toast.type {
        case .success: return theme.success
        case .error: return theme.danger
        case .warning: return theme.warning
        case .info: return theme.info
        }
    }
}
#endif
