#if os(iOS)
// In-app notification list backed by the client-side toast queue.
// Parity with NotificationComponent in the React Native package.

import SwiftUI
import WildwoodCore

public struct NotificationComponent: View {
    @Environment(\.wildwoodClient) private var client
    @Environment(\.wildwoodTheme) private var theme

    private let showClearAll: Bool

    public init(showClearAll: Bool = true) {
        self.showClearAll = showClearAll
    }

    public var body: some View {
        if let notifications = requireClient(client, component: "NotificationComponent")?.notifications {
            VStack(alignment: .leading, spacing: 8) {
                if showClearAll, !notifications.toasts.isEmpty {
                    HStack {
                        Spacer()
                        Button("Clear All") {
                            notifications.clear()
                        }
                        .font(.caption)
                    }
                }

                if notifications.toasts.isEmpty {
                    ContentUnavailableView(
                        "No notifications",
                        systemImage: "bell.slash",
                        description: Text("You're all caught up.")
                    )
                } else {
                    ForEach(notifications.toasts) { toast in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(color(for: toast.type))
                                .frame(width: 8, height: 8)
                                .padding(.top, 4)
                            VStack(alignment: .leading, spacing: 2) {
                                if !toast.title.isEmpty {
                                    Text(toast.title).font(.subheadline.weight(.semibold))
                                }
                                Text(toast.message).font(.subheadline)
                                Text(toast.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if toast.isDismissible {
                                Button {
                                    notifications.dismiss(toast.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func color(for type: NotificationType) -> Color {
        switch type {
        case .success: return theme.success
        case .error: return theme.danger
        case .warning: return theme.warning
        case .info: return theme.info
        }
    }
}
#endif
