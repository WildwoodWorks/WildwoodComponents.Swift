// Session manager ported from @wildwood/core/src/auth/sessionManager.ts
// (itself a port of WildwoodComponents.Blazor/Services/WildwoodSessionManager.cs).
// Manages session lifecycle: token storage, proactive refresh at 80% of token
// lifetime, sliding expiration, app-resume revalidation, and session expiry.

import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
public final class SessionManager {
    private static let recentRefreshWindow: TimeInterval = 30

    private let config: WildwoodConfig
    private let authService: AuthService
    private let storage: any WildwoodStorageAdapter
    private let events: WildwoodEventEmitter
    private let http: WildwoodHttpClient

    private var currentUser: AuthenticationResponse?
    private var sessionExpiry: Date?
    private var isInitializedFlag = false
    private var disposed = false

    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshInProgress: Task<Bool, Never>?
    @ObservationIgnored private var lastRefreshTime: Date = .distantPast
    @ObservationIgnored private var httpWired = false
    @ObservationIgnored private var foregroundObserver: (any NSObjectProtocol)?

    /// Injectable clock for deterministic tests.
    @ObservationIgnored var now: () -> Date = { Date() }

    public var isAuthenticated: Bool {
        guard let currentUser, !currentUser.jwtToken.isEmpty else { return false }
        return !isSessionExpired()
    }

    public var isInitialized: Bool { isInitializedFlag }

    public var accessToken: String? {
        if isSessionExpired() { return nil }
        return currentUser?.jwtToken.isEmpty == false ? currentUser?.jwtToken : nil
    }

    public var userId: String? {
        if let id = currentUser?.userId, !id.isEmpty { return id }
        if let id = currentUser?.id, !id.isEmpty { return id }
        return nil
    }

    public var userEmail: String? {
        currentUser?.email.isEmpty == false ? currentUser?.email : nil
    }

    public var user: AuthenticationResponse? { currentUser }

    public init(
        config: WildwoodConfig,
        authService: AuthService,
        storage: any WildwoodStorageAdapter,
        events: WildwoodEventEmitter,
        http: WildwoodHttpClient
    ) {
        self.config = config
        self.authService = authService
        self.storage = storage
        self.events = events
        self.http = http

        // Wire up auth service callbacks.
        authService.setAuthChangedHandler { [weak self] response in
            Task { @MainActor in self?.handleAuthChanged(response) }
        }
        authService.setLogoutHandler { [weak self] in
            Task { @MainActor in self?.handleAuthLogout() }
        }

        // Wire up the HTTP client's token provider and reactive 401 refresh
        // as soon as possible; initialize() awaits the same wiring.
        Task { await self.wireHttp() }
    }

    // MARK: - Public API

    public func initialize() async {
        if isInitializedFlag { return }
        await wireHttp()

        defer {
            isInitializedFlag = true
            events.emit(.authChanged(currentUser))
            events.emit(.sessionInitialized(isAuthenticated))
            observeAppForeground()
        }

        // Restore session expiry.
        if let expiryString = storage.getItem(WildwoodStorageKeys.sessionExpiry),
           let expiry = WildwoodJSON.parseDate(expiryString) {
            sessionExpiry = expiry
            if isSessionExpired() {
                clearSessionStorage()
                events.emit(.sessionExpired)
                return
            }
        }

        // Restore auth data.
        if let storedAuth = authService.getStoredUser(), !storedAuth.jwtToken.isEmpty {
            currentUser = storedAuth

            if sessionExpiry == nil {
                extendSession()
            }

            // If auto-refresh is enabled, try to refresh on init.
            if config.enableAutoTokenRefresh {
                let refreshed = await refreshToken()
                if !refreshed {
                    // Token might still be valid — schedule based on current exp.
                    scheduleRefreshFromToken(storedAuth.jwtToken)
                }
            }
        }
    }

    @discardableResult
    public func login(_ authResponse: AuthenticationResponse) -> Bool {
        guard !authResponse.jwtToken.isEmpty else { return false }

        currentUser = authResponse
        sessionExpiry = now().addingTimeInterval(TimeInterval(config.sessionExpirationMinutes) * 60)

        persistAuthData(authResponse)
        persistSessionExpiry()

        if config.enableAutoTokenRefresh {
            scheduleRefreshFromToken(authResponse.jwtToken)
        }

        events.emit(.authChanged(authResponse))
        return true
    }

    public func logout() {
        stopRefreshTimer()
        clearSessionStorage()
    }

