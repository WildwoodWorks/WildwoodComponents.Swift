// AI chat state — the view-model equivalent of react-shared's useAI plus the
// chat-session handling embedded in AIChatComponent.

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

    public private(set) var messages: [AIMessage] = []
    public var input = ""
    public private(set) var isSending = false
    public private(set) var sessionId: String?
    public private(set) var totalTokensUsed = 0
    public var errorMessage = ""

    public init(client: WildwoodClient, configurationId: String, useProxy: Bool = false, saveToSession: Bool = true) {
        self.client = client
        self.configurationId = configurationId
        self.useProxy = useProxy
        self.saveToSession = saveToSession
    }

    public func loadRecentSession() async {
        guard saveToSession else { return }
        let sessions = await client.ai.getSessions(configurationId: configurationId)
        guard let recent = sessions.first(where: \.isActive) ?? sessions.first else { return }
        await loadSession(recent.id)
    }

    public func loadSession(_ id: String) async {
        guard let session = await client.ai.getSession(sessionId: id) else { return }
        sessionId = session.id
        messages = session.messages.sorted { $0.messageOrder < $1.messageOrder }
    }

    public func startNewSession() {
        sessionId = nil
        messages = []
        totalTokensUsed = 0
    }

    public func send(fileData: Data? = nil, fileName: String? = nil) async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || fileData != nil, !isSending else { return }

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
                ? await client.ai.sendProxyMessageWithFile(request, fileData: fileData, fileName: fileName)
                : await client.ai.sendMessageWithFile(request, fileData: fileData, fileName: fileName)
        } else {
            response = useProxy
                ? await client.ai.sendProxyMessage(request)
                : await client.ai.sendMessage(request)
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
        } else {
            sessionId = response.sessionId ?? sessionId
            totalTokensUsed += response.tokensUsed
            messages.append(
                AIMessage(
                    role: "assistant",
                    content: response.response,
                    createdAt: response.createdAt ?? Date(),
                    tokenCount: response.tokensUsed,
                    sessionId: response.sessionId,
                    messageOrder: messages.count
                )
            )
        }
    }
}
