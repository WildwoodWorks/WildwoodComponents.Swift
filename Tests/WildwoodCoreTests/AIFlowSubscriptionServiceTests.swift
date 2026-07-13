// AIFlowSubscriptionService behavior mirrored from the Blazor
// AIFlowSubscriptionService semantics, adapted to the Swift throwing idiom
// (June 2026 decision — CRUD/lookups throw rather than swallowing errors into
// an empty/null result). Covers list/create/update/enable-disable/delete/
// latest-run, the 404 -> nil mapping on latest-run, the 429 create failure
// surfacing as a thrown WildwoodError, and request path/body shapes.

import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct AIFlowSubscriptionServiceTests {
    private func makeService(appId: String? = "app-1") -> (AIFlowSubscriptionService, MockBackend) {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        return (AIFlowSubscriptionService(http: http, appId: appId), backend)
    }

    private func jsonBody(_ req: RecordedRequest) throws -> [String: Any] {
        let data = try #require(req.body)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - List

    @Test func getSubscriptionsParsesTheListAndThrowsOnFailure() async throws {
        let (service, backend) = makeService()
        backend.stub(
            "GET", "/api/ai/flows/subscriptions",
            .init(json: #"[{"id":"s1","flowId":"f1","flowName":"Trail Forecast","name":"Backcountry","scheduleCron":"0 6 * * *","scheduleTimezone":"America/Denver","nextRunAt":"2026-07-13T06:00:00Z","isEnabled":true,"notifyOnComplete":true,"createdAt":"2026-07-01T10:00:00Z"}]"#)
        )

        let subs = try await service.getSubscriptions()
        #expect(subs.count == 1)
        #expect(subs[0].id == "s1")
        #expect(subs[0].flowName == "Trail Forecast")
        #expect(subs[0].isEnabled == true)
        #expect(subs[0].scheduleCron == "0 6 * * *")
        #expect(subs[0].nextRunAt == "2026-07-13T06:00:00Z")

        // Lookups THROW on failure — never a silent empty list.
        let (service2, _) = makeService() // no stub -> 404
        await #expect(throws: WildwoodError.self) {
            _ = try await service2.getSubscriptions()
        }
    }

    // MARK: - Create

    @Test func createPostsTheRequestBodyAndReturnsTheSubscription() async throws {
        let (service, backend) = makeService()
        backend.stub(
            "POST", "/api/ai/flows/subscriptions",
            .init(json: #"{"id":"s2","flowId":"f1","flowName":"Trail Forecast","name":"Sunrise","scheduleCron":"0 5 * * *","isEnabled":true,"notifyOnComplete":true,"createdAt":"2026-07-02T00:00:00Z"}"#)
        )

        let created = try await service.create(
            AIFlowSubscriptionCreateRequest(
                flowId: "f1",
                name: "Sunrise",
                scheduleCron: "0 5 * * *",
                inputJson: #"{"location":"peak"}"#
            )
        )
        #expect(created.id == "s2")
        #expect(created.name == "Sunrise")

        let req = try #require(backend.requests().first { $0.method == "POST" && $0.path == "/api/ai/flows/subscriptions" })
        let body = try jsonBody(req)
        #expect(body["flowId"] as? String == "f1")
        #expect(body["name"] as? String == "Sunrise")
        #expect(body["scheduleCron"] as? String == "0 5 * * *")
        #expect(body["inputJson"] as? String == #"{"location":"peak"}"#)
        // notifyOnComplete defaults to true and is always sent.
        #expect(body["notifyOnComplete"] as? Bool == true)
        // An unset optional is omitted so the server applies its default.
        #expect(body["scheduleTimezone"] == nil)
    }

    @Test func createSurfaces429AsAThrownError() async {
        let (service, backend) = makeService()
        backend.stub(
            "POST", "/api/ai/flows/subscriptions",
            .init(statusCode: 429, json: #"{"message":"Your plan's favorites limit has been reached."}"#)
        )

        do {
            _ = try await service.create(
                AIFlowSubscriptionCreateRequest(flowId: "f1", name: "x", scheduleCron: "0 5 * * *")
            )
            Issue.record("Expected create to throw on 429")
        } catch let error as WildwoodError {
            #expect(error.status == 429)
            #expect(error.message == "Your plan's favorites limit has been reached.")
        } catch {
            Issue.record("Expected WildwoodError, got \(error)")
        }
    }

    @Test func create429WithoutBodyMessageUsesFriendlyFallback() async {
        let (service, backend) = makeService()
        // 429 with no `message` in the body — the service must supply the friendly
        // upgrade copy rather than the generic HTTP status text.
        backend.stub("POST", "/api/ai/flows/subscriptions", .init(statusCode: 429, json: "{}"))

        do {
            _ = try await service.create(
                AIFlowSubscriptionCreateRequest(flowId: "f1", name: "x", scheduleCron: "0 5 * * *")
            )
            Issue.record("Expected create to throw on 429")
        } catch let error as WildwoodError {
            #expect(error.status == 429)
            #expect(error.message == "Your plan's favorites limit has been reached.")
        } catch {
            Issue.record("Expected WildwoodError, got \(error)")
        }
    }

    // MARK: - Update

    @Test func updatePutsOnlyTheProvidedFields() async throws {
        let (service, backend) = makeService()
        backend.stub(
            "PUT", "/api/ai/flows/subscriptions/s1",
            .init(json: #"{"id":"s1","flowId":"f1","flowName":"Trail Forecast","name":"Renamed","isEnabled":true,"notifyOnComplete":false,"createdAt":"2026-07-01T10:00:00Z"}"#)
        )

        let updated = try await service.update("s1", AIFlowSubscriptionUpdateRequest(name: "Renamed", notifyOnComplete: false))
        #expect(updated.name == "Renamed")
        #expect(updated.notifyOnComplete == false)

        let req = try #require(backend.requests().first { $0.method == "PUT" && $0.path == "/api/ai/flows/subscriptions/s1" })
        let body = try jsonBody(req)
        #expect(body["name"] as? String == "Renamed")
        #expect(body["notifyOnComplete"] as? Bool == false)
        // Unset optionals are omitted (leave-unchanged).
        #expect(body["scheduleCron"] == nil)
        #expect(body["inputJson"] == nil)
    }

    // MARK: - Enable / disable

    @Test func setEnabledPostsEnableWithNoBody() async throws {
        let (service, backend) = makeService()
        backend.stub(
            "POST", "/api/ai/flows/subscriptions/s1/enable",
            .init(json: #"{"id":"s1","flowId":"f1","flowName":"F","name":"N","isEnabled":true,"notifyOnComplete":true,"createdAt":"2026-07-01T10:00:00Z"}"#)
        )

        let result = try await service.setEnabled("s1", true)
        #expect(result.isEnabled == true)

        let req = try #require(backend.requests().first { $0.path == "/api/ai/flows/subscriptions/s1/enable" })
        #expect(req.method == "POST")
        #expect((req.body ?? Data()).isEmpty)
    }

    @Test func setEnabledPostsDisableWhenFalse() async throws {
        let (service, backend) = makeService()
        backend.stub(
            "POST", "/api/ai/flows/subscriptions/s1/disable",
            .init(json: #"{"id":"s1","flowId":"f1","flowName":"F","name":"N","isEnabled":false,"notifyOnComplete":true,"createdAt":"2026-07-01T10:00:00Z"}"#)
        )

        let result = try await service.setEnabled("s1", false)
        #expect(result.isEnabled == false)
        #expect(backend.requests().contains { $0.method == "POST" && $0.path == "/api/ai/flows/subscriptions/s1/disable" })
    }

    // MARK: - Delete

    @Test func deleteReturnsTrueOnSuccessAndFalseOnFailure() async {
        let (service, backend) = makeService()
        backend.stub("DELETE", "/api/ai/flows/subscriptions/s1", .init(statusCode: 200))
        #expect(await service.delete("s1") == true)
        #expect(backend.requests().contains { $0.method == "DELETE" && $0.path == "/api/ai/flows/subscriptions/s1" })

        let (service2, _) = makeService() // no stub -> 404
        #expect(await service2.delete("s1") == false)
    }

    // MARK: - Latest run

    @Test func getLatestRunParsesTheDetail() async throws {
        let (service, backend) = makeService()
        backend.stub(
            "GET", "/api/ai/flows/subscriptions/s1/latest-run",
            .init(json: #"{"id":"r1","flowId":"f1","threadId":"t1","triggerType":"schedule","status":"succeeded","createdAt":"2026-07-05T06:00:00Z","durationMs":900,"totalTokens":128,"inputJson":"{\"loc\":\"peak\"}","outputJson":"{\"summary\":\"clear\"}"}"#)
        )

        let detail = try await service.getLatestRun("s1")
        let run = try #require(detail)
        #expect(run.id == "r1")
        #expect(run.status == "succeeded")
        #expect(run.totalTokens == 128)
        #expect(run.outputJson?.contains("clear") == true)
        #expect(run.createdAt != nil)
    }

    @Test func getLatestRunMaps404ToNil() async throws {
        let (service, _) = makeService() // no stub -> 404
        let detail = try await service.getLatestRun("s1")
        #expect(detail == nil)
    }

    @Test func getLatestRunRethrowsNon404Errors() async {
        let (service, backend) = makeService()
        backend.stub("GET", "/api/ai/flows/subscriptions/s1/latest-run", .init(statusCode: 500, json: #"{"message":"boom"}"#))
        await #expect(throws: WildwoodError.self) {
            _ = try await service.getLatestRun("s1")
        }
    }
}
