// AIService session/config/TTS behavior mirrored from the JS aiService tests.
// (sendMessage/proxy paths are covered indirectly; here we exercise the CRUD
// and Bool-returning session methods that don't need an AIChatRequest fixture.)

import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct AIServiceTests {
    private func makeService(appId: String? = nil) -> (AIService, MockBackend) {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        return (AIService(http: http, appId: appId), backend)
    }

    private func jsonBody(_ req: RecordedRequest) throws -> [String: Any] {
        let data = try #require(req.body)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func getConfigurationsReturnsTheList() async throws {
        let (service, backend) = makeService(appId: "app-9")
        backend.stub("GET", "/api/ai/configurations", .init(json: #"[{"id":"cfg-1"}]"#))

        let configs = try await service.getConfigurations(configurationType: "chat")

        #expect(configs.count == 1)
        #expect(backend.requests().contains { $0.method == "GET" && $0.path == "/api/ai/configurations" })
    }

    @Test func getConfigurationReturnsNilOnError() async {
        let (service, _) = makeService() // no stub
        #expect(await service.getConfiguration(configurationId: "missing") == nil)
    }

    @Test func createSessionPostsDefaultSessionName() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/ai/sessions", .init(json: #"{"id":"sess-1"}"#))

        _ = await service.createSession(configurationId: "c1")

        let req = try #require(backend.requests().first { $0.method == "POST" && $0.path == "/api/ai/sessions" })
        let body = try jsonBody(req)
        #expect(body["configurationId"] as? String == "c1")
        #expect(body["sessionName"] as? String == "New Session")
    }

    @Test func renameSessionPutsNewName() async throws {
        let (service, backend) = makeService()
        backend.stub("PUT", "/api/ai/sessions/s1/name", .init(statusCode: 200))

        let ok = await service.renameSession(sessionId: "s1", newName: "Renamed")

        #expect(ok == true)
        let req = try #require(backend.requests().first { $0.method == "PUT" && $0.path == "/api/ai/sessions/s1/name" })
        let body = try jsonBody(req)
        #expect(body["newName"] as? String == "Renamed")
    }

    @Test func endSessionReturnsTrueThenFalse() async {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/ai/sessions/s1/end", .init(statusCode: 200))
        #expect(await service.endSession(sessionId: "s1") == true)

        let (service2, _) = makeService() // no stub -> false
        #expect(await service2.endSession(sessionId: "s1") == false)
    }

    @Test func deleteSessionIssuesDelete() async {
        let (service, backend) = makeService()
        backend.stub("DELETE", "/api/ai/sessions/s1", .init(statusCode: 200))

        #expect(await service.deleteSession(sessionId: "s1") == true)
        #expect(backend.requests().contains { $0.method == "DELETE" && $0.path == "/api/ai/sessions/s1" })
    }

    @Test func getTTSVoicesReturnsEmptyOnError() async {
        let (service, _) = makeService() // no stub -> []
        #expect(await service.getTTSVoices().isEmpty)
    }
}
