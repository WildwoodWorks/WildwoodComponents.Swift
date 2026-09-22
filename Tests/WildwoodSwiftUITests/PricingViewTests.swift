// The pricing view sells what the server says the app sells, at the price the server is quoting.
//
// Ported case for case from
// packages/wildwood-react-native/src/__tests__/pricingView.test.ts, minus the cases that only make
// sense for a JSX renderer (the source greps for `className` and web-only API).
//
// Every price assertion goes through ``WildwoodMoney/format(_:currency:)`` against a figure the
// fixture catalog carries, never against a string typed into this file — a test that hard-codes
// "$79.00" would pass just as happily against a view that hard-codes it too, which is the one
// failure the whole dynamic-pricing rule exists to prevent.
//
// Model values are decoded from `{}` (every field has a tolerant default) and then filled in,
// because the wire models carry a hand-written `init(from:)` and so have no memberwise init —
// the same fixture idiom `CatalogTests` uses.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

// MARK: - The catalog the server is pretending to serve

private let proMonthly: Double = 79
private let proAnnual: Double = 790
private let docsPackPrice: Double = 9
private let aiPackPrice: Double = 19

private func pricing(
    id: String,
    price: Double,
    billingFrequency: String,
    isDefault: Bool = false,
    displayOrder: Int = 0,
    trialDays: Int? = nil
) throws -> AppTierPricingModel {
    var value = try WildwoodJSON.decoder().decode(AppTierPricingModel.self, from: Data("{}".utf8))
    value.id = id
    value.price = price
    value.billingFrequency = billingFrequency
    value.isDefault = isDefault
    value.displayOrder = displayOrder
    value.trialDays = trialDays
    return value
}

private func tier(
    id: String,
    name: String,
    displayOrder: Int,
    isFreeTier: Bool = false,
    currency: String? = "USD",
    pricingOptions: [AppTierPricingModel] = []
) throws -> AppTierModel {
    var value = try WildwoodJSON.decoder().decode(AppTierModel.self, from: Data("{}".utf8))
    value.id = id
    value.appId = "app-1"
    value.name = name
    value.status = "Active"
    value.displayOrder = displayOrder
    value.isFreeTier = isFreeTier
    value.currency = currency
    value.pricingOptions = pricingOptions
    return value
}

private func addOnPricing(
    id: String,
    price: Double,
    billingFrequency: String,
    trialDays: Int? = nil
) throws -> AppTierAddOnPricingModel {
    var value = try WildwoodJSON.decoder().decode(AppTierAddOnPricingModel.self, from: Data("{}".utf8))
    value.id = id
    value.price = price
    value.billingFrequency = billingFrequency
    value.trialDays = trialDays
    value.isDefault = true
    return value
}

private func pack(
    id: String,
    name: String,
    category: String,
    displayOrder: Int,
    description: String = "",
    pricingOptions: [AppTierAddOnPricingModel] = []
) throws -> AppTierAddOnModel {
    var value = try WildwoodJSON.decoder().decode(AppTierAddOnModel.self, from: Data("{}".utf8))
    value.id = id
    value.appId = "app-1"
    value.name = name
    value.category = category
    value.description = description
    value.status = "Active"
    value.displayOrder = displayOrder
    value.pricingOptions = pricingOptions
    return value
}

private struct Fixtures {
    var freeTier: AppTierModel
    var proTier: AppTierModel
    /// No pricing options at all: the platform's definition of an enterprise "contact us" plan.
    var enterpriseTier: AppTierModel
    var docsPack: AppTierAddOnModel
    var aiPack: AppTierAddOnModel
    /// Defined in WildwoodAdmin but never priced, and in a category no host group claims.
    var loosePack: AppTierAddOnModel

    var tiers: [AppTierModel] { [freeTier, proTier, enterpriseTier] }
    var packs: [AppTierAddOnModel] { [docsPack, aiPack, loosePack] }

    init() throws {
        freeTier = try tier(
            id: "tier-free",
            name: "Starter",
            displayOrder: 1,
            isFreeTier: true,
            pricingOptions: [
                try pricing(id: "price-free", price: 0, billingFrequency: "Monthly", isDefault: true, displayOrder: 1)
            ]
        )
        proTier = try tier(
            id: "tier-pro",
            name: "Pro",
            displayOrder: 2,
            pricingOptions: [
                try pricing(
                    id: "price-pro-monthly",
                    price: proMonthly,
                    billingFrequency: "Monthly",
                    isDefault: true,
                    displayOrder: 1
                ),
                try pricing(
                    id: "price-pro-annual",
                    price: proAnnual,
                    billingFrequency: "Yearly",
                    displayOrder: 2
                )
            ]
        )
        enterpriseTier = try tier(id: "tier-ent", name: "Enterprise", displayOrder: 3)
        docsPack = try pack(
            id: "pack-docs",
            name: "Docs Pack",
            category: "Documents",
            displayOrder: 1,
            description: "Upload and search documents.",
            pricingOptions: [
                try addOnPricing(id: "ao-docs", price: docsPackPrice, billingFrequency: "Monthly", trialDays: 14)
            ]
        )
        aiPack = try pack(
            id: "pack-ai",
            name: "AI Pack",
            category: "AI",
            displayOrder: 2,
            pricingOptions: [
                try addOnPricing(id: "ao-ai", price: aiPackPrice, billingFrequency: "Yearly")
            ]
        )
        loosePack = try pack(id: "pack-loose", name: "Loose Pack", category: "Misc", displayOrder: 3)
    }

