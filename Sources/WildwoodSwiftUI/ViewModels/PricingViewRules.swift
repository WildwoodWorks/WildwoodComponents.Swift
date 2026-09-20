// Every decision the pricing view makes, as pure functions with no SwiftUI in them.
//
// Nothing here can be compiled into a simulator-only target, and nothing here needs one: a rule
// that lives inside a `body` is a rule that cannot be tested on a machine with no Xcode. The view
// is a thin arrangement of what is in this file — which body to render, which plans survive the
// host's options, what a pack card says about its price, how a selection grows, and what `onSelect`
// is finally handed.
//
// Ported function for function from
// packages/wildwood-react-native/src/components/registrationSubscription/views/pricingViewModel.ts,
// with the two rules that bind the whole family:
//
//  · Every price comes off the live catalog. There is no fallback price, no remembered price and no
//    "from" price here. A pack the operator has not priced SAYS so rather than implying it is free.
//  · A selection never exceeds ``Catalog/maxAddOnSelection``, the platform-wide pack cap, and always
//    reads in catalog order rather than tap order — so a basket built by tapping and one built from
//    a signup link cannot differ.

import Foundation
import WildwoodCore

// MARK: - The values the view and its host exchange

/// The billing cycle the plan grid is quoting.
public enum PricingBilling: String, Sendable, Equatable, CaseIterable {
    case monthly
    case annual
}

/// How the pack grid lets a pack be taken — the web's `packSelection` prop.
public enum PricingPackSelection: String, Sendable, Equatable, CaseIterable {
    /// One "Select" call to action per pack.
    case none
    /// Tick several packs, then one Continue.
    case multi
}

/// What the pack grid actually offers, once an App-Store-exclusive app has had its say.
public enum PricingPackAffordance: Sendable, Equatable {
    /// One "Select" call to action per pack (``PricingPackSelection/none``).
    case single
    /// Tick several packs, then one Continue (``PricingPackSelection/multi``).
    case multi
    /// The packs are LISTED but none can be taken here. A store-billed app is the case that needs
    /// it: pack checkout is a card purchase and there is no in-app-purchase product behind an
    /// add-on, so buying one is hidden while what the app sells stays visible.
    case informational
}

/// Which of the view's three bodies applies. JS names the middle one `'error'`; it is spelled for
/// what the visitor sees, because a stale price standing on screen is the failure it prevents.
public enum PricingBodyKind: String, Sendable, Equatable {
    case loading
    case unavailable
    case content
}

/// What a call to action in the pricing view hands the host — the web's `PricingSelection`.
public struct PricingSelection: Sendable, Equatable {
    /// The plan, when a plan's own call to action raised this. Nil for a pack-only selection.
    public var tierId: String?
    /// The plan's price option under ``billing``.
    public var pricingId: String?
    /// The cycle the grid was showing when it was raised.
    public var billing: PricingBilling
    /// The ticked packs, in catalog order. Possibly empty, never nil.
    public var addOnIds: [String]

    public init(
        tierId: String? = nil,
        pricingId: String? = nil,
        billing: PricingBilling,
        addOnIds: [String] = []
    ) {
        self.tierId = tierId
        self.pricingId = pricingId
        self.billing = billing
        self.addOnIds = addOnIds
    }
}

/// One heading the host files packs under, matched on an add-on's `category`.
public struct WildwoodAddOnGroup: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String?
    public var blurb: String?
    /// The add-on categories this heading claims. Matched CASE-SENSITIVELY, as JS matches them.
    public var categories: [String]

    public init(id: String, title: String? = nil, blurb: String? = nil, categories: [String]) {
        self.id = id
        self.title = title
        self.blurb = blurb
        self.categories = categories
    }
}

/// Host marketing copy for one pack — the web's `describeAddOn` answer.
///
/// Values, not views: the web hands back a node for `icon`, which on iOS would mean a type-erased
/// view in a public signature. An SF Symbol name does the same job and stays `Sendable`, testable
/// and cheap.
public struct WildwoodAddOnPresentation: Sendable, Equatable {
    /// Replaces the pack's own description.
    public var blurb: String?
    /// A short "what you get" line under the blurb.
    public var meter: String?
    /// An SF Symbol name shown before the pack's name.
    public var systemImage: String?