    /// Refresh the access token. Always available for reactive use (the HTTP
    /// client's 401 retry and app-resume) regardless of `enableAutoTokenRefresh`,
    /// which only controls the proactive refresh timer — matching the JS SDK,
    /// where an *unset* option still allows reactive refresh.
    public func refreshToken() async -> Bool {
        guard currentUser?.jwtToken.isEmpty == false else { return false }

        // Skip when refreshed recently.
        if now().timeIntervalSince(lastRefreshTime) < Self.recentRefreshWindow { return true }

        // Concurrent refresh protection — reuse the in-flight task.
        if let refreshInProgress {
            return await refreshInProgress.value
        }

        let task = Task { await self.doRefresh() }
        refreshInProgress = task
        defer { refreshInProgress = nil }
        return await task.value
    }

    public func onAppResumed() async {
        guard isInitializedFlag, currentUser != nil else { return }

        if isSessionExpired() {
            stopRefreshTimer()
            clearSessionStorage()
            events.emit(.sessionExpired)
            return
        }

        _ = await refreshToken()
    }

    /// Extend the session under sliding expiration.
    public func touchSession() {
        if isAuthenticated, config.slidingExpiration {
            extendSession()
        }
    }

    public func dispose() {
        guard !disposed else { return }
        disposed = true
        stopRefreshTimer()
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
            self.foregroundObserver = nil
        }
    }

    // MARK: - HTTP wiring

    private func wireHttp() async {
        guard !httpWired else { return }
        httpWired = true
        await http.setTokenProvider { [weak self] in
            await self?.accessToken
        }
        await http.setOn401Refresh { [weak self] in
            await self?.refreshToken() ?? false
        }
    }

    private func observeAppForeground() {
        #if canImport(UIKit)
        guard foregroundObserver == nil else { return }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.onAppResumed() }
        }
        #endif
    }

    // MARK: - Proactive refresh timer

    private func scheduleRefreshFromToken(_ jwtToken: String) {
        let delay = JWTDecoder.refreshDelay(for: jwtToken, now: now())

        if delay <= 0 {
            // Already at or past the refresh point — refresh in 1 second.
            scheduleRefreshTimer(after: 1)
            return
        }

        // Clamp: min 30s, max 55 minutes.
        scheduleRefreshTimer(after: min(max(delay, 30), 55 * 60))
    }

    private func scheduleRefreshTimer(after delay: TimeInterval) {
        stopRefreshTimer()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.handleRefreshTimerElapsed()
        }
    }

    private func stopRefreshTimer() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func handleRefreshTimerElapsed() async {
        guard !disposed, currentUser != nil else { return }

        let refreshed = await refreshToken()
        if !refreshed, !disposed, currentUser != nil {
            // Retry in 60 seconds. On success, handleAuthChanged reschedules.
            scheduleRefreshTimer(after: 60)
        }
    }

    // MARK: - Private helpers

    private func doRefresh() async -> Bool {
        // Double-check after acquiring the in-flight slot.
        if now().timeIntervalSince(lastRefreshTime) < Self.recentRefreshWindow { return true }

        let refreshed = await authService.refreshToken()
        if refreshed {
            lastRefreshTime = now()
        }
        return refreshed
    }

    private func isSessionExpired() -> Bool {
        guard let sessionExpiry else { return false }
        return now() > sessionExpiry
    }

    private func extendSession() {
        sessionExpiry = now().addingTimeInterval(TimeInterval(config.sessionExpirationMinutes) * 60)
        persistSessionExpiry()
    }

    private func persistSessionExpiry() {
        guard let sessionExpiry else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        storage.setItem(WildwoodStorageKeys.sessionExpiry, formatter.string(from: sessionExpiry))
    }

    private func persistAuthData(_ response: AuthenticationResponse) {
        if let data = try? WildwoodJSON.encoder().encode(response),
           let json = String(data: data, encoding: .utf8) {
            storage.setItem(WildwoodStorageKeys.sessionAuth, json)
        }
    }

    private func clearSessionStorage() {
        currentUser = nil
        sessionExpiry = nil
        storage.removeItem(WildwoodStorageKeys.sessionAuth)
        storage.removeItem(WildwoodStorageKeys.sessionExpiry)
    }

    // MARK: - AuthService callbacks

    private func handleAuthChanged(_ authResponse: AuthenticationResponse) {
        guard !authResponse.jwtToken.isEmpty else { return }

        currentUser = authResponse

        if config.slidingExpiration {
            extendSession()
        }

        persistAuthData(authResponse)

        if config.enableAutoTokenRefresh {
            scheduleRefreshFromToken(authResponse.jwtToken)
        }

        events.emit(.tokenRefreshed(authResponse.jwtToken))
    }

    private func handleAuthLogout() {
        stopRefreshTimer()
        currentUser = nil
        sessionExpiry = nil
    }
}
