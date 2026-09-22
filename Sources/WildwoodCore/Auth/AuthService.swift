// Authentication service ported from @wildwood/core/src/auth/authService.ts
// (itself a port of WildwoodComponents.Blazor/Services/AuthenticationService.cs).
// Handles login, registration, password reset, passkeys, 2FA, and provider configuration.

import Foundation
import Synchronization

public final class AuthService: Sendable {
    private let http: WildwoodHttpClient
    private let storage: any WildwoodStorageAdapter
    private let events: WildwoodEventEmitter
    private let defaultAppVersion: String

    private struct Callbacks: Sendable {
        var onAuthChanged: (@Sendable (AuthenticationResponse) -> Void)?
        var onLogout: (@Sendable () -> Void)?
    }

    private let callbacks = Mutex(Callbacks())

    /// How long a queued attribution claim stays valid, matching `@wildwood/core`'s
    /// `ATTRIBUTION_CLAIM_WINDOW_MS` and the server's window: WildwoodAPI refuses a claim for an
    /// account created longer ago than this.
    private static let attributionClaimWindow: TimeInterval = 15 * 60

    /// The claim waiting for a signed-in session, with the moment it was queued.
    private struct QueuedAttributionClaim: Sendable {
        var appId: String
        var queuedAt: Date
    }

    private struct AttributionWiring: Sendable {
        var source: AttributionRegistrationSource?
        var queuedClaim: QueuedAttributionClaim?
        /// Injectable clock for deterministic tests (mirrors `SessionManager.now`).
        var now: @Sendable () -> Date = { Date() }
    }

    private let attributionWiring = Mutex(AttributionWiring())

    public init(
        http: WildwoodHttpClient,
        storage: any WildwoodStorageAdapter,
        events: WildwoodEventEmitter,
        defaultAppVersion: String = "1.0.0"
    ) {
        self.http = http
        self.storage = storage
        self.events = events
        self.defaultAppVersion = defaultAppVersion
    }

    /// Register a callback for auth state changes (used by SessionManager).
    public func setAuthChangedHandler(_ handler: @escaping @Sendable (AuthenticationResponse) -> Void) {
        callbacks.withLock { $0.onAuthChanged = handler }
    }

    /// Register a callback for logout (used by SessionManager).
    public func setLogoutHandler(_ handler: @escaping @Sendable () -> Void) {
        callbacks.withLock { $0.onLogout = handler }
    }

    // MARK: - Campaign Attribution

    /// Wire the Campaign Attribution engine (`client.attribution`). Every registration path then
    /// carries the captured touches automatically and clears them after a recorded signup, and a
    /// provider sign-in claims them for the new account. `WildwoodClient` does this for you.
    public func setAttributionProvider(_ source: AttributionRegistrationSource?) {
        attributionWiring.withLock { $0.source = source }
    }

    /// Test seam: the clock the 15-minute claim window is measured against.
    func setAttributionClock(_ clock: @escaping @Sendable () -> Date) {
        attributionWiring.withLock { $0.now = clock }
    }

    /// The caller's payload when there is one, otherwise the engine's captured payload. Mirrors
    /// `@wildwood/core`'s `resolveAttribution`: an explicit value always wins, so a component that
    /// attaches the payload itself is not double-resolved. (JS distinguishes `undefined` from
    /// `null`; Swift has one `nil`, so "send none" is expressed by leaving attribution unwired or
    /// clearing it — same choice the .NET SDK made.)
    private func resolveAttribution(_ explicit: AttributionPayload?) async -> AttributionPayload? {
        if let explicit { return explicit }
        guard let source = attributionWiring.withLock({ $0.source }) else { return nil }
        return await source.payload()
    }

    /// Drops the captured touches after a recorded signup, so a second signup on this device does
    /// not reuse them. Best-effort: attribution is measurement and must never cost a signup.
    private func clearAttribution() async {
        guard let source = attributionWiring.withLock({ $0.source }) else { return }
        await source.clear()
    }

