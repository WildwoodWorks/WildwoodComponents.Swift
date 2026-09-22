// PublicCatalogStore behaviour mirrored from react-shared's usePublicCatalog module cache:
// one pair of public requests shared by every caller, a 60-second TTL, failures NEVER cached
// (the next call retries and the error reaches the UI), and invalidation for an operator price
// change. The cache key is app + currency override, as a struct — a joined string would let
// ("tenant1", "GBP") answer for ("tenant1GBP", nil).

import Foundation
import Synchronization
import Testing
@testable import WildwoodCore

/// Injectable time, so the TTL is tested without sleeping. `AttributionRules.parseTouch(now:)`
/// takes its clock the same way; the Mutex follows `CaptchaService`'s stored-state idiom.
private final class CatalogTestClock: Sendable {
    private let value = Mutex<Date>(Date(timeIntervalSince1970: 1_700_000_000))

    var now: Date { value.withLock { $0 } }

    func advance(_ seconds: TimeInterval) {
        value.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

@MainActor
struct PublicCatalogStoreTests {
    private func makeStore(
        appId: String = "app-1",
        ttl: TimeInterval = 60
    ) -> (PublicCatalogStore, MockBackend, CatalogTestClock) {
        let backend = MockBackend()
        let clock = CatalogTestClock()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: appId, enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        let store = PublicCatalogStore(
            appTier: AppTierService(http: http),
            defaultAppId: appId,
            ttl: ttl,
            now: { clock.now }
        )
        return (store, backend, clock)
    }

    private func loadCount(_ backend: MockBackend, _ path: String) -> Int {
        backend.requests().filter { $0.path == path }.count
    }

    private func stubCatalog(_ backend: MockBackend, appId: String = "app-1", tiers: String, addOns: String = "[]") {
        backend.stub("GET", "/api/app-tiers/\(appId)/public", .init(json: tiers))
        backend.stub("GET", "/api/app-tier-addons/\(appId)/public", .init(json: addOns))
    }

    @Test func servesTheCachedCatalogWithinTheTtlAndForceRefreshBypassesIt() async throws {
        let (store, backend, clock) = makeStore()
        let tierPath = "/api/app-tiers/app-1/public"
        stubCatalog(backend, tiers: #"[{"id":"t1","status":"Active"}]"#)

        let first = try await store.catalog()
        #expect(first.tiers.map(\.id) == ["t1"])
        #expect(loadCount(backend, tierPath) == 1)

        // Within the TTL the changed backend answer is NOT observed…
        backend.stub("GET", tierPath, .init(json: #"[{"id":"t2","status":"Active"}]"#))
        clock.advance(59)
        let cached = try await store.catalog()
        #expect(cached.tiers.map(\.id) == ["t1"])
        #expect(loadCount(backend, tierPath) == 1)

        // …until the entry expires.
        clock.advance(2)
        let reloaded = try await store.catalog()
        #expect(reloaded.tiers.map(\.id) == ["t2"])
        #expect(loadCount(backend, tierPath) == 2)

        // forceRefresh bypasses an entry that is still fresh.
        backend.stub("GET", tierPath, .init(json: #"[{"id":"t3","status":"Active"}]"#))
        let forced = try await store.refresh()
        #expect(forced.tiers.map(\.id) == ["t3"])
        #expect(loadCount(backend, tierPath) == 3)
    }

    @Test func aFailedLoadThrowsAndIsNeverCached() async throws {
        let (store, backend, _) = makeStore()

        // No stub → 404 on the tier request, so the load fails rather than reporting "no plans".
        await #expect(throws: WildwoodError.self) {
            _ = try await store.catalog()
        }
        #expect(store.cached() == nil)

        // The very next call goes straight back to the network — a transient error must not leave
        // the app looking like it sells nothing for the whole TTL.
        stubCatalog(backend, tiers: #"[{"id":"t1","status":"Active"}]"#)
        let loaded = try await store.catalog()
        #expect(loaded.tiers.map(\.id) == ["t1"])
    }

    @Test func concurrentCallersShareOneUpstreamLoad() async throws {
        let (store, backend, _) = makeStore()
        stubCatalog(backend, tiers: #"[{"id":"t1","status":"Active"}]"#)

        async let first: PublicCatalog = store.catalog()
        async let second: PublicCatalog = store.catalog()
        let a: PublicCatalog = try await first
        let b: PublicCatalog = try await second

        // One load, one value — the second caller joined the first caller's request.
        #expect(a == b)
        #expect(loadCount(backend, "/api/app-tiers/app-1/public") == 1)
        #expect(loadCount(backend, "/api/app-tier-addons/app-1/public") == 1)
    }

    @Test func invalidateDropsTheAppsEntriesAndTheNextCallReloads() async throws {
        let (store, backend, _) = makeStore()
        let tierPath = "/api/app-tiers/app-1/public"
        stubCatalog(backend, tiers: #"[{"id":"t1","status":"Active"}]"#)

        _ = try await store.catalog()
        _ = try await store.catalog(currencyOverride: "CAD")
        #expect(store.cached() != nil)
        #expect(store.cached(currencyOverride: "CAD") != nil)

        store.invalidate()

        // Every override for the app goes, not just the one with no override.
        #expect(store.cached() == nil)
        #expect(store.cached(currencyOverride: "CAD") == nil)

        backend.stub("GET", tierPath, .init(json: #"[{"id":"t2","status":"Active"}]"#))
        let reloaded = try await store.catalog()
        #expect(reloaded.tiers.map(\.id) == ["t2"])
    }

    @Test func theCacheKeyIsAppPlusOverrideAndCannotCollide() async throws {
        let backend = MockBackend()
        let clock = CatalogTestClock()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "tenant1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        let store = PublicCatalogStore(
            appTier: AppTierService(http: http),
            defaultAppId: "tenant1",
            ttl: 60,
            now: { clock.now }
        )

        // Neither response names a currency, so the override decides — and it is part of the key.
        stubCatalog(backend, appId: "tenant1", tiers: #"[{"id":"t1","status":"Active"}]"#)
        stubCatalog(backend, appId: "tenant1GBP", tiers: #"[{"id":"x","status":"Active"}]"#)

        let gbp = try await store.catalog(currencyOverride: "GBP")
        #expect(gbp.currency == "GBP")

        // A different override is a different entry, so it loads instead of reading GBP's answer.
        let cad = try await store.catalog(currencyOverride: "CAD")
        #expect(cad.currency == "CAD")

        // The joined-string hazard: ("tenant1", "GBP") must not answer for ("tenant1GBP", nil).
        let other = try await store.catalog(appId: "tenant1GBP")
        #expect(other.tiers.map(\.id) == ["x"])
        #expect(other.currency == "USD")

        #expect(store.cached(currencyOverride: "GBP")?.currency == "GBP")
        #expect(store.cached(currencyOverride: "CAD")?.currency == "CAD")
        #expect(store.cached(appId: "tenant1GBP")?.currency == "USD")

        // A blank override is the same key as none at all.
        let plain = try await store.catalog()
        #expect(plain.currency == "USD")
        #expect(store.cached(currencyOverride: "   ") == plain)
    }

    @Test func theLoadedCatalogIsActiveOnlyStablyOrderedAndCarriesTheServerCurrency() async throws {
        let (store, backend, _) = makeStore()
        let tiers = """
        [{"id":"b","status":"Active","displayOrder":0,"currency":"EUR"},
         {"id":"gone","status":"Deprecated","displayOrder":0},
         {"id":"c","status":"Active","displayOrder":0},
         {"id":"a","status":"Active","displayOrder":-1}]
        """
        stubCatalog(backend, tiers: tiers, addOns: #"[{"id":"pack","status":"Active"}]"#)

        let catalog = try await store.catalog(currencyOverride: "CAD")

        // The server's currency beats the caller's override…
        #expect(catalog.currency == "EUR")
        // …Deprecated is dropped, and the two displayOrder-0 tiers keep the order the server sent.
        #expect(catalog.tiers.map(\.id) == ["a", "b", "c"])
        #expect(catalog.addOns.map(\.id) == ["pack"])
        #expect(catalog.appId == "app-1")
    }

    @Test func seedFillsTheCacheWithoutFetching() async throws {
        let (store, backend, _) = makeStore()
        let seeded = PublicCatalog(appId: "app-1", currency: "GBP")

        store.seed(seeded)

        #expect(store.cached()?.currency == "GBP")
        let served = try await store.catalog()
        #expect(served == seeded)
        #expect(backend.requests().isEmpty)
    }

    @Test func withoutAnAppIdItThrowsInsteadOfRequesting() async {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        let store = PublicCatalogStore(appTier: AppTierService(http: http), defaultAppId: nil)

        await #expect(throws: WildwoodError.self) {
            _ = try await store.catalog()
        }
        #expect(backend.requests().isEmpty)
    }
}
