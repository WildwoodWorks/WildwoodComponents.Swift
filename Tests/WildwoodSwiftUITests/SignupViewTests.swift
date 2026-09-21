// The signup view's own decisions: which body renders, what the panels say, what the payment step
// is handed, and the two rules a store-billed device adds.
//
// Ported case for case from
// packages/wildwood-react-native/src/__tests__/signupView.test.ts, minus the cases that only make
// sense for a JSX renderer (the source greps) and the two bodies React Native needs because its
// store purchase is a separate sheet — this package's `PaymentComponent` drives StoreKit itself.
//
// The ORDER of the signup is the shared ``SignupMachine``, so the behavioural half drives that
// machine (or the driver over it) rather than restating the table here. The view's own half lives
// in ``SignupViewRules`` and is called as functions, because this package cannot render a view on
// a machine with no simulator.
//
// Every price assertion goes through ``WildwoodMoney/format(_:currency:)`` against a figure the
// fixture carries, never against a string typed into this file.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

// MARK: - Fixtures

private let proMonthlyPrice: Double = 79

private func pricingOption(
    id: String,
    price: Double,
    billingFrequency: String,
    pricingModelId: String,
    trialDays: Int? = nil
) throws -> AppTierPricingModel {
    var value = try WildwoodJSON.decoder().decode(AppTierPricingModel.self, from: Data("{}".utf8))
    value.id = id
    value.price = price
    value.billingFrequency = billingFrequency
    value.pricingModelId = pricingModelId
    value.isDefault = true
    value.trialDays = trialDays
    return value
}

private func planTier(
    id: String,
    name: String,
    isFreeTier: Bool = false,
    pricingOptions: [AppTierPricingModel] = []
) throws -> AppTierModel {
    var value = try WildwoodJSON.decoder().decode(AppTierModel.self, from: Data("{}".utf8))
    value.id = id
    value.appId = "app-1"
    value.name = name
    value.status = "Active"
    value.isFreeTier = isFreeTier
    value.currency = "USD"
    value.pricingOptions = pricingOptions
    return value
}

/// A catalog that sells one free plan and one paid one, for the plan-grid highlight rules.
private func planCatalog() throws -> PublicCatalog {
    let free: AppTierModel = try planTier(id: "tier-free", name: "Starter", isFreeTier: true)
    let pro: AppTierModel = try planTier(id: "tier-pro", name: "Pro")
    return PublicCatalog(appId: "app-1", currency: "USD", tiers: [free, pro])
}

private let labels: RegistrationSubscriptionSignupLabels = .defaults

/// Every body the view can render, so the rules below are answered for all of them.
private let allBodies: [SignupBody] = SignupBody.allCases

@MainActor
struct SignupViewTests {
    // MARK: - Which body renders

    @Test func everyStepRendersUnderItsOwnNameWithDoneSpelledSuccess() {
        for step in SignupStep.allCases {
            let resolved: SignupBody = SignupViewRules.body(
                SignupBodyInput(step: step, hasPlan: true, formSubmitted: true)
            )
            if step == .done {
                #expect(resolved == .success)
            } else {
                #expect(resolved.rawValue == step.rawValue)
            }
        }
    }

    @Test func aSignedInVisitorIsOfferedANoticeRatherThanASecondAccount() {
        for step in SignupStep.allCases {
            let resolved: SignupBody = SignupViewRules.body(
                SignupBodyInput(step: step, alreadySignedIn: true, hasPlan: true, formSubmitted: true)
            )
            #expect(resolved == .signedIn)
        }
        // And the web hangs no step off that notice, so neither does this.
        #expect(SignupViewRules.stepIdentifier(.signedIn) == nil)
    }

