// Required two-factor enrollment: when an app requires 2FA and the user has none, the API issues
// a RESTRICTED token (claim tfa_enroll_pending, response flag requiresTwoFactorEnrollment) and
// refuses everything but enrollment with 403 TWO_FACTOR_ENROLLMENT_REQUIRED. A refresh after
// enrolling returns an unrestricted token. Parity with @wildwood/core and the Blazor admin gate.

import Foundation
import Testing
@testable import WildwoodCore

private func makeToken(claims: [String: Any]) -> String {
    func encode(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    return "\(encode(["alg": "none"])).\(encode(claims)).sig"
}

private let restrictedToken = makeToken(claims: ["sub": "u1", "tfa_enroll_pending": "true", "exp": 4_000_000_000])
private let normalToken = makeToken(claims: ["sub": "u1", "exp": 4_000_000_000])

struct TwoFactorEnrollmentContractTests {
    @Test func decodesTheEnrollmentClaim() {
        #expect(JWTDecoder.decodePayload(restrictedToken)?.twoFactorEnrollmentPending == true)
        #expect(JWTDecoder.isTwoFactorEnrollmentPending(restrictedToken))
        #expect(!JWTDecoder.isTwoFactorEnrollmentPending(normalToken))
        #expect(!JWTDecoder.isTwoFactorEnrollmentPending("not-a-jwt"))
    }

    @Test func decodesTheResponseFlagAndToleratesItsAbsence() throws {
        let flagged = try WildwoodJSON.decoder().decode(
            AuthenticationResponse.self,
            from: Data(#"{"jwtToken":"t","requiresTwoFactorEnrollment":true}"#.utf8)
        )
        #expect(flagged.requiresTwoFactorEnrollment)

        let older = try WildwoodJSON.decoder().decode(AuthenticationResponse.self, from: Data(#"{"jwtToken":"t"}"#.utf8))
        #expect(!older.requiresTwoFactorEnrollment)
    }

    @Test func mapsTheRefusalToItsOwnCode() {
        let body = Data(#"{"error":"Two-factor authentication must be set up first.","errorCode":"TWO_FACTOR_ENROLLMENT_REQUIRED"}"#.utf8)
        let error = WildwoodError.fromResponse(status: 403, body: body, fallbackMessage: "Forbidden")
        #expect(error.code == .twoFactorEnrollmentRequired)
        #expect(error.message == "Two-factor authentication must be set up first.")
    }
}

@MainActor
struct SessionTwoFactorEnrollmentTests {
    private final class EventCounter {
        var enrollmentRequired = 0
    }

    private func makeClient() async -> (WildwoodClient, MockBackend, EventCounter) {
        let backend = MockBackend()
        let client = WildwoodClient(
            config: WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false, storage: .memory),
            urlSession: backend.makeSession()
        )
        let counter = EventCounter()
        client.events.on { event in
            if case .twoFactorEnrollmentRequired = event { counter.enrollmentRequired += 1 }
        }
        await client.session.initialize()
        return (client, backend, counter)
    }

    @Test func aFlaggedSignInIsRestrictedAndAnnounced() async {
        let (client, _, counter) = await makeClient()

        client.session.login(AuthenticationResponse(userId: "u1", jwtToken: normalToken, refreshToken: "r1", requiresTwoFactorEnrollment: true))

        #expect(client.session.requiresTwoFactorEnrollment)
        #expect(counter.enrollmentRequired == 1)
    }

    @Test func theTokenClaimAloneRestrictsTheSession() async {
        let (client, _, _) = await makeClient()

        client.session.login(AuthenticationResponse(userId: "u1", jwtToken: restrictedToken, refreshToken: "r1"))

        #expect(client.session.requiresTwoFactorEnrollment)
    }

    @Test func aNormalSignInIsNotRestricted() async {
        let (client, _, counter) = await makeClient()

        client.session.login(AuthenticationResponse(userId: "u1", jwtToken: normalToken, refreshToken: "r1"))

        #expect(!client.session.requiresTwoFactorEnrollment)
        #expect(counter.enrollmentRequired == 0)
    }

    @Test func aRefusedCallRestrictsTheSessionAndStillThrows() async {
        let (client, backend, counter) = await makeClient()
        client.session.login(AuthenticationResponse(userId: "u1", jwtToken: normalToken, refreshToken: "r1"))
        backend.stub("GET", "/api/users", .init(statusCode: 403, json: """
        {"error":"Two-factor authentication must be set up first.","errorCode":"TWO_FACTOR_ENROLLMENT_REQUIRED"}
        """))

        await #expect(throws: WildwoodError.self) {
            let _: EmptyBody = try await client.http.get("api/users")
        }

        #expect(client.session.requiresTwoFactorEnrollment)
        #expect(counter.enrollmentRequired == 1)
    }

    @Test func anOrdinaryForbiddenDoesNotRestrictTheSession() async {
        let (client, backend, _) = await makeClient()
        client.session.login(AuthenticationResponse(userId: "u1", jwtToken: normalToken, refreshToken: "r1"))
        backend.stub("GET", "/api/users", .init(statusCode: 403, json: #"{"error":"Forbidden"}"#))

        _ = try? await client.http.get("api/users") as EmptyBody

        #expect(!client.session.requiresTwoFactorEnrollment)
    }

    @Test func refreshingAfterEnrollmentLiftsTheRestriction() async {
        let (client, backend, _) = await makeClient()
        client.storage.setItem(WildwoodStorageKeys.refreshToken, "r1")
        client.session.login(AuthenticationResponse(userId: "u1", jwtToken: restrictedToken, refreshToken: "r1", requiresTwoFactorEnrollment: true))
        backend.stub("POST", "/api/auth/refresh-token", .init(json: """
        {"userId":"u1","jwtToken":"\(normalToken)","refreshToken":"r2","requiresTwoFactorEnrollment":false}
        """))

        let lifted = await client.session.refreshAfterTwoFactorEnrollment()

        #expect(lifted)
        #expect(!client.session.requiresTwoFactorEnrollment)
        #expect(client.session.accessToken == normalToken)
    }

    @Test func refreshingBeforeEnrollingKeepsTheRestriction() async {
        let (client, backend, _) = await makeClient()
        client.storage.setItem(WildwoodStorageKeys.refreshToken, "r1")
        client.session.login(AuthenticationResponse(userId: "u1", jwtToken: restrictedToken, refreshToken: "r1", requiresTwoFactorEnrollment: true))
        backend.stub("POST", "/api/auth/refresh-token", .init(json: """
        {"userId":"u1","jwtToken":"\(restrictedToken)","refreshToken":"r2","requiresTwoFactorEnrollment":true}
        """))

        let lifted = await client.session.refreshAfterTwoFactorEnrollment()

        #expect(!lifted)
        #expect(client.session.requiresTwoFactorEnrollment)
    }

    @Test func signingOutClearsTheRestriction() async {
        let (client, _, _) = await makeClient()
        client.session.login(AuthenticationResponse(userId: "u1", jwtToken: restrictedToken, refreshToken: "r1"))

        client.session.logout()

        #expect(!client.session.requiresTwoFactorEnrollment)
    }
}
