// The public catalog: what an app sells, as the server last said it. A port of the model half of
// packages/wildwood-core/src/features/catalog.ts, and the twin of
// WildwoodComponents.Shared/Models/PublicCatalogModels.cs.
//
// Nothing here is a wire model. A catalog is built from the live public tier/add-on responses the
// caller passes in and is never persisted, so no price is ever read back out of storage. The rules
// that operate on a catalog live next door in `Catalog` (CatalogHelpers.swift).

import Foundation

/// The shape the price-option resolution rule needs. Both tier pricing and add-on pricing satisfy
/// it, which is how one rule serves plans and packs alike (JS gets this structurally from its
/// `CatalogPriceOption` interface; .NET names it `ICatalogPriceOption`).
public protocol CatalogPriceOption: Sendable {
    var id: String { get }
    var price: Double { get }
    var billingFrequency: String { get }
    var isDefault: Bool { get }
    /// Ascending display order. Pricing that carries none reports 0 — the value JS's
    /// `displayOrder ?? 0` gives it.
    var displayOrder: Int { get }
    var trialDays: Int? { get }
}

extension AppTierPricingModel: CatalogPriceOption {}

extension AppTierAddOnPricingModel: CatalogPriceOption {
    /// Pack pricing has no display order on the wire. Reporting 0 for every option means the
    /// resolution rule's last step ("first in display order") keeps the order the server sent,
    /// because the sort is stable.
    public var displayOrder: Int { 0 }
}

/// What an app sells, in display order, labelled with one currency.
public struct PublicCatalog: Sendable, Equatable {
    public var appId: String
    /// ISO code every price in this catalog is quoted in.
    public var currency: String
    public var tiers: [AppTierModel]
    public var addOns: [AppTierAddOnModel]
    /// When the catalog was built, for staleness checks by the caller. JS carries the same moment
    /// as epoch milliseconds (`Date.now()`); nothing serialises a catalog, so this stays a `Date`.
    public var fetchedAt: Date

    public init(
        appId: String = "",
        currency: String = Catalog.fallbackCurrency,
        tiers: [AppTierModel] = [],
        addOns: [AppTierAddOnModel] = [],
        fetchedAt: Date = Date()
    ) {
        self.appId = appId
        self.currency = currency
        self.tiers = tiers
        self.addOns = addOns
        self.fetchedAt = fetchedAt
    }

    /// Build the catalog a pricing, signup or upgrade screen renders from (JS `buildPublicCatalog`).
    ///
    /// The currency is the first non-empty one the server sent on any tier or pack — it is an
    /// app-level setting, so every item carries the same value — then `currencyOverride`, then USD.
    /// NOTE the override is only a fallback for an older server that sends no currency; it does
    /// NOT beat a server-sent one. Only items the server marks `Active` survive, in `displayOrder`.
    /// The arrays handed in are never mutated.
    ///
    /// `now` is injected so a test can pin `fetchedAt`, the same way `AttributionRules.parseTouch`
    /// takes its clock.
    public static func build(
        appId: String,
        tiers: [AppTierModel]? = nil,
        addOns: [AppTierAddOnModel]? = nil,
        currencyOverride: String? = nil,
        now: Date = Date()
    ) -> PublicCatalog {
        let allTiers: [AppTierModel] = tiers ?? []
        let allAddOns: [AppTierAddOnModel] = addOns ?? []

        // Scanned tiers-then-add-ons, exactly as JS scans `[...tiers, ...addOns]`.
        var fromServer: String? = nil
        for tier in allTiers {
            if let sent = Catalog.trimmedOrNil(tier.currency) {
                fromServer = sent
                break
            }
        }
        if fromServer == nil {
            for addOn in allAddOns {
                if let sent = Catalog.trimmedOrNil(addOn.currency) {
                    fromServer = sent
                    break
                }
            }
        }

        let currency: String = fromServer
            ?? Catalog.trimmedOrNil(currencyOverride)
            ?? Catalog.fallbackCurrency

        var activeTiers: [AppTierModel] = []
        for tier in allTiers where Catalog.isActive(tier.status) {
            activeTiers.append(tier)
        }

        var activeAddOns: [AppTierAddOnModel] = []
        for addOn in allAddOns where Catalog.isActive(addOn.status) {
            activeAddOns.append(addOn)
        }

        let sortedTiers: [AppTierModel] = Catalog.sortedByDisplayOrder(activeTiers) { $0.displayOrder }
        let sortedAddOns: [AppTierAddOnModel] = Catalog.sortedByDisplayOrder(activeAddOns) { $0.displayOrder }

        return PublicCatalog(
            appId: appId,
            currency: currency,
            tiers: sortedTiers,
            addOns: sortedAddOns,
            fetchedAt: now
        )
    }
}

/// A tier/pack selection, as it travels in a URL.
public struct CatalogSelection: Sendable, Equatable {
    public var tierId: String?
    public var pricingId: String?
    public var addOnIds: [String]

    public init(tierId: String? = nil, pricingId: String? = nil, addOnIds: [String] = []) {
        self.tierId = tierId
        self.pricingId = pricingId
        self.addOnIds = addOnIds
    }
}

/// A selection read back out of a URL. ``addOnIds`` is always an array, possibly empty.
public struct DecodedCatalogSelection: Sendable, Equatable {
    public var tierId: String?
    public var pricingId: String?
    public var addOnIds: [String]

    public init(tierId: String? = nil, pricingId: String? = nil, addOnIds: [String] = []) {
        self.tierId = tierId
        self.pricingId = pricingId
        self.addOnIds = addOnIds
    }
}
