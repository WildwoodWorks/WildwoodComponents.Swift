// What a component hands a host when a plan needs paying for — the Swift shape of JS's
// `PaymentRequiredArgs` (JS 05dd7cb).
//
// The bug this type exists to prevent: a host that wires `onPaymentRequired` into
// `PaymentComponent` without a pricing model gets a one-off charge with no recurring
// subscription, no renewal and no trial, because the server has no pricing model to attach the
// subscription to. Every producer fills these fields from the pricing option the user picked, and
// `price` is the PLAN's own price — never the prorated charge a preview quoted for today, which
// would bill the wrong amount on the next period.

import Foundation
import WildwoodCore

public struct WildwoodPaymentRequiredArgs: Sendable, Equatable {
    /// The plan being bought.
    public var tier: AppTierModel
    /// The pricing option the user picked, when the tier sells more than one.
    public var pricing: AppTierPricingModel?
    /// The pricing MODEL id (not the tier-pricing link id) the payment must carry.
    public var pricingModelId: String?
    /// The plan's own price, in major units — not the prorated charge for today.
    public var price: Double
    /// ISO code the price is quoted in; nil means the app default (USD).
    public var currency: String?
    /// Free-trial days on the chosen pricing option, when it starts one.
    public var trialDays: Int?
    /// Whether the payment sets up a recurring subscription rather than a one-off charge.
    public var isSubscription: Bool

    /// Derive the args from the plan and the option the user picked — the producer every
    /// component uses, so no caller re-derives the rule.
    ///
    /// - Parameter fallbackCurrency: the catalog's (or the preview response's) currency, used
    ///   only when the tier itself names none. Nil all the way down formats as USD.
    public init(tier: AppTierModel, pricing: AppTierPricingModel?, fallbackCurrency: String? = nil) {
        self.tier = tier
        self.pricing = pricing
        let modelId = pricing?.pricingModelId
        self.pricingModelId = (modelId?.isEmpty == false) ? modelId : nil
        let planPrice = pricing?.price ?? 0
        self.price = planPrice
        self.currency = tier.currency ?? fallbackCurrency
        self.trialDays = pricing?.trialDays
        self.isSubscription = !tier.isFreeTier && planPrice > 0
    }

    /// Full control, for a producer that already knows every value.
    public init(
        tier: AppTierModel,
        pricing: AppTierPricingModel?,
        pricingModelId: String?,
        price: Double,
        currency: String?,
        trialDays: Int?,
        isSubscription: Bool
    ) {
        self.tier = tier
        self.pricing = pricing
        self.pricingModelId = pricingModelId
        self.price = price
        self.currency = currency
        self.trialDays = trialDays
        self.isSubscription = isSubscription
    }

    public static func == (lhs: WildwoodPaymentRequiredArgs, rhs: WildwoodPaymentRequiredArgs) -> Bool {
        lhs.tier == rhs.tier
            && lhs.pricing == rhs.pricing
            && lhs.pricingModelId == rhs.pricingModelId
            && lhs.price == rhs.price
            && lhs.currency == rhs.currency
            && lhs.trialDays == rhs.trialDays
            && lhs.isSubscription == rhs.isSubscription
    }
}
