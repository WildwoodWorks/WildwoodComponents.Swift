// AI models ported from @wildwood/core/src/ai/types.ts.

import Foundation

public struct AIMessage: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var role: String
    public var content: String
    public var createdAt: Date?
    public var tokenCount: Int
    public var isError: Bool
    public var sessionId: String?
    public var messageOrder: Int
    public var parentMessageId: String?
    public var isEdited: Bool
    public var editedAt: Date?

    public init(
        id: String = UUID().uuidString,
        role: String,
        content: String,
        createdAt: Date? = nil,
        tokenCount: Int = 0,
        isError: Bool = false,
        sessionId: String? = nil,
        messageOrder: Int = 0,
        parentMessageId: String? = nil,
        isEdited: Bool = false,
        editedAt: Date? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.tokenCount = tokenCount
        self.isError = isError
        self.sessionId = sessionId
        self.messageOrder = messageOrder
        self.parentMessageId = parentMessageId
        self.isEdited = isEdited
        self.editedAt = editedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        tokenCount = try c.decodeIfPresent(Int.self, forKey: .tokenCount) ?? 0
        isError = try c.decodeIfPresent(Bool.self, forKey: .isError) ?? false
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        messageOrder = try c.decodeIfPresent(Int.self, forKey: .messageOrder) ?? 0
        parentMessageId = try c.decodeIfPresent(String.self, forKey: .parentMessageId)
        isEdited = try c.decodeIfPresent(Bool.self, forKey: .isEdited) ?? false
        editedAt = try c.decodeIfPresent(Date.self, forKey: .editedAt)
    }
}

public struct AISession: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sessionName: String
    public var messages: [AIMessage]
    public var createdAt: Date?
    public var endedAt: Date?
    public var isActive: Bool
    public var userId: String?
    public var aiConfigurationId: String?
    public var lastAccessedAt: Date?
    public var messageCount: Int
    public var lastMessagePreview: String?

    enum CodingKeys: String, CodingKey {
        case id, sessionName, messages, createdAt, endedAt, isActive, userId
        // System.Text.Json camelCase lowercases only the first letter of "AIConfigurationId".
        case aiConfigurationId = "aIConfigurationId"
        case lastAccessedAt, messageCount, lastMessagePreview
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        sessionName = try c.decodeIfPresent(String.self, forKey: .sessionName) ?? ""
        messages = try c.decodeIfPresent([AIMessage].self, forKey: .messages) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
        aiConfigurationId = try c.decodeIfPresent(String.self, forKey: .aiConfigurationId)
        lastAccessedAt = try c.decodeIfPresent(Date.self, forKey: .lastAccessedAt)
        messageCount = try c.decodeIfPresent(Int.self, forKey: .messageCount) ?? 0
        lastMessagePreview = try c.decodeIfPresent(String.self, forKey: .lastMessagePreview)
    }
}

public struct AISessionSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sessionName: String
    public var messageCount: Int
    public var createdAt: Date?
    public var lastAccessedAt: Date?
    public var endedAt: Date?
    public var isActive: Bool
    public var lastMessagePreview: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        sessionName = try c.decodeIfPresent(String.self, forKey: .sessionName) ?? ""
        messageCount = try c.decodeIfPresent(Int.self, forKey: .messageCount) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        lastAccessedAt = try c.decodeIfPresent(Date.self, forKey: .lastAccessedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        lastMessagePreview = try c.decodeIfPresent(String.self, forKey: .lastMessagePreview)
    }
}

public struct AIConfiguration: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var description: String
    public var model: String
    public var providerTypeCode: String
    public var isActive: Bool
    public var persistentSessionEnabled: Bool
    public var configurationType: String
    public var enableTTS: Bool
    public var ttsModel: String?
    public var ttsDefaultVoice: String?
    public var ttsDefaultSpeed: Double
    public var ttsDefaultFormat: String
    public var ttsEnabledVoicesJson: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        providerTypeCode = try c.decodeIfPresent(String.self, forKey: .providerTypeCode) ?? ""
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        persistentSessionEnabled = try c.decodeIfPresent(Bool.self, forKey: .persistentSessionEnabled) ?? false
        configurationType = try c.decodeIfPresent(String.self, forKey: .configurationType) ?? ""
        enableTTS = try c.decodeIfPresent(Bool.self, forKey: .enableTTS) ?? false
        ttsModel = try c.decodeIfPresent(String.self, forKey: .ttsModel)
        ttsDefaultVoice = try c.decodeIfPresent(String.self, forKey: .ttsDefaultVoice)
        ttsDefaultSpeed = try c.decodeIfPresent(Double.self, forKey: .ttsDefaultSpeed) ?? 1.0
        ttsDefaultFormat = try c.decodeIfPresent(String.self, forKey: .ttsDefaultFormat) ?? ""
        ttsEnabledVoicesJson = try c.decodeIfPresent(String.self, forKey: .ttsEnabledVoicesJson)
    }
}

public struct AIChatRequest: Codable, Sendable, Equatable {
    public var configurationId: String
    public var sessionId: String?
    public var message: String
    public var saveToSession: Bool?
    public var macroValues: [String: String]?
    /// Base64-encoded file data for attachments.
    public var fileBase64: String?
    /// MIME type of the attached file (e.g. `image/png`).
    public var fileMediaType: String?
    public var fileName: String?

    public init(
        configurationId: String,
        sessionId: String? = nil,
        message: String,
        saveToSession: Bool? = nil,
        macroValues: [String: String]? = nil,
        fileBase64: String? = nil,
        fileMediaType: String? = nil,
        fileName: String? = nil
    ) {
        self.configurationId = configurationId
        self.sessionId = sessionId
        self.message = message
        self.saveToSession = saveToSession
        self.macroValues = macroValues
        self.fileBase64 = fileBase64
        self.fileMediaType = fileMediaType
        self.fileName = fileName
    }
}

public struct AIChatResponse: Codable, Sendable, Equatable {
    public var id: String
    public var sessionId: String?
    public var response: String
    public var tokensUsed: Int
    public var model: String
    public var providerTypeCode: String
    public var createdAt: Date?
    public var isError: Bool
    public var errorMessage: String?
    /// Structured error code from usage-limit errors (e.g. "AI_TOKENS").
    public var errorCode: String?

    public init(
        id: String = "",
        sessionId: String? = nil,
        response: String = "",
        tokensUsed: Int = 0,
        model: String = "",
        providerTypeCode: String = "",
        createdAt: Date? = nil,
        isError: Bool = false,
        errorMessage: String? = nil,
        errorCode: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.response = response
        self.tokensUsed = tokensUsed
        self.model = model
        self.providerTypeCode = providerTypeCode
        self.createdAt = createdAt
        self.isError = isError
        self.errorMessage = errorMessage
        self.errorCode = errorCode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        response = try c.decodeIfPresent(String.self, forKey: .response) ?? ""
        tokensUsed = try c.decodeIfPresent(Int.self, forKey: .tokensUsed) ?? 0
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        providerTypeCode = try c.decodeIfPresent(String.self, forKey: .providerTypeCode) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        isError = try c.decodeIfPresent(Bool.self, forKey: .isError) ?? false
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        errorCode = try c.decodeIfPresent(String.self, forKey: .errorCode)
    }
}

public struct TTSVoice: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var previewUrl: String?
}

public struct TTSSynthesisResult: Codable, Sendable, Equatable {
    public var audioBase64: String
    public var contentType: String
}
