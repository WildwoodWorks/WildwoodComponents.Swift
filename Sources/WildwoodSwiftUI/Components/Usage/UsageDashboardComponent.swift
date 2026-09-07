#if os(iOS)
// Usage dashboard with per-limit progress — parity with UsageDashboardComponent
// in React/RN/Blazor/Razor: optional header with tier badge, threshold-driven
// bars, overage / hard-block indicators, and an upgrade call to action.

import SwiftUI
import WildwoodCore

public struct UsageDashboardComponent: View {
    @Environment(\.wildwoodClient) private var client
    @Environment(\.wildwoodTheme) private var theme

    private let appId: String?
    private let title: String?
    private let subtitle: String?
    /// Show the "Overage: N over limit" line for exceeded soft caps.
    private let showOverageInfo: Bool
    /// Percentage at which a limit renders in its warning state (default 80).
    private let warningThreshold: Double
    /// Replaces the (merged) statuses instead of fetching them; never passed
    /// through `onMergeUsage` (React/RN/Blazor semantics).
    private let limitStatusesOverride: [AppTierLimitStatusModel]?
    /// Replaces the fetched subscription; nil fetches it.
    private let subscriptionOverride: UserTierSubscriptionModel?
    /// Merge or transform fetched statuses before rendering. `@MainActor async`
    /// so host closures may touch UI state, and may be sync or async.
    private let onMergeUsage: (@MainActor ([AppTierLimitStatusModel], UserTierSubscriptionModel?) async -> [AppTierLimitStatusModel])?
    private let onUpgradeClick: (() -> Void)?

    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var statuses: [AppTierLimitStatusModel] = []
    @State private var subscription: UserTierSubscriptionModel?

    public init(
        appId: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        showOverageInfo: Bool = true,
        warningThreshold: Double = 80,
        limitStatusesOverride: [AppTierLimitStatusModel]? = nil,
        subscriptionOverride: UserTierSubscriptionModel? = nil,
        onMergeUsage: (@MainActor ([AppTierLimitStatusModel], UserTierSubscriptionModel?) async -> [AppTierLimitStatusModel])? = nil,
        onUpgradeClick: (() -> Void)? = nil
    ) {
        self.appId = appId
        self.title = title
        self.subtitle = subtitle
        self.showOverageInfo = showOverageInfo
        self.warningThreshold = warningThreshold
        self.limitStatusesOverride = limitStatusesOverride
        self.subscriptionOverride = subscriptionOverride
        self.onMergeUsage = onMergeUsage
        self.onUpgradeClick = onUpgradeClick
    }

    public var body: some View {
        Group {
            if isLoading {
                LoadingSpinnerView(label: "Loading usage…")
            } else if !errorMessage.isEmpty {
                ErrorBannerView(message: errorMessage)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if title != nil || subtitle != nil || subscription != nil {
                        header
                    }

                    if statuses.isEmpty {
                        ContentUnavailableView("No usage limits", systemImage: "gauge", description: Text("This plan has no tracked limits."))
                    } else {
                        ForEach(statuses) { status in
                            UsageLimitRow(
                                status: status,
                                theme: theme,
                                warningThreshold: warningThreshold,
                                showOverageInfo: showOverageInfo
                            )
                        }
                    }

                    if UsageMath.anyAtWarning(statuses, warningThreshold: warningThreshold), onUpgradeClick != nil {
                        upgradeCallToAction
                    }
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title).font(.title3.weight(.bold))
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let subscription {
                Text(subscription.tierName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        (subscription.isFreeTier ? Color.secondary : theme.accent).opacity(0.15),
                        in: Capsule()
                    )
            }
        }
    }

    @ViewBuilder private var upgradeCallToAction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(UsageMath.anyOverage(statuses)
                 ? "You have exceeded one or more usage limits."
                 : "You are approaching your usage limits.")
                .font(.callout)
            Button {
                onUpgradeClick?()
            } label: {
                Label("Upgrade Plan", systemImage: "arrow.up")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        // Subscription is an enrichment (tier badge + onMergeUsage argument); a failed
        // lookup keeps the previous value instead of erroring the dashboard (useUsageDashboard).
        if let subscriptionOverride {
            subscription = subscriptionOverride
        } else if let client, let id = appId ?? client.config.appId {
            do { subscription = try await client.appTier.getUserSubscription(appId: id) } catch { }
        }

        // The override REPLACES the merged output; it is never passed through onMergeUsage.
        if let limitStatusesOverride {
            statuses = limitStatusesOverride
            return
        }

        guard let client = requireClient(client, component: "UsageDashboardComponent") else { return }
        guard let resolvedAppId = appId ?? client.config.appId else {
            errorMessage = "UsageDashboardComponent requires an appId."
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

struct UsageLimitRow: View {
    let status: AppTierLimitStatusModel
    let theme: WildwoodTheme
    // Defaulted so UsageLimitsPanel (the admin reuse of this row) keeps its
    // two-argument call site and both surfaces share the same 80% rule.
    var warningThreshold: Double = 80
    var showOverageInfo: Bool = true

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
            // Soft caps report the overage; hard caps report the block instead.
            if showOverageInfo, status.isExceeded, !status.isHardBlocked {
                Label("Overage: \(overageText) over limit", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(theme.warning)
            }
            if status.isExceeded, status.isHardBlocked {
                Label("Limit reached", systemImage: "nosign")
                    .font(.caption2)
                    .foregroundStyle(theme.danger)
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

    private var overageText: String {
        (status.currentUsage - status.maxValue).formatted(.number.precision(.fractionLength(0)))
    }

    private var barColor: Color {
        switch UsageMath.barState(status, warningThreshold: warningThreshold) {
        case .exceeded: return theme.danger
        case .warning: return theme.warning
        case .ok: return theme.success
        }
    }
}
#endif
