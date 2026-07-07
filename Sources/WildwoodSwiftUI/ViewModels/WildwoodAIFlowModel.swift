// AI Flow state — the view-model equivalent of the Blazor AIFlowComponent
// code-behind (Blazor is the reference implementation; there is no JS AIFlow
// yet). Owns flow loading/selection, typed input building, run/cancel via
// Task cancellation, human-review resolution, and throttled streaming UI
// updates (~10/s for token frames, immediate for structural events).

import Foundation
import Observation
import WildwoodCore

@MainActor
@Observable
public final class WildwoodAIFlowModel {
    @ObservationIgnored private let service: AIFlowService
    @ObservationIgnored public let settings: AIFlowSettings

    /// Called with the run's terminal result — never for interrupted runs
    /// (those are still awaiting human review).
    @ObservationIgnored public var onRunCompleted: ((AIFlowRunResult) -> Void)?

    public private(set) var flows: [AIFlow] = []
    public private(set) var isLoadingFlows = true
    public private(set) var isRunning = false
    public private(set) var selectedFlowId: String?
    public private(set) var selectedFlow: AIFlow?
    public private(set) var inputs: [String: String] = [:]
    public var rawInput = "{}"

    public private(set) var streamText = ""
    public private(set) var activeNode: String?
    /// Pending human-review payload (pretty JSON) when the run is interrupted.
    public private(set) var pendingInterrupt: String?
    public private(set) var isEditingResume = false
    public var resumeEditValue = ""
    public var errorMessage = ""
    public private(set) var result: AIFlowRunResult?
    public private(set) var history: [AIFlowRunSummary] = []
    public private(set) var debugEvents: [String] = []

    public private(set) var threadId: String?
    public private(set) var activeRunId: String?

    // Streamed tokens accumulate here (cheap append); streamText is
    // materialized from it only on a throttled flush so long streams don't
    // fire a SwiftUI update per token.
    @ObservationIgnored private var streamBuffer = ""
    @ObservationIgnored private var lastFlush = ContinuousClock.now
    @ObservationIgnored private var runTask: Task<Void, Never>?

    public init(client: WildwoodClient, settings: AIFlowSettings = AIFlowSettings()) {
        self.settings = settings
        if let appId = settings.appId, !appId.isEmpty, appId != client.config.appId {
            self.service = AIFlowService(http: client.http, appId: appId)
        } else {
            self.service = client.aiFlow
        }
    }

    // MARK: - Flows

    public func loadFlows() async {
        isLoadingFlows = true
        defer { isLoadingFlows = false }
        do {
            flows = try await service.getFlows()
        } catch {
            flows = []
            errorMessage = friendlyMessage(error)
            return
        }

        // Auto-select a fixed flow, or the only flow.
        if let fixed = settings.flowId, !fixed.isEmpty {
            selectFlow(id: fixed)
        } else if flows.count == 1 {
            selectFlow(id: flows[0].id)
        }
    }

    public func selectFlow(id: String?) {
        selectedFlowId = id
        selectedFlow = nil
        inputs = [:]
        rawInput = "{}"
        // A thread's checkpoint holds one flow's state — switching flows must
        // start a fresh thread, not resume the previous flow's checkpoint.
        threadId = nil
        activeRunId = nil
        history = []
        resetRunState()

        guard let id, !id.isEmpty else { return }
        selectedFlow = flows.first { $0.id == id }
    }

    public func input(for name: String) -> String {
        inputs[name] ?? ""
    }

    public func setInput(_ value: String, for name: String) {
        inputs[name] = value
    }

    // MARK: - Running

