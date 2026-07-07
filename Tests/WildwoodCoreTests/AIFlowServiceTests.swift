// AIFlowService behavior mirrored from the Blazor AIFlowService semantics:
// SSE frame parsing into a terminal result, malformed-frame tolerance,
// trailing-frame dispatch, early stop at the first terminal event, the
// plain-JSON reject path → "cancelled", 403 access denial, and throwing
// list lookups (June 2026 decision).

import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct AIFlowServiceTests {
    private func makeService(appId: String? = nil) -> (AIFlowService, MockBackend) {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        return (AIFlowService(http: http, appId: appId), backend)
    }

    private func sse(_ text: String) -> StubResponse {
        StubResponse(statusCode: 200, body: Data(text.utf8), headers: ["Content-Type": "text/event-stream"])
    }

    /// MainActor-bound event sink — a captured `var` in a @MainActor closure
    /// trips the concurrent-mutation check, a reference type does not.
    @MainActor
    private final class EventCollector {
        var events: [AIFlowRunEvent] = []
        func append(_ event: AIFlowRunEvent) { events.append(event) }
    }

    // MARK: - Lookups

    @Test func getFlowsParsesTheListAndThrowsOnFailure() async throws {
        let (service, backend) = makeService()
        backend.stub(
            "GET", "/api/ai/flows",
            .init(json: #"[{"id":"f1","name":"Draft","description":"Writes a draft","inputFields":[{"name":"topic","reducer":"overwrite"}]}]"#)
        )

        let flows = try await service.getFlows()
        #expect(flows.count == 1)
        #expect(flows[0].name == "Draft")
        #expect(flows[0].inputFields.first?.name == "topic")

        // Lookups THROW on failure — never a silent empty list.
        let (service2, _) = makeService() // no stub → 404
        await #expect(throws: WildwoodError.self) {
            _ = try await service2.getFlows()
        }
    }

    @Test func getThreadRunsParsesSummariesAndThrowsOnFailure() async throws {
        let (service, backend) = makeService()
        backend.stub(
            "GET", "/api/ai/flows/threads/t1/runs",
            .init(json: #"[{"id":"r1","flowId":"f1","threadId":"t1","triggerType":"manual","status":"succeeded","createdAt":"2026-07-01T10:00:00Z","durationMs":1500,"totalTokens":42}]"#)
        )

        let runs = try await service.getThreadRuns(threadId: "t1")
        #expect(runs.count == 1)
        #expect(runs[0].status == "succeeded")
        #expect(runs[0].durationMs == 1500)
        #expect(runs[0].createdAt != nil)

        let (service2, _) = makeService() // no stub → 404
        await #expect(throws: WildwoodError.self) {
            _ = try await service2.getThreadRuns(threadId: "t1")
        }
    }

    // MARK: - SSE run streams

    @Test func runFlowParsesTheStreamIntoATerminalResult() async {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/ai/flows/f1/runs/stream", sse("""
        event: run_started
        data: {"runId":"r1","threadId":"t1"}

        event: node_start
        data: {"node":"draft"}

        event: token
        data: {"content":"Hel"}

        event: token
        data: {"content":"lo"}

        event: node_end
        data: {"node":"draft"}

        event: usage
        data: {"totalTokens":42}

        event: done
        data: {"status":"succeeded","output":{"text":"Hello"}}

        """))

        let received = EventCollector()
        let result = await service.runFlow(
            flowId: "f1",
            inputJson: "{}",
            threadId: nil,
            onEvent: { received.append($0) }
        )

        #expect(result.status == "succeeded")
        #expect(result.runId == "r1")
        #expect(result.threadId == "t1")
        #expect(result.totalTokens == 42)
        #expect(result.outputJson?.contains("Hello") == true)
        #expect(result.errorMessage == nil)
        #expect(received.events.map(\.event) == ["run_started", "node_start", "token", "token", "node_end", "usage", "done"])
    }

    @Test func runFlowStopsAtTheFirstTerminalEvent() async {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/ai/flows/f1/runs/stream", sse("""
        event: done
        data: {"status":"succeeded"}

        event: token
        data: {"content":"IGNORED"}

        """))

        let received = EventCollector()
        let result = await service.runFlow(flowId: "f1", inputJson: "{}", onEvent: { received.append($0) })

        #expect(result.status == "succeeded")
        // Nothing after the terminal event is dispatched.
        #expect(received.events.map(\.event) == ["done"])
    }

    @Test func malformedFramesAreToleratedAndTheRunStillCompletes() async {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/ai/flows/f1/runs/stream", sse("""
        event: token
        data: {broken json !!

        event: token
        data: {"content":"ok"}

        event: done
        data: {"status":"succeeded"}

        """))

        let received = EventCollector()
        let result = await service.runFlow(flowId: "f1", inputJson: "{}", onEvent: { received.append($0) })

        #expect(result.status == "succeeded")
        // The malformed frame is still dispatched — with nil data.
        #expect(received.events.count == 3)
        #expect(received.events[0].event == "token")
        #expect(received.events[0].data == nil)
        #expect(received.events[1].data != nil)
    }

    @Test func aTrailingFrameWithoutAFinalBlankLineIsDispatched() async {
        let (service, backend) = makeService()
        // No trailing blank line (and no trailing newline) after the done frame.
        backend.stub(
            "POST", "/api/ai/flows/f1/runs/stream",
            sse("event: usage\ndata: {\"totalTokens\":7}\n\nevent: done\ndata: {\"status\":\"succeeded\"}")
        )

        let received = EventCollector()
        let result = await service.runFlow(flowId: "f1", inputJson: "{}", onEvent: { received.append($0) })

        #expect(result.status == "succeeded")
        #expect(result.totalTokens == 7)
        #expect(received.events.map(\.event) == ["usage", "done"])
    }

    @Test func interruptProducesAnInterruptedResultWithThePayload() async {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/ai/flows/f1/runs/stream", sse("""
        event: run_started
        data: {"runId":"r9","threadId":"t9"}

        event: interrupt
        data: {"payload":{"question":"Approve the draft?"}}

        """))

        let result = await service.runFlow(flowId: "f1", inputJson: "{}")

        #expect(result.status == "interrupted")
        #expect(result.runId == "r9")
        #expect(result.interruptPayloadJson?.contains("Approve the draft?") == true)
    }

    @Test func framesAfterAnInterruptAreStillConsumed() async {
        // Interrupt is NOT terminal (parity with Blazor/JS): the server can
        // still send frames like usage afterwards; only done/error stop the read.
        let (service, backend) = makeService()
        backend.stub("POST", "/api/ai/flows/f1/runs/stream", sse("""
        event: run_started
        data: {"runId":"r9","threadId":"t9"}

        event: interrupt
        data: {"payload":{"question":"Approve the draft?"}}

        event: usage
        data: {"totalTokens":13}

        """))

        let received = EventCollector()
        let result = await service.runFlow(flowId: "f1", inputJson: "{}", onEvent: { received.append($0) })

        #expect(result.status == "interrupted")
        #expect(result.interruptPayloadJson?.contains("Approve the draft?") == true)
        // The post-interrupt usage frame was consumed and counted.
        #expect(result.totalTokens == 13)
        #expect(received.events.map(\.event) == ["run_started", "interrupt", "usage"])
    }

    @Test func errorEventProducesAFailedResult() async {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/ai/flows/f1/runs/stream", sse("""
        event: error
        data: {"message":"Model unavailable"}

        """))

        let result = await service.runFlow(flowId: "f1", inputJson: "{}")

        #expect(result.status == "failed")
        #expect(result.errorMessage == "Model unavailable")
    }

    @Test func rejectAnswersWithPlainJSONWhichMapsToCancelled() async {
        let (service, backend) = makeService()
        // The reject path responds with a plain JSON body, not an SSE stream.
        backend.stub("POST", "/api/ai/flows/runs/r1/resume", .init(json: #"{"status":"rejected"}"#))

        let received = EventCollector()
        let result = await service.resolveInterrupt(runId: "r1", approve: false, onEvent: { received.append($0) })

        #expect(result.status == "cancelled")
        #expect(received.events.isEmpty)
    }

    @Test func approveStreamsTheResumedRun() async {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/ai/flows/runs/r1/resume", sse("""
        event: done
        data: {"status":"succeeded","output":"resumed"}

        """))

        let result = await service.resolveInterrupt(runId: "r1", approve: true, valueJson: #"{"ok":true}"#)

        #expect(result.status == "succeeded")
        #expect(result.outputJson?.contains("resumed") == true)
    }

    @Test func forbiddenMapsToTheAccessDeniedMessageWithoutThrowing() async {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/ai/flows/f1/runs/stream", .init(statusCode: 403, json: #"{"message":"Forbidden"}"#))

        let result = await service.runFlow(flowId: "f1", inputJson: "{}")

        #expect(result.status == "failed")
        #expect(result.errorMessage == "You don't have access to this flow.")
    }

    @Test func httpFailureProducesAFailedResultWithTheServerMessage() async {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/ai/flows/f1/runs/stream", .init(statusCode: 500, json: #"{"message":"boom"}"#))

        let result = await service.runFlow(flowId: "f1", inputJson: "{}")

        #expect(result.status == "failed")
        #expect(result.errorMessage == "boom")
    }
}
