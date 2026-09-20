// The manage view decides what a subscriber sees and where the card for a change comes from.
//
// Ported case for case from
// packages/wildwood-react-native/src/__tests__/manageView.test.ts, minus the cases that only make
// sense for a JSX renderer. The rules are pure, so they are tested as functions; the two that are
// really the DRIVER's (a closed card sheet, a host that answers nothing) are driven through
// ``WildwoodPlanChangeModel`` against a stub backend, because "back to the confirmation" and
// "abandon the change" are only true of the state the driver actually lands in.
//
// The seam's other rules — `SupportsPaymentAction` never sent without a handler, the bounded
// completion retry, a refused challenge, a drained detach — are pinned in `PlanChangeModelTests`
// against the same driver and are not repeated here.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

// MARK: - Fixtures

private func addOn(
    id: String,
    name: String,
    category: String = "",
    bundledInTierIds: [String] = [],
    pricingIds: [String] = []
) throws -> AppTierAddOnModel {
    var value = try WildwoodJSON.decoder().decode(AppTierAddOnModel.self, from: Data("{}".utf8))
    value.id = id
    value.appId = "app-1"
    value.name = name
    value.category = category
    value.status = "Active"
    value.bundledInTierIds = bundledInTierIds
    value.currency = "USD"
    value.pricingOptions = try pricingIds.enumerated().map { index, pricingId in
        var pricing = try WildwoodJSON.decoder().decode(
            AppTierAddOnPricingModel.self,
            from: Data("{}".utf8)
        )
        pricing.id = pricingId
        pricing.price = 9
        pricing.billingFrequency = "Monthly"
        pricing.isDefault = index == 0
        return pricing
    }
    return value
}

private func ownedRow(
    id: String,
    addOnId: String,
    status: String,
    isBundled: Bool = false,
    paymentTransactionId: String? = "txn-1"
) throws -> UserAddOnSubscriptionModel {
    var value = try WildwoodJSON.decoder().decode(
        UserAddOnSubscriptionModel.self,
        from: Data("{}".utf8)
    )
    value.id = id
    value.appTierAddOnId = addOnId
    value.addOnName = addOnId
    value.status = status
    value.isBundled = isBundled
    value.paymentTransactionId = paymentTransactionId
    return value
}

private func tier(id: String, name: String, currency: String? = "USD") throws -> AppTierModel {
    var value = try WildwoodJSON.decoder().decode(AppTierModel.self, from: Data("{}".utf8))
    value.id = id
    value.appId = "app-1"
    value.name = name
    value.currency = currency
    return value
}

private func paymentRequest(price: Double = 20) throws -> WildwoodPaymentRequiredArgs {
    let plan = try tier(id: "tier-pro", name: "Pro")
    return WildwoodPaymentRequiredArgs(
        tier: plan,
        pricing: nil,
        pricingModelId: "pm-1",
        price: price,
        currency: "USD",
        trialDays: nil,
        isSubscription: true
    )
}

// MARK: - Sections and layout

@MainActor
struct ManageViewSectionTests {
    @Test func everySectionRendersForAnAdminWithPacksOn() {
        let visible = ManageViewRules.visibleSections(sections: nil, isAdmin: true, showAddOns: true)
        #expect(visible == ManageViewRules.allSections)
        #expect(visible == [.subscription, .plans, .features, .addOns, .usage, .overrides])
    }

    @Test func theTwoFiltersApplyWhetherASectionWasNamedOrDefaulted() {
        let defaulted = ManageViewRules.visibleSections(sections: nil, isAdmin: false, showAddOns: false)
        #expect(defaulted == [.subscription, .plans, .features, .usage])

        // Naming them does not get past the filters: a non-admin may not see per-user grants, and
        // a surface with packs turned off does not get the packs panel back.
        let named = ManageViewRules.visibleSections(
            sections: [.overrides, .addOns, .plans],
            isAdmin: false,
            showAddOns: false
        )
        #expect(named == [.plans])
    }

    @Test func theHostsOwnOrderIsKept() {
        let visible = ManageViewRules.visibleSections(
            sections: [.usage, .subscription, .plans],
            isAdmin: false,
            showAddOns: true
        )
        #expect(visible == [.usage, .subscription, .plans])
    }

    @Test func theLiftedStatusCardIsNotAlsoASectionBelowTheTabs() {
        let lifted = ManageViewRules.layout(
            sections: nil,
            isAdmin: false,
            showAddOns: true,
            showStatusAboveTabs: true
        )
        #expect(lifted.statusAbove == true)
        #expect(lifted.body.contains(.subscription) == false)
        #expect(lifted.body == [.plans, .features, .addOns, .usage])

        let inline = ManageViewRules.layout(
            sections: nil,
            isAdmin: false,
            showAddOns: true,
            showStatusAboveTabs: false
        )
        #expect(inline.statusAbove == false)
        #expect(inline.body.first == .subscription)
    }

