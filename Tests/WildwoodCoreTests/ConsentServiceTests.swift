import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct ConsentServiceTests {
    private func makeService(storage: MemoryStorage = MemoryStorage()) -> (ConsentService, MemoryStorage, MockBackend) {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        let service = ConsentService(http: http, storage: storage, defaultAppId: "app-1")
        return (service, storage, backend)
    }

    private func stubConfig(
        _ backend: MockBackend,
        enabled: Bool = true,
        version: Int = 3,
        geoAware: Bool = false,
        geoInTarget: Bool = false,
        honorGpc: Bool = true,
        nonTargetDefault: String = "LoadAll",
        categories: String = #"["Functional","Analytics","Advertising"]"#
    ) {
        backend.stub("GET", "/api/consent/config", .init(json: """
        {"appId":"app-1","enabled":\(enabled),"version":\(version),
         "geo":{"aware":\(geoAware),"inTarget":\(geoInTarget),"resolvedTags":[]},
         "honorGpc":\(honorGpc),"showDoNotSell":false,"showLimitSensitive":false,
         "nonTargetDefault":"\(nonTargetDefault)","categories":\(categories),
         "appearance":null,"bannerText":null,"privacyPolicyUrl":null,"accessibilityUrl":null,"scripts":[]}
        """))
        backend.stub("POST", "/api/consent/record", .init(statusCode: 200))
    }

    @Test func initializeShowsBannerWhenUndecidedAndNotGeoAware() async throws {
        let (service, _, backend) = makeService()
        stubConfig(backend)

        let result = try await service.initialize()

        #expect(result.config.enabled == true)
        #expect(result.config.categories == [.functional, .analytics, .advertising])
        #expect(result.shouldShowBanner == true)
        #expect(result.state.decided == false)
        // Nothing is granted until the visitor acts (necessary is implicitly always on).
        #expect(service.isGranted(.analytics) == false)
        #expect(service.isGranted(.strictlyNecessary) == true)
    }

    @Test func disabledConfigNeverShowsBanner() async throws {
        let (service, _, backend) = makeService()
        stubConfig(backend, enabled: false)

        let result = try await service.initialize()

        #expect(result.shouldShowBanner == false)
    }

    @Test func acceptAllGrantsActiveCategoriesPersistsAndRecords() async throws {
        let (service, storage, backend) = makeService()
        stubConfig(backend)
        _ = try await service.initialize()

        _ = try await service.acceptAll()

        #expect(service.isGranted(.functional) == true)
        #expect(service.isGranted(.analytics) == true)
        #expect(service.isGranted(.advertising) == true)
        // Sensitive isn't an active category here, so it stays off.
        #expect(service.isGranted(.sensitive) == false)
        // The decision is persisted under the consent key and posted to the record endpoint.
        #expect(storage.getItem(WildwoodStorageKeys.consent) != nil)
        #expect(backend.requests().contains { $0.method == "POST" && $0.path == "/api/consent/record" })
    }

    @Test func rejectAllLeavesOnlyNecessary() async throws {
        let (service, _, backend) = makeService()
        stubConfig(backend)
        _ = try await service.initialize()

        let state = try await service.rejectAll()

        #expect(state?.isGranted(.analytics) == false)
        #expect(state?.decided == true)
        #expect(service.isGranted(.strictlyNecessary) == true)
    }

    @Test func setCategoriesAppliesOnlyTheSelection() async throws {
        let (service, _, backend) = makeService()
        stubConfig(backend)
        _ = try await service.initialize()

        _ = try await service.setCategories([.analytics: true, .advertising: false])

        #expect(service.isGranted(.analytics) == true)
        #expect(service.isGranted(.advertising) == false)
        #expect(service.isGranted(.functional) == false)
    }

    @Test func validStoredDecisionSuppressesBanner() async throws {
        let storage = MemoryStorage()
        storage.setItem(
            WildwoodStorageKeys.consent,
            #"{"visitorKey":"v-existing","consentString":"Analytics","configVersion":3}"#
        )
        let (service, _, backend) = makeService(storage: storage)
        stubConfig(backend, version: 3)

        let result = try await service.initialize()

        #expect(result.shouldShowBanner == false)
        #expect(result.state.decided == true)
        #expect(result.state.visitorKey == "v-existing")
        #expect(service.isGranted(.analytics) == true)
        #expect(service.isGranted(.advertising) == false)
    }

    @Test func staleStoredDecisionRePromptsOnVersionBump() async throws {
        let storage = MemoryStorage()
        storage.setItem(
            WildwoodStorageKeys.consent,
            #"{"visitorKey":"v-existing","consentString":"Analytics","configVersion":2}"#
        )
        let (service, _, backend) = makeService(storage: storage)
        stubConfig(backend, version: 3) // server bumped the config version

        let result = try await service.initialize()

        #expect(result.shouldShowBanner == true)
        #expect(result.state.decided == false)
    }

    @Test func withdrawClearsStoredDecision() async throws {
        let (service, storage, backend) = makeService()
        stubConfig(backend)
        _ = try await service.initialize()
        _ = try await service.acceptAll()
        #expect(storage.getItem(WildwoodStorageKeys.consent) != nil)

        _ = try await service.withdraw()

        #expect(storage.getItem(WildwoodStorageKeys.consent) == nil)
        #expect(service.isGranted(.analytics) == false)
    }

    @Test func nonTargetVisitorGetsLoadAllDefaultWithoutBanner() async throws {
        let (service, storage, backend) = makeService()
        // Geo-aware, visitor outside the target, default is LoadAll.
        stubConfig(backend, geoAware: true, geoInTarget: false, nonTargetDefault: "LoadAll")

        let result = try await service.initialize()

        #expect(result.shouldShowBanner == false)
        #expect(service.isGranted(.analytics) == true)
        // A decision was persisted for the non-target default.
        #expect(storage.getItem(WildwoodStorageKeys.consent) != nil)
    }
}
