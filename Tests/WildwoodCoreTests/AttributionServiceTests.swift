import Foundation
import Synchronization
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

    // MARK: - Funnel tracking

    private func stubFunnelConfig(
        _ backend: MockBackend,
        funnel: Bool = true,
        signupSteps: Bool = true,
        customEventNames: [String] = [],
        category: String = "StrictlyNecessary"
    ) {
        let names = customEventNames.map { "\"\($0)\"" }.joined(separator: ",")
        backend.stub("GET", "/api/attribution/config", .init(json: """
        {"appId":"app-1","isEnabled":true,"captureFirstTouch":true,"captureLastTouch":true,
         "attributionWindowDays":30,"persistenceConsentCategory":"\(category)","captureClickIds":true,
         "captureReferrer":true,"extraAllowedParamNames":[],"beaconEnabled":false,
         "funnelTrackingEnabled":\(funnel),"trackScrollDepth":false,"trackEngagement":false,
         "autoTrackCtaClicks":false,"trackSignupSteps":\(signupSteps),
         "customEventNames":[\(names)],"sessionStoragePersistenceBeforeConsent":false}
        """))
        backend.stub("POST", "/api/attribution/events", .init(statusCode: 202))
    }

    /// The events requests sent so far, decoded.
    private func eventBatches(_ backend: MockBackend) -> [[String: Any]] {
        backend.requests()
            .filter { $0.method == "POST" && $0.path == "/api/attribution/events" }
            .compactMap { request in
                guard let body = request.body else { return nil }
                return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            }
    }

    private func sentEvents(_ backend: MockBackend) -> [[String: Any]] {
        eventBatches(backend).flatMap { ($0["events"] as? [[String: Any]]) ?? [] }
    }

    private func sentNames(_ backend: MockBackend) -> [String] {
        sentEvents(backend).compactMap { $0["name"] as? String }
    }

    @Test func funnelTrackingOffSendsNothing() async {
        let (service, _, backend) = makeServices()
        stubFunnelConfig(backend, funnel: false)
        await service.initialize()

        service.trackScreen("pricing")
        service.track("cta_click", label: "hero")
        await service.flush()

        #expect(eventBatches(backend).isEmpty)
        #expect(service.queuedEventCount == 0)
        #expect(service.isFlushScheduled == false)
    }

    @Test func callsBeforeTheConfigLoadsAreBufferedAndReplayed() async {
        let (service, _, backend) = makeServices()
        stubFunnelConfig(backend)

        service.trackScreen("pricing")
        service.track("cta_click", label: "hero")
        await service.initialize()
        await service.flush()

        let events = sentEvents(backend)
        #expect(events.map { $0["name"] as? String } == ["page_view", "cta_click"])
        #expect(events.first?["path"] as? String == "/pricing")
        // Later events carry the current screen.
        #expect(events.last?["path"] as? String == "/pricing")
        #expect(events.last?["label"] as? String == "hero")
        #expect(events.first?["clientTimestamp"] is String)
    }

    @Test func anExplicitPathNamesTheEventsPage() async {
        // @wildwood/core's track(name, { path }): the event carries the named page, and a page_view
        // naming its page is a navigation that later events inherit.
        let (service, _, backend) = makeServices()
        stubFunnelConfig(backend)
        await service.initialize()

        service.trackScreen("home")
        service.track("cta_click", label: "hero", path: "pricing?plan=pro#top")
        service.track("cta_click", label: "footer")
        service.track("page_view", path: "/checkout")
        service.track("cta_click", label: "pay")
        await service.flush()

        let events = sentEvents(backend)
        #expect(events.map { $0["name"] as? String } == ["page_view", "cta_click", "cta_click", "page_view", "cta_click"])
        #expect(events.map { $0["path"] as? String } == ["/home", "/pricing", "/home", "/checkout", "/checkout"])
    }

    @Test func theEventsRequestCarriesTheVisitorAndSession() async throws {
        let (service, _, backend) = makeServices()
        stubFunnelConfig(backend)
        service.deviceClassProvider = { "tablet" }
        await service.initialize()

        service.track("cta_click", label: "hero")
        await service.flush()

        let batch = try #require(eventBatches(backend).first)
        #expect(batch["appId"] as? String == "app-1")
        #expect(batch["visitorKey"] as? String == service.visitorKey)
        #expect(batch["sessionKey"] as? String == service.sessionKey)
        #expect(batch["isReturning"] as? Bool == false)
        #expect(batch["deviceClass"] as? String == "tablet")
        #expect(batch["platform"] as? String == "ios")
        // A direct visit sends the touch as an explicit null.
        #expect(batch["touch"] is NSNull)
        let request = try #require(backend.requests().first { $0.path == "/api/attribution/events" })
        #expect(request.query?.contains("appId=app-1") == true)
    }

    @Test func eventsGoOutInBatchesOfAtMost25() async {
        let (service, _, backend) = makeServices()
        stubFunnelConfig(backend)
        service.flushInterval = .seconds(60)
        await service.initialize()

        for index in 0..<30 {
            service.track("cta_click", label: "cta_\(index)")
        }
        await service.flush()
        await waitForCondition { sentEvents(backend).count == 30 }

        let sizes = eventBatches(backend).map { (($0["events"] as? [Any]) ?? []).count }
        #expect(sizes.reduce(0, +) == 30)
        #expect(sizes.allSatisfy { $0 <= 25 })
        #expect(sizes.count >= 2)
    }

    @Test func aQueuedEventIsFlushedAfterTheInterval() async {
        let (service, _, backend) = makeServices()
        stubFunnelConfig(backend)
        service.flushInterval = .milliseconds(20)
        await service.initialize()

        service.track("cta_click", label: "hero")
        #expect(service.isFlushScheduled == true)
        await waitForCondition { !eventBatches(backend).isEmpty }

        #expect(sentNames(backend) == ["cta_click"])
        #expect(service.isFlushScheduled == false)
    }

    @Test func disposeCancelsTheTimedFlushAndSendsTheQueue() async {
        let (service, _, backend) = makeServices()
        stubFunnelConfig(backend)
        service.flushInterval = .seconds(60)
        await service.initialize()
        service.track("cta_click", label: "hero")
        #expect(service.isFlushScheduled == true)

        service.dispose()

        #expect(service.isFlushScheduled == false)
        #expect(service.queuedEventCount == 0)
        await waitForCondition { !eventBatches(backend).isEmpty }
        #expect(sentNames(backend) == ["cta_click"])
    }

    @Test func thirtyMinutesOfInactivityStartsANewSession() async {
        let clock = FunnelClock(Date(timeIntervalSince1970: 1_800_000_000))
        let (service, _, backend) = makeServices()
        stubFunnelConfig(backend)
        service.clock = { clock.now }
        await service.initialize()
        let firstKey = service.sessionKey

        service.track("cta_click", label: "a")
        clock.advance(29 * 60)
        service.track("cta_click", label: "b")
        #expect(service.sessionKey == firstKey)
        clock.advance(31 * 60)
        service.track("cta_click", label: "c")
        await service.flush()

        #expect(service.sessionKey != firstKey)
        #expect(service.sessionCount == 2)
        let batches = eventBatches(backend)
        #expect(batches.count == 2)
        #expect(batches.first?["sessionKey"] as? String == firstKey)
        #expect(batches.last?["sessionKey"] as? String == service.sessionKey)
    }

    @Test func aStoredVisitorOnANewSessionIsReturning() async {
        let storage = MemoryStorage()
        storage.setItem(WildwoodStorageKeys.attribution, """
        {"v":1,"visitorKey":"stored-visitor-0001","first":null,"last":null,"updatedAt":"",
         "sessionKey":"stored-session-0001","lastActivityAt":1000,"sessionCount":1}
        """)
        let (service, _, backend) = makeServices(storage: storage)
        stubFunnelConfig(backend)

        await service.initialize()

        #expect(service.visitorKey == "stored-visitor-0001")
        #expect(service.isReturning == true)
        #expect(service.sessionCount == 2)
        #expect(service.sessionKey != "stored-session-0001")
    }

    @Test func aStoredSessionStillActiveContinues() async {
        let clock = FunnelClock(Date(timeIntervalSince1970: 1_800_000_000))
        let storage = MemoryStorage()
        let lastActivity = (clock.now.timeIntervalSince1970 - 60) * 1000
        storage.setItem(WildwoodStorageKeys.attribution, """
        {"v":1,"visitorKey":"stored-visitor-0001","first":null,"last":null,"updatedAt":"",
         "sessionKey":"stored-session-0001","lastActivityAt":\(lastActivity),"sessionCount":4}
        """)
        let (service, _, backend) = makeServices(storage: storage)
        stubFunnelConfig(backend)
        service.clock = { clock.now }

        await service.initialize()

        #expect(service.sessionKey == "stored-session-0001")
        #expect(service.sessionCount == 4)
        #expect(service.isReturning == true)
    }

    @Test func aFirstVisitIsNotReturning() async {
        let (service, _, backend) = makeServices()
        stubFunnelConfig(backend)

        await service.initialize()

        #expect(service.isReturning == false)
        #expect(service.sessionCount == 1)
    }

    @Test func theSessionIsStoredOnlyWherePersistenceIsAllowed() async throws {
        let (allowed, allowedStorage, allowedBackend) = makeServices()
        stubFunnelConfig(allowedBackend, category: "StrictlyNecessary")
        await allowed.initialize()
        allowed.track("cta_click", label: "hero")
        await allowed.flush()

        let raw = try #require(allowedStorage.getItem(WildwoodStorageKeys.attribution))
        #expect(raw.contains(#""sessionKey":"\#(allowed.sessionKey ?? "")""#))
        #expect(raw.contains(#""sessionCount":1"#))

        let (gated, gatedStorage, gatedBackend) = makeServices()
        stubFunnelConfig(gatedBackend, category: "Analytics")
        await gated.initialize()
        gated.track("cta_click", label: "hero")
        await gated.flush()

        // No consent yet: the session lives in memory only.
        #expect(gatedStorage.getItem(WildwoodStorageKeys.attribution) == nil)
        #expect(gated.sessionKey != nil)
    }

    @Test func oneShotStepsGoOutOncePerSessionAndLabel() async {
        let (service, _, backend) = makeServices()
        stubFunnelConfig(backend)
        await service.initialize()

        service.track("signup_view")
        service.track("signup_view")
        service.track("plan_selected", label: "tier-a")
        service.track("plan_selected", label: "tier-a")
        service.track("plan_selected", label: "tier-b")
        service.track("cta_click", label: "hero")
        service.track("cta_click", label: "hero")
        await service.flush()

        #expect(sentNames(backend) == ["signup_view", "plan_selected", "plan_selected", "cta_click", "cta_click"])
    }

    @Test func signupStepsNeedTheirSwitchButPlanAndCheckoutDoNot() async {
        let (service, _, backend) = makeServices()
        stubFunnelConfig(backend, signupSteps: false)
        await service.initialize()

        service.track("signup_view")
        service.track("signup_start")
        service.track("signup_submit")
        service.track("signup_error", label: "validation")
        service.track("plan_selected", label: "tier-a")
        service.track("checkout_start", label: "price-a")
        await service.flush()

        // The JS gate: "Track signup steps" covers view/start/submit/error only.
        #expect(sentNames(backend) == ["plan_selected", "checkout_start"])
    }

    @Test func customNamesServerOnlyNamesAndMalformedNames() async {
        let (service, _, backend) = makeServices()
        stubFunnelConfig(backend, customEventNames: ["demo_booked", "purchase", "Bad-Name"])
        await service.initialize()

        service.track("demo_booked", label: "pricing", value: 1)
        service.track("webinar_joined")
        service.track("purchase")
        service.track("signup_complete")
        service.track("Bad-Name")
        await service.flush()

        #expect(sentNames(backend) == ["demo_booked"])
        #expect(sentEvents(backend).first?["value"] as? Double == 1)
        #expect(service.config?.customEventNames == ["demo_booked"])
    }

    @Test func aCtaClickNeedsALabelAndSignupErrorsCarryACategory() async {
        let (service, _, backend) = makeServices()
        stubFunnelConfig(backend)
        await service.initialize()

        service.track("cta_click")
        service.track("cta_click", label: "   ")
        service.track("signup_error", label: "Email Taken!")
        service.track("signup_error")
        await service.flush()

        let events = sentEvents(backend)
        #expect(events.map { $0["name"] as? String } == ["signup_error", "signup_error"])
        #expect(events.map { $0["label"] as? String } == ["email_taken", "unknown"])
    }

    @Test func trackScreenRecordsAPageViewAndIgnoresARepeat() async {
        let (service, _, backend) = makeServices()
        stubFunnelConfig(backend)
        await service.initialize()

        service.trackScreen("pricing")
        service.trackScreen("pricing")
        service.trackScreen("/signup?ref=x")
        service.trackScreen("pricing")
        service.trackScreen("   ")
        await service.flush()

        let events = sentEvents(backend)
        #expect(events.map { $0["name"] as? String } == ["page_view", "page_view", "page_view"])
        #expect(events.map { $0["path"] as? String } == ["/pricing", "/signup", "/pricing"])
    }

    @Test func captureRecordsAPageViewForTheUrlPath() async {
        let (service, _, backend) = makeServices()
        stubFunnelConfig(backend)
        await service.initialize()

        service.capture(url: URL(string: "https://cairnfed.ai/pricing?utm_source=reddit&utm_medium=paid")!)
        service.capture(url: URL(string: "https://cairnfed.ai/pricing")!)
        await service.flush()

        let events = sentEvents(backend)
        #expect(events.map { $0["path"] as? String } == ["/pricing"])
        // The batch carries the visitor's last touch.
        let touch = eventBatches(backend).first?["touch"] as? [String: Any]
        #expect(touch?["source"] as? String == "reddit")
    }

    @Test func registrationCarriesTheSessionKeyDeviceClassAndCount() async throws {
        let (service, _, backend) = makeServices()
        stubFunnelConfig(backend)
        service.deviceClassProvider = { "tablet" }
        await service.initialize()
        service.capture(url: adLink)

        let payload = try #require(service.getForRegistration())

        #expect(payload.sessionKey == service.sessionKey)
        #expect(payload.sessionKey != nil)
        #expect(payload.deviceClass == "tablet")
        #expect(payload.sessionCount == 1)
    }

    @Test func theKillSwitchTracksNothing() async {
        let (service, _, _, backend) = makeFullServices(enabled: false)
        stubFunnelConfig(backend)
        await service.initialize()

        service.track("cta_click", label: "hero")
        service.trackScreen("pricing")
        await service.flush()

        #expect(backend.requests().isEmpty)
        #expect(service.queuedEventCount == 0)
    }
}

