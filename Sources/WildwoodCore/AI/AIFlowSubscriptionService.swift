// Flow-subscription service ported from
// WildwoodComponents.Blazor/Services/AIFlowSubscriptionService.cs (the Blazor
// stack is the reference implementation for AI Flows). A user's standing orders
// for scheduled runs of published flows: create/list/enable/delete plus a
// latest-run sync so a client can pull the full result (including outputJson)
// of a background run it did not stream.
//
// Adapted to the Swift throwing idiom (June 2026 decision): CRUD/lookups THROW
// so a genuine failure stays distinguishable from an empty/normal result rather
// than being swallowed. In particular a 429 create failure surfaces naturally as
// a thrown WildwoodError (status 429, message from the body) — there is no
// stateful lastLimitMessage. `getLatestRun` maps a 404 to nil (no run yet) and
// rethrows anything else; `delete` reports the boolean outcome.
//
// Auth semantics live in the shared HTTP client: a 401 triggers a single
// refresh + replay whose refresh flow emits the session-expired signal (once per
// token), and a 403 (tier lacks FLOW_SUBSCRIPTIONS) is a permission denial that
// throws without any session signal.
//
// PARITY: endpoint paths are passed as double-quoted string literals to the HTTP
// verb methods so the Sync parity script can extract them.

import Foundation

public final class AIFlowSubscriptionService: Sendable {
    private let http: WildwoodHttpClient
    private let appId: String?

    public init(http: WildwoodHttpClient, appId: String? = nil) {
        self.http = http
        self.appId = appId
    }

    /// The current user's flow subscriptions. THROWS on failure — a lookup must
    /// stay distinguishable from a genuinely empty list.
    public func getSubscriptions() async throws -> [AIFlowSubscription] {
        try await http.get("api/ai/flows/subscriptions\(appQuery())")
    }

    /// Creates a subscription. THROWS on failure; a 429 (limit reached) surfaces
    /// as a WildwoodError with status 429 whose message is the server's limit copy,
    /// falling back to the friendly upgrade string when the body carries none —
    /// parity with the JS/.NET `extractLimitMessage`/`ExtractLimitMessageAsync`.
    public func create(_ request: AIFlowSubscriptionCreateRequest) async throws -> AIFlowSubscription {
        do {
            return try await http.post("api/ai/flows/subscriptions\(appQuery())", body: request)
        } catch let error as WildwoodError where error.status == 429 {
            throw WildwoodError(
                message: Self.limitMessage(from: error.details),
                status: 429,
                code: .rateLimited,
                details: error.details
            )
        }
    }

    /// Applies a partial update (unset fields are left unchanged). THROWS on failure.
    public func update(_ subscriptionId: String, _ request: AIFlowSubscriptionUpdateRequest) async throws -> AIFlowSubscription {
        try await http.put("api/ai/flows/subscriptions/\(encodePath(subscriptionId))\(appQuery())", body: request)
    }

    /// Enables or disables the subscription (no request body). THROWS on failure.
    public func setEnabled(_ subscriptionId: String, _ enabled: Bool) async throws -> AIFlowSubscription {
        if enabled {
            return try await http.post("api/ai/flows/subscriptions/\(encodePath(subscriptionId))/enable\(appQuery())")
        } else {
            return try await http.post("api/ai/flows/subscriptions/\(encodePath(subscriptionId))/disable\(appQuery())")
        }
    }

    /// Deletes the subscription. Returns whether the request succeeded (the
    /// response's ok status), matching the .NET/JS boolean contract.
    public func delete(_ subscriptionId: String) async -> Bool {
        do {
            try await http.deleteVoid("api/ai/flows/subscriptions/\(encodePath(subscriptionId))\(appQuery())")
            return true
        } catch {
            return false
        }
    }

    /// The subscription's most recent scheduled run, with full detail (input/output
    /// JSON) for syncing after a completion notification. Returns nil when no run
    /// exists yet (404); rethrows any other failure.
    public func getLatestRun(_ subscriptionId: String) async throws -> AIFlowRunDetail? {
        do {
            let detail: AIFlowRunDetail = try await http.get(
                "api/ai/flows/subscriptions/\(encodePath(subscriptionId))/latest-run\(appQuery())"
            )
            return detail
        } catch let error as WildwoodError where error.status == 404 {
            return nil
        }
    }

    // ------------------------------------------------------------------

    /// The plan-limit copy for a 429 create: the body's `message` when present,
    /// else the friendly fallback (mirrors the JS/.NET limit-message extraction).
    private static func limitMessage(from body: Data?) -> String {
        if let body,
           let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let message = object["message"] as? String, !message.isEmpty {
            return message
        }
        return "Your plan's favorites limit has been reached."
    }

    private func encodePath(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func appQuery() -> String {
        guard let appId, !appId.isEmpty else { return "" }
        return "?requestedAppId=\(appId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? appId)"
    }
}
