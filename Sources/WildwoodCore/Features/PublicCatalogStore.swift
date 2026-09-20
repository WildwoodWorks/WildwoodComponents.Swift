// Shared public-catalog cache — the Swift analog of react-shared's `usePublicCatalog` module
// cache, modelled on ``FeatureStore`` (same isolation, same per-key entry struct, same
// never-cache-a-failure rule).
//
// A pricing table, a signup screen and an upgrade sheet all want the same two public responses,
// so one pair of requests serves them all: entries are keyed by app + currency override, held for
// a 60-second TTL, and concurrent callers share ONE in-flight load.
//
// Failure policy: THE OPPOSITE of FeatureStore's. A feature gate fails OPEN because the server
// enforces entitlements anyway; a price cannot be invented, so a failed load throws and is never
// cached. The next call retries immediately and the error reaches the UI, which is what lets a
// pricing screen say "Pricing is unavailable right now" instead of "this app sells nothing".

import Foundation
import Observation

@MainActor
@Observable
public final class PublicCatalogStore {
    /// Cache identity. A struct, not a joined string: `("tenant1", "GBP")` and `("tenant1GBP",
    /// nil)` must not collide.
    public struct Key: Hashable, Sendable {
        public var appId: String
        /// Trimmed, or nil when the caller named no override.
        public var currencyOverride: String?

        public init(appId: String, currencyOverride: String? = nil) {
            self.appId = appId
            self.currencyOverride = currencyOverride
        }
    }

    /// Everything tracked per key, so invalidation clears one collection.
    private struct Entry {
        var catalog: PublicCatalog? = nil
        var loadedAt: Date? = nil
        /// The load every concurrent caller for this key awaits. Cleared once it settles.
        var inFlight: Task<PublicCatalog, any Error>? = nil
    }

    @ObservationIgnored private let appTier: AppTierService
    @ObservationIgnored private let defaultAppId: String?
    @ObservationIgnored private let ttl: TimeInterval
    /// Injected so tests can move time without sleeping, the way `AttributionRules.parseTouch`
    /// takes its `now`.
    @ObservationIgnored private let now: @Sendable () -> Date

    /// Per-key cache. Observable (not ignored) so a view reading ``cached(appId:currencyOverride:)``
    /// re-renders when a load lands.
    private var entries: [Key: Entry] = [:]

    public init(
        appTier: AppTierService,
        defaultAppId: String? = nil,
        ttl: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.appTier = appTier
        self.defaultAppId = defaultAppId
        self.ttl = ttl
        self.now = now
    }

    /// What the app sells.
    ///
    /// Served from cache while it is younger than the TTL; otherwise loaded from the two public
    /// endpoints in parallel. Concurrent callers for the same key share one load. A failure is
    /// NEVER cached — it propagates so the caller can say the catalog is unavailable, and the very
    /// next call tries again.
    ///
    /// - Parameters:
    ///   - appId: defaults to the client's configured app.
    ///   - currencyOverride: used only when the responses carry no currency (an older server).
    ///     Part of the cache key, so two screens asking for different fallbacks do not read each
    ///     other's answer.
    ///   - forceRefresh: bypass the TTL. An in-flight load is still shared, so a refresh that
    ///     races a load joins it rather than doubling the requests.
    @discardableResult
    public func catalog(
        appId: String? = nil,
        currencyOverride: String? = nil,
        forceRefresh: Bool = false
    ) async throws -> PublicCatalog {
        guard let id = resolve(appId) else { throw Self.missingAppId }
        let key = Key(appId: id, currencyOverride: Catalog.trimmedOrNil(currencyOverride))

        if !forceRefresh,
           let entry = entries[key],
           let cached = entry.catalog,
           let loadedAt = entry.loadedAt,
           now().timeIntervalSince(loadedAt) < ttl {
            return cached
        }

        if let inFlight = entries[key]?.inFlight {
            return try await inFlight.value
        }

        // Captured locally rather than through `self`: the two getters are on a `Sendable`
        // service and need no isolation of their own.
        let service: AppTierService = appTier
        let override: String? = key.currencyOverride
        let clock: @Sendable () -> Date = now

        let task: Task<PublicCatalog, any Error> = Task {
            // Both endpoints are public and independent, so they go together rather than one
            // after the other.
            async let tiers: [AppTierModel] = service.getPublicTiersThrowing(appId: id)
            async let addOns: [AppTierAddOnModel] = service.getPublicAddOns(appId: id)
            let loadedTiers: [AppTierModel] = try await tiers
            let loadedAddOns: [AppTierAddOnModel] = try await addOns
            return PublicCatalog.build(
                appId: id,
                tiers: loadedTiers,
                addOns: loadedAddOns,
                currencyOverride: override,
                now: clock()
            )
        }

        var pending: Entry = entries[key] ?? Entry()
        pending.inFlight = task
        entries[key] = pending

        do {
            let loaded: PublicCatalog = try await task.value
            // Only the caller that started this load writes it, and only if the entry still holds
            // it: an `invalidate` during the load must not be undone by the answer it invalidated.
            if entries[key]?.inFlight == task {
                entries[key] = Entry(catalog: loaded, loadedAt: now(), inFlight: nil)
            }
            return loaded
        } catch {
            // Never cache a failure: a transient error must not leave the app looking like it
            // sells nothing for the whole TTL. The entry goes entirely, stale catalog included,
            // exactly as the JS cache deletes its map entry.
            if entries[key]?.inFlight == task {
                entries[key] = nil
            }
            throw error
        }
    }

    /// Force a reload, bypassing the TTL.
    @discardableResult
    public func refresh(appId: String? = nil, currencyOverride: String? = nil) async throws -> PublicCatalog {
        try await catalog(appId: appId, currencyOverride: currencyOverride, forceRefresh: true)
    }

    /// The cached catalog, without loading one. Nil when nothing is cached for the key — this
    /// never reports staleness, so a caller that needs a fresh answer awaits ``catalog(appId:currencyOverride:forceRefresh:)``.
    public func cached(appId: String? = nil, currencyOverride: String? = nil) -> PublicCatalog? {
        guard let id = resolve(appId) else { return nil }
        return entries[Key(appId: id, currencyOverride: Catalog.trimmedOrNil(currencyOverride))]?.catalog
    }

    /// Put a catalog into the cache without fetching — the preview and test path (JS
    /// `seedPublicCatalog`; the SSR `initialCatalog` half of it has no iOS counterpart).
    public func seed(_ catalog: PublicCatalog, currencyOverride: String? = nil) {
        guard !catalog.appId.isEmpty else { return }
        let key = Key(appId: catalog.appId, currencyOverride: Catalog.trimmedOrNil(currencyOverride))
        entries[key] = Entry(catalog: catalog, loadedAt: now(), inFlight: nil)
    }

    /// Drop one app's cached catalogs, every currency override included.
    ///
    /// Buying something does NOT change what an app sells, so the purchase paths deliberately do
    /// not call this. It is for an operator changing the price list.
    public func invalidate(appId: String? = nil) {
        guard let id = resolve(appId) else { return }
        let doomed: [Key] = entries.keys.filter { $0.appId == id }
        for key in doomed { entries[key] = nil }
    }

    /// Drop every cached catalog (JS `clearPublicCatalogCache`).
    public func invalidateAll() {
        entries.removeAll()
    }

    private func resolve(_ appId: String?) -> String? {
        let id: String? = appId ?? defaultAppId
        guard let id, !id.isEmpty else { return nil }
        return id
    }

    private static let missingAppId = WildwoodError(
        message: "An appId is required to load the public catalog.",
        status: 0,
        code: .unknown
    )
}
