// The signup reducer: the pay-first order, what a registration token's grant skips, and the step
// tokens that make a doubled task or a duplicated callback a no-op.
//
// Ported case for case from packages/wildwood-react/src/__tests__/signupMachine.test.ts
// (19 cases), with the TypeScript titles kept. TS asserts an ignored event by object identity
// (`toBe(state)`); Swift states are values, so the same assertion is
// `applied == false` together with `state == before`.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

private let signupOpenMode = SignupRegistrationMode.resolve(
    SignupRegistrationSettings(allowOpenRegistration: true, allowTokenRegistration: true)
)
private let signupOpenNoTokenMode = SignupRegistrationMode.resolve(
    SignupRegistrationSettings(allowOpenRegistration: true, allowTokenRegistration: false)
)
private let signupClosedMode = SignupRegistrationMode.resolve(
    SignupRegistrationSettings(allowOpenRegistration: false, allowTokenRegistration: false)
)

@MainActor
struct SignupMachineTests {
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
    private func loaded(
        _ options: SignupMachineOptions = SignupMachineOptions(),
        mode: SignupRegistrationMode = signupOpenMode
    ) -> SignupState {
        let names = SignupCatalogNames(
            tiers: ["tier-pro": "Pro"],
            addOns: ["pack-a": "Pack A", "pack-b": "Pack B"]
        )
        return run(
            SignupMachine.initialState(options),
            [
                .initialize(signedIn: false),
                .modeLoaded(mode: mode),
                .catalogLoaded(names: names),
            ]
        )
    }

    // MARK: - Cases