    /// Claims the captured campaign touches for the signed-in user's just-created account
    /// (`POST api/attribution/claim?appId=`), for provider signups that have no registration
    /// request to carry them. Never throws: returns nil when nothing was sent or the request
    /// failed, and clears the local touches after any successful response, since the server has
    /// then decided either way.
    @discardableResult
    public func claimAttribution(appId: String) async -> AttributionClaimResponse? {
        guard !appId.isEmpty else { return nil }
        guard let payload = await resolveAttribution(nil) else { return nil }

        let body = AttributionClaimRequest(appId: appId, payload: payload)
        do {
            // appId rides in the query string too: the server's rate-limit partition reads it, and
            // it must match the body.
            let data: AttributionClaimResponse = try await http.post(
                "api/attribution/claim?appId=\(WildwoodURL.queryComponent(appId))",
                body: body
            )
            await clearAttribution()
            return data
        } catch {
            return nil
        }
    }

    /// Queues a campaign-attribution claim for the next auth change that carries a token, i.e.
    /// once a session is signed in. Provider sign-ins use it because two-factor, a forced password
    /// reset or pending disclaimers can defer the session, and a claim sent before the session
    /// exists would 401. A sign-out drops the queued claim, and it lapses after the server's
    /// claim window.
    public func queueAttributionClaim(appId: String) {
        attributionWiring.withLock {
            $0.queuedClaim = appId.isEmpty ? nil : QueuedAttributionClaim(appId: appId, queuedAt: $0.now())
        }
    }

    /// Announces an auth change and then sends a queued attribution claim if the change carries a
    /// session — the Swift stand-in for the `authChanged` subscription `@wildwood/core` uses.
    private func emitAuthChanged(_ response: AuthenticationResponse?) async {
        await events.emit(.authChanged(response))
        await sendQueuedAttributionClaim(response)
    }

    private func sendQueuedAttributionClaim(_ response: AuthenticationResponse?) async {
        // A token-less response (two-factor still pending, or a registration that returned no
        // tokens) is not a signed-in session yet: keep the claim queued.
        if let response, response.jwtToken.isEmpty { return }

        // Claimed at most once per queue, whatever happens below.
        let queued = attributionWiring.withLock { wiring -> QueuedAttributionClaim? in
            let pending = wiring.queuedClaim
            wiring.queuedClaim = nil
            return pending
        }
        // A sign-out (nil response) drops the claim without sending it.
        guard let queued, let response, !response.jwtToken.isEmpty else { return }
        // A stale claim lapses with the server's claim window.
        let elapsed = attributionWiring.withLock { $0.now() }.timeIntervalSince(queued.queuedAt)
        guard elapsed <= Self.attributionClaimWindow else { return }

        await claimAttribution(appId: queued.appId)
    }

    // MARK: - Login

    public func login(_ request: LoginRequest) async throws -> AuthenticationResponse {
        struct LoginDto: Encodable {
            let Username: String
            let Email: String?
            let Password: String?
            let AppId: String?
            let Platform: String?
            let DeviceInfo: String?
            let ProviderName: String?
            let ProviderToken: String?
            let TrustedDeviceToken: String?
            let CaptchaResponse: String?
            let AppVersion: String
        }

        let dto = LoginDto(
            Username: request.username,
            Email: request.email,
            Password: request.password,
            AppId: request.appId,
            Platform: request.platform,
            DeviceInfo: request.deviceInfo,
            ProviderName: request.providerName,
            ProviderToken: request.providerToken,
            TrustedDeviceToken: request.trustedDeviceToken,
            CaptchaResponse: request.captchaResponse,
            AppVersion: request.appVersion ?? defaultAppVersion
        )

        let data: AuthenticationResponse = try await http.post("api/auth/login", body: dto, skipAuth: true)

        // A provider sign-in may have just created the account, and a provider signup has no
        // registration request to carry the campaign touches. Queue a claim: it goes out on the
        // next signed-in auth change — the one below, or the one two-factor verification makes.
        if let providerToken = request.providerToken, !providerToken.isEmpty,
           let appId = request.appId, !appId.isEmpty {
            queueAttributionClaim(appId: appId)
        }

        // If 2FA is required, return without storing auth.
        if data.requiresTwoFactor {
            return data
        }

        storeAuthentication(data)
        notifyAuthChanged(data)
        await emitAuthChanged(data)
        return data
    }

