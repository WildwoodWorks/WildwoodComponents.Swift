import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct AttributionServiceTests {
    private func makeServices(storage: MemoryStorage = MemoryStorage()) -> (AttributionService, MemoryStorage, MockBackend) {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        let consent = ConsentService(http: http, storage: storage, defaultAppId: "app-1")
        let attribution = AttributionService(http: http, storage: storage, consent: consent, defaultAppId: "app-1", platform: "ios")
        return (attribution, storage, backend)
    }

    private func stubConfig(
        _ backend: MockBackend,
        enabled: Bool = true,
        category: String = "StrictlyNecessary",
        beacon: Bool = false
    ) {
        backend.stub("GET", "/api/attribution/config", .init(json: """
        {"appId":"app-1","isEnabled":\(enabled),"captureFirstTouch":true,"captureLastTouch":true,
         "attributionWindowDays":30,"persistenceConsentCategory":"\(category)","captureClickIds":true,
         "captureReferrer":true,"extraAllowedParamNames":[],"beaconEnabled":\(beacon)}
        """))
        backend.stub("POST", "/api/attribution/touch", .init(statusCode: 202))
    }

    private let adLink = URL(string: "cairnfed://signup?utm_source=Reddit&utm_medium=paid&utm_campaign=govcon-test-sep26&utm_content=ad1")!

    @Test func captureReadsTheUtmTagsFromADeepLink() async {
        let (service, _, backend) = makeServices()
        stubConfig(backend)
        await service.initialize()

        let touch = service.capture(url: adLink)

        #expect(touch?.source == "reddit")
        #expect(touch?.medium == "paid")
        #expect(touch?.campaign == "govcon-test-sep26")
        let payload = service.getForRegistration()
        #expect(payload?.lastTouch?.content == "ad1")
        #expect(payload?.firstTouch == payload?.lastTouch)
        #expect(payload?.sdk == "swift")
        #expect(payload?.platform == "ios")
    }

    @Test func aDirectVisitNeverOverwritesTheLastTouch() async {
        let (service, _, backend) = makeServices()
        stubConfig(backend)
        await service.initialize()
        service.capture(url: adLink)

        let direct = service.capture(url: URL(string: "cairnfed://dashboard")!)

        #expect(direct == nil)
        #expect(service.last?.source == "reddit")
    }

    @Test func anExternalReferrerWithoutTagsBecomesAReferral() async {
        let (service, _, backend) = makeServices()
        stubConfig(backend)
        await service.initialize()

        let touch = service.capture(
            url: URL(string: "https://cairnfed.ai/pricing")!,
            referrer: URL(string: "https://www.reddit.com/r/govcon/")!
        )

        #expect(touch?.source == "reddit.com")
        #expect(touch?.medium == "referral")
        #expect(touch?.landingPath == "/pricing")
    }

    @Test func strictlyNecessaryPersistsTheBlobWithoutConsent() async {
        let (service, storage, backend) = makeServices()
        stubConfig(backend, category: "StrictlyNecessary")
        await service.initialize()

        service.capture(url: adLink)

        #expect(storage.getItem(WildwoodStorageKeys.attribution) != nil)
        #expect(service.persisted == true)
    }

    @Test func analyticsStaysInMemoryUntilConsentIsGranted() async {
        let (service, storage, backend) = makeServices()
        stubConfig(backend, category: "Analytics")
        await service.initialize()

        service.capture(url: adLink)

        #expect(storage.getItem(WildwoodStorageKeys.attribution) == nil)
        #expect(service.persisted == false)
        #expect(service.getForRegistration() != nil)
    }

    @Test func aDisabledConfigCapturesAndStoresNothing() async {
        let storage = MemoryStorage()
        storage.setItem(WildwoodStorageKeys.attribution, #"{"v":1,"visitorKey":"stored-visitor-0001","first":null,"last":null,"updatedAt":""}"#)
        let (service, _, backend) = makeServices(storage: storage)
        stubConfig(backend, enabled: false)

        await service.initialize()

        #expect(service.capture(url: adLink) == nil)
        #expect(service.getForRegistration() == nil)
        #expect(storage.getItem(WildwoodStorageKeys.attribution) == nil)
    }

    @Test func clearDropsTheTouchesAndTheStoredBlob() async {
        let (service, storage, backend) = makeServices()
        stubConfig(backend)
        await service.initialize()
        service.capture(url: adLink)

        service.clear()

        #expect(service.getForRegistration() == nil)
        #expect(storage.getItem(WildwoodStorageKeys.attribution) == nil)
    }

    @Test func registrationRequestsEncodeTheAttributionPayload() throws {
        let touch = AttributionTouch(source: "reddit", medium: "paid", occurredAt: "2026-09-13T12:00:00.000Z")
        let payload = AttributionPayload(visitorKey: "visitor-key-0001", firstTouch: touch, lastTouch: touch, platform: "ios")
        let request = RegistrationRequest(email: "new@example.com", firstName: "Jane", lastName: "Doe", appId: "app-1", attribution: payload)

        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)

        #expect(json.contains(#""attribution":"#))
        #expect(json.contains(#""sdk":"swift""#))
    }
}
