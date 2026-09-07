// PaymentService behavior mirrored from the JS paymentService tests:
// endpoint/verb correctness, Bool return semantics, and request bodies.

import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct PaymentServiceTests {
    private func makeService() -> (PaymentService, MockBackend) {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        return (PaymentService(http: http), backend)
    }

    private func jsonBody(_ req: RecordedRequest) throws -> [String: Any] {
        let data = try #require(req.body)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func getAppPaymentConfigurationReturnsNilOnError() async {
        let (service, _) = makeService()
        // No stub -> 404 -> try? yields nil.
        #expect(await service.getAppPaymentConfiguration(appId: "app-1") == nil)
    }

    @Test func getAvailableProvidersRequestsTheProviderList() async throws {
        let (service, backend) = makeService()
        backend.stub("GET", "/api/payment/providers/app-1", .init(json: "{}"))

        _ = try await service.getAvailableProviders(appId: "app-1")

        #expect(backend.requests().contains { $0.method == "GET" && $0.path == "/api/payment/providers/app-1" })
    }

    @Test func requestRefundPostsTransactionAmountAndReason() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/payment/refund", .init(json: "{}"))

        _ = try await service.requestRefund(transactionId: "txn-9", amount: 4.25, reason: "duplicate")

        let req = try #require(backend.requests().first { $0.path == "/api/payment/refund" })
        let body = try jsonBody(req)
        #expect(body["transactionId"] as? String == "txn-9")
        #expect(body["amount"] as? Double == 4.25)
        #expect(body["reason"] as? String == "duplicate")
    }

    @Test func getPaymentStatusGetsStatusForTransaction() async throws {
        let (service, backend) = makeService()
        backend.stub("GET", "/api/payment/status/txn-7", .init(json: "{}"))

        _ = try await service.getPaymentStatus(transactionId: "txn-7")

        #expect(backend.requests().contains { $0.method == "GET" && $0.path == "/api/payment/status/txn-7" })
    }

    @Test func deleteSavedPaymentMethodReturnsTrueOnSuccessFalseOnError() async {
        let (service, backend) = makeService()
        backend.stub("DELETE", "/api/payment/methods/pm-1", .init(statusCode: 200))
        #expect(await service.deleteSavedPaymentMethod(paymentMethodId: "pm-1") == true)

        let (service2, _) = makeService() // no stub -> failure
        #expect(await service2.deleteSavedPaymentMethod(paymentMethodId: "pm-1") == false)
    }

    @Test func setDefaultPaymentMethodPostsToDefaultEndpoint() async {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/payment/methods/pm-9/default", .init(statusCode: 200))

        #expect(await service.setDefaultPaymentMethod(paymentMethodId: "pm-9") == true)
        #expect(backend.requests().contains { $0.method == "POST" && $0.path == "/api/payment/methods/pm-9/default" })
    }

    @Test func linkTransactionToUserPostsLinkPayload() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/paymenttransactions/link-by-external-id", .init(statusCode: 200))

        let ok = await service.linkTransactionToUser(externalTransactionId: "pi_123", userId: "u1")

        #expect(ok == true)
        let req = try #require(backend.requests().first { $0.path == "/api/paymenttransactions/link-by-external-id" })
        let body = try jsonBody(req)
        #expect(body["externalTransactionId"] as? String == "pi_123")
        #expect(body["userId"] as? String == "u1")
    }

    // MARK: - validateStorePurchase (IAP contract)

    @Test func validateStorePurchaseRoutesAppleToTheAppleEndpointWithTheFullBody() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/payment/validate-apple-receipt", .init(json: #"{"success":true,"transactionId":"ww-txn-1"}"#))

        _ = try await service.validateStorePurchase(
            appId: "app-1",
            purchase: StorePurchase(
                providerType: .appleAppStore,
                productId: "com.wildwood.pro.monthly",
                purchaseToken: "signed-jws"
            )
        )

        let req = try #require(backend.requests().first { $0.path == "/api/payment/validate-apple-receipt" })
        let body = try jsonBody(req)
        #expect(body["appId"] as? String == "app-1")
        #expect(body["providerType"] as? Int == 10)
        #expect(body["productId"] as? String == "com.wildwood.pro.monthly")
        #expect(body["purchaseToken"] as? String == "signed-jws")
        // The server binds receiptData, so the token is sent under both names.
        #expect(body["receiptData"] as? String == "signed-jws")
        // nil optionals are omitted, like `undefined` in the JS body.
        #expect(body.keys.contains("transactionId") == false)
        #expect(body.keys.contains("isRestore") == false)
    }

    @Test func validateStorePurchaseRoutesGoogleToTheGoogleEndpoint() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/payment/validate-google-receipt", .init(json: #"{"success":true}"#))

        _ = try await service.validateStorePurchase(
            appId: "app-1",
            purchase: StorePurchase(
                providerType: .googlePlayStore,
                productId: "pro_monthly",
                purchaseToken: "play-token"
            )
        )

        let req = try #require(backend.requests().first { $0.path == "/api/payment/validate-google-receipt" })
        let body = try jsonBody(req)
        #expect(body["providerType"] as? Int == 11)
        #expect(body["purchaseToken"] as? String == "play-token")
        #expect(body["receiptData"] as? String == "play-token")
    }

    @Test func validateStorePurchasePassesTheValidationResultThrough() async throws {
        let (service, backend) = makeService()
        backend.stub(
            "POST", "/api/payment/validate-apple-receipt",
            .init(json: #"{"success":true,"transactionId":"ww-txn-9","status":"completed"}"#)
        )

        let result = try await service.validateStorePurchase(
            appId: "app-1",
            purchase: StorePurchase(providerType: .appleAppStore, productId: "pro", purchaseToken: "jws")
        )

        #expect(result.success == true)
        #expect(result.transactionId == "ww-txn-9")
        #expect(result.status == "completed")
    }

    @Test func validateStorePurchaseIncludesTheStoreTransactionIdAndRestoreFlagWhenSet() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/payment/validate-apple-receipt", .init(json: #"{"success":true}"#))

        _ = try await service.validateStorePurchase(
            appId: "app-1",
            purchase: StorePurchase(
                providerType: .appleAppStore,
                productId: "pro",
                purchaseToken: "jws",
                transactionId: "store-txn-7",
                isRestore: true
            )
        )

        let req = try #require(backend.requests().first { $0.path == "/api/payment/validate-apple-receipt" })
        let body = try jsonBody(req)
        #expect(body["transactionId"] as? String == "store-txn-7")
        #expect(body["isRestore"] as? Bool == true)
    }

    @Test func validateStorePurchaseThrowsOnFailure() async {
        let (service, _) = makeService() // no stub → 404
        await #expect(throws: WildwoodError.self) {
            _ = try await service.validateStorePurchase(
                appId: "app-1",
                purchase: StorePurchase(providerType: .appleAppStore, productId: "pro", purchaseToken: "jws")
            )
        }
    }
}
