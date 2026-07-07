// FeatureStore behavior mirrored from react-shared's useFeatures tests:
// one bulk fetch, UPPERCASE key normalization for case-insensitive lookup,
// fail-open while unknown/failed, failures never cached, TTL caching with a
// refresh bypass, and LAZY invalidation (clear + epoch bump, never an eager
// refetch; logout clears without even the epoch bump).

import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct FeatureStoreTests {
    private func makeStore(ttl: Duration = .seconds(60)) -> (FeatureStore, MockBackend) {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        let store = FeatureStore(appTier: AppTierService(http: http), defaultAppId: "app-1", ttl: ttl)
        return (store, backend)
    }

    @Test func loadNormalizesKeysForCaseInsensitiveLookup() async {
        let (store, backend) = makeStore()
        backend.stub("GET", "/api/app-tiers/app-1/user-features", .init(json: #"{"ai_chat":true,"Payments":false}"#))

        await store.load()

        #expect(store.state() == .loaded)
        #expect(store.hasFeature("AI_CHAT") == true)
        #expect(store.hasFeature("ai_chat") == true)
        #expect(store.hasFeature("payments") == false)
        #expect(store.hasFeature("PAYMENTS") == false)
        // A loaded map answers unknown codes with false (a real "no access").
        #expect(store.hasFeature("UNKNOWN_CODE") == false)
    }

    @Test func failsOpenWhileUnknownAndNeverCachesAFailure() async {
        let (store, backend) = makeStore()

        // Never loaded → unknown → fail open (the server enforces).
        #expect(store.hasFeature("AI_CHAT") == true)

        // Failed load → still fail open, and the failure is not cached…
        await store.load() // no stub → 404
        #expect(store.state() == .failed)
        #expect(store.features() == nil)
        #expect(store.hasFeature("AI_CHAT") == true)

        // …so the next load goes straight back to the network.
        backend.stub("GET", "/api/app-tiers/app-1/user-features", .init(json: #"{"ai_chat":false}"#))
        await store.load()
        #expect(store.state() == .loaded)
        #expect(store.hasFeature("AI_CHAT") == false)
    }

    @Test func servesTheCachedMapWithinTheTTLAndRefreshBypassesIt() async {
        let (store, backend) = makeStore()
        backend.stub("GET", "/api/app-tiers/app-1/user-features", .init(json: #"{"a":true}"#))
        await store.load()

        // Within the TTL the changed backend answer is NOT observed…
        backend.stub("GET", "/api/app-tiers/app-1/user-features", .init(json: #"{"a":false}"#))
        await store.load()
        #expect(store.hasFeature("A") == true)

        // …until refresh bypasses the cache.
        await store.refresh()
        #expect(store.hasFeature("A") == false)
    }

    @Test func invalidateClearsSynchronouslyBumpsTheEpochAndNeverFetches() async {
        let (store, backend) = makeStore()
        backend.stub("GET", "/api/app-tiers/app-1/user-features", .init(json: #"{"a":true}"#))
        await store.load()
        #expect(store.features() != nil)
        #expect(backend.requests().count == 1)
        let epochBefore = store.epoch

        store.invalidate()

        // Cleared synchronously — gates fail open until an on-demand reload lands.
        #expect(store.features() == nil)
        #expect(store.hasFeature("A") == true)
        // Lazy invalidation: the epoch bump re-runs mounted gates' .task; the
        // store itself must NOT eagerly refetch.
        #expect(store.epoch == epochBefore + 1)
        for _ in 0..<20 { await Task.yield() }
        #expect(backend.requests().count == 1)

        // The next on-demand load() goes back to the network (TTL dropped
        // with the entry) and repopulates the map.
        backend.stub("GET", "/api/app-tiers/app-1/user-features", .init(json: #"{"a":false}"#))
        await store.load()
        #expect(store.state() == .loaded)
        #expect(store.hasFeature("A") == false)
        #expect(backend.requests().count == 2)
    }

    @Test func loginAuthChangeInvalidatesAndBumpsTheEpoch() async {
        let backend = MockBackend()
        let events = WildwoodEventEmitter()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        let store = FeatureStore(appTier: AppTierService(http: http), defaultAppId: "app-1", events: events)

        backend.stub("GET", "/api/app-tiers/app-1/user-features", .init(json: #"{"a":true}"#))
        await store.load()
        let epochBefore = store.epoch

        events.emit(.authChanged(AuthenticationResponse(userId: "u2")))

        // The old user's entitlements must not gate the new one; the epoch
        // bump makes mounted gates reload on demand.
        #expect(store.features() == nil)
        #expect(store.epoch == epochBefore + 1)
    }

    @Test func logoutOnlyClearsNoEpochBumpNoFetchAndGatesFailOpen() async {
        let backend = MockBackend()
        let events = WildwoodEventEmitter()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        let store = FeatureStore(appTier: AppTierService(http: http), defaultAppId: "app-1", events: events)

        backend.stub("GET", "/api/app-tiers/app-1/user-features", .init(json: #"{"a":false}"#))
        await store.load()
        #expect(store.hasFeature("A") == false)
        let epochBefore = store.epoch

        events.emit(.sessionExpired)

        // Cleared and failing open — but NO epoch bump (mounted gates must
        // not refetch: a fetch without a session can only 401) and NO request.
        #expect(store.features() == nil)
        #expect(store.state() == .failed)
        #expect(store.hasFeature("A") == true)
        #expect(store.epoch == epochBefore)
        for _ in 0..<20 { await Task.yield() }
        #expect(backend.requests().count == 1)

        // .authChanged(nil) behaves the same way.
        events.emit(.authChanged(nil))
        #expect(store.epoch == epochBefore)
    }

    @Test func missingAppIdFailsOpenInsteadOfLoadingForever() async {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        let store = FeatureStore(appTier: AppTierService(http: http), defaultAppId: nil)

        await store.load() // no appId anywhere → no request, no spinner
        #expect(store.state() == .failed)
        #expect(store.hasFeature("ANYTHING") == true)
        #expect(backend.requests().isEmpty)
    }
}
