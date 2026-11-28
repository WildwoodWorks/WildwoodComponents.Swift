import Foundation
import Testing
@testable import WildwoodCore

// Ported case for case from packages/wildwood-core/src/__tests__/tierChange.test.ts.
struct TierChangeRulesTests {
    private func tier(_ id: String, _ displayOrder: Int, _ allowUpgrades: Bool?, _ allowDowngrades: Bool?) throws -> AppTierModel {
        var value = try WildwoodJSON.decoder().decode(AppTierModel.self, from: Data("{}".utf8))
        value.id = id
        value.displayOrder = displayOrder
        if let allowUpgrades { value.allowUpgrades = allowUpgrades }
        if let allowDowngrades { value.allowDowngrades = allowDowngrades }
        return value
    }

    @Test func followsTheCurrentTierAsTheServerDoes_upgradesNeedAllowUpgrades() throws {
        let free = try tier("free", 1, true, false)
        let pro = try tier("pro", 2, false, false)
        let business = try tier("business", 3, true, true)

        #expect(TierChangeRules.isTierChangeAllowed(current: free, target: pro))
        #expect(!TierChangeRules.isTierChangeAllowed(current: pro, target: business))
    }

    @Test func treatsEveryNonUpgradeAsADowngradeNeedingAllowDowngrades() throws {
        let free = try tier("free", 1, true, false)
        let pro = try tier("pro", 2, false, false)
        let business = try tier("business", 3, true, true)

        #expect(!TierChangeRules.isTierChangeAllowed(current: pro, target: free))
        #expect(TierChangeRules.isTierChangeAllowed(current: business, target: free))
        // Same display order is not an upgrade on the server either.
        #expect(!TierChangeRules.isTierChangeAllowed(current: try tier("a", 2, true, false), target: try tier("b", 2, true, true)))
    }

    @Test func allowsAFirstSubscriptionAndStayingPut() throws {
        let pro = try tier("pro", 2, false, false)

        #expect(TierChangeRules.isTierChangeAllowed(current: nil, target: pro))
        #expect(TierChangeRules.isTierChangeAllowed(current: pro, target: try tier("PRO", 2, false, false)))
    }

    @Test func allowsAChangeWhenAnOlderServerLeavesTheFlagsOut() throws {
        // The decoder defaults absent flags to true, as JS reads `!== false`.
        let legacy = try tier("legacy", 2, nil, nil)
        #expect(legacy.allowUpgrades && legacy.allowDowngrades)
        #expect(TierChangeRules.isTierChangeAllowed(current: legacy, target: try tier("business", 3, true, true)))
        #expect(TierChangeRules.isTierChangeAllowed(current: legacy, target: try tier("free", 1, true, false)))
    }
}
