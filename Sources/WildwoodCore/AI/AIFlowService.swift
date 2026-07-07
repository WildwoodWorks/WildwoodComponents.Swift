// AI Flow service ported from WildwoodComponents.Blazor/Services/AIFlowService.cs
// (the Blazor stack is the reference implementation for AI Flows).
//
// Runs execute the published flow version and stream over SSE. Streaming goes
// through WildwoodHttpClient's SSE post verb so auth injection, reactive 401
// refresh + replay, and the parity script's endpoint extraction all keep
// working; frame parsing lives here, mirroring the Blazor service.

import Foundation
import Synchronization

public final class AIFlowService: Sendable {
    /// Per-frame event callback. MainActor-isolated because flow events drive
    /// UI state, matching WildwoodEventEmitter.Handler.
    public typealias EventHandler = @MainActor (AIFlowRunEvent) -> Void

    /// Default idle timeout (seconds) between SSE chunks — a flow node can
    /// work for minutes before its next event, so the JSON default (30s) is
    /// far too tight for run streams.
    public static let defaultStreamTimeout: TimeInterval = 600

    private let http: WildwoodHttpClient
    private let appId: String?

    public init(http: WildwoodHttpClient, appId: String? = nil) {
        self.http = http
        self.appId = appId
    }

    /// Published flows runnable by the current user. THROWS on failure —
    /// lookups must stay distinguishable from a genuinely empty list
    /// (June 2026 decision).
    public func getFlows() async throws -> [AIFlow] {
        try await http.get("api/ai/flows\(appQuery())")
    }

    /// Prior runs on a conversation thread. THROWS on failure — lookups must
    /// stay distinguishable from a thread with no runs (June 2026 decision).
    public func getThreadRuns(threadId: String) async throws -> [AIFlowRunSummary] {
        try await http.get("api/ai/flows/threads/\(encodePath(threadId))/runs\(appQuery())")
    }

    /// Runs a flow, invoking `onEvent` for each SSE frame, and returns the
    /// terminal outcome. Never throws — failures land in the result's
    /// status/errorMessage (mirroring the Blazor service); cancel by
    /// cancelling the surrounding Task (status becomes "cancelled").
    public func runFlow(
        flowId: String,
        inputJson: String,
        threadId: String? = nil,
        timeout: TimeInterval? = nil,
        onEvent: EventHandler? = nil
    ) async -> AIFlowRunResult {
        struct RunFlowDto: Encodable {
            let inputJson: String
            let threadId: String?
        }
        let body = RunFlowDto(inputJson: inputJson, threadId: threadId)
        return await runStream(onEvent: onEvent) { onLine in
            try await self.http.post(
                "api/ai/flows/\(self.encodePath(flowId))/runs/stream\(self.appQuery())",
                body: body,
                timeout: timeout ?? Self.defaultStreamTimeout,
                onLine: onLine
            )
        }
    }

    /// Approves or rejects a pending human-review interrupt. Approve streams
    /// the resumed run; reject answers with a plain JSON (non-SSE) body, which
    /// maps to a terminal "cancelled".
    public func resolveInterrupt(
        runId: String,
        approve: Bool,
        valueJson: String? = nil,
        timeout: TimeInterval? = nil,
        onEvent: EventHandler? = nil
    ) async -> AIFlowRunResult {
        struct ResolveDto: Encodable {
            let action: String
            let valueJson: String?
        }
        let body = ResolveDto(action: approve ? "approve" : "reject", valueJson: valueJson)
        return await runStream(onEvent: onEvent) { onLine in
            try await self.http.post(
                "api/ai/flows/runs/\(self.encodePath(runId))/resume\(self.appQuery())",
                body: body,
                timeout: timeout ?? Self.defaultStreamTimeout,
                onLine: onLine
            )
        }
    }

    // ------------------------------------------------------------------

    /// Shared stream consumption for run/resume. `send` performs the actual
    /// SSE post (keeping the endpoint literal at the verb call site for the
    /// parity script) and returns the response Content-Type.
    private func runStream(
        onEvent: EventHandler?,
        send: (@Sendable (String) async -> Bool) async throws -> String
    ) async -> AIFlowRunResult {
        let parser = AIFlowStreamParser()
        do {
            let contentType = try await send { line in
                await parser.handleLine(line, onEvent: onEvent)
            }
            if contentType.lowercased().hasPrefix("text/event-stream") {
                // Dispatch a final buffered frame that lacked its trailing blank line.
                await parser.dispatchPendingFrame(onEvent: onEvent)
            } else {
                // The reject path (and any non-approve resolution) responds
                // with a plain JSON body, not an SSE stream — a terminal
                // "cancelled".
                parser.setStatus("cancelled")
            }
        } catch is CancellationError {
            parser.markCancelledIfUnresolved()
        } catch let error as WildwoodError {
            // 403 is a permission/feature denial (e.g. tier lacks AI_FLOWS) —
            // the token is valid, so no auth signal fires. A 401 landing here
            // means the http client's single refresh + replay already failed,
            // and that refresh flow emitted the session-expired signal (once
            // per token lifetime via the single-flight refresh coordinator).
            parser.fail(with: error)
        } catch {
            parser.fail(message: error.localizedDescription)
        }
        return parser.result
    }

