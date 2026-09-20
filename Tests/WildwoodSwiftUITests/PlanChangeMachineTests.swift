// The plan-change reducer: every layout confirms the preview, 3-D Secure is a "not yet" rather
// than a refusal, and `processing` is retried instead of reported as a failure.
//
// Ported case for case from packages/wildwood-react/src/__tests__/planChangeMachine.test.ts
// (10 cases), with the TypeScript titles kept. TS asserts an ignored event by object identity
// (`toBe(state)`); Swift states are values, so the same assertion is
// `applied == false` together with `state == before`.
//
// `TierChangePreviewModel` is a read-only response model with no memberwise initialiser, so the
// fixture decodes one the way the wire delivers it.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct PlanChangeMachineTests {
    /// Its own issuer, so the tokens are deterministic however many suites run in parallel.
    private let issuer = StepTokenIssuer()

    // MARK: - Helpers

    private func send(_ state: PlanChangeState, _ event: PlanChangeEvent) -> PlanChangeTransitionResult {
        PlanChangeMachine.transition(state, event, issuer: issuer)
    }

    private func preview(
        success: Bool = true,
        isUpgrade: Bool = true,
        isDowngrade: Bool = false,
        paymentRequired: Bool = false,
        paymentBypassAllowed: Bool = false,
        proratedChargeToday: Double? = nil,
        newPrice: Double? = nil,
        errorMessage: String? = nil
    ) throws -> TierChangePreviewModel {
        var json: [String: Any] = [
            "success": success,
            "isUpgrade": isUpgrade,
            "isDowngrade": isDowngrade,
            "isBillingFrequencyChange": false,
            "paymentRequired": paymentRequired,
            "paymentBypassAllowed": paymentBypassAllowed,
            "paymentProviderAvailable": true,
            "featuresGained": [String](),
            "featuresLost": [String](),
            "currency": "USD",
            "daysRemainingInPeriod": 12,
            "allowImmediateChange": true,
            "allowScheduledChange": true,
        ]
        if let proratedChargeToday { json["proratedChargeToday"] = proratedChargeToday }
        if let newPrice { json["newPrice"] = newPrice }
        if let errorMessage { json["errorMessage"] = errorMessage }
        let data: Data = try JSONSerialization.data(withJSONObject: json)
        return try WildwoodJSON.decoder().decode(TierChangePreviewModel.self, from: data)
    }

    private func changeResult(
        success: Bool = false,
        errorMessage: String = "",
        requiresAction: Bool? = nil,
        clientSecret: String? = nil,
        pendingChangeId: String? = nil,
        amountDue: Double? = nil,
        currency: String? = nil,
        processing: Bool? = nil,
        errorCode: String? = nil
    ) -> AppTierChangeResultModel {
        AppTierChangeResultModel(
            success: success,
            errorMessage: errorMessage,
            subscription: nil,
            isScheduled: false,
            effectiveDate: nil,
            requiresAction: requiresAction,
            clientSecret: clientSecret,
            pendingChangeId: pendingChangeId,
            paymentIntentId: nil,
            expiresAt: nil,
            amountDue: amountDue,
            currency: currency,
            processing: processing,
            errorCode: errorCode
        )
    }

    private func previewed(_ previewModel: TierChangePreviewModel) throws -> PlanChangeState {
        var state = send(
            PlanChangeMachine.initialState(),
            .previewRequested(appId: "app-1", tierId: "tier-pro", pricingId: "atp-1", immediate: nil)
        ).state
        let token = try #require(state.token)
        state = send(state, .previewReceived(token: token, preview: previewModel)).state
        return state
    }

    /// Preview, confirm and park the change on 3-D Secure, which is where the completion budget
    /// starts counting.
    private func parked() throws -> PlanChangeState {
        let model = try preview()
        var state = try previewed(model)
        state = send(state, .confirmed(collectPayment: nil, immediate: nil)).state
        let changeToken = try #require(state.token)
        state = send(
            state,
            .changeResult(
                token: changeToken,
                result: changeResult(requiresAction: true, clientSecret: "s", pendingChangeId: "pending-1")
            )
        ).state
        let authToken = try #require(state.token)
        return send(state, .authenticated(token: authToken)).state
    }

    // MARK: - Cases

    @Test("previews, confirms and changes")
    func previewsConfirmsAndChanges() throws {
        let model = try preview()
        var state = try previewed(model)
        #expect(state.step == .confirm)
        #expect(state.preview?.isUpgrade == true)

        state = send(state, .confirmed(collectPayment: nil, immediate: nil)).state
        #expect(state.step == .changing)

        let token = try #require(state.token)
        state = send(state, .changeResult(token: token, result: changeResult(success: true))).state
        #expect(state.step == .done)
        #expect(state.error == nil)
    }

    @Test("parks on 3-D Secure, then completes")
    func parksOn3DSecureThenCompletes() throws {
        let model = try preview(paymentRequired: true, paymentBypassAllowed: true, proratedChargeToday: 12.5)
        var state = try previewed(model)
        state = send(state, .confirmed(collectPayment: nil, immediate: nil)).state
        #expect(state.step == .changing)

        let changeToken = try #require(state.token)
        state = send(
            state,
            .changeResult(
                token: changeToken,
                result: changeResult(
                    requiresAction: true,
                    clientSecret: "pi_secret",
                    pendingChangeId: "pending-1",
                    amountDue: 12.5,
                    currency: "USD"
                )
            )
        ).state
        #expect(state.step == .authenticating)
        #expect(state.clientSecret == "pi_secret")
        #expect(state.pendingChangeId == "pending-1")
        // "Not yet" is not a refusal: nothing is shown as an error.
        #expect(state.error == nil)

        let authToken = try #require(state.token)
        state = send(state, .authenticated(token: authToken)).state
        #expect(state.step == .completing)

        let completeToken = try #require(state.token)
        state = send(state, .completeResult(token: completeToken, result: changeResult(success: true))).state
        #expect(state.step == .done)
    }

    @Test("retries completion while the server answers processing")
    func retriesCompletionWhileProcessing() throws {
        var state = try parked()

        let firstToken = try #require(state.token)
        state = send(
            state,
            .completeResult(token: firstToken, result: changeResult(processing: true))
        ).state
        #expect(state.step == .completing)
        #expect(state.completeAttempts == 1)
        // A fresh token, so the driver's effect runs the completion again.
        #expect(state.token != firstToken)

        let secondToken = try #require(state.token)
        state = send(state, .completeResult(token: secondToken, result: changeResult(success: true))).state
        #expect(state.step == .done)
    }

    @Test("gives up after too many processing answers")
    func givesUpAfterTooManyProcessingAnswers() throws {
        var state = try parked()

        for _ in 0..<PlanChangeMachine.maxCompleteAttempts {
            let token = try #require(state.token)
            state = send(state, .completeResult(token: token, result: changeResult(processing: true))).state
        }
        #expect(state.step == .failed)
        #expect(state.completeAttempts == PlanChangeMachine.maxCompleteAttempts)
        #expect(state.retryFrom == .completing)
    }

    @Test("starts the completion budget over on a manual retry")
    func startsTheCompletionBudgetOverOnRetry() throws {
        var state = try parked()

        for _ in 0..<maxPlanChangeCompleteAttempts {
            let token = try #require(state.token)
            state = send(state, .completeResult(token: token, result: changeResult(processing: true))).state
        }
        #expect(state.step == .failed)

        // The budget belongs to one automatic run of retries: the customer's own retry gets a fresh
        // one, or it would give up on its first answer.
        state = send(state, .retry).state
        #expect(state.step == .completing)
        #expect(state.completeAttempts == 0)
    }

    @Test("carries the timing the customer chose into the change")
    func carriesTheTimingTheCustomerChose() throws {
        let model = try preview(isUpgrade: false, isDowngrade: true)
        var state = try previewed(model)
        #expect(state.immediate)

        state = send(state, .confirmed(collectPayment: nil, immediate: false)).state
        #expect(state.step == .changing)
        #expect(state.immediate == false)
    }

    @Test("reports the server errorCode on a refusal")
    func reportsTheServerErrorCode() throws {
        let model = try preview()
        var state = try previewed(model)
        state = send(state, .confirmed(collectPayment: nil, immediate: nil)).state

        let token = try #require(state.token)
        state = send(
            state,
            .changeResult(
                token: token,
                result: changeResult(
                    errorMessage: "That change is already under way",
                    errorCode: TierChangeErrorCodes.tierChangeAlreadyInProgress
                )
            )
        ).state
        #expect(state.step == .failed)
        #expect(state.error == "That change is already under way")
        #expect(state.errorCode == "tier_change_already_in_progress")
        #expect(state.retryFrom == .changing)
    }

    @Test("collects a payment first on the legacy path")
    func collectsAPaymentFirstOnTheLegacyPath() throws {
        // paymentRequired with no bypass: the host's payment handler (or the built-in sheet) runs
        // before the change is posted at all.
        let model = try preview(paymentRequired: true, paymentBypassAllowed: false, newPrice: 39)
        var state = try previewed(model)
        state = send(state, .confirmed(collectPayment: nil, immediate: nil)).state
        #expect(state.step == .collectingPayment)

        state = send(state, .paymentCompleted(paymentTransactionId: "txn-9")).state
        #expect(state.step == .changing)
        #expect(state.paymentTransactionId == "txn-9")

        let token = try #require(state.token)
        state = send(state, .changeResult(token: token, result: changeResult(success: true))).state
        #expect(state.step == .done)
    }

    @Test("a cancelled payment goes back to the confirmation, not to a failure")
    func aCancelledPaymentGoesBackToTheConfirmation() throws {
        let model = try preview(paymentRequired: true)
        var state = try previewed(model)
        state = send(state, .confirmed(collectPayment: nil, immediate: nil)).state
        state = send(state, .paymentCancelled).state
        #expect(state.step == .confirm)
        #expect(state.error == nil)
    }

    @Test("ignores a result carrying a stale step token")
    func ignoresAStaleStepToken() throws {
        var state = send(
            PlanChangeMachine.initialState(),
            .previewRequested(appId: "app-1", tierId: "tier-pro", pricingId: nil, immediate: nil)
        ).state
        let stale = try #require(state.token)
        state = send(
            state,
            .previewRequested(appId: "app-1", tierId: "tier-pro", pricingId: nil, immediate: nil)
        ).state

        let model = try preview()
        let ignored = send(state, .previewReceived(token: stale, preview: model))
        #expect(ignored.applied == false)
        #expect(ignored.state == state)
        #expect(ignored.state.step == .previewing)
    }
}
