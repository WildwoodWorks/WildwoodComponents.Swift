// Ported case for case from packages/wildwood-core/src/__tests__/catalog.test.ts.
//
// Two of that file's describe blocks are deliberately absent:
//   · `formatMoney` (3 cases) and `trialLabel` (1 case) — one implementation lives in
//     CatalogFormatting.swift and is already pinned by CatalogFormattingTests; `Catalog.formatMoney`
//     / `Catalog.trialLabel` are thin aliases onto it, checked at the bottom of this file rather
//     than re-asserted.
//   · `catalogToJsonLdOffers` (2 cases) — schema.org structured data for a web crawler, which has
//     no iOS counterpart and is not ported.
//
// Model values are decoded from `{}` (every field has a tolerant default) and then filled in,
// because the wire models carry a hand-written `init(from:)` and so have no memberwise init.

import Foundation
import Testing
@testable import WildwoodCore

// MARK: - Fixtures (the JS file's pricing()/tier()/addOn() factories)

private func pricing(
    id: String = "price-1",
    price: Double = 79,
    billingFrequency: String = "Monthly",
    isDefault: Bool = false,
    displayOrder: Int = 0,
    trialDays: Int? = nil
) throws -> AppTierPricingModel {
    var value = try WildwoodJSON.decoder().decode(AppTierPricingModel.self, from: Data("{}".utf8))
    value.id = id
    value.appTierId = "tier-1"
    value.pricingModelId = "pm-1"
    value.pricingModelName = "Monthly"
    value.price = price
    value.billingFrequency = billingFrequency
    value.isDefault = isDefault
    value.displayOrder = displayOrder
    value.trialDays = trialDays
    return value
}

private func tier(
    id: String = "tier-1",
    name: String = "Pro",
    displayOrder: Int = 0,
    status: String = "Active",
    currency: String? = nil,
    showPrice: Bool = true,
    pricingOptions: [AppTierPricingModel]? = nil
) throws -> AppTierModel {
    var value = try WildwoodJSON.decoder().decode(AppTierModel.self, from: Data("{}".utf8))
    value.id = id
    value.appId = "app-1"
    value.name = name
    value.description = "Everything"
    value.displayOrder = displayOrder
    value.status = status
    value.showPrice = showPrice
    value.currency = currency
    if let pricingOptions {
        value.pricingOptions = pricingOptions
    } else {
        let fallback = try pricing()
        value.pricingOptions = [fallback]
    }
    return value
}

private func addOnPricing(
    id: String = "ap-1",
    price: Double = 19,
    billingFrequency: String = "Monthly",
    isDefault: Bool = true
) throws -> AppTierAddOnPricingModel {
    var value = try WildwoodJSON.decoder().decode(AppTierAddOnPricingModel.self, from: Data("{}".utf8))
    value.id = id
    value.pricingModelId = "pm-2"
    value.pricingModelName = "Monthly"
    value.price = price
    value.billingFrequency = billingFrequency
    value.isDefault = isDefault
    return value
}

private func addOn(
    id: String = "addon-1",
    name: String = "Radar",
    displayOrder: Int = 0,
    status: String = "Active",
    currency: String? = nil,
    pricingOptions: [AppTierAddOnPricingModel]? = nil
) throws -> AppTierAddOnModel {
    var value = try WildwoodJSON.decoder().decode(AppTierAddOnModel.self, from: Data("{}".utf8))
    value.id = id
    value.appId = "app-1"
    value.name = name
    value.description = "Pack"
    value.displayOrder = displayOrder
    value.status = status
    value.currency = currency
    if let pricingOptions {
        value.pricingOptions = pricingOptions
    } else {
        let fallback = try addOnPricing()
        value.pricingOptions = [fallback]
    }
    return value
}

// MARK: - buildPublicCatalog

struct BuildPublicCatalogTests {
    @Test func takesTheCurrencyTheServerSentInPreferenceToTheOverride() throws {
        let gbpTier = try tier(currency: "GBP")
        let eurAddOn = try addOn(currency: "EUR")

        let catalog = PublicCatalog.build(
            appId: "app-1",
            tiers: [gbpTier],
            addOns: [eurAddOn],
            currencyOverride: "CAD"
        )

        #expect(catalog.currency == "GBP")
    }

