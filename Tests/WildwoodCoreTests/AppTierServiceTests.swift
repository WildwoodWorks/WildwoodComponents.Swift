// AppTierService behavior mirrored from the JS appTierService tests:
// public tier endpoint, empty-appId guard, PascalCase change DTO, Bool/dict returns.

import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct AppTierServiceTests {
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

    @Test func getTiersUsesPublicEndpointAndReturnsParsedTiers() async {
        let (service, backend) = makeService()
        backend.stub("GET", "/api/app-tiers/app-1/public", .init(json: #"[{"id":"t1"},{"id":"t2"}]"#))

        let tiers = await service.getTiers(appId: "app-1")

        #expect(tiers.count == 2)
        #expect(backend.requests().contains { $0.method == "GET" && $0.path == "/api/app-tiers/app-1/public" })
    }

    @Test func getTiersReturnsEmptyOnError() async {
        let (service, _) = makeService() // no stub -> []
        #expect(await service.getTiers(appId: "app-1").isEmpty)
    }

    @Test func getUserSubscriptionReturnsNilForEmptyAppIdWithoutRequest() async throws {
        let (service, backend) = makeService()

        let sub = try await service.getUserSubscription(appId: "")

        #expect(sub == nil)
        #expect(backend.requests().isEmpty)
    }

    @Test func getUserSubscriptionReturnsNilForNoContentButThrowsOnFailure() async throws {
        let (service, backend) = makeService()
        // Empty 2xx body → "no subscription", not an error.
        backend.stub("GET", "/api/app-tiers/app-1/my-subscription", .init(statusCode: 204, body: Data()))
        #expect(try await service.getUserSubscription(appId: "app-1") == nil)

        // A failed lookup must be distinguishable from "no subscription" —
        // subscribed users were shown "no plan" banners on transient errors
        // when both resolved to nil.
        let (service2, _) = makeService() // no stub → 404
        await #expect(throws: WildwoodError.self) {
            _ = try await service2.getUserSubscription(appId: "app-1")
        }
    }

    @Test func changeTierPostsPascalCasePayload() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/app-tiers/app-1/my-subscription/change", .init(json: "{}"))

        _ = try await service.changeTier(
            appId: "app-1", newTierId: "tier-2", newPricingId: "pricing-7", immediate: true, paymentTransactionId: "txn-9"
        )

        let req = try #require(backend.requests().first { $0.path == "/api/app-tiers/app-1/my-subscription/change" })
        let body = try jsonBody(req)
        #expect(body["NewAppTierId"] as? String == "tier-2")
        #expect(body["NewAppTierPricingId"] as? String == "pricing-7")
        #expect(body["Immediate"] as? Bool == true)
        #expect(body["PaymentTransactionId"] as? String == "txn-9")
    }

    @Test func cancelSubscriptionSurfacesTheScheduledPayloadAndReportsFailures() async {
        let (service, backend) = makeService()
        backend.stub(
            "POST", "/api/app-tiers/app-1/my-subscription/cancel",
            .init(json: #"{"isScheduled":true,"effectiveDate":"2026-08-01T00:00:00Z","requiresUserAction":true,"userActionInstructions":"Cancel in App Store settings."}"#)
        )

        let result = await service.cancelSubscription(appId: "app-1")
        #expect(result.success == true)
        #expect(result.isScheduled == true)
        #expect(result.effectiveDate != nil)
        #expect(result.requiresUserAction == true)
        #expect(result.userActionInstructions == "Cancel in App Store settings.")

        let failed = await service.cancelSubscription(appId: "app-2") // no stub → 404
        #expect(failed.success == false)
        #expect(failed.errorMessage?.isEmpty == false)
    }

    @Test func cancelSubscriptionSucceedsOnAnEmpty2xxBody() async {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/app-tiers/app-1/my-subscription/cancel", .init(statusCode: 200, body: Data()))

        let result = await service.cancelSubscription(appId: "app-1")

        #expect(result.success == true)
        #expect(result.isScheduled == false)
    }

    @Test func companyAndUserCancelsShareTheCancelResultShape() async {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/app-tiers/app-1/cancel/company/c1", .init(json: #"{"isScheduled":false}"#))
        backend.stub("POST", "/api/app-tiers/app-1/cancel/u1", .init(json: #"{"isScheduled":true}"#))

        let company = await service.cancelCompanySubscription(appId: "app-1", companyId: "c1")
        #expect(company.success == true)
        #expect(company.isScheduled == false)

        let user = await service.cancelUserSubscription(appId: "app-1", userId: "u1")
        #expect(user.success == true)
        #expect(user.isScheduled == true)
    }

    @Test func getUserFeaturesReturnsTheFeatureMapAndThrowsOnFailure() async throws {
        let (service, backend) = makeService()
        backend.stub("GET", "/api/app-tiers/app-1/user-features", .init(json: #"{"chat":true,"payments":false}"#))

        let features = try await service.getUserFeatures(appId: "app-1")

        #expect(features == ["chat": true, "payments": false])

        // Failures must not masquerade as an empty (= no access) map —
        // feature gates would lock entitled users out during transient errors.
        let (service2, _) = makeService() // no stub → 404
        await #expect(throws: WildwoodError.self) {
            _ = try await service2.getUserFeatures(appId: "app-1")
        }
    }
}
