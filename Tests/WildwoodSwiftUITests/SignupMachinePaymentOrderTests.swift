// The account-first signup order.
//
// `paymentOrder: .afterAccount` is what the store-billed stacks want: a StoreKit or Play purchase
// that succeeds before a registration that then fails strands a paid subscription with no account
// to attach it to, which is worse than an account with no plan. So the card moves out of the form's
// order and sits between the account and the disclaimers — and a customer who walks away from it
// still finishes the signup, with the plan's activation pending, said in so many words.
//
// The default order is asserted by SignupMachineTests, unchanged. What is defended here is that the
// option moves the step and NOTHING else: the same skip rules decide whether there is a card to
// take at all, and the same step tokens still throw stale results away.
//
// Ported case for case from
// packages/wildwood-react/src/__tests__/signupMachine.paymentOrder.test.ts (20 cases), with the
// TypeScript titles kept.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

private let paymentOrderOpenMode = SignupRegistrationMode.resolve(
    SignupRegistrationSettings(allowOpenRegistration: true, allowTokenRegistration: true)
)

@MainActor
struct SignupMachinePaymentOrderTests {
    /// Its own issuer, so the tokens are deterministic however many suites run in parallel.
    private let issuer = StepTokenIssuer()

    // MARK: - Helpers

    private func send(_ state: SignupState, _ event: SignupEvent) -> SignupTransitionResult {
        SignupMachine.transition(state, event, issuer: issuer)
    }

    private func run(_ state: SignupState, _ events: [SignupEvent]) -> SignupState {
        var current: SignupState = state
        for event in events {
            current = send(current, event).state
        }
        return current
    }

    /// Load the mode and the catalog and land on the register form.
    private func loaded(_ options: SignupMachineOptions = SignupMachineOptions()) -> SignupState {
        var accountFirst = options
        accountFirst.paymentOrder = .afterAccount
        let names = SignupCatalogNames(tiers: ["tier-pro": "Pro"], addOns: ["pack-a": "Pack A"])
        return run(
            SignupMachine.initialState(accountFirst),
            [
                .initialize(signedIn: false),
                .modeLoaded(mode: paymentOrderOpenMode),
                .catalogLoaded(names: names),
            ]
        )
    }

    /// Walk the form with a paid plan chosen, which in this order ends at `creating`.
    private func toCreating(_ options: SignupMachineOptions = SignupMachineOptions()) -> SignupState {
        run(
            loaded(options),
            [
                .registerSubmitted(email: "a@example.com"),
                .tokenSkipped,
                .planChosen(tierId: "tier-pro", pricingId: "atp-1", requiresPayment: true),
                .packsChosen(addOnIds: []),
            ]
        )
    }

    // MARK: - The account-first order

    @Test("takes the payment step out of the form order")
    func takesThePaymentStepOutOfTheFormOrder() {
        let state = toCreating()
        // Pay-first would be sitting on `payment` here; this order has already gone past it.
        #expect(state.step == .creating)
        #expect(state.token != nil)
        #expect(state.paymentAfterAccount == false)
    }

    @Test("asks for the card once the account exists, before the disclaimers")
    func asksForTheCardOnceTheAccountExists() throws {
        var state = toCreating()
        let token = try #require(state.token)
        state = send(state, .accountCreated(token: token, userId: "user-1", requiresDisclaimers: nil)).state

        #expect(state.step == .payment)
        #expect(state.paymentAfterAccount)
        #expect(state.userId == "user-1")
        // Where it goes afterwards was decided by the event, and is remembered across the card.
        #expect(state.pendingDisclaimers)
    }

