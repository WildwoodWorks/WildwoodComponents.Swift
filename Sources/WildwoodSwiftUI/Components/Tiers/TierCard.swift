#if os(iOS)
// Tier card family — parity with the TierCard/TierCardHeader/TierCardFeatures/
// TierCardLimits/TierCardFooter subcomponents in the React Native package.

import SwiftUI
import WildwoodCore

public struct TierCard: View {
    let tier: AppTierModel
    let selectedPricing: AppTierPricingModel?
    let isCurrentTier: Bool
    let onSelectPricing: ((AppTierPricingModel) -> Void)?
    let onSubscribe: ((AppTierModel, AppTierPricingModel?) -> Void)?

    public init(
        tier: AppTierModel,
        selectedPricing: AppTierPricingModel? = nil,
        isCurrentTier: Bool = false,
        onSelectPricing: ((AppTierPricingModel) -> Void)? = nil,
        onSubscribe: ((AppTierModel, AppTierPricingModel?) -> Void)? = nil
    ) {
        self.tier = tier
        self.selectedPricing = selectedPricing
        self.isCurrentTier = isCurrentTier
        self.onSelectPricing = onSelectPricing
        self.onSubscribe = onSubscribe
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TierCardHeader(tier: tier, selectedPricing: resolvedPricing, isCurrentTier: isCurrentTier)

            if tier.pricingOptions.count > 1, let onSelectPricing {
                Picker("Billing", selection: Binding(
                    get: { resolvedPricing?.id ?? "" },
                    set: { id in
                        if let pricing = tier.pricingOptions.first(where: { $0.id == id }) {
                            onSelectPricing(pricing)
                        }
                    }
                )) {
                    ForEach(tier.pricingOptions) { pricing in
                        Text(pricing.billingFrequencyLabel ?? pricing.billingFrequency).tag(pricing.id)
                    }
                }
                .pickerStyle(.segmented)
            }

            TierCardFeatures(features: tier.features)
            TierCardLimits(limits: tier.limits)
            TierCardFooter(tier: tier, isCurrentTier: isCurrentTier) {
                onSubscribe?(tier, resolvedPricing)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            if isCurrentTier {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.tint, lineWidth: 2)
            }
        }
    }

    private var resolvedPricing: AppTierPricingModel? {
        selectedPricing
            ?? tier.pricingOptions.first(where: \.isDefault)
            ?? tier.pricingOptions.first
    }
}

public struct TierCardHeader: View {
    let tier: AppTierModel
    let selectedPricing: AppTierPricingModel?
    let isCurrentTier: Bool

    public init(tier: AppTierModel, selectedPricing: AppTierPricingModel?, isCurrentTier: Bool = false) {
        self.tier = tier
        self.selectedPricing = selectedPricing
        self.isCurrentTier = isCurrentTier
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tier.name).font(.title3.weight(.bold))
                if let badgeText = tier.customBadgeText, !badgeText.isEmpty {
                    badge(badgeText)
                }
                // Lifecycle status badge — "Active" is every publicly listed
                // tier's status, so only non-default statuses (Beta,
                // Deprecated, …) are informative enough to show.
                if showStatusBadge {
                    badge(tier.status)
                }
                Spacer()
                if isCurrentTier {
                    Text("Current")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }

            if !tier.description.isEmpty {
                Text(tier.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if tier.showPrice {
                if tier.isFreeTier {
                    Text("Free").font(.title2.weight(.bold))
                } else if let pricing = selectedPricing {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(pricing.price, format: .currency(code: "USD"))
                            .font(.title2.weight(.bold))
                        Text("/ \(pricing.billingFrequencyLabel ?? pricing.billingFrequency)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.2), in: Capsule())
            .foregroundStyle(badgeColor)
    }

    private var showStatusBadge: Bool {
        !tier.badgeColor.isEmpty && !tier.status.isEmpty
            && tier.status.trimmingCharacters(in: .whitespaces).lowercased() != "active"
    }

    /// badgeColor may be a raw CSS hex color ("#c9a227") or a semantic token
    /// ("success"). rgb()/hsl() aren't supported — hex is what WildwoodAdmin
    /// emits for raw colors.
    private var badgeColor: Color {
        Color(hex: tier.badgeColor)
            ?? Color(semanticBadgeToken: tier.badgeColor)
            ?? .accentColor
    }
}

public struct TierCardFeatures: View {
    let features: [AppTierFeatureModel]

    public init(features: [AppTierFeatureModel]) {
        self.features = features
    }

    public var body: some View {
        if !features.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(features.filter(\.isEnabled)) { feature in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                        Text(feature.displayName)
                            .font(.subheadline)
                    }
                }
            }
        }
    }
}

public struct TierCardLimits: View {
    let limits: [AppTierLimitModel]

    public init(limits: [AppTierLimitModel]) {
        self.limits = limits
    }

    public var body: some View {
        if !limits.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(limits) { limit in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "gauge.with.needle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(limit.displayName): \(limitValueText(limit))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func limitValueText(_ limit: AppTierLimitModel) -> String {
        if limit.isUnlimited { return "Unlimited" }
        if let display = limit.maxValueDisplay, !display.isEmpty { return display }
        // Unit intentionally omitted: "Active Pursuits: 5 pursuits" reads as
        // noise — the value + display name already carry it. Units still show
        // in usage dashboards.
        return limit.maxValue.formatted(.number.precision(.fractionLength(0)))
    }
}

public struct TierCardFooter: View {
    let tier: AppTierModel
    let isCurrentTier: Bool
    let onSubscribe: () -> Void
    @Environment(\.openURL) private var openURL

    public init(tier: AppTierModel, isCurrentTier: Bool, onSubscribe: @escaping () -> Void) {
        self.tier = tier
        self.isCurrentTier = isCurrentTier
        self.onSubscribe = onSubscribe
    }

    public var body: some View {
        VStack(spacing: 8) {
            if tier.showSubscribeButton {
                Button {
                    onSubscribe()
                } label: {
                    Text(isCurrentTier ? "Current Plan" : "Select \(tier.name)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCurrentTier)
            }
            if tier.showContactButton, let urlString = tier.contactButtonUrl, let url = URL(string: urlString) {
                Button {
                    openURL(url)
                } label: {
                    Text("Contact Us").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

extension Color {
    /// Parse a #RRGGBB / #RGB hex string (badge colors come from the backend).
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    /// Map the ecosystem's semantic badge tokens (ww-badge-success, …) to
    /// system colors.
    init?(semanticBadgeToken token: String) {
        switch token.trimmingCharacters(in: .whitespaces).lowercased() {
        case "success": self = .green
        case "danger": self = .red
        case "warning": self = .orange
        case "info": self = .blue
        case "primary": self = .accentColor
        case "secondary": self = .gray
        default: return nil
        }
    }
}
#endif
