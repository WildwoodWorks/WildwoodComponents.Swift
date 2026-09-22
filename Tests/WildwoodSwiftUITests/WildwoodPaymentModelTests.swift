// WildwoodPaymentModel — what PaymentComponent decides before a request goes out.
//
// Three things are pinned here, each of them a bug when it was missing: the pricing MODEL id
// goes up (without it the server charges once and creates no subscription, JS 05dd7cb); a second
// press for the same plan reuses the initiation instead of starting a second subscription
// (f8b095f); and `supportsSetupIntent` is NEVER sent, because nothing in this package can
// confirm a SetupIntent and one nobody confirms leaves a trial with no saved card.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct WildwoodPaymentModelTests {
    private static let initiatePath = "/api/payment/initiate"

    private func makeModel(_ backend: TestBackend) -> WildwoodPaymentModel {
        let client = WildwoodClient(
            config: WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false, storage: .memory),
            urlSession: backend.makeSession()
        )
        return WildwoodPaymentModel(payment: client.payment)
    }

    private func attempt(
        amount: Double = 79,
        pricingModelId: String? = "pm-1",
        isSubscription: Bool = true,
        trialDays: Int? = nil
    ) -> WildwoodPaymentAttempt {
        WildwoodPaymentAttempt(
            providerId: "prov-1",
            appId: "app-1",
            amount: amount,
            currency: "USD",
            description: "Pro",
            pricingModelId: pricingModelId,
            billingFrequency: "Monthly",
            isSubscription: isSubscription,
            trialDays: trialDays
        )
    }

    private func initiateCalls(_ backend: TestBackend) -> [TestRecordedRequest] {
        backend.requests().filter { $0.method == "POST" && $0.path == Self.initiatePath }
    }

    // MARK: - The request

    @Test func theRequestCarriesThePricingModelAndTheSubscriptionFlag() {
        let request = WildwoodPaymentModel.makeRequest(attempt())
        #expect(request.pricingModelId == "pm-1")
        #expect(request.isSubscription == true)
        #expect(request.billingFrequency == "Monthly")
        #expect(request.amount == 79)
    }

    @Test func aOneOffChargeOmitsTheSubscriptionFlag() {
        let request = WildwoodPaymentModel.makeRequest(attempt(isSubscription: false))
        // nil, not false: a synthesised Encodable omits the key entirely, which is what JS's
        // `undefined` does and what an older server expects.
        #expect(request.isSubscription == nil)
    }

    @Test func supportsSetupIntentIsNeverSet() async throws {
        let backend = TestBackend()
        backend.stub("POST", Self.initiatePath, .init(json: #"{"success":true,"paymentIntentId":"pi_1"}"#))
        let model = makeModel(backend)

        #expect(WildwoodPaymentModel.makeRequest(attempt(trialDays: 14)).supportsSetupIntent == nil)

        _ = try await model.initiate(attempt(trialDays: 14))

        let sent = try #require(initiateCalls(backend).first)
        let body = try #require(sent.body)
        let text = try #require(String(data: body, encoding: .utf8))
        #expect(text.contains("supportsSetupIntent") == false)
        #expect(text.contains("pricingModelId"))
    }

    // MARK: - Intent reuse

    @Test func aSecondPressForTheSamePlanReusesTheInitiation() async throws {
        let backend = TestBackend()
        backend.stub("POST", Self.initiatePath, .init(json: #"{"success":true,"paymentIntentId":"pi_1"}"#))
        let model = makeModel(backend)

        let first = try await model.initiate(attempt())
        let second = try await model.initiate(attempt())

        #expect(first.paymentIntentId == "pi_1")
        #expect(second.paymentIntentId == "pi_1")
        // The decline-and-retry path: one subscription, not two.
        #expect(initiateCalls(backend).count == 1)
    }

    @Test func aDifferentAmountIsADifferentIntent() async throws {
        let backend = TestBackend()
        backend.stub("POST", Self.initiatePath, .init(json: #"{"success":true,"paymentIntentId":"pi_1"}"#))
        let model = makeModel(backend)

        _ = try await model.initiate(attempt(amount: 79))
        _ = try await model.initiate(attempt(amount: 99))

        #expect(initiateCalls(backend).count == 2)
    }

    @Test func aFailedInitiationIsNotReused() async throws {
        let backend = TestBackend()
        backend.stub("POST", Self.initiatePath, .init(json: #"{"success":false,"errorMessage":"Declined"}"#))
        let model = makeModel(backend)

        _ = try await model.initiate(attempt())
        _ = try await model.initiate(attempt())

        #expect(initiateCalls(backend).count == 2)
    }

    @Test func changingThePlanDropsTheReusableInitiation() async throws {
        let backend = TestBackend()
        backend.stub("POST", Self.initiatePath, .init(json: #"{"success":true,"paymentIntentId":"pi_1"}"#))
        let model = makeModel(backend)

        model.setPlan(attempt())
        _ = try await model.initiate(attempt())
        // The form is reused for another plan at the same price: the intent must not carry over.
        model.setPlan(attempt(pricingModelId: "pm-2"))
        _ = try await model.initiate(attempt(pricingModelId: "pm-2"))

        #expect(initiateCalls(backend).count == 2)
    }

    @Test func clearingThePendingIntentForcesAFreshInitiation() async throws {
        let backend = TestBackend()
        backend.stub("POST", Self.initiatePath, .init(json: #"{"success":true,"paymentIntentId":"pi_1"}"#))
        let model = makeModel(backend)

        _ = try await model.initiate(attempt())
        model.clearPendingIntent()
        _ = try await model.initiate(attempt())

        #expect(initiateCalls(backend).count == 2)
    }

    @Test func theIntentKeyDistinguishesPlanAmountAndSubscriptionness() {
        let base = WildwoodPaymentModel.intentKey(attempt())
        #expect(WildwoodPaymentModel.intentKey(attempt()) == base)
        #expect(WildwoodPaymentModel.intentKey(attempt(amount: 99)) != base)
        #expect(WildwoodPaymentModel.intentKey(attempt(pricingModelId: "pm-2")) != base)
        #expect(WildwoodPaymentModel.intentKey(attempt(isSubscription: false)) != base)
        // The trial is copy, not money: it does not change which intent is being confirmed.
        #expect(WildwoodPaymentModel.intentKey(attempt(trialDays: 14)) == base)
    }

    // MARK: - Copy

    @Test func theButtonStartsATrialRatherThanBuyingOne() {
        #expect(
            WildwoodPaymentModel.payButtonLabel(amount: 79, currency: "USD", trialDays: 14)
                == "Start 14-day free trial"
        )
        #expect(WildwoodPaymentModel.payButtonLabel(amount: 79, currency: "USD", trialDays: 0) == "Pay $79.00")
        #expect(WildwoodPaymentModel.payButtonLabel(amount: 79, currency: "CHF", trialDays: nil) == "Pay CHF\u{00A0}79.00")
        #expect(WildwoodPaymentModel.payButtonLabel(amount: 0, currency: "USD", trialDays: nil) == "Pay")
    }

    @Test func theTrialNoteSaysWhatIsDueAndWhen() {
        #expect(
            WildwoodPaymentModel.trialChargeNote(amount: 79, currency: "USD")
                == "You won't be charged today. $79.00 is due when the trial ends unless you cancel before then."
        )
    }
}
