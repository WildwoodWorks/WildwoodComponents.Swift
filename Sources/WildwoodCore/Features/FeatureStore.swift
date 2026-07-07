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

    /// Everything the store tracks per appId, so invalidation clears one
    /// collection instead of keeping three dictionaries in sync.
    private struct Entry {
        /// Normalized (UPPERCASED-key) entitlement map, nil while unknown.
        var map: [String: Bool]? = nil
        var state: LoadState = .idle
        var loadedAt: ContinuousClock.Instant? = nil
    }

    @ObservationIgnored private let appTier: AppTierService
    @ObservationIgnored private let defaultAppId: String?
    @ObservationIgnored private let ttl: Duration
    @ObservationIgnored private var authSubscription: WildwoodSubscription?

    /// Per-appId cache. Observable (not ignored) so views reading through
    /// features()/state()/hasFeature() re-render when a load lands.
    private var entries: [String: Entry] = [:]

    /// Invalidation epoch — bumped by invalidate() so mounted FeatureGates
    /// (which include it in their .task id) re-run their load lazily, on
    /// demand, instead of the store eagerly refetching every cached app.
    public private(set) var epoch = 0

    /// Normalized (UPPERCASED-key) entitlement maps per appId, so lookups are
    /// case-insensitive (codes are conventionally UPPER_SNAKE, but callers
    /// have used lowercase variants).
    public var maps: [String: [String: Bool]] { entries.compactMapValues(\.map) }
    public var states: [String: LoadState] { entries.mapValues(\.state) }

    /// `events` wires the auth-change invalidation: login/logout/session
    /// expiry drops every cached map (the old user's entitlements must not
    /// gate the new one). Logouts only clear — a refetch could only 401.
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
                case .authChanged(nil), .sessionExpired:
                    // Logged out: no entitlements can be fetched (guaranteed
                    // 401 + a wasted refresh attempt), so ONLY clear — no
                    // epoch bump, so mounted gates don't refetch. .failed
                    // keeps them failing open (the server enforces anyway).
                    self?.clearOnLogout()
                case .authChanged:
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
        return entries[id]?.map
    }

    public func state(appId: String? = nil) -> LoadState {
        // No appId anywhere → gates must fail open, not spin forever.
        guard let id = resolve(appId) else { return .failed }
        return entries[id]?.state ?? .idle
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
        if let entry = entries[id] {
            if entry.state == .loading { return }
            if let at = entry.loadedAt, at.duration(to: ContinuousClock.now) < ttl, entry.map != nil { return }
        }

        entries[id, default: Entry()].state = .loading
        do {
            let raw = try await appTier.getUserFeatures(appId: id)
            var normalized: [String: Bool] = [:]
            normalized.reserveCapacity(raw.count)
            for (key, value) in raw {
                normalized[key.uppercased()] = value
            }
            entries[id] = Entry(map: normalized, state: .loaded, loadedAt: .now)
        } catch {
            // Never cache a failure: a transient error must not lock every
            // gate for the TTL. Any stale map is kept (stale beats
            // wrongly-locked); .failed tells gates to fail open.
            var entry = entries[id] ?? Entry()
            entry.state = .failed
            entry.loadedAt = nil
            entries[id] = entry
        }
    }

    /// Bypass the TTL and refetch (the stale map keeps serving until the new
    /// one lands).
    public func refresh(appId: String? = nil) async {
        guard let id = resolve(appId) else { return }
        var entry = entries[id] ?? Entry()
        entry.loadedAt = nil
        if entry.state != .loading { entry.state = .idle }
        entries[id] = entry
        await load(appId: id)
    }

    /// Lazy invalidation: drop every cached map and bump `epoch` — NO eager
    /// network calls. Mounted FeatureGates include the epoch in their .task
    /// id, so they re-run load() on demand (deduped by the in-flight check);
    /// unmounted surfaces simply refetch the next time they appear. Call
    /// after entitlement-changing mutations (tier change/subscribe/cancel,
    /// feature overrides, add-on purchases) so gates elsewhere in the app
    /// don't serve the old plan for the cache TTL.
    /// WildwoodSubscriptionAdminModel's mutation methods call this
    /// automatically, as does the auth-change listener on login.
    public func invalidate() {
        entries.removeAll()
        epoch += 1
    }

    /// Logout-time clear: the cached maps are dropped like invalidate(), but
    /// the epoch is NOT bumped — refetching without a session can only 401.
    /// Entries flip to .failed so gates fail open instead of showing their
    /// loading fallback forever; the next login invalidates and reloads.
    private func clearOnLogout() {
        entries = entries.mapValues { _ in Entry(map: nil, state: .failed, loadedAt: nil) }
    }

    private func resolve(_ appId: String?) -> String? {
        let id = appId ?? defaultAppId
        guard let id, !id.isEmpty else { return nil }
        return id
    }
}
