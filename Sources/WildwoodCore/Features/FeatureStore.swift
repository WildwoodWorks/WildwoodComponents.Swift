// Shared feature-entitlement cache — the Swift analog of react-shared's
// useFeatures module cache. One bulk fetch of the user's entitlement map
// (GET api/app-tiers/{appId}/user-features) shared across every FeatureGate
// in the app, instead of a per-gate checkFeature round-trip.
//
// Failure policy: FAIL OPEN. Client-side gating is UX; the server enforces
// the real entitlement. A transient fetch failure is never cached and never
// locks gates — hasFeature() returns true while entitlements are unknown.

import Foundation
import Observation

@MainActor
@Observable
public final class FeatureStore {
    public enum LoadState: Sendable, Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    @ObservationIgnored private let appTier: AppTierService
    @ObservationIgnored private let defaultAppId: String?
    @ObservationIgnored private let ttl: Duration
    @ObservationIgnored private var loadedAt: [String: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var authSubscription: WildwoodSubscription?

    /// Normalized (UPPERCASED-key) entitlement maps per appId, so lookups are
    /// case-insensitive (codes are conventionally UPPER_SNAKE, but callers
    /// have used lowercase variants).
    public private(set) var maps: [String: [String: Bool]] = [:]
    public private(set) var states: [String: LoadState] = [:]

    /// `events` wires the auth-change invalidation: login/logout/session
    /// expiry drops every cached map (the old user's entitlements must not
    /// gate the new one).
    public init(
        appTier: AppTierService,
        defaultAppId: String? = nil,
        events: WildwoodEventEmitter? = nil,
        ttl: Duration = .seconds(60)
    ) {
        self.appTier = appTier
        self.defaultAppId = defaultAppId
        self.ttl = ttl
        if let events {
            authSubscription = events.on { [weak self] event in
                switch event {
                case .authChanged, .sessionExpired:
                    self?.invalidate()
                default:
                    break
                }
            }
        }
    }

    /// The normalized entitlement map, or nil while unknown (never loaded, or
    /// failed with nothing stale to serve).
    public func features(appId: String? = nil) -> [String: Bool]? {
        guard let id = resolve(appId) else { return nil }
        return maps[id]
    }

    public func state(appId: String? = nil) -> LoadState {
        // No appId anywhere → gates must fail open, not spin forever.
        guard let id = resolve(appId) else { return .failed }
        return states[id] ?? .idle
    }

    /// Whether the user's plan includes the feature (case-insensitive).
    /// FAILS OPEN while entitlements are unknown (still loading, or the fetch
    /// errored): returns true, because the server enforces the real
    /// entitlement and wrongly locking paid features is worse than briefly
    /// showing them.
    public func hasFeature(_ featureCode: String, appId: String? = nil) -> Bool {
        guard let map = features(appId: appId) else { return true }
        return map[featureCode.uppercased()] == true
    }

    /// Ensure the map is loaded (respecting the TTL). Concurrent callers
    /// dedupe on the in-flight load; N mounted gates cost one request.
    public func load(appId: String? = nil) async {
        guard let id = resolve(appId) else { return }
        if states[id] == .loading { return }
        if let at = loadedAt[id], at.duration(to: ContinuousClock.now) < ttl, maps[id] != nil { return }

        states[id] = .loading
        do {
            let raw = try await appTier.getUserFeatures(appId: id)
            var normalized: [String: Bool] = [:]
            normalized.reserveCapacity(raw.count)
            for (key, value) in raw {
                normalized[key.uppercased()] = value
            }
            maps[id] = normalized
            loadedAt[id] = .now
            states[id] = .loaded
        } catch {
            // Never cache a failure: a transient error must not lock every
            // gate for the TTL. Any stale map is kept (stale beats
            // wrongly-locked); .failed tells gates to fail open.
            loadedAt[id] = nil
            states[id] = .failed
        }
    }

    /// Bypass the TTL and refetch (the stale map keeps serving until the new
    /// one lands).
    public func refresh(appId: String? = nil) async {
        guard let id = resolve(appId) else { return }
        loadedAt[id] = nil
        if states[id] != .loading { states[id] = .idle }
        await load(appId: id)
    }

    /// Drop every cached map AND kick refetches for the apps that had one —
    /// call after entitlement-changing mutations (tier change/subscribe/
    /// cancel, feature overrides, add-on purchases) so gates elsewhere in the
    /// app don't serve the old plan for the cache TTL.
    /// WildwoodSubscriptionAdminModel's mutation methods call this
    /// automatically, as does the auth-change listener.
    public func invalidate() {
        let ids = Set(maps.keys).union(states.keys)
        maps.removeAll()
        states.removeAll()
        loadedAt.removeAll()
        for id in ids {
            Task { @MainActor in await self.load(appId: id) }
        }
    }

    private func resolve(_ appId: String?) -> String? {
        let id = appId ?? defaultAppId
        guard let id, !id.isEmpty else { return nil }
        return id
    }
}
