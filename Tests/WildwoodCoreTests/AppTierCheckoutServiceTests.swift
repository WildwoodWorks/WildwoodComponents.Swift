// Ported case for case from @wildwood/core's src/__tests__/appTierService.checkout.test.ts:
// trial eligibility, the pack-checkout quartet, the pack lifecycle, the 3-D Secure plan change
// and the error mapper.
//
// Two Swift-only cases sit alongside the ported ones, because they pin behaviour the JS suite
// has no equivalent for: task cancellation must surface as CancellationError rather than being
// folded into a refusal, and the deprecated Bool cancel must now send `?immediate=false`.

import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct AppTierCheckoutServiceTests {
    private func makeService() -> (AppTierService, MockBackend) {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        return (AppTierService(http: http), backend)
    }

    private func jsonBody(_ req: RecordedRequest) throws -> [String: Any] {
        let data = try #require(req.body)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func lastRequest(_ backend: MockBackend, _ path: String) throws -> RecordedRequest {
        try #require(backend.requests().last { $0.path == path })
    }

    // MARK: - Trial eligibility

    @Test func trialEligibilityReadsTheEligibilityEndpoint() async throws {
        let (service, backend) = makeService()
        backend.stub(
            "GET", "/api/app-tiers/app-1/trial-eligibility",
            .init(json: #"{"tierTrialEligible":false,"addOns":{"radar":true}}"#)
        )

        let eligibility = try await service.trialEligibility(appId: "app-1")

        #expect(eligibility.tierTrialEligible == false)
        #expect(eligibility.addOns == ["radar": true])
        #expect(backend.requests().contains { $0.method == "GET" && $0.path == "/api/app-tiers/app-1/trial-eligibility" })
    }

    @Test func trialEligibilityAnswersEligiblePacksUnknownWhenTheLookupFails() async throws {
        let (service, _) = makeService() // no stub -> 404

        let eligibility = try await service.trialEligibility(appId: "app-1")

        #expect(eligibility.tierTrialEligible == true)
        #expect(eligibility.addOns.isEmpty)
    }

    // MARK: - Pack checkout

    @Test func quoteAddOnCheckoutPostsAPascalCaseItemListAndMapsTheAnswer() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/app-tier-addons/app-1/checkout/quote", .init(json: """
        {"success":true,"checkoutId":"co-1","providerId":"prov-1","currency":"USD",
         "lines":[{"addOnId":"radar","pricingId":"ap-1","name":"Radar","price":19,
                   "billingFrequency":"Monthly","trialDays":14,"trialEligible":true,"dueToday":0,
                   "trialEnd":"2026-10-01T00:00:00Z"}],
         "totalDueToday":0,"requiresPaymentMethod":false,
         "savedCard":{"brand":"visa","last4":"4242"}}
        """))

        let quote = try await service.quoteAddOnCheckout(
            appId: "app-1",
            items: [AddOnCheckoutItemInput(addOnId: "radar"), AddOnCheckoutItemInput(addOnId: "vault", pricingId: "ap-9")]
        )

        let req = try lastRequest(backend, "/api/app-tier-addons/app-1/checkout/quote")
        let items = try #require(try jsonBody(req)["Items"] as? [[String: Any]])
        #expect(items.count == 2)
        #expect(items[0]["AddOnId"] as? String == "radar")
        // An omitted pricing id means "the pack's default pricing" — the key is absent, not null.
        #expect(items[0].keys.contains("PricingId") == false)
        #expect(items[1]["AddOnId"] as? String == "vault")
        #expect(items[1]["PricingId"] as? String == "ap-9")

        #expect(quote.success == true)
        #expect(quote.checkoutId == "co-1")
        #expect(quote.currency == "USD")
        #expect(quote.lines.first?.dueToday == 0)
        #expect(quote.lines.first?.trialEnd != nil)
        #expect(quote.savedCard == AddOnCheckoutSavedCardModel(brand: "visa", last4: "4242"))
    }

    @Test func quoteKeepsTheRefusedQuoteTheServerSentErrorCodeAndAll() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/app-tier-addons/app-1/checkout/quote", .init(statusCode: 400, json: """
        {"success":false,"checkoutId":"co-2","currency":"USD","lines":[],"totalDueToday":0,
         "requiresPaymentMethod":false,"errorCode":"AlreadySubscribed",
         "errorMessage":"You already have that pack"}
        """))

        let quote = try await service.quoteAddOnCheckout(appId: "app-1", items: [AddOnCheckoutItemInput(addOnId: "radar")])

        #expect(quote.success == false)
        #expect(quote.checkoutId == "co-2")
        #expect(quote.errorCode == AddOnCheckoutErrorCodes.alreadySubscribed)
        #expect(quote.errorMessage == "You already have that pack")
    }

    @Test func quoteReportsAServerWithNoCheckoutRoutesAsNotSupportedAndQuotesNoCurrency() async throws {
        let (service, _) = makeService() // no stub -> 404, and the 404 body carries no error code

        let quote = try await service.quoteAddOnCheckout(appId: "app-1", items: [AddOnCheckoutItemInput(addOnId: "radar")])

        #expect(quote.success == false)
        #expect(quote.errorCode == AppTierActionErrorCodes.notSupported)
        // Nothing was priced, so nothing names a currency.
        #expect(quote.currency == "")
        #expect(quote.lines.isEmpty)
        #expect(quote.errorMessage?.isEmpty == false)
    }

    @Test func createCheckoutPaymentMethodStartsCardCollectionForOneProvider() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/app-tier-addons/app-1/checkout/payment-method", .init(json: """
        {"success":true,"clientSecret":"seti_1_secret","setupIntentId":"seti_1","paymentTransactionId":"txn-1"}
        """))

        let result = try await service.createCheckoutPaymentMethod(appId: "app-1", providerId: "prov-1")

        let body = try jsonBody(try lastRequest(backend, "/api/app-tier-addons/app-1/checkout/payment-method"))
        #expect(body["ProviderId"] as? String == "prov-1")
        #expect(result.success == true)
        #expect(result.clientSecret == "seti_1_secret")
        #expect(result.paymentTransactionId == "txn-1")
    }

    @Test func checkoutAddOnsBuysTheBasketAndReturnsAResultPerPack() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/app-tier-addons/app-1/checkout", .init(json: """
        {"success":true,"checkoutId":"co-1",
         "results":[{"addOnId":"radar","pricingId":"ap-1","status":"trialing","subscriptionId":"sub-1"},
                    {"addOnId":"vault","pricingId":"ap-2","status":"requires_action",
                     "clientSecret":"pi_1_secret","paymentTransactionId":"txn-2"}]}
        """))

        let result = try await service.checkoutAddOns(
            appId: "app-1",
            request: AddOnCheckoutRequestModel(
                checkoutId: "co-1",
                providerId: "prov-1",
                useSavedCard: true,
                items: [AddOnCheckoutItemInput(addOnId: "radar"), AddOnCheckoutItemInput(addOnId: "vault", pricingId: "ap-2")]
            )
        )

        let req = try lastRequest(backend, "/api/app-tier-addons/app-1/checkout")
        let body = try jsonBody(req)
        #expect(body["CheckoutId"] as? String == "co-1")
        #expect(body["ProviderId"] as? String == "prov-1")
        #expect(body["UseSavedCard"] as? Bool == true)
        #expect(body.keys.contains("PaymentTransactionId") == false)
        let items = try #require(body["Items"] as? [[String: Any]])
        #expect(items.count == 2)
        #expect(items[0].keys.contains("PricingId") == false)
        #expect(items[1]["PricingId"] as? String == "ap-2")

        #expect(result.results.map(\.status) == [AddOnCheckoutItemStatuses.trialing, AddOnCheckoutItemStatuses.requiresAction])
    }

    @Test func checkoutDefaultsUseSavedCardToFalseAndKeepsTheCheckoutIdOnARefusal() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/app-tier-addons/app-1/checkout", .init(statusCode: 400, json: #"{"error":"no card"}"#))

        let result = try await service.checkoutAddOns(
            appId: "app-1",
            request: AddOnCheckoutRequestModel(
                checkoutId: "co-3",
                providerId: "prov-1",
                paymentTransactionId: "txn-1",
                items: [AddOnCheckoutItemInput(addOnId: "radar")]
            )
        )

        let body = try jsonBody(try lastRequest(backend, "/api/app-tier-addons/app-1/checkout"))
        #expect(body["UseSavedCard"] as? Bool == false)
        #expect(body["PaymentTransactionId"] as? String == "txn-1")

        #expect(result.success == false)
        #expect(result.checkoutId == "co-3")
        #expect(result.results.isEmpty)
        #expect(result.errorCode == AppTierActionErrorCodes.requestFailed)
        #expect(result.errorMessage == "no card")
    }

    @Test func completeAddOnCheckoutCompletesOnePackAndKeepsThePackARefusalWasAbout() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/app-tier-addons/app-1/checkout/complete", .init(json: """
        {"addOnId":"radar","pricingId":"ap-1","status":"active","subscriptionId":"sub-9"}
        """))

        let result = try await service.completeAddOnCheckout(appId: "app-1", paymentTransactionId: "txn-2")

        let body = try jsonBody(try lastRequest(backend, "/api/app-tier-addons/app-1/checkout/complete"))
        #expect(body["PaymentTransactionId"] as? String == "txn-2")
        #expect(result.status == AddOnCheckoutItemStatuses.active)
        #expect(result.subscriptionId == "sub-9")

        backend.stub("POST", "/api/app-tier-addons/app-1/checkout/complete", .init(statusCode: 400, json: """
        {"addOnId":"radar","pricingId":"ap-1","status":"failed","errorCode":"PaymentNotVerified",
         "errorMessage":"Payment could not be verified"}
        """))

        let failed = try await service.completeAddOnCheckout(appId: "app-1", paymentTransactionId: "txn-2")

        #expect(failed.addOnId == "radar")
        #expect(failed.pricingId == "ap-1")
        #expect(failed.status == AddOnCheckoutItemStatuses.failed)
        #expect(failed.errorCode == AddOnCheckoutErrorCodes.paymentNotVerified)
        #expect(failed.errorMessage == "Payment could not be verified")
    }

    // MARK: - Pack lifecycle

    @Test func subscribeToAddOnDetailedReturnsTheSubscriptionOrAStructuredRefusal() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/app-tier-addons/app-1/subscribe", .init(json: """
        {"id":"sub-1","userId":"u-1","appId":"app-1","appTierAddOnId":"radar"}
        """))

        let created = try await service.subscribeToAddOnDetailed(
            appId: "app-1", addOnId: "radar", pricingId: "ap-1", paymentTransactionId: "txn-1"
        )

        let body = try jsonBody(try lastRequest(backend, "/api/app-tier-addons/app-1/subscribe"))
        #expect(body["AppId"] as? String == "app-1")
        #expect(body["AppTierAddOnId"] as? String == "radar")
        #expect(body["AppTierAddOnPricingId"] as? String == "ap-1")
        #expect(body["PaymentTransactionId"] as? String == "txn-1")
        #expect(created.success == true)
        #expect(created.subscription?.id == "sub-1")
        #expect(created.error == nil)

        backend.stub("POST", "/api/app-tier-addons/app-1/subscribe", .init(statusCode: 400, json: """
        {"errorCode":"BundledInTier","errorMessage":"Already in your plan"}
        """))

        let refused = try await service.subscribeToAddOnDetailed(appId: "app-1", addOnId: "radar")

        #expect(refused.success == false)
        #expect(refused.subscription == nil)
        #expect(refused.error == AppTierActionError(code: "BundledInTier", message: "Already in your plan", status: 400))
    }

    @Test func cancelAddOnDetailedPassesTheImmediateFlagAndSurfacesTheSchedule() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/app-tier-addons/subscriptions/sub-1/cancel", .init(json: """
        {"isScheduled":true,"status":"Active","effectiveDate":"2026-10-01T00:00:00Z"}
        """))

        let scheduled = try await service.cancelAddOnDetailed(subscriptionId: "sub-1")

        #expect(scheduled.success == true)
        #expect(scheduled.isScheduled == true)
        #expect(scheduled.status == "Active")
        #expect(scheduled.effectiveDate != nil)
        #expect(scheduled.errorCode == nil)
        let scheduledRequest = try lastRequest(backend, "/api/app-tier-addons/subscriptions/sub-1/cancel")
        #expect(scheduledRequest.query == "immediate=false")

        _ = try await service.cancelAddOnDetailed(subscriptionId: "sub-1", immediate: true)

        let immediateRequest = try lastRequest(backend, "/api/app-tier-addons/subscriptions/sub-1/cancel")
        #expect(immediateRequest.query == "immediate=true")
    }

    @Test func cancelAddOnDetailedKeepsTheServerErrorCodeOnA404ThatCarriesOne() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/app-tier-addons/subscriptions/sub-nope/cancel", .init(statusCode: 404, json: """
        {"error":"Add-on subscription not found","errorCode":"addon_subscription_not_found"}
        """))

        let result = try await service.cancelAddOnDetailed(subscriptionId: "sub-nope")

        #expect(result.success == false)
        #expect(result.errorCode == AddOnSubscriptionErrorCodes.notFound)
        #expect(result.errorMessage == "Add-on subscription not found")
    }

    @Test func reactivateAddOnReturnsTheRestoredSubscription() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/app-tier-addons/subscriptions/sub-1/reactivate", .init(json: """
        {"id":"sub-1","userId":"u-1","appId":"app-1","status":"Active"}
        """))

        let result = try await service.reactivateAddOn(subscriptionId: "sub-1")

        #expect(result.success == true)
        #expect(result.status == "Active")
        #expect(result.subscription?.id == "sub-1")

        backend.stub("POST", "/api/app-tier-addons/subscriptions/sub-1/reactivate", .init(statusCode: 400, json: """
        {"error":"Not scheduled to cancel","errorCode":"addon_subscription_not_pending_cancellation"}
        """))

        let refused = try await service.reactivateAddOn(subscriptionId: "sub-1")

        #expect(refused.success == false)
        #expect(refused.errorCode == AddOnSubscriptionErrorCodes.notPendingCancellation)
        #expect(refused.errorMessage == "Not scheduled to cancel")
    }

    @Test func aNetworkFailureBecomesRequestFailedNotNotSupported() async throws {
        let (service, backend) = makeService()
        backend.stubError("POST", "/api/app-tier-addons/subscriptions/sub-1/cancel", .cannotConnectToHost)

        let result = try await service.cancelAddOnDetailed(subscriptionId: "sub-1")

        #expect(result.success == false)
        #expect(result.errorCode == AppTierActionErrorCodes.requestFailed)
        #expect(result.errorMessage?.isEmpty == false)
    }

    @Test func cancellationPropagatesInsteadOfBecomingARefusal() async throws {
        let (service, backend) = makeService()
        backend.stubError("POST", "/api/app-tier-addons/app-1/checkout/quote", .cancelled)
        backend.stubError("POST", "/api/app-tier-addons/subscriptions/sub-1/cancel", .cancelled)

        // A cancelled task is not a refused request: folding it into a `success:false` result
        // would make a torn-down screen look like a server that said no.
        await #expect(throws: CancellationError.self) {
            _ = try await service.quoteAddOnCheckout(appId: "app-1", items: [AddOnCheckoutItemInput(addOnId: "radar")])
        }
        await #expect(throws: CancellationError.self) {
            _ = try await service.cancelAddOnDetailed(subscriptionId: "sub-1")
        }
    }

    @Test func theDeprecatedBooleanWrappersStillAnswerTrueOrFalse() async throws {
        let (service, backend) = makeService()

        backend.stub("POST", "/api/app-tier-addons/app-1/subscribe", .init(json: #"{"id":"sub-1"}"#))
        #expect(await service.subscribeToAddOn(appId: "app-1", addOnId: "radar") == true)

        backend.stub("POST", "/api/app-tier-addons/app-1/subscribe", .init(statusCode: 400, json: #"{"errorCode":"TierTooLow"}"#))
        #expect(await service.subscribeToAddOn(appId: "app-1", addOnId: "radar") == false)

        backend.stub("POST", "/api/app-tier-addons/subscriptions/sub-1/cancel", .init(json: #"{"isScheduled":true}"#))
        #expect(await service.cancelAddOnSubscription(subscriptionId: "sub-1") == true)
        // Delegating to the detailed method means the deprecated wrapper now states the default.
        let cancelRequest = try lastRequest(backend, "/api/app-tier-addons/subscriptions/sub-1/cancel")
        #expect(cancelRequest.query == "immediate=false")

        backend.stub("POST", "/api/app-tier-addons/subscriptions/sub-2/cancel", .init(statusCode: 404, json: #"{"message":"Not Found"}"#))
        #expect(await service.cancelAddOnSubscription(subscriptionId: "sub-2") == false)
    }

    // MARK: - 3-D Secure plan change

    @Test func theOptionsOverloadPostsSupportsPaymentAction() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/app-tiers/app-1/my-subscription/change", .init(json: """
        {"success":false,"requiresAction":true,"clientSecret":"pi_1_secret","pendingChangeId":"pc-1",
         "amountDue":20,"currency":"USD"}
        """))

        let result = try await service.changeTier(
            appId: "app-1",
            options: SelfChangeTierOptions(newTierId: "tier-2", newPricingId: "pricing-7", supportsPaymentAction: true)
        )

        let body = try jsonBody(try lastRequest(backend, "/api/app-tiers/app-1/my-subscription/change"))
        #expect(body["NewAppTierId"] as? String == "tier-2")
        #expect(body["NewAppTierPricingId"] as? String == "pricing-7")
        #expect(body["Immediate"] as? Bool == true)
        #expect(body.keys.contains("PaymentTransactionId") == false)
        #expect(body["SupportsPaymentAction"] as? Bool == true)

        // "Authenticate this charge" arrives with success:false and is data, not a refusal.
        #expect(result.success == false)
        #expect(result.requiresAction == true)
        #expect(result.pendingChangeId == "pc-1")
        #expect(result.clientSecret == "pi_1_secret")
        #expect(result.amountDue == 20)
    }

    @Test func thePositionalOverloadPostsExactlyWhatItAlwaysDid() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/app-tiers/app-1/my-subscription/change", .init(json: #"{"success":true}"#))

        _ = try await service.changeTier(
            appId: "app-1", newTierId: "tier-2", newPricingId: "pricing-7", immediate: true, paymentTransactionId: "txn-9"
        )

        let body = try jsonBody(try lastRequest(backend, "/api/app-tiers/app-1/my-subscription/change"))
        #expect(body["NewAppTierId"] as? String == "tier-2")
        #expect(body["NewAppTierPricingId"] as? String == "pricing-7")
        #expect(body["Immediate"] as? Bool == true)
        #expect(body["PaymentTransactionId"] as? String == "txn-9")
        // An older server rejects an unknown property, so the positional form must not grow one.
        #expect(body.keys.contains("SupportsPaymentAction") == false)
    }

    @Test func completeTierChangePostsTheParkedChangeIdAndReportsRefusalsStructurally() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/app-tiers/app-1/my-subscription/change/pc-1/complete", .init(json: """
        {"success":true,"isScheduled":false,"subscription":{"id":"sub-1"}}
        """))

        let done = try await service.completeTierChange(appId: "app-1", pendingChangeId: "pc-1")

        #expect(done.success == true)
        #expect(backend.requests().contains {
            $0.method == "POST" && $0.path == "/api/app-tiers/app-1/my-subscription/change/pc-1/complete"
        })

        backend.stub("POST", "/api/app-tiers/app-1/my-subscription/change/pc-1/complete", .init(statusCode: 400, json: """
        {"errorCode":"pending_change_expired","error":"That change lapsed"}
        """))

        let expired = try await service.completeTierChange(appId: "app-1", pendingChangeId: "pc-1")

        #expect(expired.success == false)
        #expect(expired.isScheduled == false)
        #expect(expired.errorCode == TierChangeErrorCodes.pendingChangeExpired)
        #expect(expired.errorMessage == "That change lapsed")
    }

    @Test func completeTierChangeReturnsProcessingAsData() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/app-tiers/app-1/my-subscription/change/pc-1/complete", .init(json: """
        {"success":false,"processing":true}
        """))

        let pending = try await service.completeTierChange(appId: "app-1", pendingChangeId: "pc-1")

        // "The payment is in, the processor has not finished" is not a refusal: no code is set.
        #expect(pending.success == false)
        #expect(pending.processing == true)
        #expect(pending.errorCode == nil)
    }

    // MARK: - Error mapper

    @Test func actionErrorPrefersTheServerCodeNamesABare404NotSupportedAndFallsBack() {
        struct Boom: Error {}

        let coded = WildwoodError.fromResponse(
            status: 404,
            body: Data(#"{"errorCode":"addon_subscription_not_found","error":"nope"}"#.utf8),
            fallbackMessage: "Request failed"
        )
        #expect(
            AppTierActionError.from(coded, fallbackMessage: "fallback")
                == AppTierActionError(code: "addon_subscription_not_found", message: "nope", status: 404)
        )

        // A 404 with no code at all is the route itself being absent — a server older than this SDK.
        #expect(
            AppTierActionError.from(WildwoodError(message: "Not Found", status: 404), fallbackMessage: "fallback")
                == AppTierActionError(code: AppTierActionErrorCodes.notSupported, message: "Not Found", status: 404)
        )

        #expect(
            AppTierActionError.from(WildwoodError(message: "Server Error", status: 500), fallbackMessage: "fallback")
                == AppTierActionError(code: AppTierActionErrorCodes.requestFailed, message: "Server Error", status: 500)
        )

        // An error carrying no message of its own falls back to the caller's wording, never blank.
        #expect(
            AppTierActionError.from(Boom(), fallbackMessage: "fallback")
                == AppTierActionError(code: AppTierActionErrorCodes.requestFailed, message: "fallback")
        )
    }
}
