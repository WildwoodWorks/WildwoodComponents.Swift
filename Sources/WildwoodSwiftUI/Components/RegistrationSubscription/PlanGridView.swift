#if os(iOS)
// The plan grid: the monthly/annual switch over a column of ``TierCard``s.
//
// Deliberately the SAME card ``PricingDisplayComponent``, ``AppTierComponent`` and the admin
// `TierPlansPanel` render, footer call to action and all, rather than a second plan card that would
// drift from it. This grid adds only what the pricing view needs on top: the plans come from the
// live public catalog, and the billing cycle is owned by the view so a pack selection can be
// stamped with it too.
//
// Every decision here — which option a plan is quoted at, whether a toggle is honest, the best
// annual saving — is a function in ``PricingViewRules``, because nothing in a `body` can be tested
// on a machine with no simulator.

import SwiftUI
import WildwoodCore

public struct PlanGridView: View {
    @Environment(\.wildwoodTheme) private var theme

    /// Active plans in catalog order. Already filtered — this grid renders what it is given.
    let tiers: [AppTierModel]
    /// The currency every price in the grid is quoted in.
    let currency: String
    let billing: PricingBilling
    let showBillingToggle: Bool
    let showFeatures: Bool
    let showLimits: Bool
    /// Marks one plan as already chosen.
    let highlightTierId: String?
    /// Where a "contact us" plan points when it names no URL of its own.
    let contactUrl: String?
    let labels: RegistrationSubscriptionPricingLabels
    let onBillingChange: (PricingBilling) -> Void
    let onSelectTier: (AppTierModel) -> Void

    public init(
        tiers: [AppTierModel],
        currency: String,
        billing: PricingBilling,
        showBillingToggle: Bool = true,
        showFeatures: Bool = true,
        showLimits: Bool = true,
        highlightTierId: String? = nil,
        contactUrl: String? = nil,
        labels: RegistrationSubscriptionPricingLabels = .defaults,
        onBillingChange: @escaping (PricingBilling) -> Void,
        onSelectTier: @escaping (AppTierModel) -> Void
    ) {
        self.tiers = tiers
        self.currency = currency
        self.billing = billing
        self.showBillingToggle = showBillingToggle
        self.showFeatures = showFeatures
        self.showLimits = showLimits
        self.highlightTierId = highlightTierId
        self.contactUrl = contactUrl
        self.labels = labels
        self.onBillingChange = onBillingChange
        self.onSelectTier = onSelectTier
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsToggle {
                billingToggle
            }
            ForEach(tiers) { tier in
                planCard(tier)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pieces

    private func planCard(_ tier: AppTierModel) -> some View {
        TierCard(
            tier: tier,
            selectedPricing: PricingViewRules.planPriceOption(tier, billing: billing),
            currency: currency,
            discount: discount(for: tier),
            isPreSelected: PricingViewRules.isHighlighted(tierId: tier.id, highlightTierId: highlightTierId),
            showFeatures: showFeatures,
            showLimits: showLimits,
            enterpriseContactUrl: contactUrl,
            onSubscribe: { chosen, _ in onSelectTier(chosen) }
        )
    }

    @ViewBuilder private var billingToggle: some View {
        let annual: Bool = billing == .annual
        let monthlyColor: Color = annual ? Color.secondary : theme.accent
        let annualColor: Color = annual ? theme.accent : Color.secondary

        HStack(spacing: 10) {
            Text(labels.billingMonthly)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(monthlyColor)

            Toggle(isOn: toggleBinding) {
                Text(labels.billingToggleAriaLabel)
            }
            .labelsHidden()
            .accessibilityLabel(labels.billingToggleAriaLabel)
            .accessibilityIdentifier(RegistrationSubscriptionTestID.billingToggle)

            Text(labels.billingAnnual)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(annualColor)

            if bestDiscount > 0 {
                savingsBadge
            }
            Spacer()
        }
    }

    private var savingsBadge: some View {
        let savings: String = PricingViewRules.annualSavingsLabel(percent: bestDiscount, labels: labels)
        return Text(savings)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(theme.success.opacity(0.18), in: Capsule())
            .foregroundStyle(theme.success)
    }

    // MARK: - Derived state

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { billing == .annual },
            set: { isAnnual in onBillingChange(isAnnual ? .annual : .monthly) }
        )
    }

    /// A toggle with nothing to switch to is a control that lies, so it appears only once some
    /// plan is actually priced by the year.
    private var showsToggle: Bool {
        showBillingToggle && PricingViewRules.hasAnnualPricing(tiers)
    }

    private var bestDiscount: Int {
        showsToggle ? PricingViewRules.bestAnnualDiscount(tiers) : 0
    }

    /// The card's own saving badge, shown only while the year is what is being quoted.
    private func discount(for tier: AppTierModel) -> Int? {
        guard billing == .annual else { return nil }
        return PricingViewRules.annualDiscount(tier)
    }
}
#endif
