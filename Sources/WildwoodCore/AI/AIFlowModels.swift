// AI Flow models ported from WildwoodComponents.Shared/Models/AIFlowModels.cs.
// The Blazor stack is the reference implementation for AI Flows (there is no
// JS implementation yet).

import Foundation

/// A published AI Flow (LangGraph) runnable by an app user.
public struct AIFlow: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var description: String
    public var iconClass: String
    public var inputFields: [AIFlowInputField]

    public init(
        id: String = "",
        name: String = "",
        description: String = "",
        iconClass: String = "fas fa-diagram-project",
        inputFields: [AIFlowInputField] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.iconClass = iconClass
        self.inputFields = inputFields
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        iconClass = try c.decodeIfPresent(String.self, forKey: .iconClass) ?? "fas fa-diagram-project"
        inputFields = try c.decodeIfPresent([AIFlowInputField].self, forKey: .inputFields) ?? []
    }
}

/// A state channel the run can be seeded with (drives the input form).
public struct AIFlowInputField: Codable, Sendable, Equatable, Identifiable {
    public var name: String
    public var reducer: String

    public var id: String { name }

    public init(name: String = "", reducer: String = "overwrite") {
        self.name = name
        self.reducer = reducer
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        reducer = try c.decodeIfPresent(String.self, forKey: .reducer) ?? "overwrite"
    }
}

/// One SSE frame from a flow run stream.
public struct AIFlowRunEvent: Codable, Sendable, Equatable {
    /// run_started | node_start | node_end | token | usage | interrupt | done | error
    public var event: String

    /// Parsed event payload; nil when the frame carried no (or malformed) JSON.
    public var data: JSONValue?

    public init(event: String, data: JSONValue? = nil) {
        self.event = event
        self.data = data
    }
}

/// Terminal outcome of a flow run, surfaced to the component.
public struct AIFlowRunResult: Codable, Sendable, Equatable {
    /// succeeded | failed | cancelled | interrupted ("unknown" until terminal).
    public var status: String
    public var outputJson: String?
    public var errorMessage: String?
    public var totalTokens: Int

    /// Set when the run paused for human review; the payload to display.
    public var interruptPayloadJson: String?

    /// Run id (for resume/history). Populated once the run row is known.
    public var runId: String?
    public var threadId: String?

    public init(
        status: String = "unknown",
        outputJson: String? = nil,
        errorMessage: String? = nil,
        totalTokens: Int = 0,
        interruptPayloadJson: String? = nil,
        runId: String? = nil,
        threadId: String? = nil
    ) {
        self.status = status
        self.outputJson = outputJson
        self.errorMessage = errorMessage
        self.totalTokens = totalTokens
        self.interruptPayloadJson = interruptPayloadJson
        self.runId = runId
        self.threadId = threadId
    }
}

public struct AIFlowRunSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var flowId: String
    public var threadId: String
    public var triggerType: String
    public var status: String
    public var createdAt: Date?
    public var durationMs: Int?
    public var totalTokens: Int
    public var errorMessage: String?

    public init(
        id: String = "",
        flowId: String = "",
        threadId: String = "",
        triggerType: String = "",
        status: String = "",
        createdAt: Date? = nil,
        durationMs: Int? = nil,
        totalTokens: Int = 0,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.flowId = flowId
        self.threadId = threadId
        self.triggerType = triggerType
        self.status = status
        self.createdAt = createdAt
        self.durationMs = durationMs
        self.totalTokens = totalTokens
        self.errorMessage = errorMessage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        flowId = try c.decodeIfPresent(String.self, forKey: .flowId) ?? ""
        threadId = try c.decodeIfPresent(String.self, forKey: .threadId) ?? ""
        triggerType = try c.decodeIfPresent(String.self, forKey: .triggerType) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

/// Display/behavior settings for AIFlowComponent — mirrors the Blazor
/// AIFlowSettings. `apiBaseUrl` is intentionally absent: the Swift stack's
/// API host is fixed by WildwoodConfig.baseUrl (the Blazor service is a
/// standalone HttpClient and needs one; WildwoodHttpClient does not).
public struct AIFlowSettings: Sendable {
    /// Overrides the client's configured appId for the flows endpoints.
    public var appId: String?

    /// Fixed flow to run; when nil the component shows a flow picker.
    public var flowId: String?

    public var showFlowPicker: Bool
    public var showLiveProgress: Bool
    public var showDebugInfo: Bool

    /// Shows the current thread's prior runs beneath the result.
    public var showRunHistory: Bool

    public var title: String
    public var runLabel: String

    public init(
        appId: String? = nil,
        flowId: String? = nil,
        showFlowPicker: Bool = true,
        showLiveProgress: Bool = true,
        showDebugInfo: Bool = false,
        showRunHistory: Bool = true,
        title: String = "AI Flows",
        runLabel: String = "Run"
    ) {
        self.appId = appId
        self.flowId = flowId
        self.showFlowPicker = showFlowPicker
        self.showLiveProgress = showLiveProgress
        self.showDebugInfo = showDebugInfo
        self.showRunHistory = showRunHistory
        self.title = title
        self.runLabel = runLabel
    }
}
