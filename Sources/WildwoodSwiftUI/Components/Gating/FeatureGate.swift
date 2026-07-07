#if os(iOS)
// Renders content only when the authenticated user's plan includes a feature —
// parity with the React FeatureGate. Backed by the client's shared
// FeatureStore (one bulk entitlement fetch per app, ~60s TTL), so gating many
// surfaces is cheap.
//
// Client-side gating is UX only: the server must still enforce the
// entitlement. Accordingly the gate FAILS OPEN when entitlements can't be
// loaded (transient error) — content renders and the server remains the
// enforcement point — and shows `loadingFallback` while loading.

import SwiftUI
import WildwoodCore

public struct FeatureGate<Content: View, Fallback: View, LoadingFallback: View>: View {
    @Environment(\.wildwoodClient) private var client

    private let feature: String
    private let appId: String?
    private let content: Content
    private let fallback: Fallback
    private let loadingFallback: LoadingFallback

    /// - Parameters:
    ///   - feature: Feature code defined in the app's tier catalog
    ///     (case-insensitive), e.g. "AI_ASSISTANT".
    ///   - appId: Overrides the client's configured appId.
    ///   - content: Rendered when the user's plan includes the feature.
    ///   - fallback: Rendered when the plan does NOT include the feature
    ///     (e.g. an upgrade prompt).
    ///   - loadingFallback: Rendered while entitlements load. Defaults to
    ///     nothing (avoids flashing locked UI).
    public init(
        feature: String,
        appId: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder fallback: () -> Fallback,
        @ViewBuilder loadingFallback: () -> LoadingFallback
    ) {
        self.feature = feature
        self.appId = appId
        self.content = content()
        self.fallback = fallback()
        self.loadingFallback = loadingFallback()
    }

    /// Task identity: the gate must reload when the feature OR the appId
    /// changes, and after the store is invalidated (epoch bump) — the epoch
    /// makes gates lazily re-run load() instead of the store eagerly
    /// refetching for every cached app.
    private struct ReloadTrigger: Hashable {
        var feature: String
        var appId: String?
        var epoch: Int
    }

    public var body: some View {
        Group {
            if let client {
                let store = client.features
                if store.features(appId: appId) == nil, store.state(appId: appId) != .failed {
                    loadingFallback
                } else if store.hasFeature(feature, appId: appId) {
                    content
                } else {
                    fallback
                }
            } else {
                // No client in the environment — fail open; the server enforces.
                content
            }
        }
        .task(id: ReloadTrigger(feature: feature, appId: appId, epoch: client?.features.epoch ?? 0)) {
            await client?.features.load(appId: appId)
        }
    }
}

public extension FeatureGate where LoadingFallback == EmptyView {
    init(
        feature: String,
        appId: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder fallback: () -> Fallback
    ) {
        self.init(
            feature: feature,
            appId: appId,
            content: content,
            fallback: fallback,
            loadingFallback: { EmptyView() }
        )
    }
}

public extension FeatureGate where Fallback == EmptyView, LoadingFallback == EmptyView {
    init(
        feature: String,
        appId: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            feature: feature,
            appId: appId,
            content: content,
            fallback: { EmptyView() },
            loadingFallback: { EmptyView() }
        )
    }
}
#endif