    @Test func nothingIsLiftedWhenTheSubscriptionSectionWasNotAskedFor() {
        let arrangement = ManageViewRules.layout(
            sections: [.plans, .usage],
            isAdmin: false,
            showAddOns: true,
            showStatusAboveTabs: true
        )
        #expect(arrangement.statusAbove == false)
        #expect(arrangement.body == [.plans, .usage])
    }

    @Test func theOpenTabFallsBackWhenItStopsBeingOnOffer() {
        let body: [ManageSection] = [.subscription, .plans]
        #expect(ManageViewRules.currentTab(.plans, body: body) == .plans)
        // `isAdmin` flipping takes `overrides` away; a layout still pointing at it renders nothing.
        #expect(ManageViewRules.currentTab(.overrides, body: body) == .subscription)
        #expect(ManageViewRules.currentTab(nil, body: body) == .subscription)
        #expect(ManageViewRules.currentTab(.plans, body: []) == nil)
    }

    @Test func everySectionTitleIsALabel() {
        let labels = RegistrationSubscriptionLabels.defaults
        #expect(ManageViewRules.sectionTitle(.subscription, labels: labels) == labels.sectionStatus)
        #expect(ManageViewRules.sectionTitle(.plans, labels: labels) == labels.sectionPlans)
        #expect(ManageViewRules.sectionTitle(.features, labels: labels) == labels.sectionFeatures)
        #expect(ManageViewRules.sectionTitle(.addOns, labels: labels) == labels.sectionPacks)
        #expect(ManageViewRules.sectionTitle(.usage, labels: labels) == labels.sectionUsage)
        #expect(ManageViewRules.sectionTitle(.overrides, labels: labels) == labels.sectionOverrides)
    }

    @Test func onlyTheStackedLayoutShowsEverythingAtOnce() {
        #expect(ManageViewRules.isTabbed(.tabs) == true)
        #expect(ManageViewRules.isTabbed(.stacked) == false)
    }

    @Test func theScopeFollowsWhoIsBeingManaged() {
        #expect(ManageViewRules.scope(userId: nil, companyId: nil) == .currentUser)
        #expect(ManageViewRules.scope(userId: "u-1", companyId: nil) == .user(id: "u-1"))
        #expect(ManageViewRules.scope(userId: nil, companyId: "c-1") == .company(id: "c-1"))
        // A user beats a company, as the web's `userId ? ... : companyId ? ...` ladder does.
        #expect(ManageViewRules.scope(userId: "u-1", companyId: "c-1") == .user(id: "u-1"))
        // Whitespace is not an id.
        #expect(ManageViewRules.scope(userId: " ", companyId: nil) == .currentUser)
    }

    @Test func theCurrencyIsTheHostsThenTheServersAndOnlyThenTheFallback() throws {
        let priced = [try tier(id: "t-1", name: "Pro", currency: "CHF")]
        let unpriced = [try tier(id: "t-1", name: "Pro", currency: nil)]

        #expect(ManageViewRules.currency(override: "SEK", tiers: priced) == "SEK")
        #expect(ManageViewRules.currency(override: nil, tiers: priced) == "CHF")
        #expect(ManageViewRules.currency(override: nil, tiers: unpriced) == "USD")
        #expect(ManageViewRules.currency(override: "  ", tiers: priced) == "CHF")
    }

    @Test func aHostMergeThatHasNotAnsweredDoesNotBlankTheUsagePanel() {
        let fromServer = [AppTierLimitStatusModel(limitCode: "api", displayName: "API calls")]
        let merged = [AppTierLimitStatusModel(limitCode: "api", displayName: "API calls", currentUsage: 5)]

        #expect(
            ManageViewRules.effectiveLimitStatuses(merged: [], fromServer: fromServer, hasMerge: false)
                == fromServer
        )
        #expect(
            ManageViewRules.effectiveLimitStatuses(merged: [], fromServer: fromServer, hasMerge: true)
                == fromServer
        )
        #expect(
            ManageViewRules.effectiveLimitStatuses(merged: merged, fromServer: fromServer, hasMerge: true)
                == merged
        )
    }

    @Test func theRootCarriesThePlanChangeStepAndTheViewsNameAtRest() {
        #expect(ManageViewRules.stepIdentifier(nil) == nil)
        #expect(ManageViewRules.stepIdentifier(.idle) == nil)
        #expect(ManageViewRules.stepIdentifier(.collectingPayment) == "collectingPayment")
        #expect(ManageViewRules.stepIdentifier(.failed) == "failed")

        // The same strings the web hangs off `data-ww-view` and `data-ww-step`.
        #expect(RegistrationSubscriptionTestID.view(.manage) == "manage")
        #expect(
            RegistrationSubscriptionTestID.view(.manage, step: ManageViewRules.stepIdentifier(.confirm))
                == "confirm"
        )
        #expect(RegistrationSubscriptionTestID.section(.addOns) == "section:addOns")
        #expect(RegistrationSubscriptionTestID.modal("payment") == "modal:payment")
        #expect(RegistrationSubscriptionTestID.paymentModal == "modal:payment")
        #expect(RegistrationSubscriptionTestID.packsModal == "modal:packs")
    }
}