    public init(blurb: String? = nil, meter: String? = nil, systemImage: String? = nil) {
        self.blurb = blurb
        self.meter = meter
        self.systemImage = systemImage
    }
}

/// Which grids the host asked for.
public struct PricingSections: Sendable, Equatable {
    public var plans: Bool
    public var packs: Bool

    public init(plans: Bool, packs: Bool) {
        self.plans = plans
        self.packs = packs
    }
}

/// One rendered heading and the packs under it.
public struct PricingPackGroup: Sendable, Equatable, Identifiable {
    /// `all` when the host named no groups, `more` for the catch-all, else the host's own id —
    /// the values the web puts in `data-ww-group`.
    public var id: String
    public var title: String?
    public var blurb: String?
    public var addOns: [AppTierAddOnModel]

    public init(id: String, title: String? = nil, blurb: String? = nil, addOns: [AppTierAddOnModel]) {
        self.id = id
        self.title = title
        self.blurb = blurb
        self.addOns = addOns
    }
}

// MARK: - The rules

public enum PricingViewRules {
    /// The group id the packs land in when the host named no groups.
    public static let ungroupedId: String = "all"
    /// The group id the trailing catch-all carries.
    public static let moreGroupId: String = "more"

    // MARK: Loading, failure and retry

    /// Loading shows shapes, an unreadable catalog shows the unavailable panel, and only a catalog
    /// in hand shows prices.
    ///
    /// A failure wins even when a catalog is already on screen: the prices go away with the answer
    /// that produced them, rather than standing there as a quote nobody can vouch for any more. A
    /// finished load with nothing to show is unreadable, not an empty shop.
    public static func bodyKind(
        catalog: PublicCatalog?,
        isLoading: Bool,
        errorMessage: String?
    ) -> PricingBodyKind {
        if let errorMessage, !errorMessage.isEmpty { return .unavailable }
        if catalog == nil {
            return isLoading ? .loading : .unavailable
        }
        return .content
    }

    // MARK: Live prices

    /// The currency the screen quotes in.
    ///
    /// The server names the currency its catalog is quoted in (``PublicCatalog/build(appId:tiers:addOns:currencyOverride:now:)``
    /// resolves it, falling back to USD); the parameter is an override for the rare host that knows
    /// better. Empty before a catalog arrives, so nothing is quoted in a currency nobody named.
    public static func currency(override: String?, catalog: PublicCatalog?) -> String {
        if let override, !override.isEmpty { return override }
        return catalog?.currency ?? ""
    }

    /// Which grids the host asked for. A pricing screen with the plans turned off is a legitimate
    /// arrangement (a pack shop), which is why this is a rule and not an `if` buried in a `body`.
    public static func sections(showPlans: Bool, showAddOns: Bool) -> PricingSections {
        PricingSections(plans: showPlans, packs: showAddOns)
    }

    /// The plans to show: the catalog's active plans, minus the free ones the host does not offer.
    public static func visibleTiers(_ catalog: PublicCatalog?, offerFreeTierChoice: Bool) -> [AppTierModel] {
        let all: [AppTierModel] = catalog?.tiers ?? []
        if offerFreeTierChoice { return all }
        return all.filter { !$0.isFreeTier }
    }

    /// Whether a plan is the one the host marked as already chosen. Ids match case-insensitively.
    public static func isHighlighted(tierId: String?, highlightTierId: String?) -> Bool {
        guard let tierId, !tierId.isEmpty else { return false }
        guard let highlightTierId, !highlightTierId.isEmpty else { return false }
        return tierId.lowercased() == highlightTierId.lowercased()
    }

    /// The price option a plan is quoted at under the current cycle.
    public static func planPriceOption(_ tier: AppTierModel, billing: PricingBilling) -> AppTierPricingModel? {
        Catalog.resolvePriceOption(tier, billing: billing.rawValue)
    }

