// AuthService behavior mirrored from the JS authService tests: storage of
// tokens on login, 2FA short-circuit, refresh semantics, stored-user roundtrip.

import Foundation
import Testing
@testable import WildwoodCore

@MainActor
@Suite(.serialized)
struct AuthServiceTests {
    private func makeService(storage: MemoryStorage = MemoryStorage()) -> (AuthService, MemoryStorage) {
        MockURLProtocol.reset()
        let config = WildwoodConfig(baseUrl: "https://unit.test", appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: MockURLProtocol.makeSession())
        let service = AuthService(http: http, storage: storage, events: WildwoodEventEmitter())
        return (service, storage)
    }

    @Test func loginStoresTokensAndUser() async throws {
        let (service, storage) = makeService()
        MockURLProtocol.stub("POST", "/api/auth/login", .init(json: """
        {"id":"u1","userId":"u1","email":"a@b.c","firstName":"A","lastName":"B",
         "jwtToken":"jwt-123","refreshToken":"refresh-456","requiresTwoFactor":false,
         "requiresPasswordReset":false,"roles":[],"permissions":[],"requiresDisclaimerAcceptance":false}
        """))

        let response = try await service.login(LoginRequest(username: "a@b.c", password: "pw", appId: "app-1"))

        #expect(response.jwtToken == "jwt-123")
        #expect(storage.getItem(WildwoodStorageKeys.accessToken) == "jwt-123")
        #expect(storage.getItem(WildwoodStorageKeys.refreshToken) == "refresh-456")
        #expect(storage.getItem(WildwoodStorageKeys.user)?.contains("a@b.c") == true)
    }

    @Test func loginWithTwoFactorDoesNotStoreTokens() async throws {
        let (service, storage) = makeService()
        MockURLProtocol.stub("POST", "/api/auth/login", .init(json: """
        {"requiresTwoFactor":true,"twoFactorSessionId":"2fa-session",
         "availableTwoFactorMethods":[{"providerType":"Email","name":"Email","icon":""}]}
        """))

        let response = try await service.login(LoginRequest(username: "a@b.c", password: "pw"))

        #expect(response.requiresTwoFactor)
        #expect(response.twoFactorSessionId == "2fa-session")
        #expect(storage.getItem(WildwoodStorageKeys.accessToken) == nil)
    }

    @Test func loginSendsPascalCaseDto() async throws {
        let (service, _) = makeService()
        MockURLProtocol.stub("POST", "/api/auth/login", .init(json: #"{"jwtToken":"t","refreshToken":"r"}"#))

        _ = try await service.login(LoginRequest(username: "user", password: "pw", appId: "app-1"))

        let request = MockURLProtocol.requests().first
        let body = String(data: request?.body ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("\"Username\":\"user\""))
        #expect(body.contains("\"AppId\":\"app-1\""))
        #expect(body.contains("\"AppVersion\":\"1.0.0\""))
    }

    @Test func refreshTokenClearsStorageOn401() async throws {
        let storage = MemoryStorage()
        storage.setItem(WildwoodStorageKeys.refreshToken, "stale")
        storage.setItem(WildwoodStorageKeys.accessToken, "stale-access")
        let (service, _) = makeService(storage: storage)
        MockURLProtocol.stub("POST", "/api/auth/refresh-token", .init(statusCode: 401, json: #"{"message":"expired"}"#))

        let refreshed = await service.refreshToken()

        #expect(!refreshed)
        #expect(storage.getItem(WildwoodStorageKeys.refreshToken) == nil)
        #expect(storage.getItem(WildwoodStorageKeys.accessToken) == nil)
    }

    @Test func refreshTokenKeepsStorageOnServerError() async throws {
        let storage = MemoryStorage()
        storage.setItem(WildwoodStorageKeys.refreshToken, "still-good")
        let (service, _) = makeService(storage: storage)
        MockURLProtocol.stub("POST", "/api/auth/refresh-token", .init(statusCode: 503, json: "{}"))

        let refreshed = await service.refreshToken()

        #expect(!refreshed)
        #expect(storage.getItem(WildwoodStorageKeys.refreshToken) == "still-good")
    }

    @Test func registerWithTokenNormalizesTokenlessSuccess() async throws {
        let (service, storage) = makeService()
        MockURLProtocol.stub("POST", "/api/userregistration/register-with-token", .init(json: """
        {"success":true,"message":"ok","userId":"new-user-1"}
        """))

        let response = try await service.registerWithToken(
            RegistrationRequest(email: "n@b.c", firstName: "N", lastName: "U", password: "pw", appId: "app-1", registrationToken: "tok")
        )

        #expect(response.jwtToken.isEmpty)
        #expect(response.userId == "new-user-1")
        #expect(storage.getItem(WildwoodStorageKeys.accessToken) == nil)
    }

    @Test func registerWithTokenThrowsOnFailure() async {
        let (service, _) = makeService()
        MockURLProtocol.stub("POST", "/api/userregistration/register-with-token", .init(json: """
        {"success":false,"message":"Token already used"}
        """))

        await #expect(throws: WildwoodError.self) {
            _ = try await service.registerWithToken(
                RegistrationRequest(email: "n@b.c", firstName: "N", lastName: "U", password: "pw", appId: "app-1", registrationToken: "tok")
            )
        }
    }

    @Test func getStoredUserRoundtrips() async throws {
        let (service, _) = makeService()
        MockURLProtocol.stub("POST", "/api/auth/login", .init(json: """
        {"id":"u9","userId":"u9","email":"round@trip.io","jwtToken":"jwt","refreshToken":"r",
         "roles":["Admin"],"permissions":["x"]}
        """))

        _ = try await service.login(LoginRequest(username: "round@trip.io", password: "pw"))
        let stored = service.getStoredUser()

        #expect(stored?.userId == "u9")
        #expect(stored?.roles == ["Admin"])
    }

    @Test func passwordRulesEnforceConfiguredRequirements() throws {
        let json = """
        {"isEnabled":true,"allowLocalAuth":true,"passwordMinimumLength":8,
         "passwordRequireUppercase":true,"passwordRequireDigit":true,
         "passwordRequireLowercase":false,"passwordRequireSpecialChar":false}
        """
        let config = try WildwoodJSON.decoder().decode(AuthenticationConfiguration.self, from: Data(json.utf8))

        #expect(!AuthService.checkPasswordRules("short", config: config).isValid)
        #expect(!AuthService.checkPasswordRules("nouppercase1", config: config).isValid)
        #expect(!AuthService.checkPasswordRules("NoDigitsHere", config: config).isValid)
        #expect(AuthService.checkPasswordRules("GoodPass1", config: config).isValid)
    }
}
