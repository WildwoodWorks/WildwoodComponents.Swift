// The API accepts a passkey assertion only against the challenge it issued, identified by the options'
// sessionId; without it every passkey sign-in is refused as "Passkey sign-in expired". Mirrors
// @wildwood/core's passkey.integration.test.ts.

import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct PasskeySessionTests {
    private func makeService() -> (AuthService, MockBackend) {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        let service = AuthService(http: http, storage: MemoryStorage(), events: WildwoodEventEmitter())
        backend.stub("POST", "/api/webauthn/authenticate/options", .init(json: """
        {"challenge":"abc","rpId":"example.com","sessionId":"session-42"}
        """))
        backend.stub("POST", "/api/webauthn/authenticate", .init(json: #"{"jwtToken":"t","refreshToken":"r"}"#))
        return (service, backend)
    }

    private let credential = PasskeyAssertionCredential(
        id: "cred", rawId: "cred",
        response: PasskeyAssertionResponse(clientDataJSON: "c", authenticatorData: "a", signature: "s", userHandle: "u"))

    private func verifyBody(_ backend: MockBackend) -> String {
        let request = backend.requests().first { $0.path == "/api/webauthn/authenticate" }
        return String(data: request?.body ?? Data(), encoding: .utf8) ?? ""
    }

    @Test func verifySendsTheSessionIdFromTheOptions() async throws {
        let (service, backend) = makeService()
        _ = try await service.getPasskeyAuthenticationOptions(appId: "app-1")
        _ = try await service.verifyPasskeyAuthentication(appId: "app-1", credential: credential)

        #expect(verifyBody(backend).contains("\"SessionId\":\"session-42\""))
    }

    @Test func anExplicitSessionIdWins() async throws {
        let (service, backend) = makeService()
        _ = try await service.getPasskeyAuthenticationOptions(appId: "app-1")
        _ = try await service.verifyPasskeyAuthentication(appId: "app-1", credential: credential, sessionId: "explicit-1")

        #expect(verifyBody(backend).contains("\"SessionId\":\"explicit-1\""))
    }
}
