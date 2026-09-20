// The pack-checkout reducer: quote, one card, one purchase, then 3-D Secure walked one pack at a
// time. One pack failing must leave the others alone.
//
// Ported case for case from packages/wildwood-react/src/__tests__/packCheckoutMachine.test.ts
// (7 cases), with the TypeScript titles kept. TS asserts an ignored event by object identity
// (`toBe(state)`); Swift states are values, so the same assertion is
// `applied == false` together with `state == before`.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct PackCheckoutMachineTests {
    /// Its own issuer, so the tokens are deterministic however many suites run in parallel.
    private let issuer = StepTokenIssuer()

    /// 2026-10-01T00:00:00Z — the TS fixture's `trialEnd`, which Swift models as a `Date`.
    private static let trialEnd = Date(timeIntervalSince1970: 1_790_812_800)

    // MARK: - Helpers

    private func send(_ state: PackCheckoutState, _ event: PackCheckoutEvent) -> PackCheckoutTransitionResult {
        PackCheckoutMachine.transition(state, event, issuer: issuer)
    }

    private func quote(_ requiresPaymentMethod: Bool) -> AddOnCheckoutQuoteModel {
        AddOnCheckoutQuoteModel(
            success: true,
            checkoutId: "chk-1",
            providerId: "prov-1",
            currency: "USD",
            lines: [],
            totalDueToday: 20,
            requiresPaymentMethod: requiresPaymentMethod
        )
    }

    private func item(
        _ addOnId: String,
        _ status: String,
        subscriptionId: String? = nil,
        trialEnd: Date? = nil,
        clientSecret: String? = nil,
        paymentTransactionId: String? = nil
    ) -> AddOnCheckoutItemResultModel {
        AddOnCheckoutItemResultModel(
            addOnId: addOnId,
            pricingId: "\(addOnId)-pricing",
            status: status,
            subscriptionId: subscriptionId,
            trialEnd: trialEnd,
            clientSecret: clientSecret,
            paymentTransactionId: paymentTransactionId
        )
    }

    private func quoted(_ requiresPaymentMethod: Bool) throws -> PackCheckoutState {
        var state = send(
            PackCheckoutMachine.initialState(),
            .quoteRequested(
                appId: "app-1",
                items: [AddOnCheckoutItemInput(addOnId: "pack-a"), AddOnCheckoutItemInput(addOnId: "pack-b")]
            )
        ).state
        let token = try #require(state.token)
        state = send(state, .quoteReceived(token: token, quote: quote(requiresPaymentMethod))).state
        return state
    }

    // MARK: - Cases

    @Test("buys against the card on file when the quote needs no new one")
    func buysAgainstTheCardOnFile() throws {
        var state = try quoted(false)
        #expect(state.step == .quoted)
        #expect(state.useSavedCard)

        state = send(state, .checkoutRequested).state
        #expect(state.step == .checkingOut)

        let token = try #require(state.token)
        let result = AddOnCheckoutResultModel(
            success: true,
            checkoutId: "chk-1",
            results: [
                item("pack-a", AddOnCheckoutItemStatuses.active),
                item("pack-b", AddOnCheckoutItemStatuses.trialing, trialEnd: Self.trialEnd),
            ]
        )
        state = send(state, .checkoutReceived(token: token, result: result)).state
        #expect(state.step == .done)
        #expect(state.results.map(\.status) == ["active", "trialing"])
    }

    @Test("collects a card first when the quote says there is none")
    func collectsACardFirst() throws {
        var state = try quoted(true)
        #expect(state.useSavedCard == false)

        state = send(state, .cardRequested).state
        #expect(state.step == .collectingCard)

        let token = try #require(state.token)
        state = send(
            state,
            .cardIntentReceived(token: token, clientSecret: "seti_secret", paymentTransactionId: "txn-card")
        ).state
        #expect(state.cardClientSecret == "seti_secret")
        #expect(state.step == .collectingCard)

        state = send(state, .cardConfirmed(token: token, paymentTransactionId: nil)).state
        #expect(state.step == .checkingOut)
        #expect(state.paymentTransactionId == "txn-card")
        #expect(state.useSavedCard == false)
    }

    @Test("walks 3-D Secure one pack at a time, in order")
    func walks3DSecureOnePackAtATime() throws {
        var state = try quoted(false)
        state = send(state, .checkoutRequested).state

        let checkoutToken = try #require(state.token)
        let result = AddOnCheckoutResultModel(
            success: true,
            checkoutId: "chk-1",
            results: [
                item(
                    "pack-a",
                    AddOnCheckoutItemStatuses.requiresAction,
                    clientSecret: "pi_a",
                    paymentTransactionId: "txn-a"
                ),
                item(
                    "pack-b",
                    AddOnCheckoutItemStatuses.requiresAction,
                    clientSecret: "pi_b",
                    paymentTransactionId: "txn-b"
                ),
            ]
        )
        state = send(state, .checkoutReceived(token: checkoutToken, result: result)).state
        #expect(state.step == .authenticating)
        #expect(currentPackCheckoutItem(state)?.addOnId == "pack-a")

        var authToken = try #require(state.token)
        state = send(state, .itemAuthenticated(token: authToken)).state
        #expect(state.step == .completing)

        var completeToken = try #require(state.token)
        state = send(
            state,
            .itemCompleted(
                token: completeToken,
                result: item("pack-a", AddOnCheckoutItemStatuses.active, subscriptionId: "sub-a")
            )
        ).state

        // On to the second pack, not straight to done.
        #expect(state.step == .authenticating)
        #expect(currentPackCheckoutItem(state)?.addOnId == "pack-b")

        authToken = try #require(state.token)
        state = send(state, .itemAuthenticated(token: authToken)).state
        completeToken = try #require(state.token)
        state = send(
            state,
            .itemCompleted(
                token: completeToken,
                result: item("pack-b", AddOnCheckoutItemStatuses.trialing, subscriptionId: "sub-b")
            )
        ).state
        #expect(state.step == .done)
        #expect(state.results.map(\.status) == ["active", "trialing"])
    }

    @Test("one pack failing leaves the rest of the basket alone")
    func onePackFailingLeavesTheRestAlone() throws {
        var state = try quoted(false)
        state = send(state, .checkoutRequested).state

        let checkoutToken = try #require(state.token)
        let result = AddOnCheckoutResultModel(
            success: true,
            checkoutId: "chk-1",
            results: [
                item("pack-a", AddOnCheckoutItemStatuses.requiresAction, clientSecret: "pi_a"),
                item("pack-b", AddOnCheckoutItemStatuses.requiresAction, clientSecret: "pi_b"),
                item("pack-c", AddOnCheckoutItemStatuses.active),
            ]
        )
        state = send(state, .checkoutReceived(token: checkoutToken, result: result)).state

        let authToken = try #require(state.token)
        state = send(state, .itemAuthFailed(token: authToken, message: "Your bank declined the card")).state
        #expect(state.step == .authenticating)
        #expect(state.results[0].status == "failed")
        #expect(state.results[0].errorMessage == "Your bank declined the card")
        #expect(currentPackCheckoutItem(state)?.addOnId == "pack-b")

        let secondAuthToken = try #require(state.token)
        state = send(state, .itemAuthenticated(token: secondAuthToken)).state
        let completeToken = try #require(state.token)
        state = send(
            state,
            .itemCompleted(token: completeToken, result: item("pack-b", AddOnCheckoutItemStatuses.active))
        ).state
        #expect(state.step == .done)
        #expect(state.results.map(\.status) == ["failed", "active", "active"])
    }

    @Test("ignores a result carrying a stale step token")
    func ignoresAStaleStepToken() throws {
        var state = send(
            PackCheckoutMachine.initialState(),
            .quoteRequested(appId: "app-1", items: [AddOnCheckoutItemInput(addOnId: "pack-a")])
        ).state
        let stale = try #require(state.token)

        // The task ran twice: the second attempt supersedes the first.
        state = send(
            state,
            .quoteRequested(appId: "app-1", items: [AddOnCheckoutItemInput(addOnId: "pack-a")])
        ).state
        let fresh = try #require(state.token)
        #expect(fresh != stale)

        let ignored = send(state, .quoteReceived(token: stale, quote: quote(false)))
        #expect(ignored.applied == false)
        #expect(ignored.state == state)
        #expect(ignored.state.step == .quoting)

        state = send(state, .quoteReceived(token: fresh, quote: quote(false))).state
        #expect(state.step == .quoted)
    }

    @Test("a refused quote fails with the server reason and can be retried")
    func aRefusedQuoteFailsAndCanBeRetried() throws {
        var state = send(
            PackCheckoutMachine.initialState(),
            .quoteRequested(appId: "app-1", items: [AddOnCheckoutItemInput(addOnId: "pack-a")])
        ).state
        let token = try #require(state.token)
        let refusal = AddOnCheckoutQuoteModel(
            success: false,
            checkoutId: "",
            currency: "",
            lines: [],
            totalDueToday: 0,
            requiresPaymentMethod: false,
            errorCode: AddOnCheckoutErrorCodes.alreadySubscribed,
            errorMessage: "You already have that pack"
        )
        state = send(state, .quoteReceived(token: token, quote: refusal)).state
        #expect(state.step == .failed)
        #expect(state.error == "You already have that pack")
        #expect(state.errorCode == "AlreadySubscribed")

        state = send(state, .retry).state
        #expect(state.step == .quoting)
    }

    @Test("retrying the card form drops the SetupIntent the failed attempt was holding")
    func retryingTheCardFormDropsTheSetupIntent() throws {
        var state = try quoted(true)
        state = send(state, .cardRequested).state

        let token = try #require(state.token)
        state = send(
            state,
            .cardIntentReceived(
                token: token,
                clientSecret: "seti_secret_first",
                paymentTransactionId: "txn-first"
            )
        ).state
        state = send(state, .cardFailed(token: token, message: "Card declined")).state
        #expect(state.step == .failed)

        state = send(state, .retry).state
        // Back on the card form with nothing to confirm: the driver collects a fresh intent, so the
        // second card is never confirmed against the first attempt's secret.
        #expect(state.step == .collectingCard)
        #expect(state.cardClientSecret == nil)
        #expect(state.paymentTransactionId == nil)
    }
}