    @Test("carries on to the disclaimers when the card is given")
    func carriesOnToTheDisclaimersWhenTheCardIsGiven() throws {
        var state = toCreating()
        let token = try #require(state.token)
        state = send(state, .accountCreated(token: token, userId: "user-1", requiresDisclaimers: nil)).state
        state = send(state, .paymentCompleted(paymentTransactionId: "txn-1")).state

        #expect(state.step == .disclaimers)
        #expect(state.paymentTransactionId == "txn-1")
        #expect(state.paymentAfterAccount == false)

        state = send(state, .disclaimersAccepted).state
        #expect(state.step == .done)
        #expect(
            state.outcome
                == SignupOutcome(
                    userId: "user-1",
                    tier: SignupOutcomeTier(tierId: "tier-pro", name: "Pro", pricingId: "atp-1"),
                    packs: [],
                    tokenGrant: nil,
                    planActivationPending: nil
                )
        )
    }

    @Test("goes exactly where ACCOUNT_CREATED would have when there are no disclaimers")
    func goesWhereAccountCreatedWouldHaveWithoutDisclaimers() throws {
        var state = run(
            loaded(),
            [
                .registerSubmitted(email: "a@example.com"),
                .tokenSkipped,
                .planChosen(tierId: "tier-pro", pricingId: "atp-1", requiresPayment: true),
                .packsChosen(addOnIds: ["pack-a"]),
            ]
        )
        let token = try #require(state.token)
        state = send(state, .accountCreated(token: token, userId: "user-1", requiresDisclaimers: false)).state
        #expect(state.step == .payment)

        state = send(state, .paymentCompleted(paymentTransactionId: "txn-1")).state
        // Straight to the packs the visitor also asked for, as it would have been without a card.
        #expect(state.step == .packCheckout)
    }

    @Test("finishes with the plan pending when the customer walks away from the card")
    func finishesWithThePlanPendingWhenTheCardIsAbandoned() throws {
        var state = toCreating()
        let token = try #require(state.token)
        state = send(state, .accountCreated(token: token, userId: "user-1", requiresDisclaimers: false)).state
        #expect(state.step == .payment)

        state = send(state, .paymentAbandoned).state

        // The account is real, so it is not thrown away: the signup completes and says what is missing.
        #expect(state.step == .done)
        #expect(state.planActivationPending)
        #expect(state.outcome?.planActivationPending == true)
        #expect(state.outcome?.userId == "user-1")
        #expect(state.paymentTransactionId == nil)
    }

    @Test("still shows the disclaimers after an abandoned card")
    func stillShowsTheDisclaimersAfterAnAbandonedCard() throws {
        var state = toCreating()
        let token = try #require(state.token)
        state = send(state, .accountCreated(token: token, userId: "user-1", requiresDisclaimers: nil)).state
        state = send(state, .paymentAbandoned).state

        #expect(state.step == .disclaimers)
        #expect(state.planActivationPending)
    }

    @Test("carries the pending plan all the way into the outcome when the card is never retried")
    func carriesThePendingPlanIntoTheOutcome() throws {
        var state = toCreating()
        let token = try #require(state.token)
        state = send(state, .accountCreated(token: token, userId: "user-1", requiresDisclaimers: nil)).state
        state = send(state, .paymentAbandoned).state
        #expect(state.step == .disclaimers)

        state = send(state, .disclaimersAccepted).state
        #expect(state.step == .done)
        #expect(state.outcome?.planActivationPending == true)
        #expect(state.paymentTransactionId == nil)
    }

    @Test("un-pends the plan when the customer comes back and the card goes through")
    func unPendsThePlanWhenTheCardGoesThrough() throws {
        var state = toCreating()
        let token = try #require(state.token)
        state = send(state, .accountCreated(token: token, userId: "user-1", requiresDisclaimers: nil)).state
        state = send(state, .paymentAbandoned).state
        #expect(state.planActivationPending)

        // Back to the card, and this time it is given.
        state = send(state, .goTo(step: .payment)).state
        #expect(state.step == .payment)
        state = send(state, .paymentCompleted(paymentTransactionId: "txn-2")).state

        // The disclaimers were never accepted, so they are still what comes next.
        #expect(state.step == .disclaimers)
        #expect(state.planActivationPending == false)

        state = send(state, .disclaimersAccepted).state
        #expect(state.step == .done)
        // A paying customer is never told their plan is still pending.
        #expect(
            state.outcome
                == SignupOutcome(
                    userId: "user-1",
                    tier: SignupOutcomeTier(tierId: "tier-pro", name: "Pro", pricingId: "atp-1"),
                    packs: [],
                    tokenGrant: nil,
                    planActivationPending: nil
                )
        )
        #expect(state.paymentTransactionId == "txn-2")
    }

    @Test("ignores PAYMENT_ABANDONED in the pay-first order")
    func ignoresPaymentAbandonedInThePayFirstOrder() {
        // Pay-first reaches its payment step with no account behind it, so there is nothing to
        // abandon INTO — backing out there is a step back, which is `goTo`.
        let state = run(
            SignupMachine.initialState(),
            [
                .initialize(signedIn: false),
                .modeLoaded(mode: paymentOrderOpenMode),
                .catalogLoaded(names: nil),
                .registerSubmitted(email: "a@example.com"),
                .tokenSkipped,
                .planChosen(tierId: "tier-pro", pricingId: "atp-1", requiresPayment: true),
                .packsChosen(addOnIds: []),
            ]
        )
        #expect(state.step == .payment)

        let after = send(state, .paymentAbandoned)
        #expect(after.applied == false)
        #expect(after.state == state)
    }

    @Test("never asks a token grant to pay: the issuer already did")
    func neverAsksATokenGrantToPay() throws {
        var state = loaded()
        state = run(state, [.registerSubmitted(email: "a@example.com"), .tokenCheckStarted])
        let checkToken = try #require(state.token)
        let grant = SignupTokenGrant(tierId: "tier-pro", pricingId: "atp-1", addOnIds: [], featureCodes: [])
        state = send(state, .tokenAccepted(token: checkToken, value: "INVITE-1", grant: grant)).state
        #expect(state.step == .packs)

        state = send(state, .packsChosen(addOnIds: [])).state
        #expect(state.step == .creating)

        let creatingToken = try #require(state.token)
        state = send(
            state,
            .accountCreated(token: creatingToken, userId: "user-1", requiresDisclaimers: false)
        ).state
        #expect(state.step == .done)
        #expect(state.paymentAfterAccount == false)
    }

    @Test("never asks a free plan to pay")
    func neverAsksAFreePlanToPay() throws {
        var state = run(
            loaded(),
            [
                .registerSubmitted(email: "a@example.com"),
                .tokenSkipped,
                .planChosen(tierId: "tier-pro", pricingId: nil, requiresPayment: false),
                .packsChosen(addOnIds: []),
            ]
        )
        let token = try #require(state.token)
        state = send(state, .accountCreated(token: token, userId: "user-1", requiresDisclaimers: false)).state
        #expect(state.step == .done)
    }

    @Test("does not ask twice when the card was somehow already given")
    func doesNotAskTwiceWhenTheCardWasAlreadyGiven() throws {
        var state = toCreating()
        let firstToken = try #require(state.token)
        state = send(state, .accountCreated(token: firstToken, userId: "user-1", requiresDisclaimers: nil)).state
        state = send(state, .paymentCompleted(paymentTransactionId: "txn-1")).state
        #expect(state.step == .disclaimers)

        // A start-over that walks the form again carries the transaction already taken, so the card
        // step has nothing left to ask for.
        state = run(
            state,
            [
                .goTo(step: .register),
                .registerSubmitted(email: "a@example.com"),
                .tokenSkipped,
                .packsChosen(addOnIds: []),
            ]
        )
        #expect(state.step == .creating)

        let secondToken = try #require(state.token)
        state = send(state, .accountCreated(token: secondToken, userId: "user-1", requiresDisclaimers: false)).state
        #expect(state.step == .done)
    }

    @Test("still throws a stale account result away")
    func stillThrowsAStaleAccountResultAway() {
        let state = toCreating()
        // TS calls `issueStepToken()`; the suite's own issuer is monotonic, so a freshly issued
        // token is by definition not the one the state is waiting on.
        let stale = issuer.issue()
        let created = send(state, .accountCreated(token: stale, userId: "user-1", requiresDisclaimers: nil))
        #expect(created.applied == false)
        #expect(created.state == state)

        let failed = send(state, .accountFailed(token: stale, message: "no"))
        #expect(failed.applied == false)
        #expect(failed.state == state)
    }

    // MARK: - GO_TO and RESET in the account-first order

    @Test("refuses to open a card step before there is an account")
    func refusesToOpenACardStepBeforeThereIsAnAccount() {
        let state = run(loaded(), [.registerSubmitted(email: "a@example.com"), .tokenSkipped])
        #expect(state.step == .plan)
        // There is no pre-account card step in this order, so the machine stays where it is.
        let refused = send(state, .goTo(step: .payment))
        #expect(refused.applied == false)
        #expect(refused.state == state)
    }

    @Test("re-opens the card step once the account exists")
    func reOpensTheCardStepOnceTheAccountExists() throws {
        var state = toCreating()
        let token = try #require(state.token)
        state = send(state, .accountCreated(token: token, userId: "user-1", requiresDisclaimers: nil)).state
        state = send(state, .paymentAbandoned).state
        #expect(state.step == .disclaimers)

        state = send(state, .goTo(step: .payment)).state
        #expect(state.step == .payment)
        #expect(state.paymentAfterAccount)
    }

    @Test("refuses to re-open the card once one has been taken")
    func refusesToReOpenTheCardOnceTaken() throws {
        var state = toCreating()
        let token = try #require(state.token)
        state = send(state, .accountCreated(token: token, userId: "user-1", requiresDisclaimers: nil)).state
        state = send(state, .paymentCompleted(paymentTransactionId: "txn-1")).state
        #expect(state.step == .disclaimers)

        // The plan is paid for; there is nothing left to ask the customer for.
        let refused = send(state, .goTo(step: .payment))
        #expect(refused.applied == false)
        #expect(refused.state == state)
    }

    @Test("refuses to re-open the card once the signup has moved on to the packs")
    func refusesToReOpenTheCardOncePastThePacks() throws {
        var state = run(
            loaded(),
            [
                .registerSubmitted(email: "a@example.com"),
                .tokenSkipped,
                .planChosen(tierId: "tier-pro", pricingId: "atp-1", requiresPayment: true),
                .packsChosen(addOnIds: ["pack-a"]),
            ]
        )
        let token = try #require(state.token)
        state = send(state, .accountCreated(token: token, userId: "user-1", requiresDisclaimers: false)).state
        state = send(state, .paymentAbandoned).state
        #expect(state.step == .packCheckout)

        // Coming back through the card from here would re-run disclaimers already passed and
        // restart a checkout that may already be charging, so the machine stays where it is.
        let refused = send(state, .goTo(step: .payment))
        #expect(refused.applied == false)
        #expect(refused.state == state)
    }

    @Test("refuses to re-open the card once the outcome is out")
    func refusesToReOpenTheCardOnceTheOutcomeIsOut() throws {
        var state = toCreating()
        let token = try #require(state.token)
        state = send(state, .accountCreated(token: token, userId: "user-1", requiresDisclaimers: false)).state
        state = send(state, .paymentAbandoned).state
        #expect(state.step == .done)

        // `done` refuses every goTo: the outcome has been handed to the host already.
        let refusedPayment = send(state, .goTo(step: .payment))
        #expect(refusedPayment.applied == false)
        #expect(refusedPayment.state == state)

        let refusedRegister = send(state, .goTo(step: .register))
        #expect(refusedRegister.applied == false)
        #expect(refusedRegister.state == state)
    }

    @Test("keeps the order across a start-over")
    func keepsTheOrderAcrossAStartOver() {
        var state = toCreating()
        state = send(state, .reset).state
        #expect(state.options.paymentOrder == .afterAccount)
        #expect(state.paymentAfterAccount == false)
        #expect(state.planActivationPending == false)
    }

    @Test("defaults to the pay-first order when nothing asks otherwise")
    func defaultsToThePayFirstOrder() {
        #expect(SignupMachine.initialState().options.paymentOrder == .beforeAccount)
    }
}
