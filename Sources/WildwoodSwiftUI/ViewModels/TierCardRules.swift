// What a plan card's footer offers — decided once, here, as a value.
//
// One card (``TierCard``) serves five surfaces: the pricing view's plan grid, ``AppTierComponent``,
// ``PricingDisplayComponent``, the admin `TierPlansPanel` and ``SignupWithSubscriptionComponent``.
// Its footer used to decide what to show with a pair of independent `if`s inside a `body`, which
// could put two calls to action on one card — a "Contact Us" link for a plan that sells nothing
// AND a Select button that raised a selection for it.
//
// So the footer is a PRIORITY CHAIN, ported from
// packages/wildwood-react/src/components/tier/TierCardFooter.tsx, where each branch returns and
// exactly one thing renders:
//
//  0. the plan the visitor is already on — a label, not an offer;
//  1. the tier's OWN contact button (`showContactButton` + `contactButtonUrl`);
//  2. an enterprise plan under the host's `enterpriseContactUrl`;
//  3. an enterprise plan with nowhere to send anyone — React renders "Contact Sales" as a BUTTON
//     that raises the selection, leaving the host to do the contacting;
//  4. the ordinary subscribe call to action.
//
// The chain lives in this file rather than in the view because nothing inside a SwiftUI `body` can
// be tested on a machine with no simulator, and because the answer is also what decides whether a
// selection may be handed to a host at all (``raisesSelection(_:)``).

import Foundation
import WildwoodCore

/// The ONE call to action a ``TierCardFooter`` renders. Exactly one case applies to any plan, so a
/// plan with nothing to buy can never also offer to sell it.
public enum TierFooterAction: Sendable, Equatable {
    /// Priority 0 — the visitor is already on this plan. Shown disabled; it buys nothing.
    case current(title: String)
    /// Priority 1 — the tier's own contact button. Opens a URL; raises no selection.
    case contactUs(url: URL)
    /// Priority 2 — an enterprise plan under the host's contact URL. Opens a URL; raises no
    /// selection.
    case contactSales(url: URL)
    /// Priority 3 — an enterprise plan and no contact URL anywhere. The button raises the
    /// selection so the host can start its own contact flow: this is React's priority 3, and the
    /// only way a plan with no pricing may hand a payload back without being a free plan.
    case contactSalesRequest(title: String)
    /// Priority 4 — the ordinary buy/switch call to action.
    case subscribe(title: String)
    /// Nothing to offer: the tier suppressed its call to action and named no contact URL.
    case none
}

/// The plan card's decisions, as pure functions with no SwiftUI in them.
public enum TierCardRules {
    // The copy is the card's own, in every stack: one plan card serves the pricing view, the admin
    // panels, signup and the standalone grid, and none of them has ever overridden these strings.
    public static let currentPlanTitle: String = "Current Plan"
    public static let contactUsTitle: String = "Contact Us"
    public static let contactSalesTitle: String = "Contact Sales"
    public static let preSelectedSubscribeTitle: String = "Continue with This Plan"

    /// The ordinary call to action's wording.
    public static func subscribeTitle(tierName: String) -> String {
        "Select \(tierName)"
    }

    /// The platform's "contact us" plan: not free, and priced by nobody.
    public static func isEnterprise(isFreeTier: Bool, hasPricingOptions: Bool) -> Bool {
        !isFreeTier && !hasPricingOptions
    }

    /// The same rule over a tier.
    public static func isEnterprise(_ tier: AppTierModel) -> Bool {
        isEnterprise(isFreeTier: tier.isFreeTier, hasPricingOptions: !tier.pricingOptions.isEmpty)
    }

    /// The footer's single call to action, from plain values.
    ///
    /// - Parameters:
    ///   - tierName: names the ordinary call to action ("Select Pro").
    ///   - isFreeTier: a free plan is never an enterprise plan, however it is priced.
    ///   - hasPricingOptions: whether the catalog prices this plan at all.
    ///   - showSubscribeButton: the tier's own switch. Wire default `true`.
    ///   - showContactButton: the tier's own contact button. Wire default `false`.
    ///   - contactButtonUrl: where that button points. Blank or unparseable is the same as absent,
    ///     so a misconfigured link falls through to the next priority instead of rendering a
    ///     button that does nothing.
    ///   - enterpriseContactUrl: the host's fallback for a plan that names no URL of its own.
    ///   - isCurrentTier: the plan the visitor is already on.
    ///   - isPreSelected: already chosen elsewhere (a pricing link, a host's `highlightTierId`).
    public static func footerAction(
        tierName: String,
        isFreeTier: Bool,
        hasPricingOptions: Bool,
        showSubscribeButton: Bool,
        showContactButton: Bool,
        contactButtonUrl: String?,
        enterpriseContactUrl: String? = nil,
        isCurrentTier: Bool = false,
        isPreSelected: Bool = false
    ) -> TierFooterAction {
        // Priority 0. Gated on `showSubscribeButton`, which is the ONE deliberate departure from
        // React's chain: a tier that has switched its call to action off has always rendered an
        // empty footer on this stack, current plan or not, and this restructuring is not the place
        // to start putting a control there.
        if isCurrentTier, showSubscribeButton {
            return .current(title: currentPlanTitle)
        }

        // Priority 1 — the tier's own contact button wins outright. No subscribe button is
        // reachable past here, which is the whole point of the chain.
        if showContactButton, let url = link(contactButtonUrl) {
            return .contactUs(url: url)
        }

        if isEnterprise(isFreeTier: isFreeTier, hasPricingOptions: hasPricingOptions) {
            // Priority 2 — the host's fallback URL.
            if let url = link(enterpriseContactUrl) {
                return .contactSales(url: url)
            }
            // Priority 3 — nowhere to send anyone, so the host is told instead.
            return .contactSalesRequest(title: contactSalesTitle)
        }

        // Priority 4.
        guard showSubscribeButton else { return TierFooterAction.none }
        let title: String = isPreSelected ? preSelectedSubscribeTitle : subscribeTitle(tierName: tierName)
        return .subscribe(title: title)
    }

    /// The same chain over a tier.
    public static func footerAction(
        tier: AppTierModel,
        isCurrentTier: Bool = false,
        isPreSelected: Bool = false,
        enterpriseContactUrl: String? = nil
    ) -> TierFooterAction {
        footerAction(
            tierName: tier.name,
            isFreeTier: tier.isFreeTier,
            hasPricingOptions: !tier.pricingOptions.isEmpty,
            showSubscribeButton: tier.showSubscribeButton,
            showContactButton: tier.showContactButton,
            contactButtonUrl: tier.contactButtonUrl,
            enterpriseContactUrl: enterpriseContactUrl,
            isCurrentTier: isCurrentTier,
            isPreSelected: isPreSelected
        )
    }

    /// Whether this action hands the host a selection when it is tapped.
    ///
    /// Only two do: the ordinary subscribe call to action, and the enterprise request that exists
    /// precisely so the host can be told (React's priority 3). A "Contact Us"/"Contact Sales" link,
    /// a current-plan label and an empty footer raise nothing — so a plan that sells nothing and
    /// has somewhere to send people can never produce a selection payload for a purchase that
    /// cannot be made.
    public static func raisesSelection(_ action: TierFooterAction) -> Bool {
        switch action {
        case .subscribe, .contactSalesRequest:
            return true
        case .current, .contactUs, .contactSales, TierFooterAction.none:
            return false
        }
    }

    /// A configured link, or nil when the operator left it blank or unparseable.
    private static func link(_ urlString: String?) -> URL? {
        guard let urlString else { return nil }
        let trimmed: String = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}
