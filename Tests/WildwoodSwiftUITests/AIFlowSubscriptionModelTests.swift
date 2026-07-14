// WildwoodAIFlowSubscriptionModel tests — the SwiftUI analog of the
// useAIFlowSubscriptions hook. Covers refresh (success + error surfacing),
// create refresh, the 429 plan-limit routed to limitMessage (not errorMessage),
// and delete refresh, over a stubbed backend (TestBackend).

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct AIFlowSubscriptionModelTests {
    private let subJSON = #"{"id":"s1","flowId":"f1","flowName":"Trail Forecast","name":"Backcountry","isEnabled":true,"notifyOnComplete":true,"createdAt":"2026-07-01T10:00:00Z"}"#

    private func makeModel(_ backend: TestBackend) -> WildwoodAIFlowSubscriptionModel {
        let client = WildwoodClient(
            config: WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false, storage: .memory),
            urlSession: backend.makeSession()
        )
        return WildwoodAIFlowSubscriptionModel(client: client)
    }

    @Test func refreshLoadsTheList() async {
        let backend = TestBackend()
        backend.stub("GET", "/api/ai/flows/subscriptions", .init(json: "[\(subJSON)]"))
        let model = makeModel(backend)

        await model.refresh()

        #expect(model.subscriptions.count == 1)
        #expect(model.subscriptions.first?.id == "s1")
        #expect(model.isLoading == false)
        #expect(model.errorMessage == nil)
    }

    @Test func refreshSurfacesAnErrorOnFailure() async {
        let backend = TestBackend() // no stub -> 404 -> service throws
        let model = makeModel(backend)

        await model.refresh()

        #expect(model.subscriptions.isEmpty)
        #expect(model.errorMessage != nil)
        #expect(model.isLoading == false)
    }

    @Test func createRefreshesTheListAndClearsErrorAndLimit() async {
        let backend = TestBackend()
        backend.stub("POST", "/api/ai/flows/subscriptions", .init(json: subJSON))
        backend.stub("GET", "/api/ai/flows/subscriptions", .init(json: "[\(subJSON)]"))
        let model = makeModel(backend)

        let created = await model.create(
            AIFlowSubscriptionCreateRequest(flowId: "f1", name: "Backcountry", scheduleCron: "0 6 * * *")
        )

        #expect(created?.id == "s1")
        #expect(model.subscriptions.count == 1) // refreshed
        #expect(model.errorMessage == nil)
        #expect(model.limitMessage == nil)
    }

    @Test func create429RoutesToLimitMessageNotError() async {
        let backend = TestBackend()
        backend.stub(
            "POST", "/api/ai/flows/subscriptions",
            .init(statusCode: 429, json: #"{"message":"Upgrade to schedule more flows."}"#)
        )
        let model = makeModel(backend)

        let created = await model.create(
            AIFlowSubscriptionCreateRequest(flowId: "f1", name: "x", scheduleCron: "0 6 * * *")
        )

        #expect(created == nil)
        #expect(model.limitMessage == "Upgrade to schedule more flows.")
        #expect(model.errorMessage == nil)
    }

    @Test func removeRefreshesOnSuccess() async {
        let backend = TestBackend()
        backend.stub("DELETE", "/api/ai/flows/subscriptions/s1", .init(statusCode: 200))
        backend.stub("GET", "/api/ai/flows/subscriptions", .init(json: "[]"))
        let model = makeModel(backend)

        let ok = await model.remove(id: "s1")

        #expect(ok == true)
        #expect(model.subscriptions.isEmpty) // refreshed
        #expect(model.errorMessage == nil)
    }
}
