#if os(iOS)
// The plan a signup link already chose, shown above the registration form.
//
// The visitor picked this on a pricing screen, so the signup does not ask again — it shows what
// they are getting, at the price the catalog is quoting this minute, and offers a way back to the
// grid.
//
// A plan with no pricing option is never given a made-up number: a free plan says so, and anything
// else says nothing rather than implying it costs nothing. That decision, and the `/frequency`
// suffix beside the amount, are ``SignupViewRules`` so they can be tested without a simulator.

import SwiftUI
import WildwoodCore

public struct PlanSummaryCardView: View {
    @Environment(\.wildwoodTheme) private var theme

    /// The chosen plan, from the live catalog.
    let tier: AppTierModel
    /// The pricing option being bought, or nil for a plan with no price at all.
    let pricing: AppTierPricingModel?
    /// The currency the catalog is quoted in.
    let currency: String
    let labels: RegistrationSubscriptionSignupLabels
    /// Offers "Change plan". Omitted, the card is read-only — the plan is not the visitor's to
    /// change, which is what a `skip` flow means.
    let onChangePlan: (() -> Void)?

    public init(
        tier: AppTierModel,
        pricing: AppTierPricingModel? = nil,
        currency: String,
        labels: RegistrationSubscriptionSignupLabels = .defaults,
        onChangePlan: (() -> Void)? = nil
    ) {
        self.tier = tier
        self.pricing = pricing
        self.currency = currency
        self.labels = labels
        self.onChangePlan = onChangePlan
    }

    public var body: some View {
        // A free plan advertises no trial: there is nothing to trial into.
        let trial: String = tier.isFreeTier ? "" : WildwoodTrial.label(days: pricing?.trialDays)
        let priceText: String = SignupViewRules.planPriceText(
            tier: tier,
            pricing: pricing,
            currency: currency,
            labels: labels
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.name)
                        .font(.headline)
                    if !tier.description.isEmpty {
                        Text(tier.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !priceText.isEmpty {
                    Text(priceText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(theme.accent)
                }
            }

            if !trial.isEmpty {
                Text(trial)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.success)
            }

            if let onChangePlan {
                Button(labels.changePlan) { onChangePlan() }
                    .font(.footnote)
                    .accessibilityIdentifier(RegistrationSubscriptionTestID.planChange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(RegistrationSubscriptionTestID.planSummaryCard)
    }
}
#endif