    // MARK: - Registration

    public func register(_ request: RegistrationRequest) async throws -> AuthenticationResponse {
        var dto = request
        dto.confirmPassword = request.confirmPassword ?? request.password
        // Every registration path carries the captured campaign touches unless the caller supplied
        // a payload of its own (JS: `resolveAttribution`).
        dto.attribution = await resolveAttribution(request.attribution)

        let data: AuthenticationResponse = try await http.post("api/auth/register", body: dto, skipAuth: true)

        if !data.jwtToken.isEmpty {
            storeAuthentication(data)
            notifyAuthChanged(data)
            await emitAuthChanged(data)
            // Recorded with the account: a second signup on this device must not reuse the touches.
            await clearAttribution()
        }
        return data
    }

    /// Register with a registration token. The backend may return either an
    /// AuthenticationResponse (with tokens) or a token-less RegistrationResponseDto;
    /// a token-less success is normalized into an AuthenticationResponse with an empty
    /// `jwtToken` — callers must log in with credentials afterwards.
    public func registerWithToken(_ request: RegistrationRequest) async throws -> AuthenticationResponse {
        struct TokenRegistrationDto: Encodable {
            let Token: String?
            let Username: String?
            let Email: String
            let Password: String?
            let FirstName: String
            let LastName: String
            let AppId: String
            let Platform: String?
            let DeviceInfo: String?
            let Attribution: AttributionPayload?
        }

        let attribution = await resolveAttribution(request.attribution)
        let dto = TokenRegistrationDto(
            Token: request.registrationToken,
            Username: request.username ?? request.email,
            Email: request.email,
            Password: request.password,
            FirstName: request.firstName,
            LastName: request.lastName,
            AppId: request.appId,
            Platform: request.platform,
            DeviceInfo: request.deviceInfo,
            Attribution: attribution
        )

        let raw = try await http.postData("api/userregistration/register-with-token", body: dto, skipAuth: true)
        let data = (try? WildwoodJSON.decoder().decode(AuthenticationResponse.self, from: raw)) ?? AuthenticationResponse()

        if !data.jwtToken.isEmpty {
            storeAuthentication(data)
            notifyAuthChanged(data)
            await emitAuthChanged(data)
            await clearAttribution()
            return data
        }

        // RegistrationResponseDto shape — no tokens.
        struct RegistrationOutcome: Decodable {
            var success: Bool?
            var message: String?
            var userId: String?
        }
        let outcome = (try? WildwoodJSON.decoder().decode(RegistrationOutcome.self, from: raw)) ?? RegistrationOutcome()

        if outcome.success == false {
            throw WildwoodError(message: outcome.message ?? "Registration failed.", status: 0, code: .validationError)
        }
        // A token-less success is still a recorded signup: the server took the payload.
        await clearAttribution()

        return AuthenticationResponse(
            id: outcome.userId ?? "",
            userId: outcome.userId ?? "",
            firstName: request.firstName,
            lastName: request.lastName,
            email: request.email
        )
    }

    /// Open registration (AllowOpenRegistration flow). Does NOT return tokens —
    /// call `login` with the same credentials afterwards.
    public func registerOpen(_ request: RegistrationRequest, pricingModelId: String? = nil) async throws -> OpenRegistrationResult {
        struct OpenRegistrationDto: Encodable {
            let Username: String?
            let Email: String
            let Password: String?
            let FirstName: String
            let LastName: String
            let AppId: String
            let Platform: String?
            let DeviceInfo: String?
            let PricingModelId: String?
            let Attribution: AttributionPayload?
        }

        let attribution = await resolveAttribution(request.attribution)
        let dto = OpenRegistrationDto(
            Username: request.username ?? request.email,
            Email: request.email,
            Password: request.password,
            FirstName: request.firstName,
            LastName: request.lastName,
            AppId: request.appId,
            Platform: request.platform,
            DeviceInfo: request.deviceInfo,
            PricingModelId: pricingModelId,
            Attribution: attribution
        )

        let result: OpenRegistrationResult = try await http.post("api/userregistration/register", body: dto, skipAuth: true)
        if result.success {
            await clearAttribution()
        }
        return result
    }

