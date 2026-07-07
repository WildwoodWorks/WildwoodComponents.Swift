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
    @ObservationIgnored public let messaging: MessagingService
    @ObservationIgnored public let payment: PaymentService
    public let notifications: NotificationService
    @ObservationIgnored public let twoFactor: TwoFactorService
    @ObservationIgnored public let captcha: CaptchaService
    @ObservationIgnored public let disclaimer: DisclaimerService
    @ObservationIgnored public let appTier: AppTierService
    /// Shared feature-entitlement cache backing FeatureGate — one bulk fetch
    /// per app, invalidated on auth changes and entitlement mutations.
    public let features: FeatureStore
    @ObservationIgnored public let feedback: FeedbackService
    @ObservationIgnored public let consent: ConsentService
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
        self.messaging = MessagingService(http: http, storage: storage)
        self.payment = PaymentService(http: http)
        self.notifications = NotificationService()
        self.twoFactor = TwoFactorService(http: http)
        self.captcha = CaptchaService()
        self.disclaimer = DisclaimerService(http: http, defaultAppId: config.appId ?? "")
        let appTier = AppTierService(http: http)
        self.appTier = appTier
        self.features = FeatureStore(appTier: appTier, defaultAppId: config.appId, events: events)
        self.feedback = FeedbackService(http: http, defaultAppId: config.appId ?? "")
        self.consent = ConsentService(http: http, storage: storage, defaultAppId: config.appId ?? "")
        self.theme = ThemeService(storage: storage, events: events)
    }

    /// Restore the persisted session and theme. Call once at app launch
    /// (the SwiftUI `wildwoodClient(_:)` modifier does this automatically).
    public func initialize() async {
        theme.initialize()
        await session.initialize()
    }

    public func dispose() {
        session.dispose()
        events.removeAllListeners()
    }
}
