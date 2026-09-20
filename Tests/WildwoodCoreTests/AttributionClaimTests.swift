// AuthService's Campaign Attribution wiring, mirrored from @wildwood/core's authService tests:
// every registration path attaches the captured payload when the request carries none (an explicit
// payload wins), the touches are cleared only after a SUCCESSFUL signup, and a provider sign-in
// queues a claim that goes out once a session exists — at most once, inside the 15-minute window,
// dropped on sign-out, and never allowed to break a login.

import Foundation
import Synchronization
import Testing
@testable import WildwoodCore

/// A fake `AttributionRegistrationSource` that records how often the touches were cleared.
/// `Sendable` (not `@MainActor`) because `AuthService` reaches it from any isolation.
private final class RecordingAttributionSource: Sendable {
    private struct State: Sendable {
        var payload: AttributionPayload?
        var clearCount: Int = 0
    }

    private let state: Mutex<State>

    init(payload: AttributionPayload?) {
        state = Mutex(State(payload: payload))
    }

    var clearCount: Int { state.withLock { $0.clearCount } }
    var payload: AttributionPayload? { state.withLock { $0.payload } }

    var source: AttributionRegistrationSource {
        AttributionRegistrationSource(
            payload: { self.state.withLock { $0.payload } },
            clear: { self.state.withLock { $0.payload = nil; $0.clearCount += 1 } }
        )
    }
}

/// A movable clock for the claim window (the `SessionManager.now` seam, in a Sendable box).
private final class TestClock: Sendable {
    private let state: Mutex<Date>

    init(_ start: Date) {
        state = Mutex(start)
    }

    var closure: @Sendable () -> Date {
        { self.state.withLock { $0 } }
    }

    func advance(_ interval: TimeInterval) {
        state.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}

@MainActor
struct AttributionClaimTests {
    private let touch = AttributionTouch(
        source: "reddit",
        medium: "paid",
        campaign: "govcon-test-sep26",
        occurredAt: "2026-09-13T12:00:00.000Z"
    )

    private var capturedPayload: AttributionPayload {
        AttributionPayload(visitorKey: "visitor-key-0001", firstTouch: touch, lastTouch: touch, platform: "ios")
    }

    private let sessionJSON = """
    {"id":"u1","userId":"u1","email":"a@b.c","firstName":"A","lastName":"B",
     "jwtToken":"jwt-123","refreshToken":"refresh-456","requiresTwoFactor":false,
     "requiresPasswordReset":false,"roles":[],"permissions":[],"requiresDisclaimerAcceptance":false}
    """

    private func makeService(
        payload: AttributionPayload?
    ) -> (AuthService, RecordingAttributionSource, MockBackend) {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        let service = AuthService(http: http, storage: MemoryStorage(), events: WildwoodEventEmitter())
        let attribution = RecordingAttributionSource(payload: payload)
        service.setAttributionProvider(attribution.source)
        return (service, attribution, backend)
    }

    private func body(_ backend: MockBackend, path: String) -> String {
        let request = backend.requests().first { $0.path == path }
        return String(data: request?.body ?? Data(), encoding: .utf8) ?? ""
    }

    private func registrationRequest(attribution: AttributionPayload? = nil) -> RegistrationRequest {
        RegistrationRequest(
            email: "new@example.com",
            firstName: "Jane",
            lastName: "Doe",
            password: "Passw0rd!",
            appId: "app-1",
            attribution: attribution
        )
    }

    // MARK: - Attach + clear (A1 / A2)

    @Test func registerAttachesTheCapturedPayloadAndClearsAfterASuccessfulSignup() async throws {
        let (service, attribution, backend) = makeService(payload: capturedPayload)
        backend.stub("POST", "/api/auth/register", .init(json: sessionJSON))

        _ = try await service.register(registrationRequest())

        let sent = body(backend, path: "/api/auth/register")
        #expect(sent.contains(#""attribution":"#))
        #expect(sent.contains(#""visitorKey":"visitor-key-0001""#))
        #expect(sent.contains(#""sdk":"swift""#))
        // Recorded with the account: a second signup on this device must not reuse the touches.
        #expect(attribution.clearCount == 1)
        #expect(attribution.payload == nil)
    }