    public func validateRegistration(_ request: ValidateRegistrationRequest) async throws -> ValidateRegistrationResponse {
        struct ValidateDto: Encodable {
            let Username: String?
            let Email: String
            let Password: String
            let Token: String?
            let AppId: String
        }

        let dto = ValidateDto(
            Username: request.username ?? request.email,
            Email: request.email,
            Password: request.password,
            Token: request.token,
            AppId: request.appId
        )

        return try await http.post("api/userregistration/validate", body: dto, skipAuth: true)
    }

    // MARK: - Provider configuration

    public func getAvailableProviders(appId: String? = nil) async -> [AuthProvider] {
        do {
            if let appId, !appId.isEmpty {
                let data: AppComponentAuthProvidersResponse = try await http.get(
                    "api/AppComponentConfigurations/\(appId)/auth-providers",
                    skipAuth: true
                )
                guard let providers = data.authProviders else { return [] }
                return providers
                    .filter(\.isEnabled)
                    .map { p in
                        AuthProvider(
                            name: p.providerName,
                            displayName: p.displayName,
                            icon: p.icon ?? "",
                            isEnabled: p.isEnabled,
                            buttonText: p.buttonText,
                            clientId: p.clientId,
                            redirectUri: p.redirectUri
                        )
                    }
                    .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
            }

            let data: [AuthProvider] = try await http.get("api/auth/providers", skipAuth: true)
            return data
        } catch {
            return []
        }
    }

    public func getCaptchaConfiguration(appId: String) async -> CaptchaConfiguration? {
        guard !appId.isEmpty else { return nil }
        return try? await http.get("api/AppComponentConfigurations/\(appId)/captcha", skipAuth: true)
    }

    public func getAuthenticationConfiguration(appId: String) async -> AuthenticationConfiguration? {
        try? await http.get("api/AppComponentConfigurations/\(appId)/auth-configuration", skipAuth: true)
    }

    // MARK: - OAuth / provider login

    /// Get the authorization URL for an OAuth provider; open it with
    /// ASWebAuthenticationSession. The OAuth callback URL is fixed server-side.
    public func getProviderAuthorizationUrl(providerName: String, appId: String, state: String? = nil) async -> String? {
        struct AuthorizationUrlResponse: Decodable {
            var authorizationUrl: String?
        }

        var query = "provider=\(providerName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? providerName)"
        if let state {
            query += "&state=\(state.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? state)"
        }

        let data: AuthorizationUrlResponse? = try? await http.get(
            "api/auth/oauth/\(appId)/authorize?\(query)",
            skipAuth: true
        )
        return data?.authorizationUrl
    }

    /// Complete an OAuth provider login using the token/code from the provider callback.
    public func loginWithProvider(providerName: String, providerToken: String, appId: String) async throws -> AuthenticationResponse {
        let request = LoginRequest(
            username: "",
            providerName: providerName,
            providerToken: providerToken,
            appId: appId,
            platform: "ios",
            deviceInfo: ProcessInfo.processInfo.operatingSystemVersionString
        )
        return try await login(request)
    }

    // MARK: - Password

    public func validatePassword(_ password: String, appId: String) async -> PasswordValidationResult {
        guard !password.isEmpty else {
            return PasswordValidationResult(isValid: false, errorMessage: "Password is required.")
        }
        guard let config = await getAuthenticationConfiguration(appId: appId) else {
            return PasswordValidationResult(isValid: true, errorMessage: "")
        }
        return Self.checkPasswordRules(password, config: config)
    }

    public static func getPasswordRequirementsText(config: AuthenticationConfiguration) -> String {
        var reqs = ["at least \(config.passwordMinimumLength) characters"]
        if config.passwordRequireUppercase { reqs.append("uppercase letters (A-Z)") }
        if config.passwordRequireLowercase { reqs.append("lowercase letters (a-z)") }
        if config.passwordRequireDigit { reqs.append("numbers (0-9)") }
        if config.passwordRequireSpecialChar { reqs.append("special characters (!@#$%^&*)") }

        if reqs.count == 1 { return "Password must have \(reqs[0])." }
        if reqs.count == 2 { return "Password must have \(reqs[0]) and \(reqs[1])." }
        let last = reqs.removeLast()
        return "Password must have \(reqs.joined(separator: ", ")), and \(last)."
    }

