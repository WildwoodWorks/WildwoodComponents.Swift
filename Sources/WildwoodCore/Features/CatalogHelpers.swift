// The rules that operate on a public catalog — a port, function for function, of
// packages/wildwood-core/src/features/catalog.ts and the `isAnnualFrequency` rule from
// features/tierUtils.ts. The twin of WildwoodComponents.Shared/Utilities/CatalogHelpers.cs.
//
// Every member is pure and free of UI: the same helpers serve a pricing screen, a signup flow and
// an upgrade sheet. Prices are only ever read off the live public responses the caller passes in;
// nothing here caches a price or falls back to one.
//
// NOT ported, deliberately: `catalogToJsonLdOffers` / `JsonLdOffer`. They publish schema.org
// structured data for a web crawler, which has no counterpart on iOS.

import Foundation

public enum Catalog {
    /// The `TierStatus` the server publishes for a tier or pack that is on sale.
    public static let activeTierStatus: String = "Active"

    /// How many packs one selection may carry. A signup link is not a shopping cart.
    public static let maxAddOnSelection: Int = 25

    /// What a blank currency means, here and in ``WildwoodMoney``. Every price stored on the
    /// platform is in US dollars, so this matches the server's own fallback.
    public static let fallbackCurrency: String = WildwoodMoney.fallbackCurrency

    /// The query keys a catalog selection travels under. These are the keys the live sites use,
    /// and the ones an invite/signup universal link or deep link carries on iOS.
    public enum QueryKeys {
        public static let tier: String = "tier"
        public static let pricing: String = "pricing"
        public static let addOns: String = "addons"
    }

    // MARK: - Building

    /// `PublicCatalog.build` under the JS module's name (`buildPublicCatalog`). One
    /// implementation — this forwards.
    public static func build(
        appId: String,
        tiers: [AppTierModel]? = nil,
        addOns: [AppTierAddOnModel]? = nil,
        currencyOverride: String? = nil,
        now: Date = Date()
    ) -> PublicCatalog {
        PublicCatalog.build(
            appId: appId,
            tiers: tiers,
            addOns: addOns,
            currencyOverride: currencyOverride,
            now: now
        )
    }

    // MARK: - Price options

    /// The price option to charge for a tier: the one named by `pricingId`, else the one matching
    /// `billing`, else the tier's default, else the first in display order. Nil when the tier
    /// sells no pricing at all (a "contact us" tier).
    public static func resolvePriceOption(
        _ tier: AppTierModel?,
        pricingId: String? = nil,
        billing: String? = nil
    ) -> AppTierPricingModel? {
        resolveOption(tier?.pricingOptions ?? [], pricingId: pricingId, billing: billing)
    }

    /// The price option to charge for a pack, by the same rule as the tier overload.
    public static func resolvePriceOption(
        _ addOn: AppTierAddOnModel?,
        pricingId: String? = nil,
        billing: String? = nil
    ) -> AppTierAddOnPricingModel? {
        resolveOption(addOn?.pricingOptions ?? [], pricingId: pricingId, billing: billing)
    }

    /// The generic form, for a caller that already holds the options.
    public static func resolveOption<Option: CatalogPriceOption>(
        _ options: [Option],
        pricingId: String? = nil,
        billing: String? = nil
    ) -> Option? {
        if options.isEmpty { return nil }

        // An empty string is not a request for anything, which is how JS reads a falsy value.
        if let pricingId, !pricingId.isEmpty {
            for option in options where option.id == pricingId {
                return option
            }
        }

        if let billing, !billing.isEmpty {
            for option in options where matchesBilling(option.billingFrequency, wanted: billing) {
                return option
            }
        }

        for option in options where option.isDefault {
            return option
        }

        let ordered: [Option] = sortedByDisplayOrder(options) { $0.displayOrder }
        return ordered.first
    }

    /// True when a billing frequency string represents an annual cycle (JS `isAnnualFrequency`).
    /// No trimming — the JS rule lower-cases and compares, and the ports must agree.
    public static func isAnnualFrequency(_ frequency: String?) -> Bool {
        guard let frequency, !frequency.isEmpty else { return false }
        let lower: String = frequency.lowercased()
        return lower == "yearly" || lower == "annual" || lower == "annually"
    }

    /// "Yearly", "Annual" and "Annually" are the same cycle to a customer, so a request for one
    /// matches an option priced under any of them.
    static func matchesBilling(_ candidate: String?, wanted: String) -> Bool {
        if isAnnualFrequency(wanted) { return isAnnualFrequency(candidate) }
        let left: String = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let right: String = wanted.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return left == right
    }

    // MARK: - Formatting (one implementation, in CatalogFormatting.swift)

    /// JS exports `formatMoney` from catalog.ts; this is that name over ``WildwoodMoney/format(_:currency:)``.
    public static func formatMoney(_ amount: Double, currency: String?) -> String {
        WildwoodMoney.format(amount, currency: currency)
    }

    /// JS exports `trialLabel` from catalog.ts; this is that name over ``WildwoodTrial/label(days:)``.
    public static func trialLabel(_ days: Int?) -> String {
        WildwoodTrial.label(days: days)
    }

    // MARK: - Pack id lists