    func catalog(
        tiers: [AppTierModel]? = nil,
        addOns: [AppTierAddOnModel]? = nil,
        currencyOverride: String? = nil
    ) -> PublicCatalog {
        PublicCatalog.build(
            appId: "app-1",
            tiers: tiers ?? self.tiers,
            addOns: addOns ?? packs,
            currencyOverride: currencyOverride
        )
    }
}

private let groups: [WildwoodAddOnGroup] = [
    WildwoodAddOnGroup(
        id: "core",
        title: "Core packs",
        blurb: "The ones most teams start with.",
        categories: ["Documents", "AI"]
    ),
    WildwoodAddOnGroup(id: "empty", title: "Nothing here", categories: ["Nope"])
]

private let labels = RegistrationSubscriptionPricingLabels.defaults

// MARK: - The rules

@MainActor
struct PricingViewRulesTests {
    // ── Loading, failure and retry ───────────────────────────────────────────

    @Test func showsShapesWhileTheFirstCatalogIsOnItsWay() throws {
        #expect(PricingViewRules.bodyKind(catalog: nil, isLoading: true, errorMessage: nil) == .loading)
    }

    @Test func showsTheUnavailablePanelWhenTheCatalogCannotBeRead() throws {
        let fixtures = try Fixtures()
        #expect(
            PricingViewRules.bodyKind(catalog: nil, isLoading: false, errorMessage: "catalog exploded")
                == .unavailable
        )
        // Prices already on screen go away with the answer that produced them.
        #expect(
            PricingViewRules.bodyKind(
                catalog: fixtures.catalog(),
                isLoading: false,
                errorMessage: "catalog exploded"
            ) == .unavailable
        )
        // A finished load with nothing to show is unreadable, not an empty shop.
        #expect(PricingViewRules.bodyKind(catalog: nil, isLoading: false, errorMessage: nil) == .unavailable)
    }

    @Test func showsPricesOnlyOnceACatalogIsInHand() throws {
        let fixtures = try Fixtures()
        #expect(
            PricingViewRules.bodyKind(catalog: fixtures.catalog(), isLoading: false, errorMessage: nil)
                == .content
        )
        // A background refresh must not blank what is already quoted.
        #expect(
            PricingViewRules.bodyKind(catalog: fixtures.catalog(), isLoading: true, errorMessage: nil)
                == .content
        )
    }

    @Test func namesTheFailureWithTheCodeTheWebReports() {
        #expect(RegistrationSubscriptionErrorCodes.catalogUnavailable == "catalog_unavailable")
    }

    // ── Live prices ──────────────────────────────────────────────────────────

    @Test func quotesTheCatalogInTheCurrencyTheServerNamed() throws {
        let fixtures = try Fixtures()
        var euroTiers: [AppTierModel] = []
        for model in fixtures.tiers {
            var copy: AppTierModel = model
            copy.currency = "EUR"
            euroTiers.append(copy)
        }
        let euros = fixtures.catalog(tiers: euroTiers)

        #expect(PricingViewRules.currency(override: nil, catalog: euros) == "EUR")
        #expect(PricingViewRules.currency(override: "GBP", catalog: euros) == "GBP")
    }

    @Test func fallsBackToWhatTheCatalogResolvedAndNeverToACurrencyOfItsOwn() throws {
        let fixtures = try Fixtures()
        var blankTiers: [AppTierModel] = []
        for model in fixtures.tiers {
            var copy: AppTierModel = model
            copy.currency = nil
            blankTiers.append(copy)
        }
        let noCurrency = fixtures.catalog(tiers: blankTiers, addOns: [])

        #expect(PricingViewRules.currency(override: nil, catalog: noCurrency) == Catalog.fallbackCurrency)
        // Nothing is quoted before a catalog arrives.
        #expect(PricingViewRules.currency(override: nil, catalog: nil) == "")
    }

    @Test func quotesAPlanAtTheOptionForTheChosenBillingPeriod() throws {
        let fixtures = try Fixtures()
        let pro = fixtures.proTier

        #expect(PricingViewRules.planPriceOption(pro, billing: .monthly)?.id == "price-pro-monthly")
        #expect(PricingViewRules.planPriceOption(pro, billing: .monthly)?.price == proMonthly)
        #expect(PricingViewRules.planPriceOption(pro, billing: .annual)?.id == "price-pro-annual")
        #expect(PricingViewRules.planPriceOption(pro, billing: .annual)?.price == proAnnual)
    }

    @Test func quotesAContactUsPlanAtNothingAtAll() throws {
        let fixtures = try Fixtures()
        #expect(PricingViewRules.planPriceOption(fixtures.enterpriseTier, billing: .monthly) == nil)
    }

    @Test func computesTheBestAnnualSavingFromTheLivePrices() throws {
        let fixtures = try Fixtures()
        let saving = Int((((proMonthly * 12 - proAnnual) / (proMonthly * 12)) * 100).rounded())

        #expect(PricingViewRules.bestAnnualDiscount(fixtures.tiers) == saving)
        #expect(PricingViewRules.bestAnnualDiscount([fixtures.freeTier]) == 0)
        #expect(PricingViewRules.annualDiscount(fixtures.freeTier) == nil)
        #expect(PricingViewRules.hasAnnualPricing(fixtures.tiers))
        #expect(PricingViewRules.hasAnnualPricing([fixtures.freeTier]) == false)
    }

    @Test func pricesEachPackOffTheCatalogPerPeriod() throws {
        let fixtures = try Fixtures()
        let docs = PricingViewRules.packPriceText(fixtures.docsPack, currency: "USD", labels: labels)
        let ai = PricingViewRules.packPriceText(fixtures.aiPack, currency: "USD", labels: labels)

        #expect(docs == WildwoodMoney.format(docsPackPrice, currency: "USD") + "/mo")
        #expect(ai == WildwoodMoney.format(aiPackPrice, currency: "USD") + "/yr")
    }

    @Test func saysAPackHasNoPriceYetRatherThanImplyingItIsFree() throws {
        let fixtures = try Fixtures()
        #expect(
            PricingViewRules.packPriceText(fixtures.loosePack, currency: "USD", labels: labels)
                == labels.packUnavailable
        )
    }

    @Test func pricesACurrencyOutsideTheOldSymbolTableAsItself() throws {
        let fixtures = try Fixtures()
        let text = PricingViewRules.packPriceText(fixtures.docsPack, currency: "CHF", labels: labels)

        #expect(text.contains(WildwoodMoney.format(docsPackPrice, currency: "CHF")))
        #expect(text.contains("$") == false)
    }

    @Test func addsNothingToAFrequencyItDoesNotRecognise() {
        #expect(PricingViewRules.billingSuffix("OneTime") == "")
        #expect(PricingViewRules.billingSuffix(nil) == "")
        #expect(PricingViewRules.billingSuffix("Weekly") == "/wk")
        #expect(PricingViewRules.billingSuffix("Daily") == "/day")
        #expect(PricingViewRules.billingSuffix("Annually") == "/yr")
        #expect(PricingViewRules.billingSuffix("Monthly") == "/mo")
    }

    // ── The plan grid ────────────────────────────────────────────────────────

    @Test func keepsEveryActivePlanByDefaultAndHidesFreeOnesWhenAsked() throws {
        let fixtures = try Fixtures()
        let all = PricingViewRules.visibleTiers(fixtures.catalog(), offerFreeTierChoice: true)
        let paid = PricingViewRules.visibleTiers(fixtures.catalog(), offerFreeTierChoice: false)

        #expect(all.map { $0.id } == ["tier-free", "tier-pro", "tier-ent"])
        #expect(paid.map { $0.id } == ["tier-pro", "tier-ent"])
        #expect(PricingViewRules.visibleTiers(nil, offerFreeTierChoice: true).isEmpty)
    }

    @Test func marksThePlanAPricingLinkCarriedInWhateverTheCasing() {
        #expect(PricingViewRules.isHighlighted(tierId: "tier-pro", highlightTierId: "TIER-PRO"))
        #expect(PricingViewRules.isHighlighted(tierId: "tier-free", highlightTierId: "tier-pro") == false)
        #expect(PricingViewRules.isHighlighted(tierId: "tier-pro", highlightTierId: nil) == false)
        #expect(PricingViewRules.isHighlighted(tierId: nil, highlightTierId: "tier-pro") == false)
    }

    @Test func rendersThePlanGridAloneByDefaultAndPacksAloneWhenAsked() {
        #expect(
            PricingViewRules.sections(showPlans: true, showAddOns: false)
                == PricingSections(plans: true, packs: false)
        )
        #expect(
            PricingViewRules.sections(showPlans: false, showAddOns: true)
                == PricingSections(plans: false, packs: true)
        )
    }

    // ── The pack grid ────────────────────────────────────────────────────────

    @Test func filesPacksUnderTheHostGroupsDropsEmptyOnesAndKeepsTheStrays() throws {
        let fixtures = try Fixtures()
        let grouped = PricingViewRules.groupAddOns(
            fixtures.packs,
            groups: groups,
            morePacksTitle: labels.morePacks
        )

        #expect(grouped.map { $0.id } == ["core", "more"])

        let core: PricingPackGroup = try #require(grouped.first)
        let more: PricingPackGroup = try #require(grouped.last)
        #expect(core.addOns.map { $0.id } == ["pack-docs", "pack-ai"])
        #expect(more.title == labels.morePacks)
        #expect(more.addOns.map { $0.id } == ["pack-loose"])
    }

    @Test func rendersOneFlatUntitledGroupWhenTheHostNamesNone() throws {
        let fixtures = try Fixtures()
        let flat = PricingViewRules.groupAddOns(fixtures.packs, groups: nil, morePacksTitle: labels.morePacks)

        #expect(flat.count == 1)

        let only: PricingPackGroup = try #require(flat.first)
        #expect(only.id == "all")
        #expect(only.title == nil)
        #expect(only.addOns.map { $0.id } == ["pack-docs", "pack-ai", "pack-loose"])
        #expect(PricingViewRules.groupAddOns([], groups: nil, morePacksTitle: labels.morePacks).isEmpty)
    }

    @Test func dropsTheCatchAllWhenEveryPackFoundAHome() throws {
        let fixtures = try Fixtures()
        let grouped = PricingViewRules.groupAddOns(
            [fixtures.docsPack, fixtures.aiPack],
            groups: groups,
            morePacksTitle: labels.morePacks
        )

        #expect(grouped.map { $0.id } == ["core"])
    }

    @Test func matchesAGroupCategoryCaseSensitivelyJustAsTheWebDoes() throws {
        let fixtures = try Fixtures()
        let shouty = [WildwoodAddOnGroup(id: "core", title: "Core", categories: ["DOCUMENTS"])]
        let grouped = PricingViewRules.groupAddOns(
            [fixtures.docsPack],
            groups: shouty,
            morePacksTitle: labels.morePacks
        )

        // "DOCUMENTS" does not claim "Documents", so the pack is a stray rather than a member —
        // and it is still on the screen.
        #expect(grouped.map { $0.id } == ["more"])
        #expect(grouped.first?.addOns.map { $0.id } == ["pack-docs"])
    }

    @Test func returnsTheSelectionInCatalogOrderNotTapOrder() throws {
        let fixtures = try Fixtures()
        let live = fixtures.catalog()

        #expect(
            PricingViewRules.togglePackSelection(catalog: live, current: ["pack-ai"], addOnId: "pack-docs")
                == ["pack-docs", "pack-ai"]
        )
    }

    @Test func unticksAPackThatIsAlreadyTicked() throws {
        let fixtures = try Fixtures()
        let live = fixtures.catalog()

        #expect(
            PricingViewRules.togglePackSelection(
                catalog: live,
                current: ["pack-docs", "pack-ai"],
                addOnId: "pack-ai"
            ) == ["pack-docs"]
        )
        #expect(
            PricingViewRules.togglePackSelection(catalog: live, current: ["pack-docs"], addOnId: "pack-docs")
                .isEmpty
        )
    }

    @Test func stopsAtThePlatformPackCapAndStillLetsAPackBeGivenBack() throws {
        let fixtures = try Fixtures()
        var many: [AppTierAddOnModel] = []
        for index in 0 ..< Catalog.maxAddOnSelection {
            many.append(try pack(id: "pack-\(index)", name: "Pack \(index)", category: "Bulk", displayOrder: index))
        }
        let bulky = fixtures.catalog(tiers: [], addOns: many + [fixtures.docsPack])
        let full: [String] = many.map { $0.id }

        #expect(full.count == Catalog.maxAddOnSelection)
        // One more would be 26: refused, and the basket is unchanged.
        #expect(
            PricingViewRules.togglePackSelection(catalog: bulky, current: full, addOnId: "pack-docs") == full
        )
        // Unticking is never capped.
        let firstId: String = try #require(full.first)
        #expect(
            PricingViewRules.togglePackSelection(catalog: bulky, current: full, addOnId: firstId).count
                == Catalog.maxAddOnSelection - 1
        )
    }

    @Test func hasNothingToSelectFromBeforeTheCatalogArrives() {
        #expect(PricingViewRules.togglePackSelection(catalog: nil, current: [], addOnId: "pack-docs").isEmpty)
    }

    @Test func countsPacksInWordsTheHostCanTranslate() {
        #expect(PricingViewRules.continueWithPacksLabel(count: 0, labels: labels) == "Continue with 0 packs")
        #expect(PricingViewRules.continueWithPacksLabel(count: 1, labels: labels) == labels.continueWithOnePack)
        #expect(PricingViewRules.continueWithPacksLabel(count: 2, labels: labels) == "Continue with 2 packs")
        #expect(PricingViewRules.annualSavingsLabel(percent: 17, labels: labels) == "Save up to 17%")
        #expect(PricingViewRules.packSelectLabel(name: "Docs Pack", labels: labels) == "Select Docs Pack")
        // An unmatched slot is left verbatim, as the JS helper leaves it.
        #expect(RegistrationSubscriptionLabelFormat.format("Save {percent}%", values: [:]) == "Save {percent}%")
    }

    @Test func listsPacksWithoutOfferingThemWhenTheStoreOwnsBilling() {
        #expect(PricingViewRules.packAffordance(packSelection: .none, packPurchaseAvailable: true) == .single)
        #expect(PricingViewRules.packAffordance(packSelection: .multi, packPurchaseAvailable: true) == .multi)
        // Decision 5: no in-app-purchase product exists behind an add-on, so the purchase goes
        // and the listing stays.
        #expect(
            PricingViewRules.packAffordance(packSelection: .multi, packPurchaseAvailable: false)
                == .informational
        )
        #expect(
            PricingViewRules.packAffordance(packSelection: .none, packPurchaseAvailable: false)
                == .informational
        )
    }

    // ── What the host is handed ──────────────────────────────────────────────

    @Test func handsAFreePlanBackWithItsPricingOptionAndTheMonthlyCycle() throws {
        let fixtures = try Fixtures()
        let payload = PricingViewRules.planSelectionPayload(
            tier: fixtures.freeTier,
            billing: .monthly,
            selectedPackIds: []
        )

        #expect(payload == PricingSelection(tierId: "tier-free", pricingId: "price-free", billing: .monthly))
    }

    @Test func switchesToTheAnnualPricingOptionWhenTheToggleIsFlipped() throws {
        let fixtures = try Fixtures()
        let payload = PricingViewRules.planSelectionPayload(
            tier: fixtures.proTier,
            billing: .annual,
            selectedPackIds: []
        )

        #expect(
            payload == PricingSelection(tierId: "tier-pro", pricingId: "price-pro-annual", billing: .annual)
        )
    }

    @Test func carriesTheTickedPacksOnAPlanCallToAction() throws {
        let fixtures = try Fixtures()
        let payload = PricingViewRules.planSelectionPayload(
            tier: fixtures.proTier,
            billing: .monthly,
            selectedPackIds: ["pack-docs"]
        )

        #expect(
            payload == PricingSelection(
                tierId: "tier-pro",
                pricingId: "price-pro-monthly",
                billing: .monthly,
                addOnIds: ["pack-docs"]
            )
        )
    }

    @Test func takesOnePackStraightThroughAndContinuesWithTheWholeBasket() {
        #expect(
            PricingViewRules.packSelectionPayload(addOnId: "pack-docs", billing: .monthly)
                == PricingSelection(billing: .monthly, addOnIds: ["pack-docs"])
        )
        #expect(
            PricingViewRules.packsContinuePayload(billing: .annual, selectedPackIds: ["pack-docs", "pack-ai"])
                == PricingSelection(billing: .annual, addOnIds: ["pack-docs", "pack-ai"])
        )
    }

    // ── Test hooks ───────────────────────────────────────────────────────────

    @Test func carriesTheWebAttributeValuesAcrossUnchanged() {
        #expect(RegistrationSubscriptionTestID.view(.pricing) == "pricing")
        #expect(RegistrationSubscriptionTestID.view(.signup, step: "register") == "register")
        #expect(RegistrationSubscriptionTestID.view(.manage, step: "") == "manage")
        #expect(RegistrationSubscriptionTestID.view(.manage) == "manage")
    }

    @Test func keepsAPackApartFromAGroupOfTheSameName() {
        #expect(RegistrationSubscriptionTestID.pack("core") != RegistrationSubscriptionTestID.group("core"))
        #expect(RegistrationSubscriptionTestID.pack("pack-docs").contains("pack-docs"))
        #expect(RegistrationSubscriptionTestID.group("more").contains("more"))
        #expect(RegistrationSubscriptionTestID.retryButton == "pricing-retry")
        #expect(RegistrationSubscriptionTestID.skeleton == "pricing-skeleton")
        #expect(RegistrationSubscriptionTestID.billingToggle == "billing-toggle")
        #expect(RegistrationSubscriptionTestID.packsContinue == "packs-continue")
    }

    // ── The copy is the JS copy ──────────────────────────────────────────────

    @Test func saysWhatTheOtherStacksSay() {
        #expect(labels.billingMonthly == "Monthly")
        #expect(labels.billingAnnual == "Annual")
        #expect(labels.billingToggleAriaLabel == "Toggle annual billing")
        #expect(labels.annualSavings == "Save up to {percent}%")
        #expect(labels.loadingPlans == "Loading plans...")
        #expect(labels.pricingUnavailable == "Pricing is unavailable right now")
        #expect(labels.retry == "Retry")
        #expect(labels.contactUs == "Contact us")
        #expect(labels.morePacks == "More packs")
        #expect(labels.packUnavailable == "Not yet available")
        #expect(labels.packSelect == "Select")
        #expect(labels.packSelectNamed == "Select {name}")
        #expect(labels.continueWithPacks == "Continue with {count} packs")
        #expect(labels.continueWithOnePack == "Continue with 1 pack")
    }
}

