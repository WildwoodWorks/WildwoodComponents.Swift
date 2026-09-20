#if os(iOS)
// Tier card family — parity with the TierCard/TierCardHeader/TierCardFeatures/
// TierCardLimits/TierCardFooter subcomponents in the React Native package.

import SwiftUI
import WildwoodCore

public struct TierCard: View {
    let tier: AppTierModel
    let selectedPricing: AppTierPricingModel?
    let isCurrentTier: Bool
    /// Fallback ISO code for a tier that carries none of its own (the catalog's, or the app's).
    let currency: String?
    /// Percentage this plan's annual option saves against twelve monthly ones, when the grid is
    /// quoting the year. Nil (or 0) renders no badge.
    let discount: Int?
    /// The plan a pricing link or the host marked as already chosen — the web's `isPreSelected`.
    let isPreSelected: Bool
    let showFeatures: Bool
    let showLimits: Bool
    /// Where a "contact us" plan (no pricing options, not free) sends the visitor when the tier
    /// itself names no contact URL. The web's `enterpriseContactUrl`.
    let enterpriseContactUrl: String?
    let onSelectPricing: ((AppTierPricingModel) -> Void)?
    let onSubscribe: ((AppTierModel, AppTierPricingModel?) -> Void)?

    public init(
        tier: AppTierModel,
        selectedPricing: AppTierPricingModel? = nil,
        isCurrentTier: Bool = false,
        currency: String? = nil,
        discount: Int? = nil,
        isPreSelected: Bool = false,
        showFeatures: Bool = true,
        showLimits: Bool = true,
        enterpriseContactUrl: String? = nil,
        onSelectPricing: ((AppTierPricingModel) -> Void)? = nil,
        onSubscribe: ((AppTierModel, AppTierPricingModel?) -> Void)? = nil
    ) {
        self.tier = tier
        self.selectedPricing = selectedPricing
        self.isCurrentTier = isCurrentTier
        self.currency = currency
        self.discount = discount
        self.isPreSelected = isPreSelected
        self.showFeatures = showFeatures
        self.showLimits = showLimits
        self.enterpriseContactUrl = enterpriseContactUrl
        self.onSelectPricing = onSelectPricing
        self.onSubscribe = onSubscribe
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TierCardHeader(
                tier: tier,
                selectedPricing: resolvedPricing,
                isCurrentTier: isCurrentTier,
                currency: currency,
                discount: discount
            )

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

            if showFeatures {
                TierCardFeatures(features: tier.features)
            }
            if showLimits {
                TierCardLimits(limits: tier.limits)
            }
            TierCardFooter(
                tier: tier,
                isCurrentTier: isCurrentTier,
                isPreSelected: isPreSelected,
                enterpriseContactUrl: enterpriseContactUrl
            ) {
                onSubscribe?(tier, resolvedPricing)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            if isCurrentTier || isPreSelected {
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
    /// Fallback ISO code; the tier's own currency wins when it names one.
    let currency: String?
    /// Percentage saved by paying for the year, when the grid is quoting the year.
    let discount: Int?

    public init(
        tier: AppTierModel,
        selectedPricing: AppTierPricingModel?,
        isCurrentTier: Bool = false,
        currency: String? = nil,
        discount: Int? = nil
    ) {
        self.tier = tier
        self.selectedPricing = selectedPricing
        self.isCurrentTier = isCurrentTier
        self.currency = currency
        self.discount = discount
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
                if isEnterprise {
                    // The web card's word for a plan nobody has published a price for. Without
                    // it the price line is simply blank next to a "Contact Sales" button.
                    Text("Custom").font(.title2.weight(.bold))
                } else if tier.isFreeTier {
                    Text("Free").font(.title2.weight(.bold))
                } else if let pricing = selectedPricing {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        // Through the shared formatter, and in the tier's OWN currency: the
                        // hard-coded "USD" priced a CHF or SEK plan in dollars.
                        Text(WildwoodMoney.format(pricing.price, currency: resolvedCurrency))
                            .font(.title2.weight(.bold))
                        Text("/ \(pricing.billingFrequencyLabel ?? pricing.billingFrequency)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !trialText.isEmpty {
                        Text(trialText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let discount, discount > 0 {
                // The web card's own wording ("Save {discount}%"), not a label: one plan card
                // serves the pricing view, the admin panels and the standalone grid, and its
                // copy has never been host-overridable in any stack.
                let savingsText: String = "Save \(discount)%"
                Text(savingsText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
    }

    /// The platform's "contact us" plan: not free, and priced by nobody. One definition, shared
    /// with the footer, so the price line and the call to action cannot disagree about a plan.
    private var isEnterprise: Bool {
        TierCardRules.isEnterprise(tier)
    }

    /// The tier's own currency, then the catalog's, then nil — which formats as USD.
    private var resolvedCurrency: String? {
        if let own = tier.currency, !own.trimmingCharacters(in: .whitespaces).isEmpty { return own }
        return currency
    }

    /// The trial line under the price. Shown only for a paid, non-free plan whose SELECTED
    /// pricing option starts one — the same gate the web card uses.
    private var trialText: String {
        guard let pricing = selectedPricing, !tier.isFreeTier, pricing.price > 0 else { return "" }
        return WildwoodTrial.label(days: pricing.trialDays)
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
    /// Already chosen elsewhere (a pricing link, a host's `highlightTierId`): the call to action
    /// continues with this plan rather than inviting a fresh choice.
    let isPreSelected: Bool
    /// Where a "contact us" plan goes when the tier names no contact URL of its own.
    let enterpriseContactUrl: String?
    let onSubscribe: () -> Void
    @Environment(\.openURL) private var openURL

    public init(
        tier: AppTierModel,
        isCurrentTier: Bool,
        isPreSelected: Bool = false,
        enterpriseContactUrl: String? = nil,
        onSubscribe: @escaping () -> Void
    ) {
        self.tier = tier
        self.isCurrentTier = isCurrentTier
        self.isPreSelected = isPreSelected
        self.enterpriseContactUrl = enterpriseContactUrl
        self.onSubscribe = onSubscribe
    }

    public var body: some View {
        // Exactly ONE call to action renders, chosen by ``TierCardRules/footerAction(tier:isCurrentTier:isPreSelected:enterpriseContactUrl:)``
        // — the web card's priority chain (current plan, the tier's own contact button, the host's
        // enterprise URL, an enterprise button that raises the selection, then the ordinary
        // Select). A plan with nothing to buy can therefore never also offer to sell it.
        VStack(spacing: 8) {
            switch action {
            case .current(let title):
                actionButton(title, prominent: true, disabled: true) {}
            case .contactUs(let url):
                linkButton(TierCardRules.contactUsTitle, url: url)
            case .contactSales(let url):
                linkButton(TierCardRules.contactSalesTitle, url: url)
            case .contactSalesRequest(let title):
                actionButton(title, prominent: false, disabled: false, perform: onSubscribe)
            case .subscribe(let title):
                actionButton(title, prominent: true, disabled: false, perform: onSubscribe)
            case TierFooterAction.none:
                EmptyView()
            }
        }
    }

    /// The one decision this footer makes, made outside the `body`.
    private var action: TierFooterAction {
        TierCardRules.footerAction(
            tier: tier,
            isCurrentTier: isCurrentTier,
            isPreSelected: isPreSelected,
            enterpriseContactUrl: enterpriseContactUrl
        )
    }

    @ViewBuilder private func actionButton(
        _ title: String,
        prominent: Bool,
        disabled: Bool,
        perform: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(action: perform) {
                Text(title).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(disabled)
        } else {
            Button(action: perform) {
                Text(title).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(disabled)
        }
    }

    private func linkButton(_ title: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
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
