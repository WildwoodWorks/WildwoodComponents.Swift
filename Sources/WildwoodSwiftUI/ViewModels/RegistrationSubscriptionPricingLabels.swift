// The copy the pricing view says, and the `{slot}` formatter every label with a value uses.
//
// Values are the JS defaults byte for byte
// (packages/wildwood-react-shared/src/registrationSubscription/labels.ts, Appendix A C.2), so the
// stacks say the same words. Only the PRICING keys are here: the full overridable set —
// `RegistrationSubscriptionLabels`, covering signup and manage as well — arrives with those views,
// and this struct is the pricing slice of it. The view reads members BY NAME and never writes a
// sentence of its own, so the full type can take this one's place without touching a call site.
//
// What is NOT here, on purpose: the plan card's own call-to-action texts ("Current Plan",
// "Select <Tier>", "Contact Us", "Contact Sales", "Free", "Save N%"). Those live on the shared
// ``TierCard`` in every stack — React says so in as many words ("Plan-card CTAs are NOT labels")
// — because one card serves the pricing view, the admin panels and the standalone pricing grid.

import Foundation

/// The pricing view's overridable copy. Every member defaults to the JS default string, so a host
/// overrides one by naming one: `RegistrationSubscriptionPricingLabels(retry: "Try again")`.
public struct RegistrationSubscriptionPricingLabels: Sendable, Equatable {
    /// The monthly side of the billing switch.
    public var billingMonthly: String
    /// The annual side of the billing switch.
    public var billingAnnual: String
    /// What a screen reader calls the billing switch.
    public var billingToggleAriaLabel: String
    /// The best annual saving on offer. Carries a `{percent}` slot.
    public var annualSavings: String
    /// What a screen reader hears while the prices load.
    public var loadingPlans: String
    /// Said when the catalog could not be read. No price is shown with it.
    public var pricingUnavailable: String
    /// Loads the catalog again, bypassing the cache.
    public var retry: String
    /// A contact link's text, where a view rather than the plan card renders one.
    public var contactUs: String
    /// The trailing group that holds packs no host group claimed.
    public var morePacks: String
    /// Said in place of a price for a pack the operator has not priced.
    public var packUnavailable: String
    /// The single-select pack call to action.
    public var packSelect: String
    /// The same call to action for a screen reader. Carries a `{name}` slot.
    public var packSelectNamed: String
    /// The multi-select Continue, for any count but one. Carries a `{count}` slot.
    public var continueWithPacks: String
    /// The multi-select Continue when exactly one pack is ticked.
    public var continueWithOnePack: String

    public init(
        billingMonthly: String = "Monthly",
        billingAnnual: String = "Annual",
        billingToggleAriaLabel: String = "Toggle annual billing",
        annualSavings: String = "Save up to {percent}%",
        loadingPlans: String = "Loading plans...",
        pricingUnavailable: String = "Pricing is unavailable right now",
        retry: String = "Retry",
        contactUs: String = "Contact us",
        morePacks: String = "More packs",
        packUnavailable: String = "Not yet available",
        packSelect: String = "Select",
        packSelectNamed: String = "Select {name}",
        continueWithPacks: String = "Continue with {count} packs",
        continueWithOnePack: String = "Continue with 1 pack"
    ) {
        self.billingMonthly = billingMonthly
        self.billingAnnual = billingAnnual
        self.billingToggleAriaLabel = billingToggleAriaLabel
        self.annualSavings = annualSavings
        self.loadingPlans = loadingPlans
        self.pricingUnavailable = pricingUnavailable
        self.retry = retry
        self.contactUs = contactUs
        self.morePacks = morePacks
        self.packUnavailable = packUnavailable
        self.packSelect = packSelect
        self.packSelectNamed = packSelectNamed
        self.continueWithPacks = continueWithPacks
        self.continueWithOnePack = continueWithOnePack
    }

    /// The JS defaults, unchanged.
    public static let defaults = RegistrationSubscriptionPricingLabels()
}

/// The `{slot}` substitution JS calls `formatLabel`.
public enum RegistrationSubscriptionLabelFormat {
    /// Replace every `{key}` in `template` with its value. A slot with no value is left VERBATIM,
    /// exactly as the JS helper leaves it: a host that translated a label and dropped a slot sees
    /// the slot rather than a hole where a number should be.
    public static func format(_ template: String, values: [String: String]) -> String {
        var result: String = template
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{" + key + "}", with: value)
        }
        return result
    }
}