// MARK: - The plan card's footer: one call to action, chosen by priority

/// The chain in ``TierCardRules/footerAction(tier:isCurrentTier:isPreSelected:enterpriseContactUrl:)``,
/// ported from `packages/wildwood-react/src/components/tier/TierCardFooter.tsx`. The rule the whole
/// matrix exists to hold: EXACTLY ONE action applies, so a plan with nothing to buy can never also
/// offer to sell it.
@MainActor
struct TierFooterActionTests {
    private static let tierContactUrl: String = "https://example.com/sales"
    private static let hostContactUrl: String = "https://example.com/enterprise"

    private func plan(
        id: String = "tier-x",
        name: String = "Pro",
        isFreeTier: Bool = false,
        pricingOptions: [AppTierPricingModel] = [],
        showSubscribeButton: Bool = true,
        showContactButton: Bool = false,
        contactButtonUrl: String? = nil
    ) throws -> AppTierModel {
        var value: AppTierModel = try tier(
            id: id,
            name: name,
            displayOrder: 1,
            isFreeTier: isFreeTier,
            pricingOptions: pricingOptions
        )
        value.showSubscribeButton = showSubscribeButton
        value.showContactButton = showContactButton
        value.contactButtonUrl = contactButtonUrl
        return value
    }

    private func paidOption() throws -> AppTierPricingModel {
        try pricing(id: "price-x", price: proMonthly, billingFrequency: "Monthly", isDefault: true)
    }

