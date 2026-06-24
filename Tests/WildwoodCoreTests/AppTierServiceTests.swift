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

    @Test func getUserSubscriptionReturnsNilForEmptyAppIdWithoutRequest() async {
        let (service, backend) = makeService()

        let sub = await service.getUserSubscription(appId: "")

        #expect(sub == nil)
        #expect(backend.requests().isEmpty)
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

    @Test func cancelSubscriptionReturnsTrueThenFalse() async {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/app-tiers/app-1/my-subscription/cancel", .init(statusCode: 200))
        #expect(await service.cancelSubscription(appId: "app-1") == true)

        let (service2, _) = makeService() // no stub -> false
        #expect(await service2.cancelSubscription(appId: "app-1") == false)
    }

    @Test func getUserFeaturesReturnsTheFeatureMap() async {
        let (service, backend) = makeService()
        backend.stub("GET", "/api/app-tiers/app-1/user-features", .init(json: #"{"chat":true,"payments":false}"#))

        let features = await service.getUserFeatures(appId: "app-1")

        #expect(features == ["chat": true, "payments": false])
    }
}