    @Test func anExplicitPayloadWinsOverTheCapturedOne() async throws {
        let (service, _, backend) = makeService(payload: capturedPayload)
        backend.stub("POST", "/api/auth/register", .init(json: sessionJSON))
        let explicit = AttributionPayload(
            visitorKey: "explicit-key-0002",
            firstTouch: nil,
            lastTouch: touch,
            platform: "ios"
        )

        _ = try await service.register(registrationRequest(attribution: explicit))

        let sent = body(backend, path: "/api/auth/register")
        #expect(sent.contains(#""visitorKey":"explicit-key-0002""#))
        #expect(!sent.contains("visitor-key-0001"))
    }

    @Test func aFailedRegistrationKeepsTheTouches() async throws {
        let (service, attribution, backend) = makeService(payload: capturedPayload)
        backend.stub("POST", "/api/auth/register", .init(statusCode: 400, json: #"{"message":"Email already in use"}"#))

        await #expect(throws: WildwoodError.self) {
            _ = try await service.register(registrationRequest())
        }

        #expect(attribution.clearCount == 0)
        #expect(attribution.payload != nil)
    }

    @Test func tokenRegistrationAttachesThePayloadAndClears() async throws {
        let (service, attribution, backend) = makeService(payload: capturedPayload)
        backend.stub("POST", "/api/userregistration/register-with-token", .init(json: sessionJSON))
        var request = registrationRequest()
        request.registrationToken = "tok-1"

        _ = try await service.registerWithToken(request)

        let sent = body(backend, path: "/api/userregistration/register-with-token")
        #expect(sent.contains(#""Attribution":"#))
        #expect(sent.contains(#""visitorKey":"visitor-key-0001""#))
        #expect(attribution.clearCount == 1)
    }

    @Test func openRegistrationAttachesThePayloadAndClearsOnlyOnSuccess() async throws {
        let (okService, okAttribution, okBackend) = makeService(payload: capturedPayload)
        okBackend.stub("POST", "/api/userregistration/register", .init(json: #"{"success":true,"message":"","userId":"u1"}"#))

        _ = try await okService.registerOpen(registrationRequest())

        let sent = body(okBackend, path: "/api/userregistration/register")
        #expect(sent.contains(#""Attribution":"#))
        #expect(okAttribution.clearCount == 1)

        // A refused open registration is not a signup: the touches survive for the next attempt.
        let (failService, failAttribution, failBackend) = makeService(payload: capturedPayload)
        failBackend.stub("POST", "/api/userregistration/register", .init(json: #"{"success":false,"message":"Registration is closed"}"#))

        _ = try await failService.registerOpen(registrationRequest())

        #expect(failAttribution.clearCount == 0)
    }

    @Test func registrationWithoutACapturedPayloadSendsNoAttributionKey() async throws {
        let (service, _, backend) = makeService(payload: nil)
        backend.stub("POST", "/api/auth/register", .init(json: sessionJSON))

        _ = try await service.register(registrationRequest())

        #expect(!body(backend, path: "/api/auth/register").contains("attribution"))
    }

    // MARK: - Provider claim (A3)

    @Test func aProviderSignInClaimsTheTouchesOnceAndOnlyOnce() async throws {
        let (service, attribution, backend) = makeService(payload: capturedPayload)
        backend.stub("POST", "/api/auth/login", .init(json: sessionJSON))
        backend.stub("POST", "/api/attribution/claim", .init(json: #"{"recorded":true,"reason":null}"#))

        _ = try await service.login(
            LoginRequest(username: "", providerName: "Apple", providerToken: "id-token", appId: "app-1")
        )

        let claims = backend.requests().filter { $0.path == "/api/attribution/claim" }
        #expect(claims.count == 1)
        #expect(claims.first?.query?.contains("appId=app-1") == true)
        let sent = body(backend, path: "/api/attribution/claim")
        #expect(sent.contains(#""appId":"app-1""#))
        #expect(sent.contains(#""visitorKey":"visitor-key-0001""#))
        // A successful claim clears the touches, exactly like a recorded signup.
        #expect(attribution.clearCount == 1)

        // A later ordinary login must not claim again — the queue holds one claim.
        _ = try await service.login(LoginRequest(username: "a@b.c", password: "pw", appId: "app-1"))
        #expect(backend.requests().filter { $0.path == "/api/attribution/claim" }.count == 1)
    }

    @Test func anOrdinaryLoginQueuesNoClaim() async throws {
        let (service, _, backend) = makeService(payload: capturedPayload)
        backend.stub("POST", "/api/auth/login", .init(json: sessionJSON))
        backend.stub("POST", "/api/attribution/claim", .init(json: #"{"recorded":true,"reason":null}"#))

        _ = try await service.login(LoginRequest(username: "a@b.c", password: "pw", appId: "app-1"))

        #expect(!backend.requests().contains { $0.path == "/api/attribution/claim" })
    }

    @Test func twoFactorDefersTheClaimUntilVerificationCompletes() async throws {
        let (service, _, backend) = makeService(payload: capturedPayload)
        backend.stub("POST", "/api/auth/login", .init(json: #"{"requiresTwoFactor":true,"twoFactorSessionId":"2fa"}"#))
        backend.stub("POST", "/api/attribution/claim", .init(json: #"{"recorded":true,"reason":null}"#))

        _ = try await service.login(
            LoginRequest(username: "", providerName: "Google", providerToken: "id-token", appId: "app-1")
        )
        // No session yet: the claim would 401, so it waits.
        #expect(!backend.requests().contains { $0.path == "/api/attribution/claim" })

        backend.stub("POST", "/api/twofactor/verify", .init(json: """
        {"success":true,"authResponse":\(sessionJSON)}
        """))
        _ = await service.verifyTwoFactorCode(
            TwoFactorVerifyRequest(sessionId: "2fa", code: "123456", providerType: "Email")
        )

        #expect(backend.requests().filter { $0.path == "/api/attribution/claim" }.count == 1)
    }

    @Test func aQueuedClaimOlderThanTheWindowLapses() async throws {
        let (service, attribution, backend) = makeService(payload: capturedPayload)
        backend.stub("POST", "/api/auth/login", .init(json: sessionJSON))
        backend.stub("POST", "/api/attribution/claim", .init(json: #"{"recorded":true,"reason":null}"#))
        let clock = TestClock(Date(timeIntervalSince1970: 1_000_000))
        service.setAttributionClock(clock.closure)

        service.queueAttributionClaim(appId: "app-1")
        clock.advance(16 * 60)  // past the server's 15-minute claim window
        _ = try await service.login(LoginRequest(username: "a@b.c", password: "pw", appId: "app-1"))

        #expect(!backend.requests().contains { $0.path == "/api/attribution/claim" })
        #expect(attribution.clearCount == 0)
    }

    @Test func aQueuedClaimInsideTheWindowIsSent() async throws {
        let (service, _, backend) = makeService(payload: capturedPayload)
        backend.stub("POST", "/api/auth/login", .init(json: sessionJSON))
        backend.stub("POST", "/api/attribution/claim", .init(json: #"{"recorded":true,"reason":null}"#))
        let clock = TestClock(Date(timeIntervalSince1970: 1_000_000))
        service.setAttributionClock(clock.closure)

        service.queueAttributionClaim(appId: "app-1")
        clock.advance(5 * 60)
        _ = try await service.login(LoginRequest(username: "a@b.c", password: "pw", appId: "app-1"))

        #expect(backend.requests().filter { $0.path == "/api/attribution/claim" }.count == 1)
    }

    @Test func signingOutDropsTheQueuedClaim() async throws {
        let (service, _, backend) = makeService(payload: capturedPayload)
        backend.stub("POST", "/api/auth/login", .init(json: sessionJSON))
        backend.stub("POST", "/api/attribution/claim", .init(json: #"{"recorded":true,"reason":null}"#))

        service.queueAttributionClaim(appId: "app-1")
        await service.logout()
        _ = try await service.login(LoginRequest(username: "a@b.c", password: "pw", appId: "app-1"))

        #expect(!backend.requests().contains { $0.path == "/api/attribution/claim" })
    }

    @Test func aFailedClaimNeverBreaksTheLoginAndKeepsTheTouches() async throws {
        let (service, attribution, backend) = makeService(payload: capturedPayload)
        backend.stub("POST", "/api/auth/login", .init(json: sessionJSON))
        backend.stub("POST", "/api/attribution/claim", .init(statusCode: 500, json: #"{"message":"boom"}"#))

        let response = try await service.login(
            LoginRequest(username: "", providerName: "Apple", providerToken: "id-token", appId: "app-1")
        )

        #expect(response.jwtToken == "jwt-123")
        // The server never decided, so the touches stay for the next attempt.
        #expect(attribution.clearCount == 0)
        // An empty appId never reaches the network either.
        let noAppId = await service.claimAttribution(appId: "")
        #expect(noAppId == nil)
    }
}