    @Test func aCardFormIsNeverShownWithNothingToChargeFor() {
        // No plan left in the catalog, or a form that was never submitted: a card taken there
        // would be a charge with nothing to attach it to.
        #expect(
            SignupViewRules.body(SignupBodyInput(step: .payment, hasPlan: false, formSubmitted: true))
                == .loading
        )
        #expect(
            SignupViewRules.body(SignupBodyInput(step: .payment, hasPlan: true, formSubmitted: false))
                == .loading
        )
        #expect(
            SignupViewRules.body(SignupBodyInput(step: .payment, hasPlan: true, formSubmitted: true))
                == .payment
        )
    }

    @Test func theIdentifierStringsAreTheWebValues() {
        #expect(RegistrationSubscriptionTestID.view(.signup) == "signup")
        for body in allBodies where body != .signedIn {
            #expect(
                RegistrationSubscriptionTestID.view(
                    .signup,
                    step: SignupViewRules.stepIdentifier(body)
                ) == body.rawValue
            )
        }
        // The one body with no step falls back to the view's own name.
        #expect(
            RegistrationSubscriptionTestID.view(
                .signup,
                step: SignupViewRules.stepIdentifier(.signedIn)
            ) == "signup"
        )
        // The machine's `done` is `success` on the wire of a test plan, in every stack.
        #expect(SignupBody.success.rawValue == "success")
        #expect(SignupBody.packCheckout.rawValue == "packCheckout")
    }

    // MARK: - What the token granted, shown beside the step

    @Test func whatTheTokenGrantedShowsBesideEveryBodyTheWebShowsItBeside() {
        let grant = RegistrationTokenAppGrant(appId: "app-1", appTierId: "tier-team", appTierName: "Team")

        // The web renders its token summary in the outer frame, above whichever step is on screen,
        // and leaves it out of exactly one place: the signed-in early return. A signup on a token
        // that also has disclaimers to accept therefore still sees what the token paid for while
        // accepting them — the defect the sibling port had to fix.
        for body in allBodies {
            #expect(
                SignupViewRules.showsTokenPlanSummary(body: body, grant: grant) == (body != .signedIn)
            )
        }
        #expect(SignupViewRules.showsTokenPlanSummary(body: .disclaimers, grant: grant))
    }

    @Test func nothingIsShownWhenNoTokenGrantedAnything() {
        for body in allBodies {
            #expect(!SignupViewRules.showsTokenPlanSummary(body: body, grant: nil))
        }
    }

    @Test func aGrantIsNamedTheWayTheServerNamedItAndNeverPriced() {
        let grant = RegistrationTokenAppGrant(
            appId: "app-1",
            appTierId: "tier-team",
            appTierName: "Team",
            pricingName: "Annual",
            addOnIds: ["pack-docs", "pack-ai"],
            addOnNames: ["Docs Pack"],
            featureCodes: ["DOCUMENTS"],
            featureNames: nil
        )

        #expect(SignupViewRules.grantTierText(grant) == "Team (Annual)")

        let packs: [SignupGrantEntry] = SignupViewRules.grantEntries(
            ids: grant.addOnIds,
            names: grant.addOnNames
        )
        // Names by index, ids as the fallback — and the row identity carries the position, so a
        // grant that repeated an id could not hand a list two rows with one identity.
        #expect(packs.map(\.name) == ["Docs Pack", "pack-ai"])
        #expect(packs.map(\.id) == ["0:pack-docs", "1:pack-ai"])

        let features: [SignupGrantEntry] = SignupViewRules.grantEntries(
            ids: grant.featureCodes,
            names: grant.featureNames
        )
        #expect(features.map(\.name) == ["DOCUMENTS"])
    }

    @Test func aGrantWithNoTierNameFallsBackToItsId() {
        let grant = RegistrationTokenAppGrant(appId: "app-1", appTierId: "tier-team")
        #expect(SignupViewRules.grantTierText(grant) == "tier-team")
    }

    // MARK: - Packs a link carried in

    @Test func aLinksPacksAreDedupedAndStopAtThePlatformCap() {
        var many: [String] = []
        for index in 0 ..< (Catalog.maxAddOnSelection + 5) { many.append("pack-\(index)") }

        #expect(SignupViewRules.cappedPreSelectedPackIds(many).count == Catalog.maxAddOnSelection)
        #expect(SignupViewRules.cappedPreSelectedPackIds(["a", "a", "b"]) == ["a", "b"])
        #expect(SignupViewRules.cappedPreSelectedPackIds(nil).isEmpty)
        #expect(SignupViewRules.cappedPreSelectedPackIds([]).isEmpty)
    }

    @Test func aLinksPacksAreStillBoughtWhenThePackStepIsTurnedOff() throws {
        // `packSelection: .none` removes the step where packs are picked. It does not un-choose
        // the packs a signup link already chose — those are still bought after login.
        var state: SignupState = SignupMachine.initialState(
            SignupMachineOptions(
                planSelection: .skip,
                packSelection: SignupPackSelection.none,
                paymentOrder: .afterAccount,
                selection: SignupSelection(addOnIds: ["pack-docs"])
            )
        )
        let issuer = StepTokenIssuer()
        state = SignupMachine.transition(state, .initialize(signedIn: false), issuer: issuer).state
        state = SignupMachine.transition(
            state,
            .modeLoaded(mode: SignupRegistrationMode.resolve(SignupRegistrationSettings(allowOpenRegistration: true))),
            issuer: issuer
        ).state
        state = SignupMachine.transition(state, .catalogLoaded(names: nil), issuer: issuer).state
        #expect(state.step == .register)

        state = SignupMachine.transition(state, .registerSubmitted(email: "a@b.test"), issuer: issuer).state
        let creatingToken: StepToken = try #require(state.token)
        state = SignupMachine.transition(
            state,
            .accountCreated(token: creatingToken, userId: "user-1", requiresDisclaimers: false),
            issuer: issuer
        ).state

        #expect(state.step == .packCheckout)
        #expect(state.packsToBuy == ["pack-docs"])
    }

    // MARK: - Deep links

    @Test func aSignupLinkIsAppliedOnlyWhileTheFormIsStillAhead() {
        #expect(SignupViewRules.acceptsSignupLink(formSubmitted: false))
        // Past the form the visitor has committed to a plan and possibly to a card; rewriting the
        // selection underneath them would change what they agreed to buy.
        #expect(!SignupViewRules.acceptsSignupLink(formSubmitted: true))
    }

    @Test func aUrlCarryingNothingThisScreenActsOnChangesNothing() throws {
        let bare = try #require(URL(string: "myapp://signup"))
        #expect(!SignupViewRules.signupLinkCarriesSelection(SignupParams.parse(url: bare)))

        let carried = try #require(URL(string: "myapp://signup?tier=tier-pro&addons=pack-docs&email=a@b.test"))
        let params: SignupParams = SignupParams.parse(url: carried)
        #expect(SignupViewRules.signupLinkCarriesSelection(params))

        // And what it carried reaches the flow's options, which is what the view rebuilds on.
        let options = WildwoodSignupFlowOptions().applying(params)
        #expect(options.preSelectedTierId == "tier-pro")
        #expect(options.preSelectedAddOnIds == ["pack-docs"])
        #expect(options.prefillEmail == "a@b.test")
    }

    @Test func anInviteLinkMakesTheTokenTheOnlyWayIn() throws {
        let invite = try #require(URL(string: "myapp://signup?invite=inv-1"))
        let options = WildwoodSignupFlowOptions().applying(SignupParams.parse(url: invite))
        #expect(options.tokenMode == .required)
        #expect(options.registrationToken == "inv-1")

        // Invite redemption overrides a CLOSED configuration: the server validates the invitation
        // itself, and an app that turned open registration off still honours its own invitations.
        let closed = SignupRegistrationSettings(allowOpenRegistration: false, allowTokenRegistration: false)
        #expect(SignupRegistrationMode.resolve(closed).closed)
        let mode = SignupRegistrationMode.resolve(closed, tokenMode: .required)
        #expect(!mode.closed)
        #expect(mode.requireToken)
    }

    // MARK: - The plan the grid opens on

    @Test func planDefaultFreeOpensTheGridOnTheFreePlanWithoutChoosingItForThem() throws {
        let catalog: PublicCatalog = try planCatalog()
        let suggested: String? = SignupViewRules.defaultTierId(
            planDefault: SignupPlanDefault.free,
            isInvite: false,
            catalog: catalog
        )
        #expect(suggested == "tier-free")
        // A suggestion is not a choice: all it does is mark a card the visitor still taps.
        #expect(
            SignupViewRules.highlightTierId(
                selectionTierId: nil,
                defaultTierId: suggested,
                preSelectedTierId: nil
            ) == "tier-free"
        )
    }

    @Test func nothingIsMarkedWhenTheHostNamesNoDefault() throws {
        let catalog: PublicCatalog = try planCatalog()
        #expect(
            SignupViewRules.defaultTierId(
                planDefault: SignupPlanDefault.none,
                isInvite: false,
                catalog: catalog
            ) == nil
        )
        #expect(
            SignupViewRules.highlightTierId(
                selectionTierId: nil,
                defaultTierId: nil,
                preSelectedTierId: nil
            ) == nil
        )
    }

    @Test func nothingIsSuggestedWhileAnInviteIsBeingRedeemed() throws {
        // The invite's plan comes from its token, so the grid never appears for a default to open
        // on — and nothing is suggested even if it did.
        let catalog: PublicCatalog = try planCatalog()
        #expect(
            SignupViewRules.defaultTierId(
                planDefault: SignupPlanDefault.free,
                isInvite: true,
                catalog: catalog
            ) == nil
        )
    }

    @Test func theVisitorsOwnChoiceBeatsTheDefaultAndTheLink() {
        #expect(
            SignupViewRules.highlightTierId(
                selectionTierId: "tier-team",
                defaultTierId: "tier-free",
                preSelectedTierId: "tier-pro"
            ) == "tier-team"
        )
    }

    @Test func aLinksPlanLosesToTheDefaultAndMarksTheGridWhenThereIsNoDefault() {
        // The default sits AHEAD of the link on purpose: a stale or hand-edited `?tier=` is an id
        // the flow already refused, so the grid opens on the host's default rather than on nothing.
        #expect(
            SignupViewRules.highlightTierId(
                selectionTierId: nil,
                defaultTierId: "tier-free",
                preSelectedTierId: "tier-gone"
            ) == "tier-free"
        )
        #expect(
            SignupViewRules.highlightTierId(
                selectionTierId: nil,
                defaultTierId: nil,
                preSelectedTierId: "tier-pro"
            ) == "tier-pro"
        )
    }

    @Test func nothingIsSuggestedWhenTheAppSellsNoFreePlan() throws {
        // Nothing to suggest is not a failure: the grid is the one it would have been anyway.
        let pro: AppTierModel = try planTier(id: "tier-pro", name: "Pro")
        let paidOnly = PublicCatalog(appId: "app-1", currency: "USD", tiers: [pro])
        #expect(
            SignupViewRules.defaultTierId(
                planDefault: SignupPlanDefault.free,
                isInvite: false,
                catalog: paidOnly
            ) == nil
        )
        // And a catalog that has not loaded yet suggests nothing either.
        #expect(
            SignupViewRules.defaultTierId(
                planDefault: SignupPlanDefault.free,
                isInvite: false,
                catalog: nil
            ) == nil
        )
    }

    // MARK: - What the payment step is handed

    @Test func thePaymentStepChargesThePlansOwnPriceOnItsOwnPricingModel() throws {
        let pricing = try pricingOption(
            id: "price-pro-monthly",
            price: proMonthlyPrice,
            billingFrequency: "Monthly",
            pricingModelId: "pm-pro",
            trialDays: 14
        )
        let tier = try planTier(id: "tier-pro", name: "Pro", pricingOptions: [pricing])

        let payment: SignupPaymentProps = SignupViewRules.paymentProps(
            tier: tier,
            pricing: pricing,
            currency: "USD",
            trialDays: 14
        )

        #expect(payment.amount == proMonthlyPrice)
        #expect(payment.currency == "USD")
        #expect(payment.description == "Pro")
        #expect(payment.pricingModelId == "pm-pro")
        #expect(payment.isSubscription)
        #expect(payment.trialDays == 14)
        #expect(payment.billingFrequency == "Monthly")
        // The figure on screen is the same one, formatted — never a second opinion.
        #expect(
            SignupViewRules.planPriceText(tier: tier, pricing: pricing, currency: "USD", labels: labels)
                == WildwoodMoney.format(proMonthlyPrice, currency: "USD") + "/monthly"
        )
    }

    @Test func noTrialIsOfferedWhenThereIsNoneRatherThanAZeroDayOne() throws {
        let pricing = try pricingOption(
            id: "price-pro-monthly",
            price: proMonthlyPrice,
            billingFrequency: "Monthly",
            pricingModelId: "pm-pro"
        )
        let tier = try planTier(id: "tier-pro", name: "Pro", pricingOptions: [pricing])
        #expect(SignupViewRules.paymentProps(tier: tier, pricing: pricing, currency: "USD", trialDays: 0).trialDays == nil)
        #expect(SignupViewRules.planTrialLine(trialDays: 0, currency: "USD", labels: labels).isEmpty)
    }

    @Test func nothingIsInventedForAPlanWithNoPricingOption() throws {
        let paid = try planTier(id: "tier-pro", name: "Pro")
        let free = try planTier(id: "tier-free", name: "Starter", isFreeTier: true)

        let payment: SignupPaymentProps = SignupViewRules.paymentProps(
            tier: paid,
            pricing: nil,
            currency: "USD",
            trialDays: 0
        )
        #expect(payment.amount == 0)
        #expect(payment.pricingModelId == nil)

        // A free plan says so; anything else says nothing rather than implying it is free.
        #expect(SignupViewRules.planPriceText(tier: free, pricing: nil, currency: "USD", labels: labels) == labels.planFree)
        #expect(SignupViewRules.planPriceText(tier: paid, pricing: nil, currency: "USD", labels: labels).isEmpty)
    }

    @Test func thePeriodIsTheOneTheServerNamedAndNothingWhenItNamedNone() {
        #expect(SignupViewRules.planPeriodSuffix("Monthly") == "/monthly")
        #expect(SignupViewRules.planPeriodSuffix(nil).isEmpty)
        #expect(SignupViewRules.planPeriodSuffix("  ").isEmpty)
    }

    @Test func aTrialSaysNothingIsChargedToday() {
        let line: String = SignupViewRules.planTrialLine(trialDays: 14, currency: "USD", labels: labels)
        #expect(line.hasPrefix(WildwoodTrial.label(days: 14)))
        #expect(line.contains(labels.dueToday))
        #expect(line.contains(WildwoodMoney.format(0, currency: "USD")))
    }

    @Test func theFormSaysWhatHappensNext() {
        // Byte for byte the web's two submit texts.
        #expect(SignupViewRules.submitTitle(planStepAhead: true, labels: labels) == labels.continueLabel)
        #expect(SignupViewRules.submitTitle(planStepAhead: false, labels: labels) == "Create Account")
        #expect(SignupViewRules.createAccountSubmitText == "Create Account")
    }

    // MARK: - What the success panel says

    @Test func theSuccessPanelSaysWhatActuallyHappened() {
        let base = SignupSuccessInput(labels: labels, hasPlan: true)

        // No plan at all.
        #expect(
            SignupViewRules.successMessage(
                SignupSuccessInput(labels: labels, hasPlan: false)
            ) == labels.signupCompletePlain
        )
        // The server refused the subscription.
        #expect(
            SignupViewRules.successMessage(
                SignupSuccessInput(labels: labels, hasPlan: true, subscriptionFailed: true)
            ) == labels.signupCompletePending
        )
        // The account-first card was walked away from: an account and no plan, said plainly.
        #expect(
            SignupViewRules.successMessage(
                SignupSuccessInput(labels: labels, hasPlan: true, planActivationPending: true)
            ) == labels.signupCompletePending
        )
        // A trial counts the days the plan actually carries.
        #expect(
            SignupViewRules.successMessage(
                SignupSuccessInput(labels: labels, hasPlan: true, trialDays: 14)
            ).contains("14")
        )
        // Otherwise the plan is simply running.
        #expect(SignupViewRules.successMessage(base) == labels.signupCompleteActive)
    }

    @Test func aTokenSignupSaysWhichPlanTheTokenSetUp() {
        #expect(
            SignupViewRules.successMessage(
                SignupSuccessInput(
                    labels: labels,
                    tokenPlanName: "Team",
                    hasTokenGrant: true,
                    hasPlan: true
                )
            ).contains("Team")
        )
        // A token that named no plan still granted one; "plan" is what the web calls it then.
        #expect(
            SignupViewRules.successMessage(
                SignupSuccessInput(labels: labels, tokenPlanName: nil, hasTokenGrant: true, hasPlan: true)
            ) == labels.signupCompleteToken.replacingOccurrences(of: "{tier}", with: "plan")
        )
    }

    // MARK: - Outcome ordering

    @Test func theGrantedPacksAreReportedFirstUnpricedBesideTheOnesThatWereBought() throws {
        let issuer = StepTokenIssuer()
        var names = SignupCatalogNames()
        names.tiers = ["tier-team": "Team"]
        names.addOns = ["pack-docs": "Docs Pack", "pack-ai": "AI Pack"]

        var state: SignupState = SignupMachine.initialState(
            SignupMachineOptions(
                packSelection: SignupPackSelection.none,
                paymentOrder: .afterAccount,
                selection: SignupSelection(addOnIds: ["pack-docs", "pack-ai"])
            )
        )
        state = SignupMachine.transition(state, .initialize(signedIn: false), issuer: issuer).state
        state = SignupMachine.transition(
            state,
            .modeLoaded(
                mode: SignupRegistrationMode.resolve(
                    SignupRegistrationSettings(allowOpenRegistration: true, allowTokenRegistration: true)
                )
            ),
            issuer: issuer
        ).state
        state = SignupMachine.transition(state, .catalogLoaded(names: names), issuer: issuer).state
        state = SignupMachine.transition(state, .registerSubmitted(email: "a@b.test"), issuer: issuer).state
        #expect(state.step == .token)

        state = SignupMachine.transition(state, .tokenCheckStarted, issuer: issuer).state
        let checkToken: StepToken = try #require(state.token)
        state = SignupMachine.transition(
            state,
            .tokenAccepted(
                token: checkToken,
                value: "tok-1",
                grant: SignupTokenGrant(
                    tierId: "tier-team",
                    pricingId: "price-team",
                    addOnIds: ["pack-docs"],
                    featureCodes: ["DOCUMENTS"]
                )
            ),
            issuer: issuer
        ).state

        // A grant skips the plan and the card, and the pack it covers is not bought again.
        #expect(state.step == .creating)
        #expect(state.packsToBuy == ["pack-ai"])

        let creatingToken: StepToken = try #require(state.token)
        state = SignupMachine.transition(
            state,
            .accountCreated(token: creatingToken, userId: "user-1", requiresDisclaimers: false),
            issuer: issuer
        ).state
        #expect(state.step == .packCheckout)

        let checkoutToken: StepToken = try #require(state.token)
        state = SignupMachine.transition(
            state,
            .packCheckoutFinished(
                token: checkoutToken,
                packs: [
                    SignupPackOutcome(addOnId: "pack-ai", name: "AI Pack", status: SignupPackStatuses.active)
                ]
            ),
            issuer: issuer
        ).state

        #expect(state.step == .done)
        let packs: [SignupPackOutcome] = state.outcome?.packs ?? []
        #expect(packs.count == 2)
        #expect(packs.first?.addOnId == "pack-docs")
        #expect(packs.first?.status == SignupPackStatuses.granted)
        #expect(packs.first?.name == "Docs Pack")
        #expect(packs.last?.addOnId == "pack-ai")
        #expect(packs.last?.status == SignupPackStatuses.active)
        #expect(state.outcome?.tier == SignupOutcomeTier(tierId: "tier-team", name: "Team", pricingId: "price-team"))
    }

    @Test func anOutcomeRowSaysWhatBecameOfItsPack() {
        #expect(SignupViewRules.packStatusLabel(SignupPackStatuses.trialing, labels: labels) == labels.packStatusTrialing)
        #expect(SignupViewRules.packStatusLabel(SignupPackStatuses.active, labels: labels) == labels.packStatusActive)
        #expect(SignupViewRules.packStatusLabel(SignupPackStatuses.granted, labels: labels) == labels.packStatusGranted)
        #expect(SignupViewRules.packStatusLabel(SignupPackStatuses.failed, labels: labels) == labels.packStatusFailed)
        // Anything the server invents is read as a failure rather than shown raw.
        #expect(SignupViewRules.packStatusLabel("something-new", labels: labels) == labels.packStatusFailed)

        #expect(!SignupViewRules.packOutcomeFailed(SignupPackStatuses.granted))
        #expect(SignupViewRules.packOutcomeFailed(SignupPackStatuses.failed))
        #expect(SignupViewRules.trialEndText(nil).isEmpty)
        #expect(!SignupViewRules.trialEndText(Date(timeIntervalSince1970: 1_700_000_000)).isEmpty)
    }

    // MARK: - Buying packs with no payment SDK

    @Test func thePackCheckoutUsesTheCardOnFileWhenTheQuoteSaysThereIsOne() {
        #expect(
            SignupViewRules.packCheckoutCardBranch(requiresPaymentMethod: false, canConfirmCardSetup: false)
                == .savedCard
        )
        #expect(
            SignupViewRules.packCheckoutCardBranch(requiresPaymentMethod: false, canConfirmCardSetup: true)
                == .savedCard
        )
        #expect(
            SignupViewRules.packCheckoutCardBranch(requiresPaymentMethod: true, canConfirmCardSetup: true)
                == .handlerCard
        )
        // Nothing on the device can confirm a card, so none is asked for.
        #expect(
            SignupViewRules.packCheckoutCardBranch(requiresPaymentMethod: true, canConfirmCardSetup: false)
                == .finishOnWeb
        )
    }

    @Test func aBasketThatCannotTakeACardIsOfferedNoTryAgain() {
        #expect(!SignupViewRules.packCheckoutCanRetry(.finishOnWeb))
        #expect(SignupViewRules.packCheckoutCanRetry(.handlerCard))
        #expect(SignupViewRules.packCheckoutCanRetry(.savedCard))
    }

    @Test func theStatusLineNamesThePackTheBankIsBeingAskedAbout() {
        #expect(
            SignupViewRules.packCheckoutStatusText(step: .checkingOut, packName: "Docs Pack", labels: labels)
                == labels.buyingPacks
        )
        #expect(
            SignupViewRules.packCheckoutStatusText(step: .authenticating, packName: "Docs Pack", labels: labels)
                .contains("Docs Pack")
        )
        #expect(
            SignupViewRules.packCheckoutStatusText(step: .completing, packName: "Docs Pack", labels: labels)
                .contains("Docs Pack")
        )
        // Quoting and collecting a card are "setting up", not a bank challenge.
        #expect(
            SignupViewRules.packCheckoutStatusText(step: .quoting, packName: "", labels: labels)
                == labels.buyingPacks
        )
    }

    @Test func theStatusLineShowsWhileThereIsSomethingToSayAndNotAfterwards() {
        #expect(SignupViewRules.packCheckoutWorking(step: .idle, busy: false))
        #expect(SignupViewRules.packCheckoutWorking(step: .quoting, busy: false))
        #expect(SignupViewRules.packCheckoutWorking(step: .collectingCard, busy: false))
        #expect(SignupViewRules.packCheckoutWorking(step: .checkingOut, busy: true))
        #expect(!SignupViewRules.packCheckoutWorking(step: .failed, busy: false))
        #expect(!SignupViewRules.packCheckoutWorking(step: .done, busy: false))
    }

    @Test func theSavedCardIsNamedTheWayTheQuoteNamedIt() {
        #expect(SignupViewRules.savedCardLine(nil, labels: labels) == nil)
        let line: String? = SignupViewRules.savedCardLine(
            AddOnCheckoutSavedCardModel(brand: "Visa", last4: "4242"),
            labels: labels
        )
        #expect(line == "Visa ending in 4242")
    }

    // MARK: - A store-billed device

    @Test func aStoreBilledDeviceDoesNotOfferToSellPacks() {
        // No store product stands behind an add-on, so the purchase is not offered.
        #expect(!SignupViewRules.packPurchaseOffered(packPurchaseAvailable: true, storeOnly: true))
        #expect(SignupViewRules.packPurchaseOffered(packPurchaseAvailable: true, storeOnly: false))
        // The host's own say is the other half.
        #expect(!SignupViewRules.packPurchaseOffered(packPurchaseAvailable: false, storeOnly: false))
    }

    @Test func thePacksItCannotBuyAreReportedRatherThanQuietlyForgotten() {
        let outcomes: [SignupPackOutcome] = SignupViewRules.unbuyablePackOutcomes(
            items: [AddOnCheckoutItemInput(addOnId: "pack-docs"), AddOnCheckoutItemInput(addOnId: "pack-unknown")],
            names: ["pack-docs": "Docs Pack"],
            message: labels.finishOnWeb
        )

        #expect(outcomes.count == 2)
        #expect(outcomes[0].name == "Docs Pack")
        #expect(outcomes[0].status == SignupPackStatuses.failed)
        #expect(outcomes[0].errorMessage == labels.finishOnWeb)
        // A pack the catalog never named is still named — by its id, never dropped.
        #expect(outcomes[1].name == "pack-unknown")
        #expect(outcomes[1].errorMessage == labels.finishOnWeb)

        // The id-only form the driver uses answers the same.
        let byId: [SignupPackOutcome] = SignupViewRules.unbuyablePackOutcomes(
            addOnIds: ["pack-docs"],
            names: ["pack-docs": "Docs Pack"],
            message: labels.finishOnWeb
        )
        #expect(byId == [outcomes[0]])
    }

    // MARK: - The copy

    @Test func theDefaultCopyIsTheSameWordsTheOtherStacksSay() {
        #expect(labels.loadingSignup == "Getting things ready...")
        #expect(labels.registrationClosed == "Registration is closed")
        #expect(labels.alreadySignedIn == "You are already signed in")
        #expect(labels.checkingToken == "Checking your registration token...")
        #expect(labels.tokenPlanIncludes == "Your registration token includes")
        #expect(labels.orderSummary == "Order Summary")
        #expect(labels.dueToday == "Due today")
        #expect(labels.savedCardOnFile == "{brand} ending in {last4}")
        #expect(labels.buyingPacks == "Setting up your packs...")
        #expect(labels.authenticatingPack == "Confirming {name} with your bank...")
        #expect(labels.packStatusGranted == "Included")
        #expect(labels.disclaimersTitle == "One more step")
        #expect(labels.processingWait == "Please wait while we set up your account.")
        #expect(labels.signupFailed == "Something Went Wrong")
        #expect(labels.signupCompleteTitle == "You're All Set!")
        #expect(labels.getStarted == "Get Started")
        #expect(labels.finishOnWeb == "This purchase has to be finished on the web.")
        #expect(
            labels.signupCompletePending
                == "Your account is ready! Plan activation is pending - you can select a plan from your dashboard."
        )
    }

    @Test func theHostsOwnWordsReachTheDriversMessagesToo() {
        let overridden = RegistrationSubscriptionSignupLabels(
            packsUnavailable: "No packs for you.",
            statusCreatingAccount: "Making your account.",
            finishOnWeb: "Finish it on the site."
        )
        let driver: RegistrationSubscriptionDriverLabels = overridden.driverLabels

        #expect(driver.finishOnWeb == "Finish it on the site.")
        #expect(driver.packsUnavailable == "No packs for you.")
        #expect(driver.statusCreatingAccount == "Making your account.")
        // Anything this host did not override keeps the shipped wording — the slices are one type
        // now, so the whole set travels and only what was named changes.
        #expect(driver.planChangeExpired == RegistrationSubscriptionDriverLabels.defaults.planChangeExpired)
    }
}

