#if os(iOS)
// Public pricing grid (no auth required) — parity with PricingDisplayComponent.

import SwiftUI
import WildwoodCore

public struct PricingDisplayComponent: View {
    @Environment(\.wildwoodClient) private var client

    private let appId: String?
    private let onTierSelected: ((AppTierModel, AppTierPricingModel?) -> Void)?

    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var tiers: [AppTierModel] = []
    @State private var selectedPricingByTier: [String: String] = [:]

    public init(appId: String? = nil, onTierSelected: ((AppTierModel, AppTierPricingModel?) -> Void)? = nil) {
        self.appId = appId
        self.onTierSelected = onTierSelected
    }

    public var body: some View {
        Group {
            if isLoading {
                LoadingSpinnerView(label: "Loading plans…")
            } else if !errorMessage.isEmpty {
                ErrorBannerView(message: errorMessage)
            } else if tiers.isEmpty {
                ContentUnavailableView("No plans available", systemImage: "rectangle.on.rectangle.slash")
            } else {
                VStack(spacing: 16) {
                    ForEach(tiers) { tier in
                        TierCard(
                            tier: tier,
                            selectedPricing: selectedPricing(for: tier),
                            onSelectPricing: { pricing in
                                selectedPricingByTier[tier.id] = pricing.id
                            },
                            onSubscribe: { tier, pricing in
                                onTierSelected?(tier, pricing)
                            }
                        )
                    }
                }
            }
        }
        .task { await load() }
    }

    private func selectedPricing(for tier: AppTierModel) -> AppTierPricingModel? {
        if let id = selectedPricingByTier[tier.id] {
            return tier.pricingOptions.first { $0.id == id }
        }
        return tier.pricingOptions.first(where: \.isDefault) ?? tier.pricingOptions.first
    }

    private func load() async {
        guard let client = requireClient(client, component: "PricingDisplayComponent") else { return }
        isLoading = true
        defer { isLoading = false }
        guard let resolvedAppId = appId ?? client.config.appId else {
            errorMessage = "PricingDisplayComponent requires an appId."
            return
        }
        let loaded = await client.appTier.getTiers(appId: resolvedAppId)
        tiers = loaded.sorted { $0.displayOrder < $1.displayOrder }
    }
}
#endif