    @Test func fallsBackToTheOverrideThenToUsdWhenNoResponseCarriesACurrency() throws {
        let plain = try tier()
        let overridden = PublicCatalog.build(appId: "app-1", tiers: [plain], currencyOverride: "CAD")
        #expect(overridden.currency == "CAD")

        // An add-on can supply it just as well as a tier — it is one app-level setting.
        let paddedEuroPack = try addOn(currency: " EUR ")
        let fromPack = PublicCatalog.build(appId: "app-1", tiers: [plain], addOns: [paddedEuroPack])
        #expect(fromPack.currency == "EUR")

        #expect(PublicCatalog.build(appId: "app-1").currency == "USD")

        // An empty string on the wire is not an answer.
        let blankCurrency = try tier(currency: "")
        #expect(PublicCatalog.build(appId: "app-1", tiers: [blankCurrency]).currency == "USD")
    }

    @Test func keepsOnlyActiveItemsInDisplayOrder() throws {
        let builtAt = Date(timeIntervalSince1970: 1_700_000_000)
        let late = try tier(id: "late", displayOrder: 3)
        let retired = try tier(id: "retired", displayOrder: 1, status: "Deprecated")
        let early = try tier(id: "early", displayOrder: 1)
        let packB = try addOn(id: "b", displayOrder: 2)
        let packOff = try addOn(id: "off", displayOrder: 0, status: "Inactive")
        let packA = try addOn(id: "a", displayOrder: 1)

        let catalog = PublicCatalog.build(
            appId: "app-1",
            tiers: [late, retired, early],
            addOns: [packB, packOff, packA],
            now: builtAt
        )

        #expect(catalog.tiers.map(\.id) == ["early", "late"])
        #expect(catalog.addOns.map(\.id) == ["a", "b"])
        #expect(catalog.appId == "app-1")
        // JS asserts `typeof fetchedAt === 'number'`; the Swift clock is injected, so pin it.
        #expect(catalog.fetchedAt == builtAt)
    }

    @Test func tiesKeepTheOrderTheServerSent() throws {
        // Swift's sort is explicitly NOT guaranteed stable, so this is the case the hand-written
        // index tiebreak exists for. `Array.prototype.sort` IS stable, and the two must agree.
        let a = try tier(id: "a", displayOrder: 0)
        let b = try tier(id: "b", displayOrder: 0)
        let c = try tier(id: "c", displayOrder: 0)
        let first = try tier(id: "first", displayOrder: -1)
        let x = try addOn(id: "x", displayOrder: 5)
        let y = try addOn(id: "y", displayOrder: 5)
        let z = try addOn(id: "z", displayOrder: 5)

        let catalog = PublicCatalog.build(appId: "app-1", tiers: [a, b, c, first], addOns: [x, y, z])

        #expect(catalog.tiers.map(\.id) == ["first", "a", "b", "c"])
        #expect(catalog.addOns.map(\.id) == ["x", "y", "z"])
    }

    @Test func doesNotMutateTheResponsesItWasGiven() throws {
        // Structural in Swift (arrays are values), asserted anyway so a later rewrite that takes
        // an `inout` or a reference type trips here.
        let b = try tier(id: "b", displayOrder: 2)
        let a = try tier(id: "a", displayOrder: 1)
        let tiers: [AppTierModel] = [b, a]

        _ = PublicCatalog.build(appId: "app-1", tiers: tiers)

        #expect(tiers.map(\.id) == ["b", "a"])
    }

    @Test func theCatalogNamespaceForwardsToTheSameBuilder() throws {
        let builtAt = Date(timeIntervalSince1970: 42)
        let plain = try tier()

        let viaNamespace = Catalog.build(appId: "app-1", tiers: [plain], now: builtAt)
        let viaType = PublicCatalog.build(appId: "app-1", tiers: [plain], now: builtAt)

        #expect(viaNamespace == viaType)
    }
}

// MARK: - resolvePriceOption

struct ResolvePriceOptionTests {
    @Test func prefersTheNamedOption() throws {
        let monthly = try pricing(id: "m", billingFrequency: "Monthly", displayOrder: 2)
        let yearly = try pricing(id: "y", price: 790, billingFrequency: "Yearly", displayOrder: 3)
        let item = try tier(pricingOptions: [monthly, yearly])

        #expect(Catalog.resolvePriceOption(item, pricingId: "y")?.id == "y")
    }

