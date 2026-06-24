// TwoFactorService behavior mirrored from the JS twoFactorService tests:
// endpoint/verb correctness, Bool/Int return semantics, and request bodies.

import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct TwoFactorServiceTests {
    private func makeService() -> (TwoFactorService, MockBackend) {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        return (TwoFactorService(http: http), backend)
    }

    @Test func getConfigurationReturnsNilOnErrorAndRequestsAnonymousEndpoint() async throws {
        let (service, backend) = makeService()
        // No stub registered -> 404 -> try? yields nil.
        let config = await service.getConfiguration(appId: "app-1")

        #expect(config == nil)
        #expect(backend.requests().contains { $0.method == "GET" && $0.path == "/api/twofactor/configuration/app-1" })
    }

    @Test func getStatusDecodesUserStatus() async throws {
        let (service, backend) = makeService()
        backend.stub("GET", "/api/twofactor/status", .init(json: #"{"isEnabled":true,"methodCount":2}"#))

        let status = try await service.getStatus()

        #expect(status.isEnabled == true)
        #expect(status.methodCount == 2)
    }

    @Test func getCredentialsReturnsEmptyOnError() async throws {
        let (service, _) = makeService()
        // No stub -> error -> [].
        let creds = await service.getCredentials()
        #expect(creds.isEmpty)
    }

    @Test func enrollEmailPostsEmailToEnrollmentEndpoint() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/twofactor/enroll/email", .init(json: #"{"success":true,"credentialId":"cred-1","maskedEmail":"u***@x.com","expiresIn":600}"#))

        let result = try await service.enrollEmail(email: "user@example.com")

        #expect(result.credentialId == "cred-1")
        let req = try #require(backend.requests().first { $0.method == "POST" && $0.path == "/api/twofactor/enroll/email" })
        let body = try #require(req.body)
        let dict = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(dict["email"] as? String == "user@example.com")
    }

    @Test func verifyEmailEnrollmentReturnsTrueOnSuccessFalseOnError() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/twofactor/enroll/email/verify", .init(statusCode: 200))

        let ok = await service.verifyEmailEnrollment(credentialId: "cred-1", code: "123456")
        #expect(ok == true)

        // A different code path with no stub for a fresh backend -> failure.
        let (service2, _) = makeService()
        let bad = await service2.verifyEmailEnrollment(credentialId: "cred-1", code: "000000")
        #expect(bad == false)
    }

    @Test func setPrimaryCredentialPutsToPrimaryEndpoint() async throws {
        let (service, backend) = makeService()
        backend.stub("PUT", "/api/twofactor/credentials/cred-9/primary", .init(statusCode: 200))

        let ok = await service.setPrimaryCredential(credentialId: "cred-9")

        #expect(ok == true)
        #expect(backend.requests().contains { $0.method == "PUT" && $0.path == "/api/twofactor/credentials/cred-9/primary" })
    }

    @Test func removeCredentialReturnsFalseWhenDeletionFails() async throws {
        let (service, _) = makeService()
        // No stub -> delete fails -> false.
        let ok = await service.removeCredential(credentialId: "cred-9")
        #expect(ok == false)
    }

    @Test func revokeAllTrustedDevicesReturnsTheRevokedCount() async throws {
        let (service, backend) = makeService()
        backend.stub("DELETE", "/api/twofactor/trusted-devices", .init(json: #"{"revokedCount":3}"#))

        let count = await service.revokeAllTrustedDevices()

        #expect(count == 3)
        #expect(backend.requests().contains { $0.method == "DELETE" && $0.path == "/api/twofactor/trusted-devices" })
    }
}