// MARK: - The card, the notice and the store

@MainActor
struct ManageViewCardTests {
    @Test func theHostsHandlerWinsWhereverItExists() throws {
        let request = try paymentRequest()
        #expect(
            ManageViewRules.planChangeCardSource(
                step: .collectingPayment,
                hasHostHandler: true,
                paymentRequest: nil,
                collectsPaymentInApp: true
            ) == .host
        )
        // Even with a request in hand: the driver only exposes one when no host handler exists,
        // but the rule does not depend on that.
        #expect(
            ManageViewRules.planChangeCardSource(
                step: .collectingPayment,
                hasHostHandler: true,
                paymentRequest: request,
                collectsPaymentInApp: true
            ) == .host
        )
    }

    @Test func aSurfaceThatMountsTheSheetTakesTheCardAndOneThatDoesNotSaysSo() throws {
        let request = try paymentRequest()
        #expect(
            ManageViewRules.planChangeCardSource(
                step: .collectingPayment,
                hasHostHandler: false,
                paymentRequest: request,
                collectsPaymentInApp: true
            ) == .builtIn
        )
        #expect(
            ManageViewRules.planChangeCardSource(
                step: .collectingPayment,
                hasHostHandler: false,
                paymentRequest: request,
                collectsPaymentInApp: false
            ) == .finishOnWeb
        )
    }

    @Test func noCardIsWantedAnywhereElseInTheFlow() throws {
        let request = try paymentRequest()
        for step in PlanChangeStep.allCases where step != .collectingPayment {
            #expect(
                ManageViewRules.planChangeCardSource(
                    step: step,
                    hasHostHandler: false,
                    paymentRequest: request,
                    collectsPaymentInApp: true
                ) == PlanChangeCardSource.none
            )
        }
        // And a step that wants one with nothing to collect is not a card step either.
        #expect(
            ManageViewRules.planChangeCardSource(
                step: .collectingPayment,
                hasHostHandler: false,
                paymentRequest: nil,
                collectsPaymentInApp: true
            ) == PlanChangeCardSource.none
        )
    }

    @Test func theNoticeSpeaksForTheBankAndForAFailureAndNothingElse() throws {
        let labels = RegistrationSubscriptionLabels.defaults
        let request = try paymentRequest()

        let authenticating = ManageViewRules.planChangeNoticeContent(
            step: .authenticating,
            paymentRequest: nil,
            error: nil,
            canRetry: false,
            labels: labels,
            collectsPaymentInApp: true
        )
        #expect(authenticating.kind == .progress)
        #expect(authenticating.message == labels.authenticatingChange)

        let completing = ManageViewRules.planChangeNoticeContent(
            step: .completing,
            paymentRequest: nil,
            error: nil,
            canRetry: false,
            labels: labels,
            collectsPaymentInApp: true
        )
        #expect(completing.message == labels.applyingChange)

        // The surface mounts the sheet, so the notice stays out of the card step entirely.
        let collecting = ManageViewRules.planChangeNoticeContent(
            step: .collectingPayment,
            paymentRequest: request,
            error: nil,
            canRetry: false,
            labels: labels,
            collectsPaymentInApp: true
        )
        #expect(collecting.kind == PlanChangeNoticeKind.none)

        let stranded = ManageViewRules.planChangeNoticeContent(
            step: .collectingPayment,
            paymentRequest: request,
            error: nil,
            canRetry: false,
            labels: labels,
            collectsPaymentInApp: false
        )
        #expect(stranded.kind == .payment)
        #expect(stranded.message == labels.finishOnWeb)
        #expect(stranded.canDismiss == true)

        let failed = ManageViewRules.planChangeNoticeContent(
            step: .failed,
            paymentRequest: nil,
            error: "Your bank said no.",
            canRetry: true,
            labels: labels,
            collectsPaymentInApp: true
        )
        #expect(failed.kind == .failed)
        #expect(failed.title == labels.planChangeFailed)
        #expect(failed.message == "Your bank said no.")
        #expect(failed.canRetry == true)
        #expect(failed.canDismiss == true)

        let idle = ManageViewRules.planChangeNoticeContent(
            step: .idle,
            paymentRequest: nil,
            error: nil,
            canRetry: false,
            labels: labels,
            collectsPaymentInApp: true
        )
        #expect(idle.kind == PlanChangeNoticeKind.none)
        #expect(idle.message.isEmpty)
    }

    @Test func theCardSheetIsTitledAfterThePlanBeingBought() {
        #expect(
            ManageViewRules.paymentSheetTitle(labels: .defaults, tierName: "Pro") == "Upgrade to Pro"
        )
    }

    @Test func aChangeIsAChangeOnlyWhenSomethingIsAlreadySubscribed() throws {
        let plan = try tier(id: "tier-pro", name: "Pro")
        #expect(
            ManageViewRules.planChangeSelection(tier: plan, pricing: nil, hasSubscription: true).isChange
                == true
        )
        #expect(
            ManageViewRules.planChangeSelection(tier: plan, pricing: nil, hasSubscription: false).isChange
                == false
        )
    }
}

