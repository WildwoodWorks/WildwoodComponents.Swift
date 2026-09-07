#if os(iOS)
// Summary of limits at or over their threshold — parity with
// OverageSummaryComponent. Shares the override/merge hooks with the dashboard.

import SwiftUI
import WildwoodCore

public struct OverageSummaryComponent: View {
    @Environment(\.wildwoodClient) private var client
    @Environment(\.wildwoodTheme) private var theme

    private let appId: String?
    /// Replaces the (merged) statuses instead of fetching them; never passed
    /// through `onMergeUsage` (React/RN/Blazor semantics).
    private let limitStatusesOverride: [AppTierLimitStatusModel]?
    /// Same closure shape as UsageDashboardComponent so the package has one type.
    private let onMergeUsage: (@MainActor ([AppTierLimitStatusModel], UserTierSubscriptionModel?) async -> [AppTierLimitStatusModel])?
    private let onUpgradeRequested: (() -> Void)?

    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var statuses: [AppTierLimitStatusModel] = []
    @State private var subscription: UserTierSubscriptionModel?

    public init(
        appId: String? = nil,
        limitStatusesOverride: [AppTierLimitStatusModel]? = nil,
        onMergeUsage: (@MainActor ([AppTierLimitStatusModel], UserTierSubscriptionModel?) async -> [AppTierLimitStatusModel])? = nil,
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

    /// The same 80% threshold the dashboard defaults to, so both surfaces flag
    /// the same limits.
    private var flagged: [AppTierLimitStatusModel] {
        statuses.filter { UsageMath.barState($0, warningThreshold: 80) != .ok }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        // Subscription is an enrichment passed to onMergeUsage; a failed lookup
        // keeps the previous value instead of erroring the summary.
        if let client, let id = appId ?? client.config.appId {
            do { subscription = try await client.appTier.getUserSubscription(appId: id) } catch { }
        }

        // The override REPLACES the merged output; it is never passed through onMergeUsage.
        if let limitStatusesOverride {
            statuses = limitStatusesOverride
            return
        }

        guard let client = requireClient(client, component: "OverageSummaryComponent") else { return }
        guard let resolvedAppId = appId ?? client.config.appId else {
            errorMessage = "OverageSummaryComponent requires an appId."
            return
        }
        let fetched = await client.appTier.getAllLimitStatuses(appId: resolvedAppId)
        if let onMergeUsage {
            statuses = await onMergeUsage(fetched, subscription)
        } else {
            statuses = fetched
        }
    }
}
#endif