    /// Whether ANY plan is priced by the year. A toggle with nothing to switch to is a control that
    /// lies, so this gates it.
    public static func hasAnnualPricing(_ tiers: [AppTierModel]) -> Bool {
        for tier in tiers {
            for option in tier.pricingOptions where Catalog.isAnnualFrequency(option.billingFrequency) {
                return true
            }
        }
        return false
    }

    /// The percentage a plan's annual option saves against twelve of its monthly one, or nil when
    /// the plan is not cheaper by the year. The JS rule (`computeAnnualDiscount`), which this stack
    /// has no core counterpart for yet.
    public static func annualDiscount(_ tier: AppTierModel) -> Int? {
        let options: [AppTierPricingModel] = tier.pricingOptions
        if options.count < 2 { return nil }

        let monthly: AppTierPricingModel? = options.first { $0.billingFrequency.lowercased() == "monthly" }
        let annual: AppTierPricingModel? = options.first { Catalog.isAnnualFrequency($0.billingFrequency) }
        guard let monthly, let annual, monthly.price > 0 else { return nil }

        let monthlyTotal: Double = monthly.price * 12
        guard annual.price < monthlyTotal else { return nil }
        return Int((((monthlyTotal - annual.price) / monthlyTotal) * 100).rounded())
    }

    /// The largest annual saving on offer, or 0 when no plan is cheaper by the year.
    public static func bestAnnualDiscount(_ tiers: [AppTierModel]) -> Int {
        var best: Int = 0
        for tier in tiers {
            if let discount = annualDiscount(tier), discount > best { best = discount }
        }
        return best
    }