    @discardableResult
    public func requestPasswordReset(email: String, appId: String) async throws -> Bool {
        struct ForgotPasswordDto: Encodable {
            let Email: String
            let AppId: String
        }
        try await http.postVoid("api/auth/forgot-password", body: ForgotPasswordDto(Email: email, AppId: appId), skipAuth: true)
        return true
    }

    /// Sets a new password.
    ///
    /// `POST api/auth/reset-password` is `[Authorize]` on the server and identifies the user
    /// solely from the JWT — the request body carries no email or user id. The forced-reset
    /// flow (login with a temporary password) already has a real token: `login` short-circuits
    /// only for `requiresTwoFactor`, so a `requiresPasswordReset` response still reaches
    /// `storeAuthentication`. That token MUST be sent or the reset fails with 401 and the user
    /// is stranded on the reset screen.
    ///
    /// `resetToken` is reserved for a future emailed-link flow, which is the only case that is
    /// legitimately anonymous — hence `skipAuth` follows it rather than being hardcoded.
    @discardableResult
    public func resetPassword(newPassword: String, confirmPassword: String, appId: String, resetToken: String? = nil) async throws -> Bool {
        struct ResetPasswordDto: Encodable {
            let ResetToken: String?
            let NewPassword: String
            let ConfirmPassword: String
            let AppId: String
        }
        try await http.postVoid(
            "api/auth/reset-password",
            body: ResetPasswordDto(ResetToken: resetToken, NewPassword: newPassword, ConfirmPassword: confirmPassword, AppId: appId),
            skipAuth: resetToken != nil
        )
        return true
    }

    // MARK: - Token / license validation

    public func validateLicenseToken(_ token: String) async -> Bool {
        struct ValidateLicenseDto: Encodable {
            let Token: String
        }
        struct LicenseValidationResponse: Decodable {
            var isValid: Bool?
        }
        let data: LicenseValidationResponse? = try? await http.post(
            "api/auth/validate-license",
            body: ValidateLicenseDto(Token: token),
            skipAuth: true
        )
        return data?.isValid ?? false
    }

    public func hasRegistrationTokens(appId: String) async -> Bool {
        let data: Bool? = try? await http.get("api/registrationtokens/app/\(appId)/has-tokens", skipAuth: true)
        return data ?? false
    }

    public func validateRegistrationToken(_ token: String) async -> Bool {
        let data: Bool? = try? await http.get("api/registrationtokens/validate-simple/\(token)", skipAuth: true)
        return data ?? false
    }

    /// What a registration token grants — the tier, its pricing, the packs and the features, per
    /// app — from the server's detailed token validation, optionally scoped to one app.
    ///
    /// Returns nil when the details cannot be READ: a server older than this route, a 404, a
    /// transport failure, or a body that will not decode. That is NOT the same as an invalid
    /// token, and callers must not report it as one — they fall back to
    /// ``validateRegistrationToken(_:)``. An INVALID token comes back as details with
    /// `isValid == false` and the server's own message.
    public func getRegistrationTokenDetails(
        token: String,
        appId: String? = nil
    ) async -> RegistrationTokenDetails? {
        // encodeURIComponent semantics for both: a token is a single path segment (a '/' in it
        // must not open a new one), and the appId is a query value.
        let encodedToken = WildwoodURL.queryComponent(token)
        var appQuery = ""
        if let appId, !appId.isEmpty {
            appQuery = "?appId=\(WildwoodURL.queryComponent(appId))"
        }
        let data: RegistrationTokenDetails? = try? await http.get(
            "api/registrationtokens/validate-detailed/\(encodedToken)\(appQuery)",
            skipAuth: true
        )
        return data
    }

    // MARK: - Logout / refresh

