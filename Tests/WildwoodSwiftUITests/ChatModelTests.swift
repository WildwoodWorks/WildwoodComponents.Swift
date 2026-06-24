// WildwoodChatModel state tests (no network) — the SwiftUI analog of useAI/chat.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct ChatModelTests {
    private func makeModel() -> WildwoodChatModel {
        let client = WildwoodClient(
            config: WildwoodConfig(baseUrl: "https://unit.test", appId: "app-1", storage: .memory)
        )
        return WildwoodChatModel(client: client, configurationId: "cfg-1")
    }

    @Test func initialStateIsEmpty() {
        let model = makeModel()
        #expect(model.messages.isEmpty)
        #expect(model.input == "")
        #expect(model.isSending == false)
        #expect(model.sessionId == nil)
        #expect(model.totalTokensUsed == 0)
    }

    @Test func isTTSEnabledFalseWithoutConfiguration() {
        #expect(makeModel().isTTSEnabled == false)
    }

    @Test func startNewSessionResetsSessionStateButKeepsTheInputDraft() {
        let model = makeModel()
        model.input = "draft text"

        model.startNewSession()

        #expect(model.sessionId == nil)
        #expect(model.messages.isEmpty)
        #expect(model.totalTokensUsed == 0)
        // startNewSession only clears session state, not the composer input.
        #expect(model.input == "draft text")
    }
}