    private func encodePath(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func appQuery() -> String {
        guard let appId, !appId.isEmpty else { return "" }
        return "?requestedAppId=\(appId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? appId)"
    }
}

/// Incremental SSE frame parser + terminal-result accumulator for flow run
/// streams. Sendable via Mutex: lines arrive through the HTTP actor's
/// @Sendable line callback while the result is read by the calling task.
final class AIFlowStreamParser: Sendable {
    private struct State {
        var eventName: String?
        var dataText = ""
        var result = AIFlowRunResult()
        var terminal = false
    }

    private let state = Mutex(State())

    var result: AIFlowRunResult {
        state.withLock { $0.result }
    }

    /// Feed one SSE line. Returns whether the transport should keep reading —
    /// false once a terminal event (done/error) has been dispatched.
    func handleLine(_ line: String, onEvent: AIFlowService.EventHandler?) async -> Bool {
        let frame: (name: String, dataText: String)? = state.withLock { s in
            if line.hasPrefix("event: ") {
                s.eventName = String(line.dropFirst("event: ".count))
                return nil
            }
            if line.hasPrefix("data: ") {
                s.dataText += String(line.dropFirst("data: ".count))
                return nil
            }
            if line.isEmpty, let name = s.eventName {
                let text = s.dataText
                s.eventName = nil
                s.dataText = ""
                return (name, text)
            }
            return nil
        }
        guard let frame else { return true }
        let terminal = await dispatch(name: frame.name, dataText: frame.dataText, onEvent: onEvent)
        return !terminal
    }

    /// Dispatch a final frame that arrived without a trailing blank line.
    func dispatchPendingFrame(onEvent: AIFlowService.EventHandler?) async {
        let frame: (name: String, dataText: String)? = state.withLock { s in
            guard let name = s.eventName, !s.terminal else { return nil }
            let text = s.dataText
            s.eventName = nil
            s.dataText = ""
            return (name, text)
        }
        if let frame {
            _ = await dispatch(name: frame.name, dataText: frame.dataText, onEvent: onEvent)
        }
    }

    func setStatus(_ status: String) {
        state.withLock { $0.result.status = status }
    }

    /// Task cancellation → "cancelled", unless a terminal event already landed.
    func markCancelledIfUnresolved() {
        state.withLock { s in
            if s.result.status == "unknown" { s.result.status = "cancelled" }
        }
    }

    func fail(with error: WildwoodError) {
        let message: String = switch error.status {
        case 403: "You don't have access to this flow."
        case 401: "Not authorized"
        default: error.message.isEmpty ? "Run failed" : error.message
        }
        fail(message: message)
    }

    func fail(message: String) {
        state.withLock { s in
            s.result.status = "failed"
            s.result.errorMessage = message
        }
    }

    /// Returns true when the event is terminal (done/error). All
    /// property reads are guarded — a truncated/unparseable frame leaves
    /// `data` nil and must never crash the stream.
    private func dispatch(name: String, dataText: String, onEvent: AIFlowService.EventHandler?) async -> Bool {
        let data: JSONValue? = dataText.isEmpty
            ? nil
            : try? JSONDecoder().decode(JSONValue.self, from: Data(dataText.utf8))
        let obj = data?.objectValue

        let terminal: Bool = state.withLock { s in
            switch name {
            case "run_started":
                // Server emits this first, carrying the run + thread ids the
                // client needs for resume and thread continuity.
                if let runId = obj?["runId"]?.stringValue { s.result.runId = runId }
                if let threadId = obj?["threadId"]?.stringValue { s.result.threadId = threadId }
            case "done":
                s.result.status = obj?["status"]?.stringValue ?? "succeeded"
                if let output = obj?["output"], output != .null {
                    s.result.outputJson = output.rawJSONString
                }
                s.terminal = true
            case "interrupt":
                // NOT terminal: Blazor/JS keep consuming post-interrupt frames
                // (e.g. usage) and only stop on done/error; the server closes
                // the stream when it has nothing more to send.
                s.result.status = "interrupted"
                if let payload = obj?["payload"] {
                    s.result.interruptPayloadJson = payload.rawJSONString
                }
            case "error":
                s.result.status = "failed"
                s.result.errorMessage = obj?["message"]?.stringValue ?? "Run failed"
                s.terminal = true
            case "usage":
                if let tokens = obj?["totalTokens"]?.numberValue {
                    s.result.totalTokens += Int(tokens)
                }
            default:
                break
            }
            return s.terminal
        }

        if let onEvent {
            await onEvent(AIFlowRunEvent(event: name, data: data))
        }
        return terminal
    }
}