    // ── Priority 0: the plan you are already on ──────────────────────────────

    @Test func labelsThePlanTheVisitorIsAlreadyOnAndSellsNothingElseOnThatCard() throws {
        let everything: AppTierModel = try plan(
            id: "tier-ent",
            name: "Enterprise",
            showContactButton: true,
            contactButtonUrl: Self.tierContactUrl
        )
        let action: TierFooterAction = TierCardRules.footerAction(
            tier: everything,
            isCurrentTier: true,
            enterpriseContactUrl: Self.hostContactUrl
        )

        #expect(action == .current(title: TierCardRules.currentPlanTitle))
        #expect(TierCardRules.raisesSelection(action) == false)
    }

    @Test func keepsAnEmptyFooterForACurrentPlanThatSwitchedItsCallToActionOff() throws {
        let quiet: AppTierModel = try plan(
            pricingOptions: [try paidOption()],
            showSubscribeButton: false
        )

        // The one departure from the web chain, and the behaviour this stack has always had: a
        // tier with `showSubscribeButton == false` renders no control, current plan or not.
        #expect(TierCardRules.footerAction(tier: quiet, isCurrentTier: true) == TierFooterAction.none)
    }

    // ── Priority 1: the tier's own contact button ────────────────────────────

    @Test func showsOnlyContactUsForAnEnterprisePlanWithItsOwnContactButton() throws {
        // The reviewer's exact scenario: no pricing options, not free, a contact button with a
        // URL, and `showSubscribeButton` left at the wire default of true.
        let enterprise: AppTierModel = try plan(
            id: "tier-ent",
            name: "Enterprise",
            pricingOptions: [],
            showContactButton: true,
            contactButtonUrl: Self.tierContactUrl
        )
        let url: URL = try #require(URL(string: Self.tierContactUrl))
        let action: TierFooterAction = TierCardRules.footerAction(
            tier: enterprise,
            enterpriseContactUrl: Self.hostContactUrl
        )

        #expect(enterprise.showSubscribeButton)
        #expect(TierCardRules.isEnterprise(enterprise))
        // One action, and it is the tier's own link — not a Select button beside it.
        #expect(action == .contactUs(url: url))
        #expect(TierCardRules.raisesSelection(action) == false)
    }