    @Test func fallsBackToTheBillingFrequencyMatchingAnnualSynonyms() throws {
        let monthly = try pricing(id: "m", billingFrequency: "Monthly", displayOrder: 2)
        let yearly = try pricing(id: "y", price: 790, billingFrequency: "Yearly", displayOrder: 3)
        let item = try tier(pricingOptions: [monthly, yearly])

        #expect(Catalog.resolvePriceOption(item, pricingId: "gone", billing: "Monthly")?.id == "m")
        #expect(Catalog.resolvePriceOption(item, billing: "annual")?.id == "y")
        #expect(Catalog.resolvePriceOption(item, billing: "MONTHLY")?.id == "m")
    }

    @Test func fallsBackToTheDefaultOptionThenToTheFirstInDisplayOrder() throws {
        let monthly = try pricing(id: "m", billingFrequency: "Monthly", displayOrder: 2)
        let preferred = try pricing(id: "d", billingFrequency: "Quarterly", isDefault: true, displayOrder: 4)
        let first = try pricing(id: "f", billingFrequency: "Weekly", displayOrder: 1)
        let withDefault = try tier(pricingOptions: [first, monthly, preferred])
        let withoutDefault = try tier(pricingOptions: [monthly, first])

        #expect(Catalog.resolvePriceOption(withDefault, billing: "Daily")?.id == "d")
        #expect(Catalog.resolvePriceOption(withoutDefault, billing: "Daily")?.id == "f")
    }

    @Test func returnsNilWhenTheItemSellsNoPricing() throws {
        let contactUs = try tier(pricingOptions: [])

        #expect(Catalog.resolvePriceOption(contactUs) == nil)
        #expect(Catalog.resolvePriceOption(nil as AppTierModel?) == nil)
    }

    @Test func worksOnAddOnPricingWhichCarriesNoDisplayOrder() throws {
        let plainPack = try addOn()
        #expect(Catalog.resolvePriceOption(plainPack)?.id == "ap-1")

        // Every pack option reports displayOrder 0, so "first in display order" is the first the
        // server sent — which only holds because the sort is stable.
        let second = try addOnPricing(id: "second", isDefault: false)
        let third = try addOnPricing(id: "third", isDefault: false)
        let packed = try addOn(pricingOptions: [second, third])
        #expect(Catalog.resolvePriceOption(packed)?.id == "second")
    }

    @Test func isAnnualFrequencyKnowsTheThreeSynonyms() {
        #expect(Catalog.isAnnualFrequency("Yearly"))
        #expect(Catalog.isAnnualFrequency("annual"))
        #expect(Catalog.isAnnualFrequency("ANNUALLY"))
        #expect(Catalog.isAnnualFrequency("Monthly") == false)
        #expect(Catalog.isAnnualFrequency("") == false)
        #expect(Catalog.isAnnualFrequency(nil) == false)
    }
}

// MARK: - parseAddOnIdList / selectPacks

struct CatalogPackSelectionTests {
    @Test func trimsSplitsOnCommasAndWhitespaceAndDeDuplicates() {
        #expect(Catalog.parseAddOnIdList(" a, b  c ,,a ") == ["a", "b", "c"])
        #expect(Catalog.parseAddOnIdList(["a", "b,a"] as [String?]) == ["a", "b"])
        #expect(Catalog.parseAddOnIdList("") == [])
        // JS distinguishes null from undefined; Swift has one nil for both.
        #expect(Catalog.parseAddOnIdList(nil as String?) == [])
    }

    @Test func capsTheSelectionAtTwentyFive() {
        #expect(Catalog.maxAddOnSelection == 25)
        let many: [String] = (0..<(Catalog.maxAddOnSelection + 10)).map { "a\($0)" }
        let joined: String = many.joined(separator: ",")

        #expect(Catalog.parseAddOnIdList(joined).count == Catalog.maxAddOnSelection)
    }

    @Test func keepsOnlyIdsTheCatalogSellsWhenOneIsGiven() throws {
        let radar = try addOn(id: "radar")
        let vault = try addOn(id: "vault", displayOrder: 1)
        let catalog = PublicCatalog.build(appId: "app-1", addOns: [radar, vault])

        #expect(Catalog.parseAddOnIdList("radar,smuggled,vault", catalog: catalog) == ["radar", "vault"])
        // The cap counts what survives the filter, not what was asked for.
        #expect(Catalog.parseAddOnIdList("nope", catalog: catalog) == [])
    }