    /// The per-period suffix. An unrecognised frequency contributes nothing rather than a guess —
    /// OneTime and Lifetime amounts stand on their own.
    public static func billingSuffix(_ billingFrequency: String?) -> String {
        let value: String = (billingFrequency ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch value {
        case "monthly": return "/mo"
        case "yearly", "annually", "annual": return "/yr"
        case "weekly": return "/wk"
        case "daily": return "/day"
        default: return ""
        }
    }

    /// What a pack card shows where its price goes.
    ///
    /// A pack the operator defined but never priced says "not yet available" rather than rendering
    /// a blank, a zero or the plan's price — any of which a visitor would read as "free".
    public static func packPriceText(
        _ addOn: AppTierAddOnModel,
        currency: String,
        labels: RegistrationSubscriptionPricingLabels
    ) -> String {
        guard let pricing = Catalog.resolvePriceOption(addOn) else { return labels.packUnavailable }
        return WildwoodMoney.format(pricing.price, currency: currency) + billingSuffix(pricing.billingFrequency)
    }

    // MARK: The pack grid

    /// What the pack grid offers, once an App-Store-exclusive app has had its say (Decision 5).
    public static func packAffordance(
        packSelection: PricingPackSelection,
        packPurchaseAvailable: Bool
    ) -> PricingPackAffordance {
        guard packPurchaseAvailable else { return .informational }
        switch packSelection {
        case .none: return .single
        case .multi: return .multi
        }
    }

    /// The packs under the host's headings. Empty groups are dropped; packs matching no group land
    /// in a trailing group titled by `morePacksTitle`. With no groups at all, one untitled group.
    ///
    /// The stray rule is the important one: a pack the company sells and has priced going silently
    /// missing from the screen that sells it is the failure this must not have.
    public static func groupAddOns(
        _ addOns: [AppTierAddOnModel],
        groups: [WildwoodAddOnGroup]?,
        morePacksTitle: String
    ) -> [PricingPackGroup] {
        guard let groups, !groups.isEmpty else {
            if addOns.isEmpty { return [] }
            return [PricingPackGroup(id: ungroupedId, addOns: addOns)]
        }

        var filed: [PricingPackGroup] = []
        for group in groups {
            let members: [AppTierAddOnModel] = addOns.filter { group.categories.contains($0.category) }
            if members.isEmpty { continue }
            filed.append(
                PricingPackGroup(id: group.id, title: group.title, blurb: group.blurb, addOns: members)
            )
        }

        var known = Set<String>()
        for group in groups {
            for category in group.categories { known.insert(category) }
        }
        let orphans: [AppTierAddOnModel] = addOns.filter { !known.contains($0.category) }
        if orphans.isEmpty { return filed }

        filed.append(PricingPackGroup(id: moreGroupId, title: morePacksTitle, addOns: orphans))
        return filed
    }

    /// Tick or untick one pack.
    ///
    /// The answer is in CATALOG order rather than tap order, so what comes back reads the same as
    /// the grid it was picked from, and it never grows past ``Catalog/maxAddOnSelection`` — the same
    /// cap `parseAddOnIdList` applies to a selection arriving in a link. Unticking is always
    /// allowed, cap or no cap.
    public static func togglePackSelection(
        catalog: PublicCatalog?,
        current: [String],
        addOnId: String
    ) -> [String] {
        let selected: Bool = current.contains(addOnId)
        if !selected, current.count >= Catalog.maxAddOnSelection { return current }

        var next = Set(current)
        if selected {
            next.remove(addOnId)
        } else {
            next.insert(addOnId)
        }

        // Without a catalog there is no order to read the selection in — and no grid to have
        // picked from.
        guard let catalog else { return [] }
        return Catalog.selectPacks(catalog, addOnIds: Array(next)).map { $0.id }
    }

    /// The Continue button's copy, singular when exactly one pack is ticked.
    public static func continueWithPacksLabel(
        count: Int,
        labels: RegistrationSubscriptionPricingLabels
    ) -> String {
        if count == 1 { return labels.continueWithOnePack }
        return RegistrationSubscriptionLabelFormat.format(
            labels.continueWithPacks,
            values: ["count": String(count)]
        )
    }

    /// The best annual saving, worded.
    public static func annualSavingsLabel(
        percent: Int,
        labels: RegistrationSubscriptionPricingLabels
    ) -> String {
        RegistrationSubscriptionLabelFormat.format(
            labels.annualSavings,
            values: ["percent": String(percent)]
        )
    }

    /// One pack's call to action, worded for a screen reader.
    public static func packSelectLabel(
        name: String,
        labels: RegistrationSubscriptionPricingLabels
    ) -> String {
        RegistrationSubscriptionLabelFormat.format(labels.packSelectNamed, values: ["name": name])
    }

    // MARK: What the host is handed

    /// The payload a plan's call to action hands back: the plan, its option under the current
    /// cycle, and whatever packs are ticked — so one tap buys the whole basket.
    ///
    /// Nil when the plan's footer raises no selection at all, decided by the SAME chain the card
    /// renders from (``TierCardRules/footerAction(tier:isCurrentTier:isPreSelected:enterpriseContactUrl:)``).
    /// A plan the operator points at a contact page sells nothing here, so no host is handed a
    /// payload naming it; a genuinely free plan still is, pricing option or not, and so is the
    /// enterprise plan with no contact URL anywhere — being told is the only thing its button can
    /// do, which is what the web card does with it too.
    ///
    /// - Parameter contactUrl: the host's fallback contact URL, as the plan grid passes it to the
    ///   card. It decides priority 2, so the guard must see the same value the footer does.
    public static func planSelectionPayload(
        tier: AppTierModel,
        billing: PricingBilling,
        selectedPackIds: [String],
        contactUrl: String? = nil
    ) -> PricingSelection? {
        let action: TierFooterAction = TierCardRules.footerAction(
            tier: tier,
            enterpriseContactUrl: contactUrl
        )
        guard TierCardRules.raisesSelection(action) else { return nil }

        return PricingSelection(
            tierId: tier.id,
            pricingId: planPriceOption(tier, billing: billing)?.id,
            billing: billing,
            addOnIds: selectedPackIds
        )
    }

    /// The payload a single pack's call to action hands back. No plan is implied.
    public static func packSelectionPayload(addOnId: String, billing: PricingBilling) -> PricingSelection {
        PricingSelection(billing: billing, addOnIds: [addOnId])
    }

    /// The payload the multi-select Continue hands back.
    public static func packsContinuePayload(
        billing: PricingBilling,
        selectedPackIds: [String]
    ) -> PricingSelection {
        PricingSelection(billing: billing, addOnIds: selectedPackIds)
    }
}