// MARK: - The driver, told it cannot buy packs

@MainActor
struct SignupViewStoreOnlyTests {
    private static let appId = "app-1"

    private var authConfigPath: String { "/api/AppComponentConfigurations/\(Self.appId)/auth-configuration" }
    private var publicTiersPath: String { "/api/app-tiers/\(Self.appId)/public" }
    private var publicAddOnsPath: String { "/api/app-tier-addons/\(Self.appId)/public" }
    private var registerPath: String { "/api/userregistration/register" }
    private var loginPath: String { "/api/auth/login" }
    private var subscribePath: String { "/api/app-tiers/\(Self.appId)/my-subscription" }
    private var quotePath: String { "/api/app-tier-addons/\(Self.appId)/checkout/quote" }

    /// A free default plan (so no card step stands in the way) and one pack the app sells.
    private func stubCatalog(_ backend: TestBackend) {
        backend.stub(
            "GET",
            publicTiersPath,
            TestStubResponse(
                json: """
                [{"id":"tier-free","appId":"\(Self.appId)","name":"Starter","status":"Active","displayOrder":1,
                  "isFreeTier":true,"isDefault":true,"currency":"USD","pricingOptions":[]}]
                """
            )
        )
        backend.stub(
            "GET",
            publicAddOnsPath,
            TestStubResponse(
                json: """
                [{"id":"pack-docs","appId":"\(Self.appId)","name":"Docs Pack","status":"Active","displayOrder":1,
                  "currency":"USD","pricingOptions":[{"id":"ap-1","appTierAddOnId":"pack-docs","price":9,
                    "billingFrequency":"Monthly","pricingModelId":"pm-docs","isDefault":true}]}]
                """
            )
        )
    }