    @Test func returnsThePacksInCatalogOrderNotTheOrderTheyWereAskedFor() throws {
        let a = try addOn(id: "a", displayOrder: 1)
        let b = try addOn(id: "b", displayOrder: 2)
        let c = try addOn(id: "c", displayOrder: 3)
        let catalog = PublicCatalog.build(appId: "app-1", addOns: [a, b, c])

        #expect(Catalog.selectPacks(catalog, addOnIds: ["c", "a"]).map(\.id) == ["a", "c"])
        #expect(Catalog.selectPacks(catalog, addOnIds: ["unknown"]).isEmpty)
        #expect(Catalog.selectPacks(catalog, addOnIds: []).isEmpty)
        #expect(Catalog.selectPacks(catalog, addOnIds: nil).isEmpty)
    }
}

// MARK: - Selection round trip

struct CatalogSelectionRoundTripTests {
    @Test func encodesAndDecodesUnderTheTierPricingAddonsKeys() {
        let selection = CatalogSelection(tierId: "tier-1", pricingId: "price-1", addOnIds: ["a", "b", "a"])
        let encoded: String = Catalog.encodeSelection(selection)

        // Byte-identical to URLSearchParams.toString(): the comma joining the ids is %2C, not the
        // literal comma URLComponents would have written.
        #expect(encoded == "tier=tier-1&pricing=price-1&addons=a%2Cb")

        let expected = DecodedCatalogSelection(tierId: "tier-1", pricingId: "price-1", addOnIds: ["a", "b"])
        #expect(Catalog.decodeSelection(encoded) == expected)
    }

    @Test func decodesAFullUrlALeadingQuestionMarkRepeatedParamsAndParsedParams() {
        let fromUrl = Catalog.decodeSelection("https://example.test/signup?tier=t1&addons=a&addons=b#top")
        #expect(fromUrl == DecodedCatalogSelection(tierId: "t1", pricingId: nil, addOnIds: ["a", "b"]))

        let fromQuery = Catalog.decodeSelection("?tier= t1 &pricing=")
        #expect(fromQuery == DecodedCatalogSelection(tierId: "t1", pricingId: nil, addOnIds: []))

        #expect(Catalog.decodeSelection(CatalogQuery.parse("tier=t1")).tierId == "t1")
    }

    @Test func encodesNothingForAnEmptySelection() {
        #expect(Catalog.encodeSelection(CatalogSelection()) == "")
        #expect(Catalog.encodeSelection(CatalogSelection(tierId: "  ", addOnIds: [])) == "")
    }

    @Test func catalogQueryNormalisesEveryUrlShape() {
        // The Swift stand-in for JS `asSearchParams`.
        #expect(CatalogQuery.parse("a=1").first("a") == "1")
        #expect(CatalogQuery.parse("?a=1").first("a") == "1")
        #expect(CatalogQuery.parse("https://example.test/x?a=1").first("a") == "1")
        #expect(CatalogQuery.parse("").first("a") == nil)
        // `+` is a space and %XX is UTF-8, as the urlencoded rules say.
        #expect(CatalogQuery.parse("q=a+b%2Cc").first("q") == "a b,c")

        // WHATWG `set`: the first occurrence keeps its slot and the later ones are dropped.
        var params = CatalogQuery.parse("a=1&b=2&a=3")
        #expect(params.all("a") == ["1", "3"])
        params.set("a", "9")
        #expect(params.queryString == "a=9&b=2")
    }
}

// MARK: - Formatting aliases (one implementation; CatalogFormattingTests holds the full matrix)

struct CatalogFormattingAliasTests {
    @Test func theCatalogNamespaceForwardsToTheSharedFormatters() {
        #expect(Catalog.formatMoney(79, currency: "USD") == WildwoodMoney.format(79, currency: "USD"))
        #expect(Catalog.trialLabel(14) == WildwoodTrial.label(days: 14))
        #expect(Catalog.fallbackCurrency == WildwoodMoney.fallbackCurrency)
    }
}