// MARK: - Packs

@MainActor
struct ManageViewPackTests {
    @Test func onlyPacksTheAccountLacksAreOnOffer() throws {
        let packs = [
            try addOn(id: "pack-a", name: "A", pricingIds: ["pa-1", "pa-2"]),
            try addOn(id: "pack-b", name: "B", pricingIds: ["pb-1"]),
            try addOn(id: "pack-c", name: "C", pricingIds: ["pc-1"]),
            try addOn(id: "pack-d", name: "D", bundledInTierIds: ["tier-pro"], pricingIds: ["pd-1"]),
        ]
        let rows = [
            // Owned outright.
            try ownedRow(id: "s-1", addOnId: "pack-a", status: "Active"),
            // Scheduled to cancel: still owned, so it is not sold twice.
            try ownedRow(id: "s-2", addOnId: "pack-b", status: "PendingCancellation"),
            // Cancelled: on offer again.
            try ownedRow(id: "s-3", addOnId: "pack-c", status: "Cancelled"),
        ]

        let offered = ManageViewRules.availablePacks(
            packs,
            subscriptions: rows,
            currentTierId: "tier-pro"
        )
        #expect(offered.map(\.id) == ["pack-c"])

        // A granted row grants access exactly as a bought one does, so its pack stays off the
        // list; and without the bundling plan, pack D is on offer again.
        let granted = [try ownedRow(id: "s-4", addOnId: "pack-a", status: "Active", paymentTransactionId: nil)]
        let withoutPlan = ManageViewRules.availablePacks(packs, subscriptions: granted, currentTierId: nil)
        #expect(withoutPlan.map(\.id) == ["pack-b", "pack-c", "pack-d"])
    }

    @Test func aBasketBuysEachPacksDefaultPricingAndDropsWhatIsNotSold() throws {
        let packs = [
            try addOn(id: "pack-a", name: "A", pricingIds: ["pa-1", "pa-2"]),
            try addOn(id: "pack-b", name: "B"),
        ]
        let items = ManageViewRules.checkoutItems(ids: ["pack-b", "pack-a", "pack-gone"], addOns: packs)

        // Catalog order, not tick order — the server prices a basket, not a sequence.
        #expect(items.map(\.addOnId) == ["pack-a", "pack-b"])
        #expect(items.first?.pricingId == "pa-1")
        // A pack with no pricing option sends none rather than inventing one.
        #expect(items.last?.pricingId == nil)

        let names = ManageViewRules.packNames(packs)
        #expect(names["pack-a"] == "A")
        #expect(names["pack-b"] == "B")
    }

    @Test func aStoreBilledAppListsPacksAndSellsNone() {
        #expect(
            ManageViewRules.packSelfServiceOffered(
                allowPackSelfService: true, showAddOns: true, requiresAppStorePayment: false
            ) == true
        )
        // Decision 5 / DD-4: pack checkout is a card purchase and Apple's product mapping is
        // tier-only, so the PURCHASE is hidden while owned rows keep rendering.
        #expect(
            ManageViewRules.packSelfServiceOffered(
                allowPackSelfService: true, showAddOns: true, requiresAppStorePayment: true
            ) == false
        )
        #expect(
            ManageViewRules.packSelfServiceOffered(
                allowPackSelfService: false, showAddOns: true, requiresAppStorePayment: false
            ) == false
        )
        #expect(
            ManageViewRules.packSelfServiceOffered(
                allowPackSelfService: true, showAddOns: false, requiresAppStorePayment: false
            ) == false
        )
    }
}

