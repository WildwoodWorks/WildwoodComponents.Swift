// WildwoodSubscriptionAdminModel state tests (no network) — the SwiftUI analog
// of useSubscriptionAdmin, plus the SubscriptionAdminScope.isAdmin derivation.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct SubscriptionAdminModelTests {
    private func makeModel(scope: SubscriptionAdminScope = .currentUser) -> WildwoodSubscriptionAdminModel {
        let client = WildwoodClient(
            config: WildwoodConfig(baseUrl: "https://unit.test", appId: "app-1", storage: .memory)
        )
        return WildwoodSubscriptionAdminModel(client: client, appId: "app-1", scope: scope)
    }

    @Test func scopeIsAdminReflectsTheScope() {
        #expect(SubscriptionAdminScope.currentUser.isAdmin == false)
        #expect(SubscriptionAdminScope.user(id: "u1").isAdmin == true)
        #expect(SubscriptionAdminScope.company(id: "c1").isAdmin == true)
    }

    @Test func initialStateIsEmpty() {
        let model = makeModel()
        #expect(model.subscription == nil)
        #expect(model.tiers.isEmpty)
        #expect(model.features.isEmpty)
        #expect(model.isLoading == false)
        #expect(model.errorMessage == "")
        #expect(model.successMessage == "")
    }

    @Test func clearPreviewLeavesNoPendingPreview() {
        let model = makeModel()
        model.clearPreview()
        #expect(model.tierChangePreview == nil)
    }
}
