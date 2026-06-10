// Client configuration mirroring @wildwood/core's WildwoodConfig.

import Foundation

public struct WildwoodConfig: Sendable {
    /// Base URL for the WildwoodAPI server (e.g. `https://api.wildwoodworks.io/`).
    public var baseUrl: String
    /// Optional API key for server-to-server authentication (sent as `X-API-Key`).
    public var apiKey: String?
    /// Application identifier.
    public var appId: String?
    /// Application version sent with auth requests. Default "1.0.0".
    public var appVersion: String
    /// Show detailed error messages (default true).
    public var enableDetailedErrors: Bool
    /// HTTP request timeout in seconds (default 30).
    public var requestTimeoutSeconds: TimeInterval
    /// Enable automatic retry on 5xx/network failure (default true).
    public var enableRetry: Bool
    /// Maximum attempts including the first (default 3).
    public var maxRetryAttempts: Int
    /// Session expiration in minutes (default 60).
    public var sessionExpirationMinutes: Int
    /// Automatically refresh the JWT before expiry (default false).
    public var enableAutoTokenRefresh: Bool
    /// Extend the session on activity (default true).
    public var slidingExpiration: Bool
    /// Storage backing (default `.composite`: tokens in Keychain, rest in UserDefaults).
    public var storage: WildwoodStorageOption

    public init(
        baseUrl: String,
        apiKey: String? = nil,
        appId: String? = nil,
        appVersion: String = "1.0.0",
        enableDetailedErrors: Bool = true,
        requestTimeoutSeconds: TimeInterval = 30,
        enableRetry: Bool = true,
        maxRetryAttempts: Int = 3,
        sessionExpirationMinutes: Int = 60,
        enableAutoTokenRefresh: Bool = false,
        slidingExpiration: Bool = true,
        storage: WildwoodStorageOption = .composite
    ) {
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.appId = appId
        self.appVersion = appVersion
        self.enableDetailedErrors = enableDetailedErrors
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.enableRetry = enableRetry
        self.maxRetryAttempts = maxRetryAttempts
        self.sessionExpirationMinutes = sessionExpirationMinutes
        self.enableAutoTokenRefresh = enableAutoTokenRefresh
        self.slidingExpiration = slidingExpiration
        self.storage = storage
    }

    public init(baseURL: URL, appId: String? = nil) {
        self.init(baseUrl: baseURL.absoluteString, appId: appId)
    }
}