    @Test("walks a free plan: register, token, plan, create, disclaimers, done")
    func walksAFreePlan() throws {
        var state = loaded()
        #expect(state.step == .register)

        state = send(state, .registerSubmitted(email: "a@example.com")).state
        #expect(state.step == .token)

        state = send(state, .tokenSkipped).state
        #expect(state.step == .plan)

        // A free plan needs no card, so the payment step is skipped.
        state = send(state, .planChosen(tierId: "tier-pro", pricingId: nil, requiresPayment: false)).state
        #expect(state.step == .packs)

        state = send(state, .packsChosen(addOnIds: [])).state
        #expect(state.step == .creating)
        #expect(state.token != nil)

        let token = try #require(state.token)
        state = send(state, .accountCreated(token: token, userId: "user-1", requiresDisclaimers: nil)).state
        #expect(state.step == .disclaimers)

        state = send(state, .disclaimersAccepted).state
        #expect(state.step == .done)
        #expect(
            state.outcome
                == SignupOutcome(
                    userId: "user-1",
                    tier: SignupOutcomeTier(tierId: "tier-pro", name: "Pro", pricingId: nil),
                    packs: [],
                    tokenGrant: nil,
                    planActivationPending: nil
                )
        )
    }

    @Test("a paid plan takes the card before the account exists")
    func aPaidPlanTakesTheCardFirst() {
        var state = loaded()
        state = run(
            state,
            [
                .registerSubmitted(email: "a@example.com"),
                .tokenSkipped,
                .planChosen(tierId: "tier-pro", pricingId: "atp-1", requiresPayment: true),
                .packsChosen(addOnIds: []),
            ]
        )
        #expect(state.step == .payment)

        state = send(state, .paymentCompleted(paymentTransactionId: "txn-1")).state
        #expect(state.step == .creating)
        #expect(state.paymentTransactionId == "txn-1")
    }

    @Test("a token grant skips the plan and the payment and drops the packs it already covers")
    func aTokenGrantSkipsThePlanAndThePayment() throws {
        var state = loaded()
        state = send(state, .registerSubmitted(email: "a@example.com")).state
        state = send(state, .tokenCheckStarted).state

        let checkToken = try #require(state.token)
        let grant = SignupTokenGrant(
            tierId: "tier-pro",
            pricingId: "atp-1",
            addOnIds: ["pack-a"],
            featureCodes: ["DOCUMENTS"]
        )
        state = send(state, .tokenAccepted(token: checkToken, value: "INVITE-1", grant: grant)).state
        // Straight past plan AND payment: the token issuer is paying.
        #expect(state.step == .packs)

        state = send(state, .packsChosen(addOnIds: ["pack-a", "pack-b"])).state
        #expect(state.packsToBuy == ["pack-b"])
        #expect(state.step == .creating)

        let creatingToken = try #require(state.token)
        state = send(
            state,
            .accountCreated(token: creatingToken, userId: "user-1", requiresDisclaimers: false)
        ).state
        // The extra pack still has to be bought once the account is signed in.
        #expect(state.step == .packCheckout)

        let checkoutToken = try #require(state.token)
        let bought = SignupPackOutcome(addOnId: "pack-b", name: "Pack B", status: SignupPackStatuses.active)
        state = send(state, .packCheckoutFinished(token: checkoutToken, packs: [bought])).state
        #expect(state.step == .done)
        #expect(
            state.outcome?.packs
                == [
                    SignupPackOutcome(addOnId: "pack-a", name: "Pack A", status: SignupPackStatuses.granted),
                    SignupPackOutcome(addOnId: "pack-b", name: "Pack B", status: SignupPackStatuses.active),
                ]
        )
        #expect(state.outcome?.tier == SignupOutcomeTier(tierId: "tier-pro", name: "Pro", pricingId: "atp-1"))
        #expect(state.outcome?.tokenGrant?.featureCodes == ["DOCUMENTS"])
    }

    @Test("tokenMode 'required' skips the packs as well")
    func requiredTokenModeSkipsThePacks() throws {
        let inviteMode = SignupRegistrationMode.resolve(nil, tokenMode: .required)
        var state = loaded(SignupMachineOptions(tokenMode: .required), mode: inviteMode)
        state = send(state, .registerSubmitted(email: "a@example.com")).state
        #expect(state.step == .token)

        // A required token cannot be skipped.
        let refused = send(state, .tokenSkipped)
        #expect(refused.applied == false)
        #expect(refused.state == state)

        state = send(state, .tokenCheckStarted).state
        let checkToken = try #require(state.token)
        let grant = SignupTokenGrant(tierId: "tier-pro", pricingId: nil, addOnIds: [], featureCodes: [])
        state = send(state, .tokenAccepted(token: checkToken, value: "INVITE-1", grant: grant)).state
        #expect(state.step == .creating)
    }

    @Test("tokenMode 'required' skips the plan even when the token carries no plan")
    func requiredTokenModeSkipsThePlanWithoutAGrant() throws {
        let inviteMode = SignupRegistrationMode.resolve(nil, tokenMode: .required)
        var state = loaded(SignupMachineOptions(tokenMode: .required), mode: inviteMode)
        state = run(state, [.registerSubmitted(email: "a@example.com"), .tokenCheckStarted])

        let checkToken = try #require(state.token)
        state = send(state, .tokenAccepted(token: checkToken, value: "INVITE-2", grant: nil)).state
        // Redeeming an invite is "take what the invite gives", not a shopping trip.
        #expect(state.step == .creating)
    }

    @Test("a plan the link already chose takes the plan step out of the flow")
    func aPresetPlanTakesThePlanStepOutOfTheFlow() {
        // The catalog vetted the link's plan before the form opened.
        var state = run(
            SignupMachine.initialState(SignupMachineOptions(packSelection: SignupPackSelection.none)),
            [
                .initialize(signedIn: false),
                .modeLoaded(mode: signupOpenNoTokenMode),
                .selectionResolved(tierId: "tier-pro", pricingId: "atp-1", addOnIds: nil, requiresPayment: true),
                .catalogLoaded(names: SignupCatalogNames(tiers: ["tier-pro": "Pro"])),
            ]
        )
        #expect(state.step == .register)
        #expect(state.planPreset)

        state = send(state, .registerSubmitted(email: "a@example.com")).state
        // Straight to the card: the plan was chosen on the pricing page, and it is a paid one.
        #expect(state.step == .payment)
        #expect(state.selection == SignupSelection(tierId: "tier-pro", pricingId: "atp-1", addOnIds: []))

        // ... and "change plan" is still a way back to the grid.
        state = send(state, .goTo(step: .plan)).state
        #expect(state.step == .plan)
    }

    @Test("sends a plan changed before the form is filled in back to the form, not onward")
    func aPlanChangedBeforeTheFormGoesBackToTheForm() {
        // A signup link preselected a plan, and the visitor pressed "change plan" before typing.
        var state = run(
            SignupMachine.initialState(SignupMachineOptions(packSelection: SignupPackSelection.none)),
            [
                .initialize(signedIn: false),
                .modeLoaded(mode: signupOpenNoTokenMode),
                .selectionResolved(tierId: "tier-pro", pricingId: "atp-1", addOnIds: nil, requiresPayment: true),
                .catalogLoaded(names: SignupCatalogNames(tiers: ["tier-pro": "Pro", "tier-free": "Starter"])),
                .goTo(step: .plan),
            ]
        )
        #expect(state.step == .plan)

        // A free plan: without the gate this would have gone straight to `creating` with no details.
        state = send(state, .planChosen(tierId: "tier-free", pricingId: nil, requiresPayment: false)).state
        #expect(state.step == .register)
        #expect(state.selection.tierId == "tier-free")
        #expect(state.formSubmitted == false)

        // The form now finishes the signup, and the plan step is not asked again.
        state = send(state, .registerSubmitted(email: "a@example.com")).state
        #expect(state.step == .creating)
        #expect(state.selection.tierId == "tier-free")
    }

    @Test("sends a paid plan changed before the form is filled in back to the form, not to a card")
    func aPaidPlanChangedBeforeTheFormGoesBackToTheForm() {
        var state = run(
            SignupMachine.initialState(SignupMachineOptions(packSelection: SignupPackSelection.none)),
            [
                .initialize(signedIn: false),
                .modeLoaded(mode: signupOpenNoTokenMode),
                .selectionResolved(tierId: "tier-free", pricingId: nil, addOnIds: nil, requiresPayment: false),
                .catalogLoaded(names: SignupCatalogNames(tiers: ["tier-pro": "Pro"])),
                .goTo(step: .plan),
                .planChosen(tierId: "tier-pro", pricingId: "atp-1", requiresPayment: true),
            ]
        )
        // No card may be asked for before the form: a payment taken there has no account to attach to.
        #expect(state.step == .register)
        #expect(state.planRequiresPayment)

        state = send(state, .registerSubmitted(email: "a@example.com")).state
        #expect(state.step == .payment)
    }

    @Test("never reaches payment or creating from a pack chosen before the form")
    func aPackChosenBeforeTheFormNeverReachesPaymentOrCreating() {
        let state = run(
            SignupMachine.initialState(),
            [
                .initialize(signedIn: false),
                .modeLoaded(mode: signupOpenNoTokenMode),
                .selectionResolved(tierId: "tier-pro", pricingId: nil, addOnIds: nil, requiresPayment: true),
                .catalogLoaded(names: nil),
                .goTo(step: .packs),
                .packsChosen(addOnIds: ["pack-a"]),
            ]
        )
        #expect(state.step == .register)
        #expect(state.packsToBuy == ["pack-a"])
    }

    @Test("carries the packs the link asked for into the checkout without a pack step")
    func carriesLinkPacksWithoutAPackStep() {
        var state = run(
            SignupMachine.initialState(SignupMachineOptions(packSelection: SignupPackSelection.none)),
            [
                .initialize(signedIn: false),
                .modeLoaded(mode: signupOpenNoTokenMode),
                .selectionResolved(
                    tierId: "tier-pro",
                    pricingId: nil,
                    addOnIds: ["pack-a"],
                    requiresPayment: false
                ),
                .catalogLoaded(names: SignupCatalogNames(addOns: ["pack-a": "Pack A"])),
            ]
        )

        state = send(state, .registerSubmitted(email: "a@example.com")).state
        #expect(state.step == .creating)
        #expect(state.packsToBuy == ["pack-a"])
    }

    @Test("refuses a selection once the form has been submitted")
    func refusesASelectionAfterTheForm() {
        let state = run(loaded(), [.registerSubmitted(email: "a@example.com")])
        // A catalog reloading underneath must not rewrite what the visitor is buying.
        let refused = send(
            state,
            .selectionResolved(tierId: "tier-other", pricingId: nil, addOnIds: nil, requiresPayment: nil)
        )
        #expect(refused.applied == false)
        #expect(refused.state == state)
    }

    @Test("planSelection 'skip' goes past the plan step")
    func planSelectionSkipGoesPastThePlanStep() {
        var state = loaded(
            SignupMachineOptions(planSelection: .skip, packSelection: SignupPackSelection.none)
        )
        state = send(state, .registerSubmitted(email: "a@example.com")).state
        state = send(state, .tokenSkipped).state
        #expect(state.step == .creating)
    }

    @Test("skips the token step when the app offers no token path")
    func skipsTheTokenStepWithoutATokenPath() {
        var state = loaded(SignupMachineOptions(), mode: signupOpenNoTokenMode)
        state = send(state, .registerSubmitted(email: "a@example.com")).state
        #expect(state.step == .plan)
    }

    @Test("shows the closed panel when registration is off")
    func showsTheClosedPanel() {
        let state = loaded(SignupMachineOptions(), mode: signupClosedMode)
        #expect(state.step == .closed)
    }

    @Test("ignores a result carrying a stale step token")
    func ignoresAStaleStepToken() throws {
        var state = loaded(
            SignupMachineOptions(planSelection: .skip, packSelection: SignupPackSelection.none)
        )
        state = run(state, [.registerSubmitted(email: "a@example.com"), .tokenSkipped])
        #expect(state.step == .creating)
        let stale = try #require(state.token)

        // The task re-ran: the step is re-entered with a new token.
        state = send(state, .goTo(step: .register)).state
        state = run(state, [.registerSubmitted(email: "a@example.com"), .tokenSkipped])
        let fresh = try #require(state.token)
        #expect(fresh != stale)

        let ignored = send(state, .accountCreated(token: stale, userId: "ghost", requiresDisclaimers: nil))
        #expect(ignored.applied == false)
        #expect(ignored.state == state)
        #expect(ignored.state.userId == "")

        state = send(state, .accountCreated(token: fresh, userId: "user-1", requiresDisclaimers: nil)).state
        #expect(state.step == .disclaimers)
    }

    @Test("ignores a duplicated result event")
    func ignoresADuplicatedResultEvent() throws {
        var state = loaded(
            SignupMachineOptions(planSelection: .skip, packSelection: SignupPackSelection.none)
        )
        state = run(state, [.registerSubmitted(email: "a@example.com"), .tokenSkipped])
        let token = try #require(state.token)

        state = send(state, .accountCreated(token: token, userId: "user-1", requiresDisclaimers: nil)).state
        #expect(state.step == .disclaimers)

        // The same callback firing twice must not advance anything.
        let again = send(state, .accountCreated(token: token, userId: "user-2", requiresDisclaimers: nil))
        #expect(again.applied == false)
        #expect(again.state == state)
        #expect(again.state.userId == "user-1")
    }

    @Test("latches \"already signed in\" at the first INIT only")
    func latchesAlreadySignedInOnce() {
        var state = SignupMachine.initialState()
        #expect(state.alreadySignedInLatched == false)

        state = send(state, .initialize(signedIn: false)).state
        #expect(state.initialized)
        #expect(state.alreadySignedInLatched == false)

        // The visitor logs in mid-flow; that is not "you were already signed in".
        let after = send(state, .initialize(signedIn: true))
        #expect(after.applied == false)
        #expect(after.state == state)
        #expect(after.state.alreadySignedInLatched == false)
    }

    @Test("a failed account creation can be retried from the same step")
    func aFailedAccountCreationCanBeRetried() throws {
        var state = loaded(
            SignupMachineOptions(planSelection: .skip, packSelection: SignupPackSelection.none)
        )
        state = run(state, [.registerSubmitted(email: "a@example.com"), .tokenSkipped])

        let token = try #require(state.token)
        state = send(state, .accountFailed(token: token, message: "Email already in use")).state
        #expect(state.step == .failed)
        #expect(state.error == "Email already in use")
        #expect(state.retryFrom == .creating)

        state = send(state, .retry).state
        #expect(state.step == .creating)
        #expect(state.error == nil)
    }

    @Test("a rejected token is a form error, not a failed flow")
    func aRejectedTokenIsAFormError() throws {
        var state = loaded()
        state = send(state, .registerSubmitted(email: "a@example.com")).state
        state = send(state, .tokenCheckStarted).state

        let token = try #require(state.token)
        state = send(state, .tokenRejected(token: token, message: "That token has expired")).state

        #expect(state.step == .token)
        #expect(state.tokenError == "That token has expired")
        #expect(state.tokenChecking == false)
    }
}
