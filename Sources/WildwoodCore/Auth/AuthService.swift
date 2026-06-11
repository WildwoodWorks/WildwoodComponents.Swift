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

        // If 2FA is required, return without storing auth.
        if data.requiresTwoFactor {
            return data
        }

        storeAuthentication(data)
        notifyAuthChanged(data)
        await events.emit(.authChanged(data))
        return data
    }

    // MARK: - Registration

    public func register(_ request: RegistrationRequest) async throws -> AuthenticationResponse {
        var dto = request
        dto.confirmPassword = request.confirmPassword ?? request.password

        let data: AuthenticationResponse = try await http.post("api/auth/register", body: dto, skipAuth: true)

        if !data.jwtToken.isEmpty {
            storeAuthentication(data)
            notifyAuthChanged(data)
            await events.emit(.authChanged(data))
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
        }

        let dto = TokenRegistrationDto(
            Token: request.registrationToken,
            Username: request.username ?? request.email,
            Email: request.email,
            Password: request.password,
            FirstName: request.firstName,
            LastName: request.lastName,
            AppId: request.appId,
            Platform: request.platform,
            DeviceInfo: request.deviceInfo
        )

        let raw = try await http.postData("api/userregistration/register-with-token", body: dto, skipAuth: true)
        let data = (try? WildwoodJSON.decoder().decode(AuthenticationResponse.self, from: raw)) ?? AuthenticationResponse()

        if !data.jwtToken.isEmpty {
            storeAuthentication(data)
            notifyAuthChanged(data)
            await events.emit(.authChanged(data))
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
        }

        let dto = OpenRegistrationDto(
            Username: request.username ?? request.email,
            Email: request.email,
            Password: request.password,
            FirstName: request.firstName,
            LastName: request.lastName,
            AppId: request.appId,
            Platform: request.platform,
            DeviceInfo: request.deviceInfo,
            PricingModelId: pricingModelId
        )

        return try await http.post("api/userregistration/register", body: dto, skipAuth: true)
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
            skipAuth: true
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
        await events.emit(.authChanged(nil))
    }

    public func refreshToken() async -> Bool {
        struct RefreshTokenDto: Encodable {
            let RefreshToken: String
        }
        guard let refreshToken = storage.getItem(WildwoodStorageKeys.refreshToken) else { return false }

        do {
            let data: AuthenticationResponse = try await http.post(
                "api/auth/refresh-token",
                body: RefreshTokenDto(RefreshToken: refreshToken),
                skipAuth: true
            )

            if !data.jwtToken.isEmpty {
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
        await events.emit(.authChanged(data))
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
                await events.emit(.authChanged(authResponse))
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
                await events.emit(.authChanged(authResponse))
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
