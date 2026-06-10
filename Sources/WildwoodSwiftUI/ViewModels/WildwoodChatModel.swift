// AI chat state — the view-model equivalent of react-shared's useAI plus the
// chat-session handling embedded in AIChatComponent. Supports session
// management (list/rename/delete) and server-side TTS synthesis.

import Foundation
import Observation
import WildwoodCore

@MainActor
@Observable
public final class WildwoodChatModel {
    @ObservationIgnored private let client: WildwoodClient
    @ObservationIgnored public let configurationId: String
    @ObservationIgnored public let useProxy: Bool
    @ObservationIgnored public let saveToSession: Bool
    /// Per-request timeout override for long generations (seconds).
    @ObservationIgnored public var requestTimeout: TimeInterval?

    public private(set) var messages: [AIMessage] = []
    public var input = ""
    public private(set) var isSending = false
    public private(set) var sessionId: String?
    public private(set) var sessions: [AISessionSummary] = []
    public private(set) var configuration: AIConfiguration?
    public private(set) var totalTokensUsed = 0
    public var errorMessage = ""

    public init(
        client: WildwoodClient,
        configurationId: String,
        useProxy: Bool = false,
        saveToSession: Bool = true,
        requestTimeout: TimeInterval? = nil
    ) {
        self.client = client
        self.configurationId = configurationId
        self.useProxy = useProxy
        self.saveToSession = saveToSession
        self.requestTimeout = requestTimeout
    }

    public var isTTSEnabled: Bool {
        configuration?.enableTTS == true
    }

    public func loadConfiguration() async {
        configuration = await client.ai.getConfiguration(configurationId: configurationId)
    }

    // MARK: - Sessions

    public func loadSessions() async {
        sessions = await client.ai.getSessions(configurationId: configurationId)
    }

    public func loadRecentSession() async {
        guard saveToSession else { return }
        await loadSessions()
        guard let recent = sessions.first(where: \.isActive) ?? sessions.first else { return }
        await loadSession(recent.id)
    }

    public func loadSession(_ id: String) async {
        guard let session = await client.ai.getSession(sessionId: id) else { return }
        sessionId = session.id
        messages = session.messages.sorted { $0.messageOrder < $1.messageOrder }
        totalTokensUsed = session.messages.reduce(0) { $0 + $1.tokenCount }
    }

    public func startNewSession() {
        sessionId = nil
        messages = []
        totalTokensUsed = 0
    }

    public func deleteSession(_ id: String) async {
        if await client.ai.deleteSession(sessionId: id) {
            sessions.removeAll { $0.id == id }
            if sessionId == id {
                startNewSession()
            }
        }
    }

    public func renameSession(_ id: String, to newName: String) async {
        if await client.ai.renameSession(sessionId: id, newName: newName) {
            await loadSessions()
        }
    }

    // MARK: - Sending

    /// Send the drafted message. Returns the assistant's reply on success,
    /// nil on error (the error is reflected in `errorMessage` and an error
    /// bubble) — callers use the return value for onMessageReceived so the
    /// callback never fires for history loads or error bubbles.
    @discardableResult
    public func send(fileData: Data? = nil, fileName: String? = nil) async -> AIMessage? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || fileData != nil, !isSending else { return nil }

        errorMessage = ""
        isSending = true
        input = ""
        defer { isSending = false }

        messages.append(AIMessage(role: "user", content: text, createdAt: Date(), messageOrder: messages.count))

        let request = AIChatRequest(
            configurationId: configurationId,
            sessionId: sessionId,
            message: text,
            saveToSession: saveToSession
        )

        let response: AIChatResponse
        if let fileData, let fileName {
            response = useProxy
                ? await client.ai.sendProxyMessageWithFile(request, fileData: fileData, fileName: fileName, timeout: requestTimeout)
                : await client.ai.sendMessageWithFile(request, fileData: fileData, fileName: fileName, timeout: requestTimeout)
        } else {
            response = useProxy
                ? await client.ai.sendProxyMessage(request, timeout: requestTimeout)
                : await client.ai.sendMessage(request, timeout: requestTimeout)
        }

        if response.isError {
            errorMessage = response.errorMessage ?? "The assistant could not respond."
            messages.append(
                AIMessage(
                    role: "assistant",
                    content: response.errorMessage ?? "Something went wrong.",
                    createdAt: Date(),
                    isError: true,
                    messageOrder: messages.count
                )
            )
            return nil
        }

        sessionId = response.sessionId ?? sessionId
        totalTokensUsed += response.tokensUsed
        let assistantMessage = AIMessage(
            role: "assistant",
            content: response.response,
            createdAt: response.createdAt ?? Date(),
            tokenCount: response.tokensUsed,
            sessionId: response.sessionId,
            messageOrder: messages.count
        )
        messages.append(assistantMessage)
        return assistantMessage
    }

    // MARK: - TTS

    /// Synthesize speech for a message via the server TTS endpoint, using the
    /// configuration's default voice/speed. Returns decoded audio data.
    public func synthesizeSpeech(for message: AIMessage) async -> Data? {
        guard isTTSEnabled else { return nil }
        let voice = configuration?.ttsDefaultVoice ?? ""
        let speed = configuration?.ttsDefaultSpeed ?? 1.0
        guard let result = await client.ai.synthesizeSpeech(
            text: message.content,
            voice: voice,
            speed: speed,
            configurationId: configurationId
        ) else { return nil }
        return Data(base64Encoded: result.audioBase64)
    }
}