// MARK: - The built-in card sheet, through the driver

@MainActor
struct ManageViewPaymentSheetTests {
    private static let appId = "app-1"

    private var previewPath: String { "/api/app-tiers/\(Self.appId)/my-subscription/preview-change" }
    private var changePath: String { "/api/app-tiers/\(Self.appId)/my-subscription/change" }

    private func planSelection() throws -> PlanChangeSelection {
        let json = """
        {"id":"tier-pro","appId":"\(Self.appId)","name":"Pro","isFreeTier":false,
         "pricingOptions":[{"id":"p-1","appTierId":"tier-pro","price":20,"billingFrequency":"Monthly",
         "pricingModelId":"pm-1","isDefault":true}]}
        """
        let plan = try WildwoodJSON.decoder().decode(AppTierModel.self, from: Data(json.utf8))
        return PlanChangeSelection(tier: plan, pricing: plan.pricingOptions.first, isChange: true)
    }

    private func makeModel(_ backend: TestBackend) -> WildwoodPlanChangeModel {
        let client = makeTestClient(backend, appId: Self.appId)
        let admin = WildwoodSubscriptionAdminModel(client: client, appId: Self.appId, scope: .currentUser)
        let model = WildwoodPlanChangeModel(
            client: client,
            admin: admin,
            paymentActionHandler: nil,
            issuer: StepTokenIssuer()
        )
        model.completeRetryDelay = .zero
        return model
    }

    private func stubPaidPreview(_ backend: TestBackend) {
        backend.stub(
            "POST",
            previewPath,
            TestStubResponse(
                json: """
                {"success":true,"paymentRequired":true,"paymentBypassAllowed":false,
                 "newPrice":20,"currency":"USD"}
                """
            )
        )
    }

    @Test func withNoHostHandlerTheBuiltInSheetIsWhatTheCardComesFrom() async throws {
        let backend = TestBackend()
        stubPaidPreview(backend)
        let model = makeModel(backend)

        model.selectTier(try planSelection())
        await waitUntil { model.step == .confirm }
        model.confirm(immediate: true)
        await waitUntil { model.step == .collectingPayment }

        let request: WildwoodPaymentRequiredArgs? = model.paymentRequest
        #expect(request != nil)
        #expect(request?.pricingModelId == "pm-1")
        // The PLAN's price, never the prorated charge a preview quoted for today.
        #expect(request?.price == 20)
        #expect(
            ManageViewRules.planChangeCardSource(
                step: model.step,
                hasHostHandler: false,
                paymentRequest: request,
                collectsPaymentInApp: true
            ) == .builtIn
        )
        // Nothing has been posted yet: the card comes first.
        #expect(requestCount(backend, path: changePath) == 0)
    }

    @Test func closingTheBuiltInSheetGoesBackToTheConfirmationWithThePricedChangeIntact() async throws {
        let backend = TestBackend()
        stubPaidPreview(backend)
        let model = makeModel(backend)

        model.selectTier(try planSelection())
        await waitUntil { model.step == .confirm }
        model.confirm(immediate: true)
        await waitUntil { model.step == .collectingPayment }

        // What the sheet's dismissal does — the opposite of a host handler answering nothing,
        // which abandons the whole change (`PlanChangeModelTests`).
        model.providePayment(nil)
        await waitUntil { model.step == .confirm }

        #expect(model.step == .confirm)
        #expect(model.preview != nil)
        #expect(requestCount(backend, path: changePath) == 0)
    }

    @Test func aPaidSheetPostsTheChangeWithTheTransactionId() async throws {
        let backend = TestBackend()
        stubPaidPreview(backend)
        backend.stub("POST", changePath, TestStubResponse(json: #"{"success":true,"errorMessage":""}"#))
        let model = makeModel(backend)

        model.selectTier(try planSelection())
        await waitUntil { model.step == .confirm }
        model.confirm(immediate: true)
        await waitUntil { model.step == .collectingPayment }
        model.providePayment("txn-9")
        await waitUntil { model.step == .done || model.step == .failed }

        #expect(model.step == .done)
        let sent = bodies(backend, path: changePath).first ?? ""
        #expect(sent.contains("txn-9"))
        // No handler, so the server is never told this device can answer a challenge.
        #expect(!sent.contains("SupportsPaymentAction"))
    }
}