    @Test func letsAPricedPlansOwnContactButtonWinOverItsSubscribeButtonToo() throws {
        let paid: AppTierModel = try plan(
            pricingOptions: [try paidOption()],
            showContactButton: true,
            contactButtonUrl: Self.tierContactUrl
        )
        let url: URL = try #require(URL(string: Self.tierContactUrl))

        #expect(TierCardRules.isEnterprise(paid) == false)
        #expect(TierCardRules.footerAction(tier: paid) == .contactUs(url: url))
    }

    @Test func treatsABlankContactUrlAsNoContactButtonAtAll() throws {
        let blank: AppTierModel = try plan(
            pricingOptions: [try paidOption()],
            showContactButton: true,
            contactButtonUrl: ""
        )
        let spaces: AppTierModel = try plan(
            pricingOptions: [try paidOption()],
            showContactButton: true,
            contactButtonUrl: "   "
        )

        // A misconfigured link falls THROUGH to the next priority rather than rendering a button
        // that does nothing.
        #expect(TierCardRules.footerAction(tier: blank) == .subscribe(title: "Select Pro"))
        #expect(TierCardRules.footerAction(tier: spaces) == .subscribe(title: "Select Pro"))
    }

    // ── Priorities 2 and 3: the enterprise plan ──────────────────────────────

