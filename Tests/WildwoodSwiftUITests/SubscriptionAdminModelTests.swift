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

    // MARK: - Refusals (JS `refusalMessage` / `runFlag`)

    @Test func aRefusalNamesTheOperationAndTheServersCode() {
        #expect(
            WildwoodSubscriptionAdminModel.refusalMessage("update the usage limit")
                == "The request was refused: could not update the usage limit."
        )
        #expect(
            WildwoodSubscriptionAdminModel.refusalMessage("change the plan", message: nil, code: "TierTooLow")
                == "The request was refused: could not change the plan (TierTooLow)."
        )
        // The server's own words always win.
        #expect(
            WildwoodSubscriptionAdminModel.refusalMessage(
                "change the plan", message: "That tier is closed to new signups.", code: "TierTooLow"
            ) == "That tier is closed to new signups."
        )
    }

    @Test func theUsageOperationNamesTheScopeItActsOn() {
        #expect(
            WildwoodSubscriptionAdminModel.limitOperation(.currentUser, reset: false) == "update the usage limit"
        )
        #expect(
            WildwoodSubscriptionAdminModel.limitOperation(.user(id: "u"), reset: true)
                == "reset the user's usage counter"
        )
        #expect(
            WildwoodSubscriptionAdminModel.limitOperation(.company(id: "c"), reset: false)
                == "update the company's usage limit"
        )
    }

    @Test func aBareFalseMutationSetsTheErrorInsteadOfReadingAsSuccess() async {
        let backend = TestBackend()
        backend.stub(
            "PUT",
            "/api/app-tiers/app-1/admin/usage-limits/API_CALLS",
            TestStubResponse(statusCode: 403, json: #"{"message":"nope"}"#)
        )
        let client = makeTestClient(backend, appId: "app-1")
        let model = WildwoodSubscriptionAdminModel(client: client, appId: "app-1", scope: .currentUser)

        await model.updateLimit("API_CALLS", newMaxValue: 100)

        #expect(model.successMessage == "")
        #expect(model.errorMessage == "The request was refused: could not update the usage limit.")
    }

    @Test func aRequiresActionChangeIsNotReportedAsAFailure() async {
        let backend = TestBackend()
        backend.stub(
            "POST",
            "/api/app-tiers/app-1/my-subscription/change",
            TestStubResponse(
                json: """
                {"success":false,"requiresAction":true,"clientSecret":"cs_1","pendingChangeId":"pc-1",
                 "errorMessage":""}
                """
            )
        )
        let client = makeTestClient(backend, appId: "app-1")
        let model = WildwoodSubscriptionAdminModel(client: client, appId: "app-1", scope: .currentUser)

        let result = await model.postTierChange(
            tierId: "tier-pro",
            pricingId: "p-1",
            isChange: true,
            immediate: true,
            supportsPaymentAction: true
        )

        #expect(result.requiresAction == true)
        // "Not yet" is not "no": the customer must not be told the change failed.
        #expect(model.errorMessage == "")

        let sent = bodies(backend, path: "/api/app-tiers/app-1/my-subscription/change").first ?? ""
        #expect(sent.contains("\"SupportsPaymentAction\":true"))
    }

    @Test func aRefusedChangeKeepsTheServersReason() async {
        let backend = TestBackend()
        backend.stub(
            "POST",
            "/api/app-tiers/app-1/my-subscription/change",
            TestStubResponse(
                json: #"{"success":false,"errorMessage":"","errorCode":"tier_change_already_in_progress"}"#
            )
        )
        let client = makeTestClient(backend, appId: "app-1")
        let model = WildwoodSubscriptionAdminModel(client: client, appId: "app-1", scope: .currentUser)

        _ = await model.postTierChange(
            tierId: "tier-pro",
            pricingId: nil,
            isChange: true,
            immediate: true,
            supportsPaymentAction: false
        )

        #expect(
            model.errorMessage
                == "The request was refused: could not change the plan (tier_change_already_in_progress)."
        )
        // No handler said so, so the flag never reached the wire.
        let sent = bodies(backend, path: "/api/app-tiers/app-1/my-subscription/change").first ?? ""
        #expect(!sent.contains("SupportsPaymentAction"))
    }
}
