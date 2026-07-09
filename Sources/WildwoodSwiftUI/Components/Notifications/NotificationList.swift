#if os(iOS)
// Standalone backend-connected inbox list — parity with NotificationList in the
// React Native package. Owns a single WildwoodNotificationInboxModel (list + count
// polled ~45s) so it stays fresh; per-item mark-read + delete (swipe actions),
// tap-to-navigate via the item's http(s) link, and a "Mark all read" action.
//
// The presentational NotificationItemsView + timeAgo helper below are shared with
// NotificationsBell, mirroring NotificationItemsNative in the React Native package.

import SwiftUI
import WildwoodCore

public struct NotificationList: View {
    @Environment(\.wildwoodClient) private var client
    @Environment(\.openURL) private var openURL

    private let pollIntervalSeconds: Int
    private let emptyText: String
    private let onNavigate: ((AppNotification) -> Void)?

    @State private var model: WildwoodNotificationInboxModel?

    public init(
        pollIntervalSeconds: Int = 45,
        emptyText: String = "No notifications",
        onNavigate: ((AppNotification) -> Void)? = nil
    ) {
        self.pollIntervalSeconds = pollIntervalSeconds
        self.emptyText = emptyText
        self.onNavigate = onNavigate
    }

    public var body: some View {
        Group {
            if let model {
                NotificationItemsView(
                    model: model,
                    emptyText: emptyText,
                    showMarkAllRead: true,
                    onItemTap: { handleTap($0, model: model) }
                )
            } else {
                LoadingSpinnerView(label: "Loading notifications…")
            }
        }
        .onAppear {
            if model == nil, let client = requireClient(client, component: "NotificationList") {
                model = WildwoodNotificationInboxModel(client: client)
            }
            model?.start(pollIntervalSeconds: pollIntervalSeconds)
        }
        .onDisappear { model?.stop() }
    }

    private func handleTap(_ n: AppNotification, model: WildwoodNotificationInboxModel) {
        if n.isUnread { Task { await model.markRead(id: n.id) } }
        if let onNavigate {
            onNavigate(n)
            return
        }
        openHTTPLink(n.link, using: openURL)
    }
}

// MARK: - Shared presentational list

/// Renders a WildwoodNotificationInboxModel's items with per-item actions.
/// Shared by NotificationList (standalone) and NotificationsBell (sheet) — one
/// polling model per surface, matching the React Native NotificationItemsNative.
struct NotificationItemsView: View {
    @Environment(\.wildwoodTheme) private var theme
    let model: WildwoodNotificationInboxModel
    let emptyText: String
    let showMarkAllRead: Bool
    let onItemTap: (AppNotification) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if showMarkAllRead {
                HStack {
                    Text("Notifications").font(.headline)
                    Spacer()
                    Button("Mark all read") {
                        Task { await model.markAllRead() }
                    }
                    .font(.subheadline)
                    .disabled(model.unreadCount == 0)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }

            if let error = model.errorMessage {
                ErrorBannerView(message: error) { model.errorMessage = nil }
                    .padding(.horizontal)
            }

            if model.isLoading, model.notifications.isEmpty {
                LoadingSpinnerView(label: "Loading…")
            } else if model.notifications.isEmpty {
                ContentUnavailableView(
                    emptyText,
                    systemImage: "bell.slash",
                    description: Text("You're all caught up.")
                )
            } else {
                List {
                    ForEach(model.notifications) { item in
                        NotificationRow(
                            item: item,
                            accent: theme.accent,
                            onTap: { onItemTap(item) },
                            onMarkRead: { Task { await model.markRead(id: item.id) } },
                            onRemove: { Task { await model.remove(id: item.id) } }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

private struct NotificationRow: View {
    let item: AppNotification
    let accent: Color
    let onTap: () -> Void
    let onMarkRead: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if item.isUnread {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let title = item.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Text(item.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Text(timeAgo(item.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onRemove) {
                Label("Delete", systemImage: "trash")
            }
            if item.isUnread {
                Button(action: onMarkRead) {
                    Label("Read", systemImage: "checkmark")
                }
                .tint(.blue)
            }
        }
        .listRowBackground(item.isUnread ? accent.opacity(0.08) : Color.clear)
    }
}

// MARK: - Helpers

/// Open a link only when it is an absolute http(s) URL, mirroring the React Native
/// `/^https?:\/\//i` guard. Relative/other schemes are ignored.
@MainActor
@discardableResult
func openHTTPLink(_ link: String?, using openURL: OpenURLAction) -> Bool {
    guard let link,
          let url = URL(string: link),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https"
    else { return false }
    openURL(url)
    return true
}

/// Relative "time ago" from an ISO 8601 timestamp, matching the React Native
/// NotificationItemsNative formatting (<60s "just now", <60m "Nm ago",
/// <24h "Nh ago", else "Nd ago"). Returns "" for an unparseable value.
func timeAgo(_ iso: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = formatter.date(from: iso)
    if date == nil {
        formatter.formatOptions = [.withInternetDateTime]
        date = formatter.date(from: iso)
    }
    guard let date else { return "" }
    let diff = Date().timeIntervalSince(date)
    if diff < 60 { return "just now" }
    let minutes = Int(diff / 60)
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    return "\(hours / 24)d ago"
}
#endif