    @Test func sendsAnEnterprisePlanToTheHostContactUrlWhenItNamesNoneOfItsOwn() throws {
        let enterprise: AppTierModel = try plan(id: "tier-ent", name: "Enterprise")
        let url: URL = try #require(URL(string: Self.hostContactUrl))
        let action: TierFooterAction = TierCardRules.footerAction(
            tier: enterprise,
            enterpriseContactUrl: Self.hostContactUrl
        )

        #expect(action == .contactSales(url: url))
        #expect(TierCardRules.raisesSelection(action) == false)
    }

    @Test func asksTheHostToDoTheContactingWhenThereIsNoUrlAnywhere() throws {
        let enterprise: AppTierModel = try plan(id: "tier-ent", name: "Enterprise")
        let action: TierFooterAction = TierCardRules.footerAction(tier: enterprise)

        // React's priority 3: a "Contact Sales" BUTTON that raises the selection, because being
        // told is the only thing it can do.
        #expect(action == .contactSalesRequest(title: TierCardRules.contactSalesTitle))
        #expect(TierCardRules.raisesSelection(action))
    }

    @Test func offersContactSalesEvenWhenTheEnterprisePlanSuppressedItsSubscribeButton() throws {
        let enterprise: AppTierModel = try plan(
            id: "tier-ent",
            name: "Enterprise",
            showSubscribeButton: false
        )

        #expect(
            TierCardRules.footerAction(tier: enterprise)
                == .contactSalesRequest(title: TierCardRules.contactSalesTitle)
        )
    }

    // ── Priority 4: the ordinary call to action ──────────────────────────────

    @Test func offersTheOrdinaryCallToActionForAPricedPlan() throws {
        let paid: AppTierModel = try plan(pricingOptions: [try paidOption()])
        let action: TierFooterAction = TierCardRules.footerAction(tier: paid)

        #expect(action == .subscribe(title: TierCardRules.subscribeTitle(tierName: "Pro")))
        #expect(action == .subscribe(title: "Select Pro"))
        #expect(TierCardRules.raisesSelection(action))
    }

    @Test func offersAFreePlanEvenWhenNobodyPricedIt() throws {
        let free: AppTierModel = try plan(id: "tier-free", name: "Starter", isFreeTier: true)
        let action: TierFooterAction = TierCardRules.footerAction(tier: free)

        // A free plan is never the "contact us" plan, however it is priced.
        #expect(TierCardRules.isEnterprise(free) == false)
        #expect(action == .subscribe(title: "Select Starter"))
        #expect(TierCardRules.raisesSelection(action))
    }

    @Test func continuesWithAPlanAPricingLinkAlreadyChose() throws {
        let paid: AppTierModel = try plan(pricingOptions: [try paidOption()])

        #expect(
            TierCardRules.footerAction(tier: paid, isPreSelected: true)
                == .subscribe(title: TierCardRules.preSelectedSubscribeTitle)
        )
    }

    @Test func rendersNothingForAPricedPlanThatSwitchedItsCallToActionOff() throws {
        let quiet: AppTierModel = try plan(
            pricingOptions: [try paidOption()],
            showSubscribeButton: false
        )
        let action: TierFooterAction = TierCardRules.footerAction(tier: quiet)

        #expect(action == TierFooterAction.none)
        #expect(TierCardRules.raisesSelection(action) == false)
    }
}