/// A movable clock for the funnel session tests (the service's `clock` seam), in a Sendable box.
private final class FunnelClock: Sendable {
    private let state: Mutex<Date>

    init(_ start: Date) {
        state = Mutex(start)
    }

    var now: Date { state.withLock { $0 } }

    func advance(_ interval: TimeInterval) {
        state.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}

/// Polls until the condition holds or the timeout passes (the flushes run on their own tasks).
@MainActor
private func waitForCondition(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

struct AttributionFunnelRulesTests {
    @Test func signupErrorCategoriesComeFromCodesThenStatus() {
        #expect(SignupFunnelRules.errorCategory(code: "USERNAME_EXISTS") == "username_taken")
        #expect(SignupFunnelRules.errorCategory(code: "UsernameExists") == "username_taken")
        #expect(SignupFunnelRules.errorCategory(code: "DuplicateEmail") == "email_taken")
        #expect(SignupFunnelRules.errorCategory(code: "PASSWORD_TOO_SHORT") == "password_policy")
        #expect(SignupFunnelRules.errorCategory(code: "InvalidCaptcha") == "captcha")
        #expect(SignupFunnelRules.errorCategory(code: "registration_token_rejected") == "invalid_token")
        #expect(SignupFunnelRules.errorCategory(code: "TOKEN_EXPIRED") == "invalid_token")
        #expect(SignupFunnelRules.errorCategory(code: "OpenRegistrationNotAllowed") == "registration_closed")
        #expect(SignupFunnelRules.errorCategory(code: "RateLimited") == "rate_limited")
        #expect(SignupFunnelRules.errorCategory(code: "NetworkError") == "network")
        #expect(SignupFunnelRules.errorCategory(code: "something_else") == "unknown")
        #expect(SignupFunnelRules.errorCategory(code: nil, status: 0) == "network")
        #expect(SignupFunnelRules.errorCategory(code: nil, status: 429) == "rate_limited")
        #expect(SignupFunnelRules.errorCategory(code: nil, status: 503) == "server")
        #expect(SignupFunnelRules.errorCategory(code: "", status: 422) == "validation")
        #expect(SignupFunnelRules.errorCategory(code: nil, status: 404) == "unknown")
    }

    @Test func aWildwoodErrorPrefersTheServersOwnErrorCode() {
        let body = Data(#"{"message":"Email already in use","errorCode":"EMAIL_EXISTS"}"#.utf8)
        let refused = WildwoodError.fromResponse(status: 400, body: body, fallbackMessage: "")
        #expect(SignupFunnelRules.errorCategory(for: refused) == "email_taken")

        let noCode = WildwoodError(message: "Oops", status: 500)
        #expect(SignupFunnelRules.errorCategory(for: noCode) == "server")

        let offline = WildwoodError(message: "Offline", status: 0)
        #expect(SignupFunnelRules.errorCategory(for: offline) == "network")

        #expect(SignupFunnelRules.errorCategory(for: URLError(.notConnectedToInternet)) == "network")
        #expect(SignupFunnelRules.errorCategories.count == 11)
    }

    @Test func planKeysPreferTheIdThenASlugOfTheName() {
        #expect(SignupFunnelRules.planKey(id: " tier-1 ") == "tier-1")
        #expect(SignupFunnelRules.planKey(id: nil, name: "Pro Plan (Annual)") == "pro_plan_annual")
        #expect(SignupFunnelRules.planKey(id: "", name: "!!!") == nil)
        #expect(SignupFunnelRules.planKey(id: nil) == nil)
    }

    @Test func eventNamesFollowTheServerShape() {
        #expect(AttributionRules.isFunnelEventName("demo_booked"))
        #expect(AttributionRules.isFunnelEventName("a1_b2"))
        #expect(!AttributionRules.isFunnelEventName(""))
        #expect(!AttributionRules.isFunnelEventName("Demo"))
        #expect(!AttributionRules.isFunnelEventName("demo-booked"))
        #expect(!AttributionRules.isFunnelEventName(String(repeating: "a", count: 41)))
        #expect(AttributionRules.isFunnelEventName(String(repeating: "a", count: 40)))
        #expect(
            AttributionRules.normalizeCustomEventNames([" Demo_Booked ", "page_view", "purchase", "demo_booked", "x-y"])
                == ["demo_booked"]
        )
    }

    @Test func signupErrorLabelsAndScreenPathsAreReduced() {
        #expect(AttributionRules.signupErrorLabel("Email Taken!") == "email_taken")
        #expect(AttributionRules.signupErrorLabel("__server__") == "server")
        #expect(AttributionRules.signupErrorLabel(nil) == "unknown")
        #expect(AttributionRules.signupErrorLabel(String(repeating: "a", count: 50)).count == 40)

        #expect(AttributionRules.funnelPath("pricing") == "/pricing")
        #expect(AttributionRules.funnelPath("/signup?ref=x#top") == "/signup")
        #expect(AttributionRules.funnelPath("  ") == nil)
        #expect(AttributionRules.funnelPath("?only=query") == nil)
    }

    @MainActor
    @Test func deviceClassFollowsTheIdiom() {
        #if canImport(UIKit)
        #expect(AttributionRules.deviceClass(for: .phone) == "mobile")
        #expect(AttributionRules.deviceClass(for: .pad) == "tablet")
        #expect(AttributionRules.deviceClass(for: .mac) == "desktop")
        #else
        #expect(AttributionRules.currentDeviceClass() == "desktop")
        #endif
    }

    @Test func theConfigKeepsFunnelTrackingOffWhileAttributionIsOff() throws {
        let json = Data(#"{"appId":"app-1","isEnabled":false,"funnelTrackingEnabled":true}"#.utf8)
        let raw = try JSONDecoder().decode(PublicAttributionConfig.self, from: json)
        let config = AttributionRules.normalized(raw, fallbackAppId: "app-1")
        #expect(config.funnelTrackingEnabled == false)

        let bare = try JSONDecoder().decode(PublicAttributionConfig.self, from: Data(#"{"isEnabled":true}"#.utf8))
        #expect(bare.funnelTrackingEnabled == false)
        #expect(bare.trackSignupSteps == false)
        #expect(bare.customEventNames.isEmpty)
    }
}
