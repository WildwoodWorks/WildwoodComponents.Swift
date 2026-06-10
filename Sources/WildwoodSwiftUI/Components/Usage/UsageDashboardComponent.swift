#if os(iOS)
// Usage dashboard with per-limit progress — parity with UsageDashboardComponent,
// including the limitStatusesOverride / onMergeUsage hooks added May 2026.

import SwiftUI
import WildwoodCore

public struct UsageDashboardComponent: View {
    @Environment(\.wildwoodClient) private var client
    @Environment(\.wildwoodTheme) private var theme

    private let appId: String?
    /// Bypass the API call entirely and render these statuses.
    private let limitStatusesOverride: [AppTierLimitStatusModel]?
    /// Merge or transform fetched statuses with local data before rendering.
    private let onMergeUsage: (([AppTierLimitStatusModel]) -> [AppTierLimitStatusModel])?

    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var statuses: [AppTierLimitStatusModel] = []

    public init(
        appId: String? = nil,
        limitStatusesOverride: [AppTierLimitStatusModel]? = nil,
        onMergeUsage: (([AppTierLimitStatusModel]) -> [AppTierLimitStatusModel])? = nil
    ) {
        self.appId = appId
        self.limitStatusesOverride = limitStatusesOverride
        self.onMergeUsage = onMergeUsage
    }

    public var body: some View {
        Group {
            if isLoading {
                LoadingSpinnerView(label: "Loading usage…")
            } else if !errorMessage.isEmpty {
                ErrorBannerView(message: errorMessage)
            } else if statuses.isEmpty {
                ContentUnavailableView("No usage limits", systemImage: "gauge", description: Text("This plan has no tracked limits."))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(statuses) { status in
                        UsageLimitRow(status: status, theme: theme)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        if let limitStatusesOverride {
            statuses = onMergeUsage?(limitStatusesOverride) ?? limitStatusesOverride
            return
        }

        guard let client = requireClient(client, component: "UsageDashboardComponent") else { return }
        guard let resolvedAppId = appId ?? client.config.appId else {
            errorMessage = "UsageDashboardComponent requires an appId."
            return
        }
        let fetched = await client.appTier.getAllLimitStatuses(appId: resolvedAppId)
        statuses = onMergeUsage?(fetched) ?? fetched
    }
}

struct UsageLimitRow: View {
    let status: AppTierLimitStatusModel
    let theme: WildwoodTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(status.displayName).font(.subheadline.weight(.medium))
                Spacer()
                Text(valueText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !status.isUnlimited {
                ProgressView(value: min(status.usagePercent / 100, 1))
                    .tint(barColor)
            }
            if !status.statusMessage.isEmpty {
                Text(status.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(status.isExceeded ? theme.danger : .secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var valueText: String {
        let used = status.currentUsage.formatted(.number.precision(.fractionLength(0)))
        if status.isUnlimited {
            return status.unit.isEmpty ? "\(used) (unlimited)" : "\(used) \(status.unit) (unlimited)"
        }
        let max = status.maxValue.formatted(.number.precision(.fractionLength(0)))
        return status.unit.isEmpty ? "\(used) / \(max)" : "\(used) / \(max) \(status.unit)"
    }

    private var barColor: Color {
        if status.isExceeded { return theme.danger }
        if status.isAtWarningThreshold { return theme.warning }
        return theme.success
    }
}
#endif
