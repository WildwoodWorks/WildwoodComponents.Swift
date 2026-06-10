#if os(iOS)
// Summary of limits at or over their threshold — parity with
// OverageSummaryComponent. Shares the override/merge hooks with the dashboard.

import SwiftUI
import WildwoodCore

public struct OverageSummaryComponent: View {
    @Environment(\.wildwoodClient) private var client
    @Environment(\.wildwoodTheme) private var theme

    private let appId: String?
    private let limitStatusesOverride: [AppTierLimitStatusModel]?
    private let onMergeUsage: (([AppTierLimitStatusModel]) -> [AppTierLimitStatusModel])?
    private let onUpgradeRequested: (() -> Void)?

    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var statuses: [AppTierLimitStatusModel] = []

    public init(
        appId: String? = nil,
        limitStatusesOverride: [AppTierLimitStatusModel]? = nil,
        onMergeUsage: (([AppTierLimitStatusModel]) -> [AppTierLimitStatusModel])? = nil,
        onUpgradeRequested: (() -> Void)? = nil
    ) {
        self.appId = appId
        self.limitStatusesOverride = limitStatusesOverride
        self.onMergeUsage = onMergeUsage
        self.onUpgradeRequested = onUpgradeRequested
    }

    public var body: some View {
        Group {
            if isLoading {
                LoadingSpinnerView()
            } else if !errorMessage.isEmpty {
                ErrorBannerView(message: errorMessage)
            } else if flagged.isEmpty {
                Label("All usage is within plan limits.", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("\(flagged.count) limit(s) need attention", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(theme.warning)

                    ForEach(flagged) { status in
                        HStack(alignment: .firstTextBaseline) {
                            Circle()
                                .fill(status.isExceeded ? theme.danger : theme.warning)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(status.displayName).font(.subheadline.weight(.medium))
                                Text(status.statusMessage.isEmpty
                                     ? "\(Int(status.usagePercent))% of limit used"
                                     : status.statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }

                    if let onUpgradeRequested {
                        Button("Upgrade Plan") { onUpgradeRequested() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .task { await load() }
    }

    private var flagged: [AppTierLimitStatusModel] {
        statuses.filter { $0.isExceeded || $0.isAtWarningThreshold }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        if let limitStatusesOverride {
            statuses = onMergeUsage?(limitStatusesOverride) ?? limitStatusesOverride
            return
        }

        guard let client = requireClient(client, component: "OverageSummaryComponent") else { return }
        guard let resolvedAppId = appId ?? client.config.appId else {
            errorMessage = "OverageSummaryComponent requires an appId."
            return
        }
        let fetched = await client.appTier.getAllLimitStatuses(appId: resolvedAppId)
        statuses = onMergeUsage?(fetched) ?? fetched
    }
}
#endif
