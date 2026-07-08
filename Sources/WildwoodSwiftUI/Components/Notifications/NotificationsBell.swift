#if os(iOS)
// Notification bell with an unread-count badge that presents the inbox in a sheet —
// parity with NotificationsBell in the React Native package. Owns a single
// WildwoodNotificationInboxModel (list + count polled ~45s) so the badge and the
// sheet stay in sync. Distinct from the toast surface (NotificationToastComponent).

import SwiftUI
import WildwoodCore

public struct NotificationsBell: View {
    @Environment(\.wildwoodClient) private var client
    @Environment(\.wildwoodTheme) private var theme
    @Environment(\.openURL) private var openURL

    private let maxBadge: Int
    private let pollIntervalSeconds: Int
    private let emptyText: String
    private let onNavigate: ((AppNotification) -> Void)?

    @State private var model: WildwoodNotificationInboxModel?
    @State private var isOpen = false

    public init(
        maxBadge: Int = 99,
        pollIntervalSeconds: Int = 45,
        emptyText: String = "No notifications",
        onNavigate: ((AppNotification) -> Void)? = nil
    ) {
        self.maxBadge = maxBadge
        self.pollIntervalSeconds = pollIntervalSeconds
        self.emptyText = emptyText
        self.onNavigate = onNavigate
    }

    public var body: some View {
        Button {
            isOpen = true
        } label: {
            bell
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            if model == nil, let client = requireClient(client, component: "NotificationsBell") {
                model = WildwoodNotificationInboxModel(client: client)
            }
            model?.start(pollIntervalSeconds: pollIntervalSeconds)
        }
        .onDisappear { model?.stop() }
        .sheet(isPresented: $isOpen) {
            if let model {
                NavigationStack {
                    NotificationItemsView(
                        model: model,
                        emptyText: emptyText,
                        showMarkAllRead: true,
                        onItemTap: { handleTap($0, model: model) }
                    )
                    .navigationTitle("Notifications")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { isOpen = false }
                        }
                    }
                }
            }
        }
    }

    private var unread: Int { model?.unreadCount ?? 0 }

    private var bell: some View {
        Image(systemName: "bell.fill")
            .font(.title3)
            .foregroundStyle(theme.accent)
            .overlay(alignment: .topTrailing) {
                if unread > 0 {
                    Text(badgeLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(theme.danger, in: Capsule())
                        .offset(x: 8, y: -6)
                }
            }
    }

    private var badgeLabel: String {
        unread > maxBadge ? "\(maxBadge)+" : "\(unread)"
    }

    private var accessibilityLabel: String {
        unread > 0 ? "Notifications, \(unread) unread" : "Notifications"
    }

    private func handleTap(_ n: AppNotification, model: WildwoodNotificationInboxModel) {
        if n.isUnread { Task { await model.markRead(id: n.id) } }
        if let onNavigate {
            onNavigate(n)
            isOpen = false
            return
        }
        if let link = n.link,
           let url = URL(string: link),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            openURL(url)
            isOpen = false
        }
    }
}
#endif
