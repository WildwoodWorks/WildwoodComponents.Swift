import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct AttributionServiceTests {
    private func makeServices(storage: MemoryStorage = MemoryStorage()) -> (AttributionService, MemoryStorage, MockBackend) {
        let services = makeFullServices(storage: storage)
        return (services.0, services.2, services.3)
    }

    /// The consent engine too, for the tests that drive the persistence gate through a real
    /// consent decision, plus the event emitter for `attributionCaptured`.
    private func makeFullServices(
        storage: MemoryStorage = MemoryStorage(),
        events: WildwoodEventEmitter? = nil,
        enabled: Bool = true
    ) -> (AttributionService, ConsentService, MemoryStorage, MockBackend) {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        let consent = ConsentService(http: http, storage: storage, defaultAppId: "app-1")
        let attribution = AttributionService(
            http: http,
            storage: storage,
            consent: consent,
            defaultAppId: "app-1",
            platform: "ios",
            events: events,
            enabled: enabled
        )
        return (attribution, consent, storage, backend)
    }

    private func stubConsentConfig(_ backend: MockBackend) {
        backend.stub("GET", "/api/consent/config", .init(json: """
        {"appId":"app-1","enabled":true,"version":3,
         "geo":{"aware":false,"inTarget":false,"resolvedTags":[]},
         "honorGpc":true,"showDoNotSell":false,"showLimitSensitive":false,
         "nonTargetDefault":"LoadAll","categories":["Analytics"],
         "appearance":null,"bannerText":null,"privacyPolicyUrl":null,"accessibilityUrl":null,"scripts":[]}
        """))
        backend.stub("POST", "/api/consent/record", .init(statusCode: 200))
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

    @Test func captureEmitsAttributionCapturedOncePerRealTouch() async {
        let events = WildwoodEventEmitter()
        let (service, _, _, backend) = makeFullServices(events: events)
        stubConfig(backend)
        await service.initialize()
        var captured: [AttributionTouch] = []
        events.on { event in
            if case .attributionCaptured(let touch) = event { captured.append(touch) }
        }

        service.capture(url: adLink)
        // A direct visit produces no touch, so it produces no event either.
        service.capture(url: URL(string: "cairnfed://dashboard")!)

        #expect(captured.count == 1)
        #expect(captured.first?.source == "reddit")
        #expect(captured.first?.campaign == "govcon-test-sep26")
    }

    @Test func grantingConsentLaterPersistsWithoutAHostCallingConsentDidChange() async throws {
        let (service, consent, storage, backend) = makeFullServices()
        stubConfig(backend, category: "Analytics")
        stubConsentConfig(backend)
        await service.initialize()
        try await consent.initialize()  // undecided: the banner would show
        service.capture(url: adLink)

        // Undecided → the touches are held in memory and nothing is written.
        #expect(storage.getItem(WildwoodStorageKeys.attribution) == nil)
        #expect(service.persisted == false)
        #expect(service.getForRegistration() != nil)

        _ = try await consent.acceptAll()

        // The consent change hook re-ran the persistence gate on its own.
        #expect(service.persisted == true)
        #expect(storage.getItem(WildwoodStorageKeys.attribution) != nil)
    }

    @Test func decliningConsentRemovesTheStoredCopyButKeepsTheTouchesInMemory() async throws {
        let (service, consent, storage, backend) = makeFullServices()
        stubConfig(backend, category: "Analytics")
        stubConsentConfig(backend)
        await service.initialize()
        try await consent.initialize()
        _ = try await consent.acceptAll()
        service.capture(url: adLink)
        #expect(storage.getItem(WildwoodStorageKeys.attribution) != nil)

        _ = try await consent.rejectAll()

        #expect(storage.getItem(WildwoodStorageKeys.attribution) == nil)
        #expect(service.persisted == false)
        // Registration can still report the campaign: only persistence is gated.
        #expect(service.getForRegistration()?.lastTouch?.source == "reddit")
    }

    @Test func theHostKillSwitchCapturesNothingAndFetchesNoConfig() async {
        let (service, _, storage, backend) = makeFullServices(enabled: false)
        stubConfig(backend)

        await service.initialize()

        #expect(service.capture(url: adLink) == nil)
        #expect(service.getForRegistration() == nil)
        #expect(storage.getItem(WildwoodStorageKeys.attribution) == nil)
        // attributionEnabled: false never even asks the server for the app's config.
        #expect(backend.requests().isEmpty)
    }

    @Test func theClientStartsAttributionAndWiresItIntoRegistration() async throws {
        let backend = MockBackend()
        stubConfig(backend)
        backend.stub("POST", "/api/auth/register", .init(json: """
        {"id":"u1","userId":"u1","email":"new@example.com","firstName":"Jane","lastName":"Doe",
         "jwtToken":"jwt-123","refreshToken":"refresh-456","requiresTwoFactor":false,
         "requiresPasswordReset":false,"roles":[],"permissions":[],"requiresDisclaimerAcceptance":false}
        """))
        let client = WildwoodClient(
            config: WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false, storage: .memory),
            urlSession: backend.makeSession()
        )

        // A4: the client starts attribution — the host does not have to.
        await client.initialize()
        #expect(backend.requests().contains { $0.path == "/api/attribution/config" })

        client.attribution.capture(url: adLink)
        _ = try await client.auth.register(
            RegistrationRequest(email: "new@example.com", firstName: "Jane", lastName: "Doe", password: "Passw0rd!", appId: "app-1")
        )

        // A1: the stock registration path carried the touches without the caller attaching them…
        let register = backend.requests().first { $0.path == "/api/auth/register" }
        let sent = String(data: register?.body ?? Data(), encoding: .utf8) ?? ""
        #expect(sent.contains(#""attribution":"#))
        #expect(sent.contains(#""campaign":"govcon-test-sep26""#))
        // …A2: and they were dropped once the signup was recorded.
        #expect(client.attribution.getForRegistration() == nil)
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
