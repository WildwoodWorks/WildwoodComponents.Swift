// WildwoodConsentModel state tests (no network) — the SwiftUI analog of useConsent.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct ConsentModelTests {
    private func makeModel() -> WildwoodConsentModel {
        let client = WildwoodClient(
            config: WildwoodConfig(baseUrl: "https://unit.test", appId: "app-1", storage: .memory)
        )
        return WildwoodConsentModel(client: client, appId: "app-1")
    }

    @Test func initialStateHasNoConfigOrBanner() {
        let model = makeModel()
        #expect(model.config == nil)
        #expect(model.state == nil)
        #expect(model.shouldShowBanner == false)
        #expect(model.isLoading == false)
        #expect(model.errorMessage == nil)
    }

    @Test func nonNecessaryCategoriesAreDeniedBeforeInitialize() {
        let model = makeModel()
        // Nothing is granted until the visitor decides.
        #expect(model.isGranted(.analytics) == false)
        #expect(model.isGranted(.advertising) == false)
    }

    @Test func activeCategoriesEmptyBeforeConfigLoads() {
        #expect(makeModel().activeCategories().isEmpty)
    }
}
