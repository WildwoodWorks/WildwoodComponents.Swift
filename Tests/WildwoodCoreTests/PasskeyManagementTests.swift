// Passkey management over api/webauthn — the same four routes and body shapes as .NET
// PasskeyManagementService and @wildwood/core (passkeyManagement.integration.test.ts).

import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct PasskeyManagementTests {
    private func makeService() -> (AuthService, MockBackend) {
        let backend = MockBackend()
        let client = WildwoodClient(
            config: WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false, storage: .memory),
            urlSession: backend.makeSession()
        )
        return (client.auth, backend)
    }

    private func body(_ backend: MockBackend, _ method: String, _ path: String) throws -> [String: Any] {
        let request = try #require(backend.requests().last { $0.method == method && $0.path == path })
        let data = try #require(request.body)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private let passkeyJSON = """
    {"id":"pk-1","friendlyName":"Laptop","deviceInfo":null,"isPlatformAuthenticator":true,"isActive":true,
     "lastUsedAt":null,"usageCount":3,"createdAt":"2026-11-01T00:00:00Z"}
    """

    @Test func listsTheSignedInUsersPasskeysForTheApp() async throws {
        let (auth, backend) = makeService()
        backend.stub("GET", "/api/webauthn/credentials", .init(json: "[\(passkeyJSON)]"))

        let list = try await auth.listPasskeys(appId: "app-1")

        #expect(list.map(\.id) == ["pk-1"])
        #expect(list.first?.displayName == "Laptop")
        let request = try #require(backend.requests().last { $0.path == "/api/webauthn/credentials" })
        #expect(request.query == "appId=app-1")
    }

    @Test func renamesWithAPatchCarryingTheTrimmedFriendlyName() async throws {
        let (auth, backend) = makeService()
        backend.stub("PATCH", "/api/webauthn/credentials/pk-1", .init(json: passkeyJSON.replacingOccurrences(of: "Laptop", with: "Phone")))

        let renamed = try await auth.renamePasskey(id: "pk-1", friendlyName: "  Phone ")

        #expect(renamed.friendlyName == "Phone")
        #expect(try body(backend, "PATCH", "/api/webauthn/credentials/pk-1")["FriendlyName"] as? String == "Phone")
    }

    @Test func deletesById() async throws {
        let (auth, backend) = makeService()
        backend.stub("DELETE", "/api/webauthn/credentials/pk-1", .init(statusCode: 204, json: ""))

        try await auth.deletePasskey(id: "pk-1")

        #expect(backend.requests().contains { $0.method == "DELETE" && $0.path == "/api/webauthn/credentials/pk-1" })
    }

    @Test func aRefusedDeleteThrows() async {
        let (auth, backend) = makeService()
        backend.stub("DELETE", "/api/webauthn/credentials/pk-1", .init(statusCode: 404, json: #"{"message":"Not yours"}"#))

        await #expect(throws: WildwoodError.self) { try await auth.deletePasskey(id: "pk-1") }
    }

    @Test func readsTheEnabledAnswerInEitherShape() {
        #expect(AuthService.readPasskeyEnabled(Data("true".utf8)))
        #expect(AuthService.readPasskeyEnabled(Data(#"{"enabled":true}"#.utf8)))
        #expect(AuthService.readPasskeyEnabled(Data(#"{"Enabled":true}"#.utf8)))
        #expect(!AuthService.readPasskeyEnabled(Data(#"{"enabled":false}"#.utf8)))
        #expect(!AuthService.readPasskeyEnabled(Data("false".utf8)))
        #expect(!AuthService.readPasskeyEnabled(Data("not json".utf8)))
    }

    @Test func answersNotEnabledWhenTheCheckFails() async {
        let (auth, backend) = makeService()
        backend.stub("GET", "/api/webauthn/enabled/app-1", .init(statusCode: 500, json: "{}"))

        #expect(await auth.isPasskeyEnabled(appId: "app-1") == false)
    }

    @Test func sendsFriendlyNameOnRegisterOptions_nullWhenBlank() async throws {
        let (auth, backend) = makeService()
        backend.stub("POST", "/api/webauthn/register/options", .init(json: #"{"challenge":"c"}"#))

        _ = try await auth.getPasskeyRegistrationOptions(appId: "app-1", friendlyName: " Work key ")
        #expect(try body(backend, "POST", "/api/webauthn/register/options")["FriendlyName"] as? String == "Work key")

        _ = try await auth.getPasskeyRegistrationOptions(appId: "app-1", friendlyName: "   ")
        let blank = try body(backend, "POST", "/api/webauthn/register/options")
        #expect(blank["FriendlyName"] is NSNull)
        #expect(blank["AppId"] as? String == "app-1")
    }

    @Test func theDisplayNameFallsBackToTheAuthenticatorKind() {
        #expect(UserPasskey(id: "a", friendlyName: "  ", isPlatformAuthenticator: false).displayName == "Security key")
        #expect(UserPasskey(id: "b", isPlatformAuthenticator: true).displayName == "This device (built-in)")
    }
}