    private func stubRegistration(_ backend: TestBackend) {
        backend.stub(
            "GET",
            authConfigPath,
            TestStubResponse(json: #"{"allowOpenRegistration":true,"allowTokenRegistration":false}"#)
        )
        backend.stub(
            "POST",
            registerPath,
            TestStubResponse(json: #"{"success":true,"message":"ok","userId":"user-1"}"#)
        )
        backend.stub(
            "POST",
            loginPath,
            TestStubResponse(
                json: """
                {"id":"user-1","userId":"user-1","email":"a@b.test","jwtToken":"jwt-1",
                 "requiresDisclaimerAcceptance":false}
                """
            )
        )
        // The app's default plan is free, but the flow still starts it; stubbed so the run is
        // about the packs rather than about an unstubbed subscribe.
        backend.stub("POST", subscribePath, TestStubResponse(json: #"{"success":true}"#))
    }

    private func form() -> RegistrationFormData {
        RegistrationFormData(
            firstName: "Ada",
            lastName: "Lovelace",
            username: "ada",
            email: "a@b.test",
            password: "Sekrit!1"
        )
    }

    @Test func aStoreBilledSignupReportsThePacksItCannotBuyAndNeverQuotesThem() async {
        let backend = TestBackend()
        stubCatalog(backend)
        stubRegistration(backend)

        let model = WildwoodSignupFlowModel(
            client: makeTestClient(backend, appId: Self.appId),
            options: WildwoodSignupFlowOptions(
                preSelectedAddOnIds: ["pack-docs"],
                planSelection: .skip
            ),
            paymentActionHandler: nil,
            issuer: StepTokenIssuer()
        )
        // What the view does once the app's platform-filtered providers answer.
        model.setPackPurchaseAvailable(false)

        model.start()
        await waitUntil { model.step == .register || model.step == .failed }
        #expect(model.step == .register)

        model.submitForm(form())
        await waitUntil { model.step == .done || model.step == .failed }

        #expect(model.step == .done)
        // The basket is never priced: a quote nothing can pay for is a call worth not making.
        #expect(requestCount(backend, path: quotePath) == 0)

        let packs: [SignupPackOutcome] = model.outcome?.packs ?? []
        #expect(packs.count == 1)
        #expect(packs.first?.addOnId == "pack-docs")
        #expect(packs.first?.name == "Docs Pack")
        #expect(packs.first?.status == SignupPackStatuses.failed)
        #expect(packs.first?.errorMessage == RegistrationSubscriptionSignupLabels.defaults.finishOnWeb)
    }

    @Test func aStoreBilledSignupSkipsThePackStepRatherThanOfferingAGridThatGoesNowhere() async {
        let backend = TestBackend()
        stubCatalog(backend)
        stubRegistration(backend)

        let model = WildwoodSignupFlowModel(
            client: makeTestClient(backend, appId: Self.appId),
            options: WildwoodSignupFlowOptions(
                planSelection: .skip,
                packSelection: .choose
            ),
            paymentActionHandler: nil,
            issuer: StepTokenIssuer()
        )
        model.setPackPurchaseAvailable(false)

        model.start()
        await waitUntil { model.step == .register || model.step == .failed }
        model.submitForm(form())
        await waitUntil { model.step == .done || model.step == .failed }

        // Straight past the pack step and on to the account: there was nothing to choose.
        #expect(model.step == .done)
        #expect(requestCount(backend, path: registerPath) == 1)
    }
}

#if os(iOS)
// MARK: - The shell's configuration carries what the view takes
//
// Guarded because the views and their configuration structs live inside `#if os(iOS)` while
// `swift test` runs on the macOS host: this case is built when the tests are run against an iOS
// destination. It is worth having anyway — a line forgotten in `init(configuration:)` drops the
// host's setting SILENTLY: nothing fails, the signup simply ignores what it was told.

@MainActor
struct RegistrationSubscriptionSignupConfigurationTests {
    /// Reflection rather than a property read: the view's parameters are `private let`, which is
    /// exactly what the rest of the package cannot see either.
    private func storedPlanDefault(_ view: RegistrationSubscriptionSignupView) -> SignupPlanDefault? {
        for child in Mirror(reflecting: view).children where child.label == "planDefault" {
            return child.value as? SignupPlanDefault
        }
        return nil
    }

    @Test func theConfigurationForwardsPlanDefaultToTheView() {
        let chosen = RegistrationSubscriptionSignupConfiguration(planDefault: SignupPlanDefault.free)
        #expect(chosen.planDefault == SignupPlanDefault.free)
        #expect(storedPlanDefault(RegistrationSubscriptionSignupView(configuration: chosen)) == SignupPlanDefault.free)

        // And a host that names nothing gets the view's own default, not a dropped value.
        let plain = RegistrationSubscriptionSignupConfiguration()
        #expect(plain.planDefault == SignupPlanDefault.none)
        #expect(storedPlanDefault(RegistrationSubscriptionSignupView(configuration: plain)) == SignupPlanDefault.none)
    }
}
#endif