// MARK: - The view model, against a stubbed catalog

@MainActor
struct PricingViewModelTests {
    private static let appId = "app-1"

    private var tiersPath: String { "/api/app-tiers/\(Self.appId)/public" }
    private var addOnsPath: String { "/api/app-tier-addons/\(Self.appId)/public" }

    private func stubCatalog(_ backend: TestBackend) {
        backend.stub(
            "GET",
            tiersPath,
            TestStubResponse(
                json: """
                [{"id":"tier-free","name":"Starter","status":"Active","displayOrder":1,"isFreeTier":true,
                  "currency":"USD",
                  "pricingOptions":[{"id":"price-free","price":0,"billingFrequency":"Monthly","isDefault":true}]},
                 {"id":"tier-pro","name":"Pro","status":"Active","displayOrder":2,"currency":"USD",
                  "pricingOptions":[
                    {"id":"price-pro-monthly","price":79,"billingFrequency":"Monthly","isDefault":true,"displayOrder":1},
                    {"id":"price-pro-annual","price":790,"billingFrequency":"Yearly","displayOrder":2}]}]
                """
            )
        )
        backend.stub(
            "GET",
            addOnsPath,
            TestStubResponse(
                json: """
                [{"id":"pack-docs","name":"Docs Pack","category":"Documents","status":"Active","displayOrder":1,
                  "pricingOptions":[{"id":"ao-docs","price":9,"billingFrequency":"Monthly","isDefault":true}]},
                 {"id":"pack-ai","name":"AI Pack","category":"AI","status":"Active","displayOrder":2,
                  "pricingOptions":[{"id":"ao-ai","price":19,"billingFrequency":"Yearly","isDefault":true}]}]
                """
            )
        )
    }

    private func makeModel(
        _ backend: TestBackend,
        currency: String? = nil,
        offerFreeTierChoice: Bool = true
    ) -> WildwoodPricingViewModel {
        WildwoodPricingViewModel(
            client: makeTestClient(backend, appId: Self.appId),
            appId: Self.appId,
            currency: currency,
            offerFreeTierChoice: offerFreeTierChoice
        )
    }

    @Test func showsShapesAndNoPricesBeforeTheFirstCatalogLands() {
        let backend = TestBackend()
        let model = makeModel(backend)

        #expect(model.bodyKind == .loading)
        // Nothing is formatted, because there is nothing to format: no plans, no packs, and not
        // even a currency to quote in.
        #expect(model.visiblePlans.isEmpty)
        #expect(model.packs.isEmpty)
        #expect(model.displayCurrency.isEmpty)
        #expect(model.catalog == nil)
    }

