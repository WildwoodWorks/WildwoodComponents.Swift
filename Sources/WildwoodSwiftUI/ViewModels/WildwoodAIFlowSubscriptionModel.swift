// Flow-subscription state — the SwiftUI analog of react-shared's
// useAIFlowSubscriptions hook. Wraps WildwoodCore's AIFlowSubscriptionService:
// a user's standing orders for scheduled runs of published flows (list, create,
// update, enable/disable, delete) plus a latest-run sync.
//
// The service throws (the June-2026 Swift lookup idiom), so each call is a
// do/catch that surfaces a friendly errorMessage — EXCEPT a 429 create, whose
// plan-limit copy is routed to `limitMessage` (an upgrade CTA), not errorMessage.

import Foundation
import Observation
import WildwoodCore

@MainActor
@Observable
public final class WildwoodAIFlowSubscriptionModel {
    @ObservationIgnored private let service: AIFlowSubscriptionService

    public private(set) var subscriptions: [AIFlowSubscription] = []
    public private(set) var isLoading = true
    public var errorMessage: String?
    /// Server's upgrade copy after a create hit the plan limit (429); nil otherwise.
    public private(set) var limitMessage: String?

    public init(client: WildwoodClient, appId: String? = nil) {
        if let appId, !appId.isEmpty, appId != client.config.appId {
            self.service = AIFlowSubscriptionService(http: client.http, appId: appId)
        } else {
            self.service = client.aiFlowSubscriptions
        }
    }

    // MARK: - Load

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            subscriptions = try await service.getSubscriptions()
            errorMessage = nil
        } catch {
            errorMessage = friendlyMessage(error)
        }
    }

    // MARK: - Mutations (each refreshes so the list stays in sync)

    @discardableResult
    public func create(_ request: AIFlowSubscriptionCreateRequest) async -> AIFlowSubscription? {
        errorMessage = nil
        limitMessage = nil
        do {
            let created = try await service.create(request)
            await refresh()
            return created
        } catch let error as WildwoodError where error.status == 429 {
            // A plan-limit hit is surfaced via limitMessage (the CTA path), not errorMessage.
            limitMessage = error.message
            return nil
        } catch {
            errorMessage = friendlyMessage(error)
            return nil
        }
    }

    @discardableResult
    public func update(id: String, _ request: AIFlowSubscriptionUpdateRequest) async -> AIFlowSubscription? {
        errorMessage = nil
        do {
            let updated = try await service.update(id, request)
            await refresh()
            return updated
        } catch {
            errorMessage = friendlyMessage(error)
            return nil
        }
    }

    @discardableResult
    public func setEnabled(id: String, enabled: Bool) async -> AIFlowSubscription? {
        errorMessage = nil
        do {
            let result = try await service.setEnabled(id, enabled)
            await refresh()
            return result
        } catch {
            errorMessage = friendlyMessage(error)
            return nil
        }
    }

    @discardableResult
    public func remove(id: String) async -> Bool {
        errorMessage = nil
        // delete is non-throwing (reports the boolean outcome).
        let deleted = await service.delete(id)
        if deleted { await refresh() } else { errorMessage = "Couldn't delete the subscription." }
        return deleted
    }

    /// Full detail of the subscription's latest scheduled run (nil when none yet
    /// or on failure). A best-effort sync; a lookup failure never disturbs the list.
    public func latestRun(id: String) async -> AIFlowRunDetail? {
        (try? await service.getLatestRun(id)) ?? nil
    }

    private func friendlyMessage(_ error: any Error) -> String {
        (error as? WildwoodError)?.message ?? error.localizedDescription
    }
}