    public func logout() async {
        struct RevokeTokenDto: Encodable {
            let RefreshToken: String
        }
        if let refreshToken = storage.getItem(WildwoodStorageKeys.refreshToken) {
            // Best-effort server logout.
            try? await http.postVoid("api/auth/revoke-token", body: RevokeTokenDto(RefreshToken: refreshToken))
        }
        clearAuthentication()
        notifyLogout()
        // Signing out also drops any queued attribution claim.
        await emitAuthChanged(nil)
    }

    public func refreshToken() async -> Bool {
        struct RefreshTokenDto: Encodable {
            let RefreshToken: String
        }
        guard let refreshToken = storage.getItem(WildwoodStorageKeys.refreshToken) else { return false }

        do {
            var data: AuthenticationResponse = try await http.post(
                "api/auth/refresh-token",
                body: RefreshTokenDto(RefreshToken: refreshToken),
                skipAuth: true
            )

            if !data.jwtToken.isEmpty {
                // The refresh-token endpoint does not carry requiresPasswordReset, so it always
                // comes back false. Storing that would clear a pending forced reset — a user who
                // refreshes before resetting would silently stop being asked. Carry the prior
                // value forward; the next real login returns the authoritative one.
                if getStoredUser()?.requiresPasswordReset == true {
                    data.requiresPasswordReset = true
                }

                storeAuthentication(data)
                notifyAuthChanged(data)
                await events.emit(.tokenRefreshed(data.jwtToken))
                return true
            }
            return false
        } catch let error as WildwoodError {
            // Only clear tokens on explicit rejection (400/401), not server errors.
            if error.status == 400 || error.status == 401 {
                clearAuthentication()
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Passkey / WebAuthn

    public func getPasskeyAuthenticationOptions(appId: String) async throws -> Data {
        struct AppIdDto: Encodable {
            let AppId: String
        }
        return try await http.postData("api/webauthn/authenticate/options", body: AppIdDto(AppId: appId))
    }

    public func verifyPasskeyAuthentication(appId: String, credential: PasskeyAssertionCredential) async throws -> AuthenticationResponse {
        struct PasskeyAuthDto: Encodable {
            let AppId: String
            let Id: String
            let RawId: String
            let `Type`: String
            let Response: PasskeyAssertionResponse
        }
        let dto = PasskeyAuthDto(
            AppId: appId,
            Id: credential.id,
            RawId: credential.rawId,
            Type: credential.type,
            Response: credential.response
        )

        let data: AuthenticationResponse = try await http.post("api/webauthn/authenticate", body: dto)
        storeAuthentication(data)
        notifyAuthChanged(data)
        await emitAuthChanged(data)
        return data
    }

    public func getPasskeyRegistrationOptions(appId: String) async throws -> Data {
        struct AppIdDto: Encodable {
            let AppId: String
        }
        return try await http.postData("api/webauthn/register/options", body: AppIdDto(AppId: appId))
    }

    public func completePasskeyRegistration(appId: String, credential: PasskeyRegistrationCredential) async throws {
        struct PasskeyRegDto: Encodable {
            let AppId: String
            let Id: String
            let RawId: String
            let `Type`: String
            let Response: PasskeyRegistrationResponse
        }
        let dto = PasskeyRegDto(
            AppId: appId,
            Id: credential.id,
            RawId: credential.rawId,
            Type: credential.type,
            Response: credential.response
        )
        try await http.postVoid("api/webauthn/register", body: dto)
    }

    // MARK: - Two-factor authentication (login challenge)

    public func sendTwoFactorCode(sessionId: String) async -> TwoFactorSendCodeResponse {
        struct SendCodeDto: Encodable {
            let SessionId: String
        }
        do {
            return try await http.post("api/twofactor/send-code", body: SendCodeDto(SessionId: sessionId), skipAuth: true)
        } catch {
            return TwoFactorSendCodeResponse(success: false, errorMessage: "Failed to send verification code")
        }
    }

    public func verifyTwoFactorCode(_ request: TwoFactorVerifyRequest) async -> TwoFactorVerifyResponse {
        do {
            let data: TwoFactorVerifyResponse = try await http.post("api/twofactor/verify", body: request, skipAuth: true)
            if data.success, let authResponse = data.authResponse {
                storeAuthentication(authResponse)
                notifyAuthChanged(authResponse)
                await emitAuthChanged(authResponse)
            }
            return data
        } catch {
            return TwoFactorVerifyResponse(success: false, errorMessage: "Verification failed")
        }
    }

    public func verifyTwoFactorRecoveryCode(sessionId: String, recoveryCode: String, ipAddress: String) async -> TwoFactorVerifyResponse {
        struct RecoveryDto: Encodable {
            let SessionId: String
            let RecoveryCode: String
            let IpAddress: String
        }
        do {
            let data: TwoFactorVerifyResponse = try await http.post(
                "api/twofactor/recovery",
                body: RecoveryDto(SessionId: sessionId, RecoveryCode: recoveryCode, IpAddress: ipAddress),
                skipAuth: true
            )
            if data.success, let authResponse = data.authResponse {
                storeAuthentication(authResponse)
                notifyAuthChanged(authResponse)
                await emitAuthChanged(authResponse)
            }
            return data
        } catch {
            return TwoFactorVerifyResponse(success: false, errorMessage: "Recovery code verification failed")
        }
    }

    // MARK: - Stored credentials

    public func getStoredAccessToken() -> String? {
        storage.getItem(WildwoodStorageKeys.accessToken)
    }

    public func getStoredRefreshToken() -> String? {
        storage.getItem(WildwoodStorageKeys.refreshToken)
    }

    public func getStoredUser() -> AuthenticationResponse? {
        guard let json = storage.getItem(WildwoodStorageKeys.user),
              let data = json.data(using: .utf8) else { return nil }
        return try? WildwoodJSON.decoder().decode(AuthenticationResponse.self, from: data)
    }

    // MARK: - Internal storage

    private func storeAuthentication(_ response: AuthenticationResponse) {
        if !response.jwtToken.isEmpty {
            storage.setItem(WildwoodStorageKeys.accessToken, response.jwtToken)
        }
        if !response.refreshToken.isEmpty {
            storage.setItem(WildwoodStorageKeys.refreshToken, response.refreshToken)
        }
        if let data = try? WildwoodJSON.encoder().encode(response),
           let json = String(data: data, encoding: .utf8) {
            storage.setItem(WildwoodStorageKeys.user, json)
        }
    }

    private func clearAuthentication() {
        storage.removeItem(WildwoodStorageKeys.accessToken)
        storage.removeItem(WildwoodStorageKeys.refreshToken)
        storage.removeItem(WildwoodStorageKeys.user)
    }

    private func notifyAuthChanged(_ response: AuthenticationResponse) {
        callbacks.withLock { $0.onAuthChanged }?(response)
    }

    private func notifyLogout() {
        callbacks.withLock { $0.onLogout }?()
    }

    // MARK: - Client-side password rules

    static func checkPasswordRules(_ password: String, config: AuthenticationConfiguration) -> PasswordValidationResult {
        if password.count < config.passwordMinimumLength {
            return PasswordValidationResult(
                isValid: false,
                errorMessage: "Password must be at least \(config.passwordMinimumLength) characters long."
            )
        }
        if config.passwordRequireUppercase, password.range(of: "[A-Z]", options: .regularExpression) == nil {
            return PasswordValidationResult(isValid: false, errorMessage: "Password must contain at least one uppercase letter (A-Z).")
        }
        if config.passwordRequireLowercase, password.range(of: "[a-z]", options: .regularExpression) == nil {
            return PasswordValidationResult(isValid: false, errorMessage: "Password must contain at least one lowercase letter (a-z).")
        }
        if config.passwordRequireDigit, password.range(of: "[0-9]", options: .regularExpression) == nil {
            return PasswordValidationResult(isValid: false, errorMessage: "Password must contain at least one number (0-9).")
        }
        if config.passwordRequireSpecialChar, password.range(of: "[^a-zA-Z0-9]", options: .regularExpression) == nil {
            return PasswordValidationResult(isValid: false, errorMessage: "Password must contain at least one special character (!@#$%^&*).")
        }
        return PasswordValidationResult(isValid: true, errorMessage: "")
    }
}
