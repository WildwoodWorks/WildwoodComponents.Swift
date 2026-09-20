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

    /// The LEGACY direct path — a host, or the older panels, calling the model with no
    /// ``WildwoodPlanChangeModel`` anywhere. Nobody else can settle the change, so this model
    /// still does: one invalidation, one `entitlementsChanged`, one read of each of the three
    /// things a plan move changes. (Driven by the driver instead, it is asked with
    /// `settles: false` and the driver settles once — `PlanChangeModelTests`.)
    @Test func theDirectPathStillSettlesAChangeExactlyOnce() async {
        let backend = TestBackend()
        backend.stub(
            "POST",
            "/api/app-tiers/app-1/my-subscription/change",
            TestStubResponse(json: #"{"success":true,"errorMessage":""}"#)
        )
        backend.stub(
            "GET",
            "/api/app-tiers/app-1/my-subscription",
            TestStubResponse(json: #"{"id":"sub-1","appId":"app-1","appTierId":"tier-pro","status":"Active"}"#)
        )
        backend.stub("GET", "/api/app-feature-definitions/app-1/active", TestStubResponse(json: "[]"))
        backend.stub("GET", "/api/app-tiers/app-1/user-features", TestStubResponse(json: #"{"PRO":true}"#))
        backend.stub("GET", "/api/app-tiers/app-1/limit-statuses", TestStubResponse(json: "[]"))

        let client = makeTestClient(backend, appId: "app-1")
        let model = WildwoodSubscriptionAdminModel(client: client, appId: "app-1", scope: .currentUser)
        let seen = Recorder<String>()
        client.events.on { event in
            if case .entitlementsChanged(let appId, let reason) = event {
                seen.record("\(appId)|\(reason.rawValue)")
            }
        }
        let epochBefore: Int = client.features.epoch

        let result = await model.postTierChange(
            tierId: "tier-pro",
            pricingId: "p-1",
            tierName: "Pro",
            isChange: true,
            immediate: true
        )

        #expect(result.success == true)
        #expect(client.features.epoch == epochBefore + 1)
        #expect(seen.values == ["app-1|tierChange"])
        #expect(requestCount(backend, path: "/api/app-tiers/app-1/my-subscription") == 1)
        #expect(requestCount(backend, path: "/api/app-tiers/app-1/user-features") == 1)
        #expect(requestCount(backend, path: "/api/app-tiers/app-1/limit-statuses") == 1)
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