    public func run() {
        guard let flow = selectedFlow, !isRunning else { return }
        resetRunState()

        guard let inputJson = buildInputJson() else {
            errorMessage = "Input must be valid JSON."
            return
        }

        isRunning = true
        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.service.runFlow(
                flowId: flow.id,
                inputJson: inputJson,
                threadId: self.threadId,
                onEvent: { [weak self] event in self?.handleEvent(event) }
            )
            await self.finishRun(result)
            self.isRunning = false
        }
    }

    /// Stop the active run — Task cancellation surfaces as a "cancelled" result.
    public func cancel() {
        runTask?.cancel()
    }

    // MARK: - Human review

    public func approve() {
        resolve(approve: true, valueJson: nil)
    }

    public func reject() {
        resolve(approve: false, valueJson: nil)
    }

    public func startResumeEdit() {
        isEditingResume = true
        errorMessage = ""
        // Start empty: an unchanged submit falls back to the server's default
        // approval resolution, which is shape-correct for BOTH agent HITL and
        // plain interrupt nodes.
        resumeEditValue = ""
    }

    public func cancelResumeEdit() {
        isEditingResume = false
    }

    public func submitResumeEdit() {
        let trimmed = resumeEditValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            resolve(approve: true, valueJson: nil) // empty edit → default approve
            return
        }
        // Fail fast on malformed JSON — don't send it.
        guard (try? JSONDecoder().decode(JSONValue.self, from: Data(trimmed.utf8))) != nil else {
            errorMessage = "Edited resume value must be valid JSON."
            return
        }
        resolve(approve: true, valueJson: trimmed)
    }

    private func resolve(approve: Bool, valueJson: String?) {
        guard let runId = activeRunId, !runId.isEmpty, !isRunning else { return }
        pendingInterrupt = nil
        isEditingResume = false
        isRunning = true
        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.service.resolveInterrupt(
                runId: runId,
                approve: approve,
                valueJson: valueJson,
                onEvent: { [weak self] event in self?.handleEvent(event) }
            )
            await self.finishRun(result)
            self.isRunning = false
        }
    }

    // MARK: - Event handling

    private func handleEvent(_ event: AIFlowRunEvent) {
        let obj = event.data?.objectValue
        switch event.event {
        case "run_started":
            if let runId = obj?["runId"]?.stringValue, !runId.isEmpty { activeRunId = runId }
            if let thread = obj?["threadId"]?.stringValue, !thread.isEmpty { threadId = thread }
        case "node_start":
            activeNode = obj?["node"]?.stringValue
        case "node_end":
            if activeNode == obj?["node"]?.stringValue { activeNode = nil }
        case "token":
            streamBuffer += obj?["content"]?.stringValue ?? ""
        case "interrupt":
            if let payload = obj?["payload"] {
                pendingInterrupt = payload.prettyJSONString ?? ""
            }
        default:
            break
        }

        if settings.showDebugInfo {
            debugEvents.append("\(event.event): \(Self.shortData(event))")
            if debugEvents.count > 200 { debugEvents.removeFirst() }
        }

        // Flush immediately for structural events; throttle token-only
        // updates to ~10/s so a long stream doesn't thrash the UI.
        let isToken = event.event == "token"
        let now = ContinuousClock.now
        if !isToken || lastFlush.duration(to: now) >= .milliseconds(100) {
            lastFlush = now
            streamText = streamBuffer
        }
    }

    private func finishRun(_ result: AIFlowRunResult) async {
        // Materialize tokens that arrived after the last throttled flush.
        streamText = streamBuffer
        if let runId = result.runId, !runId.isEmpty { activeRunId = runId }
        if let thread = result.threadId, !thread.isEmpty { threadId = thread }
        activeNode = nil
        if result.status != "interrupted" {
            pendingInterrupt = nil
        }
        self.result = result
        if result.status != "interrupted" {
            onRunCompleted?(result)
        }
        await loadHistory()
    }

    /// Refresh the current thread's run history. Best-effort: history is an
    /// enrichment and a lookup failure must never disturb the run result
    /// already on screen.
    public func loadHistory() async {
        guard settings.showRunHistory, let threadId, !threadId.isEmpty else { return }
        if let runs = try? await service.getThreadRuns(threadId: threadId) {
            history = runs
        }
    }

    private func resetRunState() {
        streamText = ""
        streamBuffer = ""
        activeNode = nil
        pendingInterrupt = nil
        isEditingResume = false
        resumeEditValue = ""
        errorMessage = ""
        result = nil
        debugEvents = []
    }

    private func friendlyMessage(_ error: any Error) -> String {
        (error as? WildwoodError)?.message ?? error.localizedDescription
    }

    // MARK: - Input building (internal for tests)

    func buildInputJson() -> String? {
        Self.buildInputJson(
            fields: selectedFlow?.inputFields ?? [],
            inputs: inputs,
            rawInput: rawInput
        )
    }

    static func buildInputJson(
        fields: [AIFlowInputField],
        inputs: [String: String],
        rawInput: String
    ) -> String? {
        if !fields.isEmpty {
            // Preserve JSON types: numbers/bools/null/objects entered in a
            // field pass through as typed values; everything else is a string.
            var object: [String: JSONValue] = [:]
            for field in fields {
                if let value = inputs[field.name], !value.isEmpty {
                    object[field.name] = parseInputValue(value)
                }
            }
            return JSONValue.object(object).rawJSONString ?? "{}"
        }

        // Free-form JSON input must be a valid object.
        let raw = rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : rawInput
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)),
              value.objectValue != nil else {
            return nil
        }
        return raw
    }

    /// Parses a raw field value into a typed JSON value where possible:
    /// whole-string true/false/null/number, JSON object/array verbatim,
    /// anything else stays a string.
    static func parseInputValue(_ raw: String) -> JSONValue {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "null": return .null
        default: break
        }

        // Only treat as a number when the whole string is a JSON number
        // (decoding enforces the grammar — no "5 apples", "inf", or hex).
        if let first = trimmed.first, first == "-" || first.isNumber,
           let value = try? JSONDecoder().decode(JSONValue.self, from: Data(trimmed.utf8)),
           value.numberValue != nil {
            return value
        }

        // JSON object/array typed through verbatim; anything else stays a string.
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")),
           let value = try? JSONDecoder().decode(JSONValue.self, from: Data(trimmed.utf8)) {
            return value
        }
        return .string(raw)
    }

    private static func shortData(_ event: AIFlowRunEvent) -> String {
        guard let data = event.data, let text = data.rawJSONString else { return "" }
        return text.count > 120 ? String(text.prefix(120)) + "…" : text
    }
}
