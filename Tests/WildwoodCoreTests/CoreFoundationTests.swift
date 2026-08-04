// JWT decoding, date parsing, storage keys, error mapping, and the HTTP
// client's reactive 401 retry + replay safety.

import Foundation
import Testing
@testable import WildwoodCore

// MARK: - JWT

struct JWTDecoderTests {
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

    @Test func decodesStandardClaims() {
        let token = makeToken(claims: [
            "sub": "user-1", "email": "x@y.z", "role": ["Admin", "User"],
            "company_id": "co-1", "exp": 2_000_000_000, "iat": 1_999_990_000,
        ])
        let payload = JWTDecoder.decodePayload(token)
        #expect(payload?.sub == "user-1")
        #expect(payload?.roles == ["Admin", "User"])
        #expect(payload?.companyId == "co-1")
        #expect(payload?.exp == 2_000_000_000)
    }

    @Test func singleRoleStringBecomesArray() {
        let token = makeToken(claims: ["role": "Admin", "exp": 2_000_000_000])
        #expect(JWTDecoder.decodePayload(token)?.roles == ["Admin"])
    }

    @Test func refreshDelayIsEightyPercentOfLifetime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // 1000-second lifetime issued exactly now → refresh at +800s.
        let token = makeToken(claims: ["iat": 1_000_000, "exp": 1_001_000])
        let delay = JWTDecoder.refreshDelay(for: token, now: now)
        #expect(abs(delay - 800) < 1)
    }

    @Test func refreshDelayFallsBackToFiveMinutesBeforeExpiry() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let token = makeToken(claims: ["exp": 1_001_000]) // no iat; 1000s remaining
        let delay = JWTDecoder.refreshDelay(for: token, now: now)
        #expect(abs(delay - 700) < 1) // 1000 - 300
    }

    @Test func malformedTokenIsExpired() {
        #expect(JWTDecoder.isExpired("not-a-jwt"))
        #expect(JWTDecoder.decodePayload("a.b") == nil)
    }
}

// MARK: - Wire format

struct WildwoodJSONTests {
    @Test func parsesDotNetDateVariants() {
        // ISO with timezone + fractions, ISO without fractions, .NET 7-digit
        // fractional without timezone, plain without timezone.
        #expect(WildwoodJSON.parseDate("2026-06-10T12:34:56.789Z") != nil)
        #expect(WildwoodJSON.parseDate("2026-06-10T12:34:56Z") != nil)
        #expect(WildwoodJSON.parseDate("2026-06-10T12:34:56.1234567") != nil)
        #expect(WildwoodJSON.parseDate("2026-06-10T12:34:56") != nil)
        #expect(WildwoodJSON.parseDate("not a date") == nil)
    }

    @Test func decodesCamelCaseModelLeniently() throws {
        let json = #"{"id":"t1","name":"Pro","pricingOptions":[],"limits":[]}"#
        let tier = try WildwoodJSON.decoder().decode(AppTierModel.self, from: Data(json.utf8))
        #expect(tier.id == "t1")
        #expect(tier.name == "Pro")
        #expect(tier.features.isEmpty)
        #expect(tier.allowUpgrades) // default
    }
}

// MARK: - Storage

struct StorageTests {
    @Test func sharedKeyLiteralsMatchTheOtherStacks() {
        #expect(WildwoodStorageKeys.accessToken == "ww_accessToken")
        #expect(WildwoodStorageKeys.refreshToken == "ww_refreshToken")
        #expect(WildwoodStorageKeys.user == "ww_user")
        #expect(WildwoodStorageKeys.sessionAuth == "ww_session_auth")
        #expect(WildwoodStorageKeys.sessionExpiry == "ww_session_expiry")
        #expect(WildwoodStorageKeys.theme == "ww_theme")
        #expect(WildwoodStorageKeys.draft(threadId: "t1") == "ww_draft_t1")
    }

    @Test func memoryStorageRoundtrips() {
        let storage = MemoryStorage()
        storage.setItem("k", "v")
        #expect(storage.getItem("k") == "v")
        storage.removeItem("k")
        #expect(storage.getItem("k") == nil)
    }
}

// MARK: - Errors

struct WildwoodErrorTests {
    @Test func mapsStatusCodes() {
        #expect(WildwoodError(message: "x", status: 401).code == .unauthorized)
        #expect(WildwoodError(message: "x", status: 404).code == .notFound)
        #expect(WildwoodError(message: "x", status: 429).code == .rateLimited)
        #expect(WildwoodError(message: "x", status: 503).code == .serverError)
        #expect(WildwoodError(message: "x", status: 0).code == .networkError)
    }

