// WildwoodAIFlowModel tests — typed input parsing and input-JSON building
// mirrored from the Blazor AIFlowComponent semantics, resume-edit validation,
// and the interrupt/resume lifecycle over a stubbed backend (TestBackend).

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct AIFlowModelTests {
    private func makeModel(settings: AIFlowSettings = AIFlowSettings()) -> WildwoodAIFlowModel {
        let client = WildwoodClient(
            config: WildwoodConfig(baseUrl: "https://unit.test", appId: "app-1", storage: .memory)
        )
        return WildwoodAIFlowModel(client: client, settings: settings)
    }

    // MARK: - Typed input parsing

    @Test func parseInputValueProducesTypedJSONValues() {
        #expect(WildwoodAIFlowModel.parseInputValue("true") == .bool(true))
        #expect(WildwoodAIFlowModel.parseInputValue(" false ") == .bool(false))
        #expect(WildwoodAIFlowModel.parseInputValue("null") == .null)
        #expect(WildwoodAIFlowModel.parseInputValue("42") == .number(42))
        #expect(WildwoodAIFlowModel.parseInputValue("-7") == .number(-7))
        #expect(WildwoodAIFlowModel.parseInputValue("3.5") == .number(3.5))
        #expect(WildwoodAIFlowModel.parseInputValue(#"{"a":1}"#) == .object(["a": .number(1)]))
        #expect(WildwoodAIFlowModel.parseInputValue("[1,2]") == .array([.number(1), .number(2)]))
    }

    @Test func parseInputValueKeepsNonWholeMatchesAsStrings() {
        // Only whole-string primitives are typed — "5 apples" is not a number.
        #expect(WildwoodAIFlowModel.parseInputValue("5 apples") == .string("5 apples"))
        #expect(WildwoodAIFlowModel.parseInputValue("hello") == .string("hello"))
        #expect(WildwoodAIFlowModel.parseInputValue("True") == .string("True"))
        // Malformed object/array input stays a verbatim string.
        #expect(WildwoodAIFlowModel.parseInputValue("{broken") == .string("{broken"))
        #expect(WildwoodAIFlowModel.parseInputValue("{broken}") == .string("{broken}"))
    }

    // MARK: - Input JSON building

    @Test func buildInputJsonSerializesTypedFieldsAndSkipsEmptyOnes() throws {
        let fields = [
            AIFlowInputField(name: "topic"),
            AIFlowInputField(name: "count"),
            AIFlowInputField(name: "draft"),
            AIFlowInputField(name: "skipped"),
        ]
        let json = WildwoodAIFlowModel.buildInputJson(
            fields: fields,
            inputs: ["topic": "AI news", "count": "3", "draft": "true"],
            rawInput: "ignored"
        )

        let text = try #require(json)
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        #expect(value == .object([
            "topic": .string("AI news"),
            "count": .number(3),
            "draft": .bool(true),
        ]))
    }

    @Test func buildInputJsonValidatesTheRawFallbackAsAnObject() {
        // No fields → the raw JSON must be a valid object.
        #expect(WildwoodAIFlowModel.buildInputJson(fields: [], inputs: [:], rawInput: #"{"a":1}"#) == #"{"a":1}"#)
        #expect(WildwoodAIFlowModel.buildInputJson(fields: [], inputs: [:], rawInput: "   ") == "{}")
        #expect(WildwoodAIFlowModel.buildInputJson(fields: [], inputs: [:], rawInput: "not json") == nil)
        #expect(WildwoodAIFlowModel.buildInputJson(fields: [], inputs: [:], rawInput: "[1,2]") == nil)
        #expect(WildwoodAIFlowModel.buildInputJson(fields: [], inputs: [:], rawInput: "42") == nil)
    }

    // MARK: - Resume edit validation

    @Test func submitResumeEditRejectsMalformedJSONWithoutSending() {
        let model = makeModel()
        model.resumeEditValue = "{oops"
        model.submitResumeEdit()
        #expect(model.errorMessage == "Edited resume value must be valid JSON.")
    }

    @Test func initialStateIsEmpty() {
        let model = makeModel()
        #expect(model.flows.isEmpty)
        #expect(model.selectedFlow == nil)
        #expect(model.isRunning == false)
        #expect(model.result == nil)
        #expect(model.pendingInterrupt == nil)
        #expect(model.rawInput == "{}")
    }

    // MARK: - Resume failure restores the interrupt

    @Test func failedResumeRestoresThePendingInterruptForRetry() async {
        let backend = TestBackend()
        backend.stub("GET", "/api/ai/flows", .init(json: #"[{"id":"f1","name":"Draft"}]"#))
        backend.stub("POST", "/api/ai/flows/f1/runs/stream", .init(sse: """
        event: run_started
        data: {"runId":"r1","threadId":"t1"}

        event: interrupt
        data: {"payload":{"question":"Approve the draft?"}}

        """))
        // The resume attempt fails — the interrupt is still pending server-side.
        backend.stub("POST", "/api/ai/flows/runs/r1/resume", .init(statusCode: 500, json: #"{"message":"boom"}"#))

        let client = WildwoodClient(
            config: WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false, storage: .memory),
            urlSession: backend.makeSession()
        )
        let model = WildwoodAIFlowModel(client: client, settings: AIFlowSettings(showRunHistory: false))

        await model.loadFlows() // auto-selects the only flow
        model.run()
        await model.runTask?.value
        #expect(model.isRunning == false)
        #expect(model.result?.status == "interrupted")
        let interrupt = model.pendingInterrupt
        #expect(interrupt?.contains("Approve the draft?") == true)

        model.approve()
        // Cleared while the resolution is in flight…
        #expect(model.pendingInterrupt == nil)
        await model.runTask?.value

        // …but a FAILED resume restores it so the Approve/Reject panel
        // returns and the user can retry (finishRun must not re-clear it).
        #expect(model.result?.status == "failed")
        #expect(model.pendingInterrupt == interrupt)
        #expect(model.isRunning == false)
    }

    @Test func successfulResumeDoesNotRestoreTheInterrupt() async {
        let backend = TestBackend()
        backend.stub("GET", "/api/ai/flows", .init(json: #"[{"id":"f1","name":"Draft"}]"#))
        backend.stub("POST", "/api/ai/flows/f1/runs/stream", .init(sse: """
        event: run_started
        data: {"runId":"r1","threadId":"t1"}

        event: interrupt
        data: {"payload":{"question":"Approve the draft?"}}

        """))
        backend.stub("POST", "/api/ai/flows/runs/r1/resume", .init(sse: """
        event: done
        data: {"status":"succeeded","output":"resumed"}

        """))

        let client = WildwoodClient(
            config: WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false, storage: .memory),
            urlSession: backend.makeSession()
        )
        let model = WildwoodAIFlowModel(client: client, settings: AIFlowSettings(showRunHistory: false))

        await model.loadFlows()
        model.run()
        await model.runTask?.value
        #expect(model.pendingInterrupt != nil)

        model.approve()
        await model.runTask?.value

        #expect(model.result?.status == "succeeded")
        #expect(model.pendingInterrupt == nil)
        #expect(model.isRunning == false)
    }
}
