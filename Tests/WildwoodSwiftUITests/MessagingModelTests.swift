// WildwoodMessagingModel state tests (no network) — the SwiftUI analog of useMessaging.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct MessagingModelTests {
    private func makeModel() -> WildwoodMessagingModel {
        let client = WildwoodClient(
            config: WildwoodConfig(baseUrl: "https://unit.test", appId: "app-1", storage: .memory)
        )
        return WildwoodMessagingModel(client: client, companyAppId: "cap-1")
    }

    @Test func initialStateIsEmpty() {
        let model = makeModel()
        #expect(model.threads.isEmpty)
        #expect(model.selectedThread == nil)
        #expect(model.messages.isEmpty)
        #expect(model.draft == "")
        #expect(model.errorMessage == "")
        #expect(model.isLoading == false)
    }

    @Test func closeThreadResetsConversationState() {
        let model = makeModel()
        model.draft = "unsent text"

        model.closeThread()

        #expect(model.draft == "")
        #expect(model.selectedThread == nil)
        #expect(model.messages.isEmpty)
    }

    @Test func sendMessageIsANoOpWhenNoThreadIsSelected() async {
        let model = makeModel()

        await model.sendMessage()

        // Guard returns before any network call; no error is surfaced.
        #expect(model.errorMessage == "")
        #expect(model.messages.isEmpty)
    }
}
