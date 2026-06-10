#if os(iOS)
// Current tier display + upgrade path for the authenticated user — parity
// with AppTierComponent.

import SwiftUI
import WildwoodCore

public struct AppTierComponent: View {
    @Environment(\.wildwoodClient) private var client

    private let appId: String?
    private let showUpgradeOptions: Bool
    private let onTierChangeRequested: ((AppTierModel, AppTierPricingModel?) -> Void)?

    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var subscription: UserTierSubscriptionModel?
    @State private var tiers: [AppTierModel] = []
    @State private var selectedPricingByTier: [String: String] = [:]

    public init(
        appId: String? = nil,
        showUpgradeOptions: Bool = true,
        onTierChangeRequested: ((AppTierModel, AppTierPricingModel?) -> Void)? = nil
    ) {
        self.appId = appId
        self.showUpgradeOptions = showUpgradeOptions
        self.onTierChangeRequested = onTierChangeRequested
    }

    public var body: some View {
        Group {
            if isLoading {
                LoadingSpinnerView(label: "Loading subscription…")
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if !errorMessage.isEmpty {
                        ErrorBannerView(message: errorMessage) { errorMessage = "" }
                    }

                    currentSubscriptionCard

                    if showUpgradeOptions, !tiers.isEmpty {
                        Text("Available Plans").font(.headline)
                        ForEach(tiers) { tier in
                            TierCard(
                                tier: tier,
                                selectedPricing: selectedPricing(for: tier),
                                isCurrentTier: tier.id == subscription?.appTierId,
                                onSelectPricing: { pricing in
                                    selectedPricingByTier[tier.id] = pricing.id
                                },
                                onSubscribe: { tier, pricing in
                                    onTierChangeRequested?(tier, pricing)
                                }
                            )
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder private var currentSubscriptionCard: some View {
        if let subscription {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(subscription.tierName).font(.title3.weight(.bold))
                    Spacer()
                    Text(subscription.status)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.green.opacity(0.15), in: Capsule())
                }
                if !subscription.tierDescription.isEmpty {
                    Text(subscription.tierDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let periodEnd = subscription.currentPeriodEnd {
                    Text("Current period ends \(periodEnd.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !subscription.pendingTierName.isEmpty, let changeDate = subscription.pendingChangeDate {
                    Label(
                        "Changing to \(subscription.pendingTierName) on \(changeDate.formatted(date: .abbreviated, time: .omitted))",
                        systemImage: "clock.arrow.circlepath"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        } else {
            ContentUnavailableView(
                "No active subscription",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("Choose a plan below to get started.")
            )
        }
    }

    private func selectedPricing(for tier: AppTierModel) -> AppTierPricingModel? {
        if let id = selectedPricingByTier[tier.id] {
            return tier.pricingOptions.first { $0.id == id }
        }
        return tier.pricingOptions.first(where: \.isDefault) ?? tier.pricingOptions.first
    }

    private func load() async {
        guard let client = requireClient(client, component: "AppTierComponent") else { return }
        isLoading = true
        defer { isLoading = false }
        guard let resolvedAppId = appId ?? client.config.appId else {
            errorMessage = "AppTierComponent requires an appId."
            return
        }
        async let sub = client.appTier.getUserSubscription(appId: resolvedAppId)
        async let loadedTiers = client.appTier.getTiers(appId: resolvedAppId)
        subscription = await sub
        tiers = await loadedTiers.sorted { $0.displayOrder < $1.displayOrder }
    }
}
#endif