    /// Read a list of add-on ids out of a query value: comma- or whitespace-separated, trimmed,
    /// de-duplicated and capped at ``maxAddOnSelection``. Pass a catalog to keep only ids the app
    /// actually sells, so a hand-edited link cannot smuggle an unknown pack into a checkout.
    public static func parseAddOnIdList(_ value: String?, catalog: PublicCatalog? = nil) -> [String] {
        parseAddOnIdList([value], catalog: catalog)
    }

    /// The repeated-parameter form (`?addons=a&addons=b`), read by the same rules.
    public static func parseAddOnIdList(_ values: [String?], catalog: PublicCatalog? = nil) -> [String] {
        var known: Set<String>? = nil
        if let catalog {
            var ids = Set<String>()
            for addOn in catalog.addOns { ids.insert(addOn.id) }
            known = ids
        }

        var seen = Set<String>()
        var ids: [String] = []

        for value in values {
            guard let value else { continue }
            for candidate in splitOnCommasAndWhitespace(value) {
                if candidate.isEmpty || seen.contains(candidate) { continue }
                // The cap counts what survives the filter, not what was asked for — an id the app
                // does not sell is dropped before it is ever "seen".
                if let known, !known.contains(candidate) { continue }
                seen.insert(candidate)
                ids.append(candidate)
                if ids.count >= maxAddOnSelection { return ids }
            }
        }

        return ids
    }

    /// The packs named by `addOnIds`, in catalog order rather than the order they were asked for.
    public static func selectPacks(_ catalog: PublicCatalog, addOnIds: [String]?) -> [AppTierAddOnModel] {
        guard let addOnIds, !addOnIds.isEmpty else { return [] }
        let wanted = Set(addOnIds)
        if wanted.isEmpty { return [] }

        var packs: [AppTierAddOnModel] = []
        for addOn in catalog.addOns where wanted.contains(addOn.id) {
            packs.append(addOn)
        }
        return packs
    }

    // MARK: - Selection round trip

    /// Encode a selection as a query string (no leading `?`), under ``QueryKeys``. Byte-identical
    /// to `URLSearchParams.toString()`: `tier=t1&pricing=p2&addons=a%2Cb`.
    public static func encodeSelection(_ selection: CatalogSelection) -> String {
        var params = CatalogQuery()

        if let tierId = trimmedOrNil(selection.tierId) {
            params.set(QueryKeys.tier, tierId)
        }
        if let pricingId = trimmedOrNil(selection.pricingId) {
            params.set(QueryKeys.pricing, pricingId)
        }

        let candidates: [String?] = selection.addOnIds.map { Optional($0) }
        let addOnIds: [String] = parseAddOnIdList(candidates)
        if !addOnIds.isEmpty {
            params.set(QueryKeys.addOns, addOnIds.joined(separator: ","))
        }

        return params.queryString
    }

    /// Read a selection back out of a URL or a query string. Pass a catalog to drop add-on ids the
    /// app does not sell.
    public static func decodeSelection(
        _ searchOrUrl: String?,
        catalog: PublicCatalog? = nil
    ) -> DecodedCatalogSelection {
        decodeSelection(CatalogQuery.parse(searchOrUrl), catalog: catalog)
    }

    /// Read a selection out of already-parsed parameters.
    public static func decodeSelection(
        _ params: CatalogQuery,
        catalog: PublicCatalog? = nil
    ) -> DecodedCatalogSelection {
        let values: [String] = params.all(QueryKeys.addOns)
        let candidates: [String?] = values.map { Optional($0) }

        return DecodedCatalogSelection(
            tierId: trimmedOrNil(params.first(QueryKeys.tier)),
            pricingId: trimmedOrNil(params.first(QueryKeys.pricing)),
            addOnIds: parseAddOnIdList(candidates, catalog: catalog)
        )
    }

    // MARK: - Shared primitives

    static func trimmedOrNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed: String = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func isActive(_ status: String?) -> Bool {
        let trimmed: String = (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased() == activeTierStatus.lowercased()
    }

    /// JS splits on `/[\s,]+/` and trims each part; the parts are already trimmed here because
    /// every whitespace character is itself a separator.
    static func splitOnCommasAndWhitespace(_ value: String) -> [String] {
        var parts: [String] = []
        var current = ""

        for character in value {
            if character == "," || character.isWhitespace {
                if !current.isEmpty {
                    parts.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty { parts.append(current) }
        return parts
    }

    /// Ascending by display order, STABLE — ties keep the order the server sent, matching
    /// `Array.prototype.sort`. Swift's `sort` is explicitly not guaranteed stable, so the original
    /// index is the tiebreaker; these lists hold a pricing page's worth of items.
    static func sortedByDisplayOrder<T>(_ items: [T], _ displayOrder: (T) -> Int) -> [T] {
        let indexed: [(offset: Int, element: T)] = Array(items.enumerated())
        let sorted: [(offset: Int, element: T)] = indexed.sorted { left, right in
            let leftOrder: Int = displayOrder(left.element)
            let rightOrder: Int = displayOrder(right.element)
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return left.offset < right.offset
        }
        return sorted.map { $0.element }
    }
}