    @Test func extractsMessageAndTwoFactorFlagFromBody() {
        let body = Data(#"{"message":"Bad credentials","requiresTwoFactor":true}"#.utf8)
        let error = WildwoodError.fromResponse(status: 400, body: body, fallbackMessage: "fallback")
        #expect(error.message == "Bad credentials")
        #expect(error.code == .twoFactorRequired)
    }
}

// MARK: - HTTP client

struct HttpClientTests {
    @Test func reactive401RefreshesAndRetriesOnce() async throws {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, enableRetry: true, maxRetryAttempts: 3)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())

        // First call 401s; after "refresh" the stub is swapped to success.
        backend.stub("GET", "/api/secure", .init(statusCode: 401, json: #"{"message":"expired"}"#))
        await http.setTokenProvider { "token" }
        await http.setOn401Refresh {
            backend.stub("GET", "/api/secure", .init(json: #"{"ok":true}"#))
            return true
        }

        struct OkResponse: Decodable { var ok: Bool }
        let result: OkResponse = try await http.get("api/secure")
        #expect(result.ok)
    }

    @Test func clientErrorsAreNotRetried() async {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, enableRetry: true, maxRetryAttempts: 3)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        backend.stub("GET", "/api/missing", .init(statusCode: 404, json: #"{"message":"nope"}"#))

        do {
            let _: EmptyBody = try await http.get("api/missing", skipAuth: true)
            Issue.record("Expected a 404 error")
        } catch let error as WildwoodError {
            #expect(error.status == 404)
        } catch {
            Issue.record("Unexpected error type")
        }
        #expect(backend.requests().count == 1)
    }

    // MARK: Replay safety
    //
    // Parity with @wildwood/core: a 5xx or network failure says nothing about whether
    // the server already applied the request, so only idempotent methods may be
    // replayed. Timeouts and cancellations are never replayed, for any method.

    @Test func postIsStillReplayedAfterA401Refresh() async throws {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, enableRetry: true, maxRetryAttempts: 3)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())

        backend.stub("POST", "/api/submit", .init(statusCode: 401, json: #"{"message":"expired"}"#))
        await http.setTokenProvider { "token" }
        await http.setOn401Refresh {
            backend.stub("POST", "/api/submit", .init(json: #"{"ok":true}"#))
            return true
        }

        // A 401 is refused by auth middleware before the handler runs, so the request
        // provably had no effect — replaying it is safe even though POST is not
        // idempotent. This guards the ordering of the guards in request().
        struct OkResponse: Decodable { var ok: Bool }
        let result: OkResponse = try await http.post("api/submit", body: EmptyBody())
        #expect(result.ok)
        #expect(backend.requests().count == 2)
    }

    @Test func serverErrorsAreRetriedForGet() async {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, enableRetry: true, maxRetryAttempts: 2)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        backend.stub("GET", "/api/flaky", .init(statusCode: 503, json: #"{"message":"down"}"#))

        let _: EmptyBody? = try? await http.get("api/flaky", skipAuth: true)

        #expect(backend.requests().count == 2)
    }

    @Test func serverErrorsAreRetriedForPutAndDelete() async {
        let putBackend = MockBackend()
        let putConfig = WildwoodConfig(baseUrl: putBackend.baseUrl, enableRetry: true, maxRetryAttempts: 2)
        let putHttp = WildwoodHttpClient(config: putConfig, urlSession: putBackend.makeSession())
        putBackend.stub("PUT", "/api/thing", .init(statusCode: 500, json: #"{"message":"boom"}"#))

        _ = try? await putHttp.putVoid("api/thing", body: EmptyBody(), skipAuth: true)
        #expect(putBackend.requests().count == 2)

        let deleteBackend = MockBackend()
        let deleteConfig = WildwoodConfig(baseUrl: deleteBackend.baseUrl, enableRetry: true, maxRetryAttempts: 2)
        let deleteHttp = WildwoodHttpClient(config: deleteConfig, urlSession: deleteBackend.makeSession())
        deleteBackend.stub("DELETE", "/api/thing", .init(statusCode: 500, json: #"{"message":"boom"}"#))

        _ = try? await deleteHttp.deleteVoid("api/thing", skipAuth: true)
        #expect(deleteBackend.requests().count == 2)
    }

    @Test func serverErrorsAreNotReplayedForPost() async {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, enableRetry: true, maxRetryAttempts: 3)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        backend.stub("POST", "/api/feedback", .init(statusCode: 500, json: #"{"message":"boom"}"#))

        do {
            try await http.postVoid("api/feedback", body: EmptyBody(), skipAuth: true)
            Issue.record("Expected a 500 error")
        } catch let error as WildwoodError {
            #expect(error.status == 500)
        } catch {
            Issue.record("Unexpected error type")
        }

        // The submit must be delivered exactly once — replaying it would file the
        // feedback again, because the row commits before the response is produced.
        #expect(backend.requests().count == 1)
    }

    @Test func serverErrorsAreNotReplayedForPatch() async {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, enableRetry: true, maxRetryAttempts: 3)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        backend.stub("PATCH", "/api/thing", .init(statusCode: 500, json: #"{"message":"boom"}"#))

        let _: EmptyBody? = try? await http.patch("api/thing", body: EmptyBody(), skipAuth: true)

        #expect(backend.requests().count == 1)
    }

    @Test func networkErrorsAreNotReplayedForPost() async {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, enableRetry: true, maxRetryAttempts: 3)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        backend.stubError("POST", "/api/feedback", .cannotConnectToHost)

        do {
            try await http.postVoid("api/feedback", body: EmptyBody(), skipAuth: true)
            Issue.record("Expected a network error")
        } catch let error as WildwoodError {
            #expect(error.code == .networkError)
        } catch {
            Issue.record("Unexpected error type")
        }
        #expect(backend.requests().count == 1)
    }

    @Test func networkErrorsAreRetriedForGet() async {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, enableRetry: true, maxRetryAttempts: 2)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        backend.stubError("GET", "/api/flaky", .cannotConnectToHost)

        let _: EmptyBody? = try? await http.get("api/flaky", skipAuth: true)

        #expect(backend.requests().count == 2)
    }

    @Test func timeoutsAreNeverRetried() async {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, enableRetry: true, maxRetryAttempts: 3)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        backend.stubError("GET", "/api/slow", .timedOut)

        do {
            let _: EmptyBody = try await http.get("api/slow", skipAuth: true)
            Issue.record("Expected a timeout error")
        } catch let error as WildwoodError {
            #expect(error.code == .timeout)
        } catch {
            Issue.record("Unexpected error type")
        }

        // A timeout says nothing about whether the server processed the request,
        // so it is not replayed even though GET is idempotent.
        #expect(backend.requests().count == 1)
    }

    @Test func cancellationIsNeverRetried() async {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, enableRetry: true, maxRetryAttempts: 3)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        backend.stubError("GET", "/api/thing", .cancelled)

        do {
            let _: EmptyBody = try await http.get("api/thing", skipAuth: true)
            Issue.record("Expected a cancellation")
        } catch is CancellationError {
            // Expected: Swift surfaces caller cancellation as CancellationError rather
            // than JS's typed 'Cancelled' code — same behaviour, each stack's idiom.
        } catch {
            Issue.record("Unexpected error type")
        }
        #expect(backend.requests().count == 1)
    }

    @Test func emptyBodyDecodesToNilForOptionalTargets() async throws {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        backend.stub("GET", "/api/empty", .init(statusCode: 200, body: Data()))

        let value: EmptyBody? = try await http.get("api/empty", skipAuth: true)
        #expect(value == nil)
    }

    @Test func bearerTokenAndApiKeyHeadersAreAttached() async throws {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, apiKey: "api-key-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        await http.setTokenProvider { "bearer-token" }
        backend.stub("GET", "/api/thing", .init(json: "{}"))

        let _: EmptyBody = try await http.get("api/thing")

        let headers = backend.requests().first?.headers ?? [:]
        #expect(headers["Authorization"] == "Bearer bearer-token")
        #expect(headers["X-API-Key"] == "api-key-1")
    }
}

// MARK: - AI error parsing

struct AIServiceErrorParsingTests {
    @Test func parsesUsageLimitErrorBody() {
        let body = Data("""
        {"error":"AI token limit reached","limitCode":"AI_TOKENS",
         "currentUsage":5000,"maxValue":5000,"unit":"tokens"}
        """.utf8)
        let error = WildwoodError(message: "Too many requests", status: 429, details: body)

        let response = AIService.parseErrorResponse(error)
        #expect(response.isError)
        #expect(response.errorCode == "AI_TOKENS")
        #expect(response.errorMessage?.contains("AI token limit reached") == true)
        #expect(response.errorMessage?.contains("tokens") == true)
    }

    @Test func fallsBackToErrorMessage() {
        let error = WildwoodError(message: "Boom", status: 500)
        let response = AIService.parseErrorResponse(error)
        #expect(response.isError)
        #expect(response.errorMessage == "Boom")
    }
}
