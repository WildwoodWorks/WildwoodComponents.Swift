// DisclaimerService behavior mirrored from the JS disclaimerService tests:
// default-appId fallback, single accept payload, and bulk accept mapping.

import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct DisclaimerServiceTests {
    private func makeService() -> (DisclaimerService, MockBackend) {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        return (DisclaimerService(http: http, defaultAppId: "default-app"), backend)
    }

    private func jsonBody(_ req: RecordedRequest) throws -> [String: Any] {
        let data = try #require(req.body)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func getPendingDisclaimersFallsBackToDefaultAppId() async throws {
        let (service, backend) = makeService()
        backend.stub("GET", "/api/disclaimeracceptance/pending/default-app", .init(json: "{}"))

        let result = try await service.getPendingDisclaimers()

        #expect(result.hasPendingDisclaimers == false)
        #expect(backend.requests().contains { $0.method == "GET" && $0.path == "/api/disclaimeracceptance/pending/default-app" })
    }

    @Test func getPendingDisclaimersPrefersExplicitAppId() async throws {
        let (service, backend) = makeService()
        backend.stub("GET", "/api/disclaimeracceptance/pending/other-app", .init(json: #"{"hasPendingDisclaimers":true,"disclaimers":[]}"#))

        let result = try await service.getPendingDisclaimers(appId: "other-app")

        #expect(result.hasPendingDisclaimers == true)
        #expect(backend.requests().contains { $0.path == "/api/disclaimeracceptance/pending/other-app" })
    }

    @Test func acceptDisclaimerPostsSinglePayloadWithResolvedAppId() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/disclaimeracceptance/accept", .init(json: #"{"success":true,"message":"ok"}"#))

        let result = try await service.acceptDisclaimer(disclaimerId: "disc-1", versionId: "ver-1")

        #expect(result.success == true)
        let req = try #require(backend.requests().first { $0.method == "POST" && $0.path == "/api/disclaimeracceptance/accept" })
        let body = try jsonBody(req)
        #expect(body["companyDisclaimerId"] as? String == "disc-1")
        #expect(body["companyDisclaimerVersionId"] as? String == "ver-1")
        #expect(body["appId"] as? String == "default-app")
    }

    @Test func acceptAllDisclaimersPostsBulkPayloadMappingIds() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/disclaimeracceptance/accept-bulk", .init(json: #"{"success":true}"#))

        let result = try await service.acceptAllDisclaimers(
            [
                DisclaimerAcceptanceInput(disclaimerId: "d1", versionId: "v1"),
                DisclaimerAcceptanceInput(disclaimerId: "d2", versionId: "v2"),
            ],
            appId: "app-x"
        )

        #expect(result.success == true)
        let req = try #require(backend.requests().first { $0.path == "/api/disclaimeracceptance/accept-bulk" })
        let body = try jsonBody(req)
        #expect(body["appId"] as? String == "app-x")
        let acceptances = try #require(body["acceptances"] as? [[String: Any]])
        #expect(acceptances.count == 2)
        #expect(acceptances[0]["companyDisclaimerId"] as? String == "d1")
        #expect(acceptances[1]["companyDisclaimerVersionId"] as? String == "v2")
    }
}
