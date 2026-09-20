// WildwoodPackCheckoutModel: one quote, one card at most, one purchase, then each pack the bank
// wants authenticated, in order.
//
// The rules these pin are the ones a stack with no payment SDK has to get right: a card is never
// asked for when nothing can confirm one (`createCheckoutPaymentMethod` must not be called), a
// basket with a card already on file is still bought (`UseSavedCard`), a pack the bank wants
// authenticated is reported as NOT COMPLETED with the finish-on-the-web copy rather than silently
// failed, and nothing is quoted or bought twice.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct PackCheckoutModelTests {
    private static let appId = "app-1"

    private var quotePath: String { "/api/app-tier-addons/\(Self.appId)/checkout/quote" }
    private var cardPath: String { "/api/app-tier-addons/\(Self.appId)/checkout/payment-method" }
    private var checkoutPath: String { "/api/app-tier-addons/\(Self.appId)/checkout" }
    private var completePath: String { "/api/app-tier-addons/\(Self.appId)/checkout/complete" }
    private var paymentConfigPath: String { "/api/payment/configuration/\(Self.appId)" }

    private let items: [AddOnCheckoutItemInput] = [AddOnCheckoutItemInput(addOnId: "pack-a")]

    private func stubQuote(_ backend: TestBackend, requiresPaymentMethod: Bool) {
        backend.stub(
            "POST",
            quotePath,
            TestStubResponse(
                json: """
                {"success":true,"checkoutId":"co-1","providerId":"prov-1","currency":"USD",
                 "requiresPaymentMethod":\(requiresPaymentMethod),"totalDueToday":10,
                 "lines":[{"addOnId":"pack-a","pricingId":"ap-1","name":"Pack A","price":10,
                           "billingFrequency":"Monthly","trialDays":0,"trialEligible":false,"dueToday":10}]}
                """
            )
        )
    }

    private func stubPaymentConfig(_ backend: TestBackend) {
        backend.stub(
            "GET",
            paymentConfigPath,
            TestStubResponse(
                json: """
                {"appId":"\(Self.appId)","providers":[
                  {"id":"prov-1","name":"Stripe","providerType":1,"isEnabled":true,"isDefault":true,
                   "publishableKey":"pk_test_1"}],
                 "defaultProviderId":"prov-1"}
                """
            )
        )
    }

    private func makeModel(
        _ backend: TestBackend,
        handler: (any WildwoodPaymentActionHandler)?,
        items: [AddOnCheckoutItemInput]? = nil
    ) -> WildwoodPackCheckoutModel {
        WildwoodPackCheckoutModel(
            client: makeTestClient(backend, appId: Self.appId),
            appId: Self.appId,
            items: items ?? self.items,
            names: ["pack-a": "Pack A", "pack-b": "Pack B"],
            paymentActionHandler: handler,
            issuer: StepTokenIssuer()
        )
    }

    // MARK: - The saved-card branch

    @Test func aBasketWithACardOnFileIsBoughtWithoutCollectingOne() async {
        let backend = TestBackend()
        stubQuote(backend, requiresPaymentMethod: false)
        backend.stub(
            "POST",
            checkoutPath,
            TestStubResponse(
                json: """
                {"success":true,"checkoutId":"co-1",
                 "results":[{"addOnId":"pack-a","pricingId":"ap-1","status":"active"}]}
                """
            )
        )

        let model = makeModel(backend, handler: nil)
        let packs = Recorder<[SignupPackOutcome]>()
        model.onFinished = { packs.record($0) }
        model.start()
        await waitUntil { model.step == .done || model.step == .failed }

        #expect(model.step == .done)
        // No handler and no card asked for: the server said one was already on file.
        #expect(requestCount(backend, path: cardPath) == 0)
        let sent = bodies(backend, path: checkoutPath).first ?? ""
        #expect(sent.contains("\"UseSavedCard\":true"))
        let settled: [SignupPackOutcome] = packs.last ?? []
        #expect(settled.count == 1)
        #expect(settled.first?.status == AddOnCheckoutItemStatuses.active)
        #expect(settled.first?.name == "Pack A")
    }

    // MARK: - The card-once branch

    @Test func aHandlerThatCanSaveACardCollectsOneForTheWholeBasket() async {
        let backend = TestBackend()
        stubQuote(backend, requiresPaymentMethod: true)
        stubPaymentConfig(backend)
        backend.stub(
            "POST",
            cardPath,
            TestStubResponse(
                json: """
                {"success":true,"clientSecret":"seti_secret","setupIntentId":"seti_1",
                 "paymentTransactionId":"txn-1"}
                """
            )
        )
        backend.stub(
            "POST",
            checkoutPath,
            TestStubResponse(
                json: """
                {"success":true,"checkoutId":"co-1",
                 "results":[{"addOnId":"pack-a","pricingId":"ap-1","status":"trialing"}]}
                """
            )
        )

        let handler = RecordingPaymentActionHandler()
        let model = makeModel(backend, handler: handler)
        model.start()
        await waitUntil { model.step == .done || model.step == .failed }

        #expect(model.step == .done)
        #expect(requestCount(backend, path: cardPath) == 1)
        #expect(handler.recorded().count == 1)
        #expect(handler.recorded().first?.kind == .cardSetup)
        #expect(handler.recorded().first?.clientSecret == "seti_secret")
        let sent = bodies(backend, path: checkoutPath).first ?? ""
        #expect(sent.contains("\"PaymentTransactionId\":\"txn-1\""))
        #expect(sent.contains("\"UseSavedCard\":false"))
    }

    @Test func aPaymentOnlyHandlerNeverAsksForASetupIntent() async {
        let backend = TestBackend()
        stubQuote(backend, requiresPaymentMethod: true)
        stubPaymentConfig(backend)

        // Can answer a 3-D Secure challenge, cannot save a card.
        let handler = RecordingPaymentActionHandler(supportsCardSetup: false)
        let model = makeModel(backend, handler: handler)
        model.start()
        await waitUntil { model.step == .failed }

        #expect(model.canCollectCard == false)
        #expect(requestCount(backend, path: cardPath) == 0)
        #expect(model.error == RegistrationSubscriptionDriverLabels.defaults.finishOnWeb)
        #expect(handler.recorded().isEmpty)
    }

    @Test func withNoHandlerNoCardIsEverCollected() async {
        let backend = TestBackend()
        stubQuote(backend, requiresPaymentMethod: true)
        stubPaymentConfig(backend)

        let model = makeModel(backend, handler: nil)
        let reported = Recorder<RegistrationSubscriptionError>()
        model.onError = { reported.record($0) }
        model.start()
        await waitUntil { model.step == .failed }

        #expect(requestCount(backend, path: cardPath) == 0)
        #expect(requestCount(backend, path: checkoutPath) == 0)
        #expect(model.error == RegistrationSubscriptionDriverLabels.defaults.finishOnWeb)
        #expect(reported.first?.code == RegistrationSubscriptionErrorCodes.packCardFailed)
    }

    // MARK: - Per-item 3-D Secure

    @Test func everyPackTheBankWantsIsAuthenticatedOneAtATime() async {
        let backend = TestBackend()
        stubQuote(backend, requiresPaymentMethod: false)
        stubPaymentConfig(backend)
        backend.stub(
            "POST",
            checkoutPath,
            TestStubResponse(
                json: """
                {"success":true,"checkoutId":"co-1","results":[
                  {"addOnId":"pack-a","pricingId":"ap-1","status":"requires_action",
                   "clientSecret":"pi_a","paymentTransactionId":"txn-a"},
                  {"addOnId":"pack-b","pricingId":"bp-1","status":"requires_action",
                   "clientSecret":"pi_b","paymentTransactionId":"txn-b"}]}
                """
            )
        )
        backend.stub(
            "POST",
            completePath,
            TestStubResponse(json: #"{"addOnId":"","pricingId":"","status":"active"}"#)
        )

        let handler = RecordingPaymentActionHandler()
        let model = makeModel(
            backend,
            handler: handler,
            items: [AddOnCheckoutItemInput(addOnId: "pack-a"), AddOnCheckoutItemInput(addOnId: "pack-b")]
        )
        let packs = Recorder<[SignupPackOutcome]>()
        model.onFinished = { packs.record($0) }
        model.start()
        await waitUntil { model.step == .done || model.step == .failed }

        #expect(model.step == .done)
        let calls = handler.recorded()
        #expect(calls.count == 2)
        #expect(calls.first?.clientSecret == "pi_a")
        #expect(calls.last?.clientSecret == "pi_b")
        #expect(requestCount(backend, path: completePath) == 2)
        let settled: [SignupPackOutcome] = packs.last ?? []
        #expect(settled.count == 2)
        // The completion answered with an empty pack id; the item's own id is kept.
        #expect(settled.first?.addOnId == "pack-a")
        #expect(settled.first?.status == AddOnCheckoutItemStatuses.active)
        #expect(settled.last?.addOnId == "pack-b")
    }

    @Test func aChallengeNobodyCanAnswerIsReportedAsFinishOnTheWeb() async {
        let backend = TestBackend()
        stubQuote(backend, requiresPaymentMethod: false)
        backend.stub(
            "POST",
            checkoutPath,
            TestStubResponse(
                json: """
                {"success":true,"checkoutId":"co-1","results":[
                  {"addOnId":"pack-a","pricingId":"ap-1","status":"requires_action",
                   "clientSecret":"pi_a","paymentTransactionId":"txn-a"}]}
                """
            )
        )

        let model = makeModel(backend, handler: nil)
        let packs = Recorder<[SignupPackOutcome]>()
        model.onFinished = { packs.record($0) }
        model.start()
        await waitUntil { model.step == .done || model.step == .failed }

        #expect(model.step == .done)
        #expect(requestCount(backend, path: completePath) == 0)
        let settled: [SignupPackOutcome] = packs.last ?? []
        #expect(settled.count == 1)
        #expect(settled.first?.status == SignupPackStatuses.failed)
        #expect(settled.first?.errorMessage == RegistrationSubscriptionDriverLabels.defaults.finishOnWeb)
    }

    // MARK: - Idempotency

    @Test func aDoubledStartQuotesAndBuysExactlyOnce() async {
        let backend = TestBackend()
        stubQuote(backend, requiresPaymentMethod: false)
        backend.stub(
            "POST",
            checkoutPath,
            TestStubResponse(
                json: """
                {"success":true,"checkoutId":"co-1",
                 "results":[{"addOnId":"pack-a","pricingId":"ap-1","status":"active"}]}
                """
            )
        )

        let finished = CallCounter()
        let model = makeModel(backend, handler: nil)
        model.onFinished = { _ in finished.bump() }
        model.start()
        model.start()
        model.start()
        await waitUntil { model.step == .done || model.step == .failed }

        #expect(requestCount(backend, path: quotePath) == 1)
        #expect(requestCount(backend, path: checkoutPath) == 1)
        #expect(finished.count == 1)
    }

    @Test func skippingReportsEveryRequestedPackRatherThanForgettingThem() async {
        let backend = TestBackend()
        backend.stub(
            "POST",
            quotePath,
            TestStubResponse(json: #"{"success":false,"errorCode":"AddOnNotAvailable","errorMessage":"Not on sale."}"#)
        )

        let model = makeModel(backend, handler: nil)
        let packs = Recorder<[SignupPackOutcome]>()
        model.onFinished = { packs.record($0) }
        model.start()
        await waitUntil { model.step == .failed }

        #expect(model.error == "Not on sale.")
        model.skip()
        let settled: [SignupPackOutcome] = packs.last ?? []
        #expect(settled.count == 1)
        #expect(settled.first?.status == SignupPackStatuses.failed)
        #expect(settled.first?.errorMessage == "Not on sale.")

        // Finishing is once and for all: a second skip cannot double-report.
        model.skip()
        #expect(packs.count == 1)
    }

    // MARK: - Teardown

    @Test func detachSilencesTheCallbacksAndStartsNothingNew() async {
        let backend = TestBackend()
        stubQuote(backend, requiresPaymentMethod: false)

        let model = makeModel(backend, handler: nil)
        let finished = CallCounter()
        model.onFinished = { _ in finished.bump() }
        model.detach()
        model.start()
        await waitUntil(timeout: 0.2) { requestCount(backend, path: quotePath) > 0 }

        #expect(requestCount(backend, path: quotePath) == 0)
        #expect(finished.count == 0)
        model.detach()
    }
}