    @Test func quotesTheLivePriceForEachBillingPeriod() async throws {
        let backend = TestBackend()
        stubCatalog(backend)
        let model = makeModel(backend)

        await model.load()

        #expect(model.bodyKind == .content)
        #expect(model.displayCurrency == "USD")
        #expect(model.visiblePlans.map { $0.id } == ["tier-free", "tier-pro"])

        let pro: AppTierModel = try #require(model.visiblePlans.first { $0.id == "tier-pro" })
        #expect(PricingViewRules.planPriceOption(pro, billing: .monthly)?.id == "price-pro-monthly")

        model.setBilling(.annual)
        #expect(model.billing == .annual)
        #expect(PricingViewRules.planPriceOption(pro, billing: model.billing)?.id == "price-pro-annual")

        // The pack price is the server's figure, formatted by the shared formatter.
        let docs: AppTierAddOnModel = try #require(model.packs.first { $0.id == "pack-docs" })
        let expected: String = WildwoodMoney.format(9, currency: "USD") + "/mo"
        #expect(
            PricingViewRules.packPriceText(docs, currency: model.displayCurrency, labels: labels) == expected
        )
    }

    @Test func letsTheCurrencyOverrideWinAndHidesFreePlansWhenTheHostSaysSo() async {
        let backend = TestBackend()
        stubCatalog(backend)
        let model = makeModel(backend, currency: "GBP", offerFreeTierChoice: false)

        await model.load()

        #expect(model.displayCurrency == "GBP")
        #expect(model.visiblePlans.map { $0.id } == ["tier-pro"])
    }

    @Test func saysPricingIsUnavailableAndReportsTheFailureOncePerMessage() async {
        let backend = TestBackend()
        backend.stub("GET", addOnsPath, TestStubResponse(json: "[]"))
        backend.stub(
            "GET",
            tiersPath,
            TestStubResponse(statusCode: 500, json: #"{"message":"catalog exploded"}"#)
        )

        let model = makeModel(backend)
        let failures = Recorder<RegistrationSubscriptionError>()
        model.onError = { failures.record($0) }

        await model.load()

        #expect(model.bodyKind == .unavailable)
        #expect(model.catalog == nil)
        #expect(model.errorMessage?.isEmpty == false)
        #expect(failures.count == 1)
        #expect(failures.first?.code == RegistrationSubscriptionErrorCodes.catalogUnavailable)

        // The same failure again is not news.
        await model.retry()
        #expect(failures.count == 1)

        // A different one is.
        backend.stub(
            "GET",
            tiersPath,
            TestStubResponse(statusCode: 500, json: #"{"message":"catalog still exploded"}"#)
        )
        await model.retry()
        #expect(failures.count == 2)
    }

    @Test func retryLoadsAgainRatherThanReadingTheCache() async {
        let backend = TestBackend()
        stubCatalog(backend)
        let model = makeModel(backend)

        await model.load()
        #expect(requestCount(backend, path: tiersPath) == 1)

        // Well inside the 60-second TTL: a plain load would be answered from the cache and the
        // button would look broken, so Retry forces a refresh.
        await model.retry()
        #expect(requestCount(backend, path: tiersPath) == 2)
        #expect(model.bodyKind == .content)
        #expect(model.errorMessage == nil)
    }

    @Test func recoversWhenTheCatalogComesBack() async {
        let backend = TestBackend()
        backend.stub("GET", addOnsPath, TestStubResponse(json: "[]"))
        backend.stub("GET", tiersPath, TestStubResponse(statusCode: 500, json: #"{"message":"nope"}"#))
        let model = makeModel(backend)

        await model.load()
        #expect(model.bodyKind == .unavailable)

        stubCatalog(backend)
        await model.retry()

        #expect(model.bodyKind == .content)
        #expect(model.errorMessage == nil)
        #expect(model.visiblePlans.isEmpty == false)
    }

    @Test func ticksPacksInCatalogOrderAndHandsThemToThePlanCallToAction() async throws {
        let backend = TestBackend()
        stubCatalog(backend)
        let model = makeModel(backend)

        await model.load()

        model.togglePack("pack-ai")
        model.togglePack("pack-docs")
        #expect(model.selectedPackIds == ["pack-docs", "pack-ai"])
        #expect(model.isPackSelected("pack-ai"))

        let pro: AppTierModel = try #require(model.visiblePlans.first { $0.id == "tier-pro" })
        #expect(
            model.planSelectionPayload(for: pro) == PricingSelection(
                tierId: "tier-pro",
                pricingId: "price-pro-monthly",
                billing: .monthly,
                addOnIds: ["pack-docs", "pack-ai"]
            )
        )
        #expect(
            model.packsContinuePayload()
                == PricingSelection(billing: .monthly, addOnIds: ["pack-docs", "pack-ai"])
        )
        #expect(
            model.packSelectionPayload(forPack: "pack-docs")
                == PricingSelection(billing: .monthly, addOnIds: ["pack-docs"])
        )

        model.togglePack("pack-docs")
        #expect(model.selectedPackIds == ["pack-ai"])

        model.clearPackSelection()
        #expect(model.selectedPackIds.isEmpty)
    }

    /// A catalog whose only plans are a "contact us" one with its own contact page and a free one
    /// nobody priced.
    private func stubContactOnlyCatalog(_ backend: TestBackend) {
        backend.stub("GET", addOnsPath, TestStubResponse(json: "[]"))
        backend.stub(
            "GET",
            tiersPath,
            TestStubResponse(
                json: """
                [{"id":"tier-ent","name":"Enterprise","status":"Active","displayOrder":1,"currency":"USD",
                  "showContactButton":true,"contactButtonUrl":"https://example.com/sales","pricingOptions":[]},
                 {"id":"tier-quiet","name":"Quiet","status":"Active","displayOrder":2,"currency":"USD",
                  "showSubscribeButton":false,
                  "pricingOptions":[{"id":"price-quiet","price":5,"billingFrequency":"Monthly","isDefault":true}]},
                 {"id":"tier-free","name":"Starter","status":"Active","displayOrder":3,"isFreeTier":true,
                  "currency":"USD","pricingOptions":[]}]
                """
            )
        )
    }

    @Test func handsNoSelectionBackForAPlanWhoseCallToActionOnlyOpensAContactPage() async throws {
        let backend = TestBackend()
        stubContactOnlyCatalog(backend)
        let model = makeModel(backend)

        await model.load()

        let enterprise: AppTierModel = try #require(model.visiblePlans.first { $0.id == "tier-ent" })
        let quiet: AppTierModel = try #require(model.visiblePlans.first { $0.id == "tier-quiet" })

        // Its footer opens the operator's contact page; nothing is bought, so no host is told a
        // plan with no price was chosen.
        #expect(model.planSelectionPayload(for: enterprise) == nil)
        // Nor for a plan that renders no call to action at all.
        #expect(model.planSelectionPayload(for: quiet) == nil)
    }

    @Test func stillTellsTheHostAboutAPlanThatCanOnlyBeAskedAbout() async throws {
        let backend = TestBackend()
        stubContactOnlyCatalog(backend)
        let model = makeModel(backend)

        await model.load()

        var enterprise: AppTierModel = try #require(model.visiblePlans.first { $0.id == "tier-ent" })
        enterprise.showContactButton = false
        enterprise.contactButtonUrl = nil

        // The host named a contact URL, so the card is a link again and raises nothing.
        #expect(
            model.planSelectionPayload(for: enterprise, contactUrl: "https://example.com/enterprise") == nil
        )
        // With nowhere to send anyone the host IS told, exactly as the web card does it, and the
        // payload is honest about there being no price.
        #expect(
            model.planSelectionPayload(for: enterprise)
                == PricingSelection(tierId: "tier-ent", pricingId: nil, billing: .monthly)
        )
    }

    @Test func stillHandsBackAFreePlanNobodyPriced() async throws {
        let backend = TestBackend()
        stubContactOnlyCatalog(backend)
        let model = makeModel(backend)

        await model.load()

        let free: AppTierModel = try #require(model.visiblePlans.first { $0.id == "tier-free" })

        #expect(
            model.planSelectionPayload(for: free)
                == PricingSelection(tierId: "tier-free", pricingId: nil, billing: .monthly)
        )
    }
}
