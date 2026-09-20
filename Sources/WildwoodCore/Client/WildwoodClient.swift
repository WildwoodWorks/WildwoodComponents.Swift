// WildwoodClient — main entry point, mirroring @wildwood/core's createWildwoodClient.
// Constructs all services with shared config, storage, HTTP client, and events.

import Foundation
import Observation

@MainActor
@Observable
public final class WildwoodClient {
    public let config: WildwoodConfig
    @ObservationIgnored public let storage: any WildwoodStorageAdapter
    @ObservationIgnored public let http: WildwoodHttpClient
    @ObservationIgnored public let auth: AuthService
    public let session: SessionManager
    @ObservationIgnored public let ai: AIService
    @ObservationIgnored public let aiFlow: AIFlowService
    /// Per-user scheduled flow-run "standing orders" (list/create/enable/delete +
    /// latest-run sync). Distinct from `aiFlow`, which streams live runs.
    @ObservationIgnored public let aiFlowSubscriptions: AIFlowSubscriptionService
    /// Tenant document store (upload/list/get/text/download/delete).
    @ObservationIgnored public let documents: DocumentService
    @ObservationIgnored public let messaging: MessagingService
    @ObservationIgnored public let payment: PaymentService
    public let notifications: NotificationService
    /// Backend-connected notification inbox + delivery preferences (distinct from
    /// `notifications`, the transient in-memory toast queue).
    @ObservationIgnored public let notificationInbox: NotificationInboxService
    @ObservationIgnored public let twoFactor: TwoFactorService
    @ObservationIgnored public let captcha: CaptchaService
    @ObservationIgnored public let disclaimer: DisclaimerService
    @ObservationIgnored public let appTier: AppTierService
    /// Shared feature-entitlement cache backing FeatureGate — one bulk fetch
    /// per app, invalidated on auth changes and entitlement mutations.
    public let features: FeatureStore
    /// Shared public-catalog cache (what the app sells) — one pair of public
    /// requests per app + currency override, 60-second TTL, failures never cached.
    public let catalog: PublicCatalogStore
    @ObservationIgnored public let feedback: FeedbackService
    @ObservationIgnored public let consent: ConsentService
    /// Campaign Attribution: started by `initialize()`, fed by `.onOpenURL` (the
    /// `.wildwoodClient(_:)` modifier wires both), and attached to every registration
    /// automatically. Observable, so a view can read `first`/`last`/`persisted`.
    public let attribution: AttributionService
    public let theme: ThemeService
    public let events: WildwoodEventEmitter

    public init(config: WildwoodConfig, urlSession: URLSession = .shared) {
        self.config = config
        let events = WildwoodEventEmitter()
        let storage = config.storage.makeAdapter()
        let http = WildwoodHttpClient(config: config, urlSession: urlSession)
        let auth = AuthService(http: http, storage: storage, events: events, defaultAppVersion: config.appVersion)

        self.events = events
        self.storage = storage
        self.http = http
        self.auth = auth
        self.session = SessionManager(config: config, authService: auth, storage: storage, events: events, http: http)
        self.ai = AIService(http: http, appId: config.appId)
        self.aiFlow = AIFlowService(http: http, appId: config.appId)
        self.aiFlowSubscriptions = AIFlowSubscriptionService(http: http, appId: config.appId)
        self.documents = DocumentService(http: http, appId: config.appId)
        self.messaging = MessagingService(http: http, storage: storage)
        self.payment = PaymentService(http: http)
        self.notifications = NotificationService()
        self.notificationInbox = NotificationInboxService(http: http, defaultAppId: config.appId ?? "")
        self.twoFactor = TwoFactorService(http: http)
        self.captcha = CaptchaService()
        self.disclaimer = DisclaimerService(http: http, defaultAppId: config.appId ?? "")
        let appTier = AppTierService(http: http)
        self.appTier = appTier
        self.features = FeatureStore(appTier: appTier, defaultAppId: config.appId, events: events)
        self.catalog = PublicCatalogStore(appTier: appTier, defaultAppId: config.appId)
        self.feedback = FeedbackService(http: http, defaultAppId: config.appId ?? "")
        let consent = ConsentService(http: http, storage: storage, defaultAppId: config.appId ?? "")
        self.consent = consent
        let attribution = AttributionService(
            http: http,
            storage: storage,
            consent: consent,
            defaultAppId: config.appId ?? "",
            platform: config.attributionPlatform ?? AttributionService.defaultPlatform,
            events: events,
            enabled: config.attributionEnabled
        )
        self.attribution = attribution
        self.theme = ThemeService(storage: storage, events: events)

        // Registration paths carry the captured campaign touches and clear them after a recorded
        // signup; a provider sign-in claims them for the new account. Closures rather than a
        // reference: AttributionService is main-actor isolated and AuthService is not, so the hop
        // is explicit (JS: `auth.setAttributionProvider(attribution)`).
        auth.setAttributionProvider(
            AttributionRegistrationSource(
                payload: { await attribution.getForRegistration() },
                clear: { await attribution.clear() }
            )
        )
    }

    /// Restore the persisted session and theme, and start Campaign Attribution (load the app's
    /// attribution config, restore persisted touches). Call once at app launch (the SwiftUI
    /// `wildwoodClient(_:)` modifier does this automatically, and also captures opened URLs).
    ///
    /// Ordering note: consent may not be initialized yet when this runs. That is fine — the
    /// touches stay in memory and the attribution engine's consent subscription re-applies the
    /// persistence gate as soon as `consent.initialize()` (or a decision) reports a state.
    public func initialize() async {
        theme.initialize()
        await session.initialize()
        await attribution.initialize()
    }

    public func dispose() {
        session.dispose()
        attribution.dispose()
        events.removeAllListeners()
    }
}
