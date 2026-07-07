// WildwoodAIFlowModel state tests (no network) — typed input parsing and
// input-JSON building mirrored from the Blazor AIFlowComponent semantics,
// plus resume-edit validation.

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
}
