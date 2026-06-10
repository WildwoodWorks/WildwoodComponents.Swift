// Authentication flow state machine — port of react-shared's
// useAuthenticationLogic. No SwiftUI import: views observe this model.

import Foundation
import Observation
import WildwoodCore

public enum AuthView: Sendable {
    case login, register, twoFactor, passwordReset, forgotPassword, disclaimers
}

@MainActor
@Observable
public final class WildwoodAuthModel {
    @ObservationIgnored private let client: WildwoodClient
    @ObservationIgnored public let appId: String?
    @ObservationIgnored private let title: String?
    @ObservationIgnored private let showDetailedErrors: Bool
    @ObservationIgnored private let platform: String
    @ObservationIgnored private let deviceInfo: String
    @ObservationIgnored private let deviceName: String
    @ObservationIgnored private let onAuthenticationSuccess: ((AuthenticationResponse) -> Void)?
    @ObservationIgnored private let onAuthenticationError: ((String) -> Void)?

    // View state
    public private(set) var view: AuthView = .login
    public var isLoading = false
    public var errorMessage = ""
    public var successMessage = ""

    // Config
    public private(set) var authConfig: AuthenticationConfiguration?
    public private(set) var captchaConfig: CaptchaConfiguration?
    public private(set) var providers: [AuthProvider] = []

    // Login form
    public var username = ""
    public var password = ""
    public var rememberMe = false

    // Registration form
    public var regFirstName = ""
    public var regLastName = ""
    public var regUsername = ""
    public var regEmail = ""
    public var regPassword = ""
    public var regConfirmPassword = ""

    // 2FA
    public private(set) var twoFactorSessionId = ""
    public private(set) var twoFactorMethods: [TwoFactorMethodInfo] = []
    public var selectedTwoFactorMethod = ""
    public var twoFactorCode = ""
    public var showRecoveryInput = false
    public var recoveryCode = ""
    public var rememberDevice = false

    // Password reset
    public var newPassword = ""
    public var confirmPassword = ""

    // Forgot password
    public var forgotEmail = ""

    // Auth response held between views (2FA / reset / disclaimers)
    public private(set) var pendingAuth: AuthenticationResponse?

    public init(
        client: WildwoodClient,
        appId: String? = nil,
        title: String? = nil,
        showDetailedErrors: Bool = true,
        onAuthenticationSuccess: ((AuthenticationResponse) -> Void)? = nil,
        onAuthenticationError: ((String) -> Void)? = nil
    ) {
        self.client = client
        self.appId = appId ?? client.config.appId
        self.title = title
        self.showDetailedErrors = showDetailedErrors
        self.platform = "ios"
        self.deviceInfo = PlatformDetection.deviceInfo()
        self.deviceName = "iOS Device"
        self.onAuthenticationSuccess = onAuthenticationSuccess
        self.onAuthenticationError = onAuthenticationError
    }

    // MARK: - Configuration

    public func loadConfiguration() async {
        guard let appId, !appId.isEmpty else { return }
        async let ac = client.auth.getAuthenticationConfiguration(appId: appId)
        async let cc = client.auth.getCaptchaConfiguration(appId: appId)
        async let prov = client.auth.getAvailableProviders(appId: appId)
        authConfig = await ac
        captchaConfig = await cc
        providers = await prov
        if let captchaConfig {
            client.captcha.setConfiguration(captchaConfig)
        }
    }

    // MARK: - View navigation

    public func setView(_ nextView: AuthView) {
        if nextView == .login || nextView == .register {
            resetChallengeState()
        }
        view = nextView
    }

    public func toggleMode() {
        clearMessages()
        password = ""
        regPassword = ""
        regConfirmPassword = ""
        resetChallengeState()
        view = view == .login ? .register : .login
    }

    public func resolveTitle() -> String {
        if let title { return title }
        switch view {
        case .login: return "Sign In"
        case .register: return "Create Account"
        case .twoFactor: return "Two-Factor Authentication"
        case .passwordReset: return "Reset Password"
        case .forgotPassword: return "Forgot Password"
        case .disclaimers: return "Accept Disclaimers"
        }
    }

    public var allowRegistration: Bool {
        guard let authConfig else { return true }
        return authConfig.allowOpenRegistration || authConfig.allowTokenRegistration
    }

    public var allowPasswordReset: Bool {
        authConfig?.allowPasswordReset ?? true
    }

    // MARK: - Helpers

    public func clearMessages() {
        errorMessage = ""
        successMessage = ""
    }

    private func resetChallengeState() {
        twoFactorSessionId = ""
        twoFactorCode = ""
        twoFactorMethods = []
        selectedTwoFactorMethod = ""
        showRecoveryInput = false
        recoveryCode = ""
        rememberDevice = false
        newPassword = ""
        confirmPassword = ""
        pendingAuth = nil
    }

    private func handleError(_ error: any Error) {
        let message = (error as? WildwoodError)?.message ?? error.localizedDescription
        errorMessage = showDetailedErrors ? message : "Authentication failed. Please try again."
        onAuthenticationError?(message)
    }

    // MARK: - Auth completion

    private func completeAuth(_ response: AuthenticationResponse) {
        client.session.login(response)
        onAuthenticationSuccess?(response)
    }

    /// Route an auth response through the 2FA / password-reset / disclaimers gates.
    public func processAuthResponse(_ response: AuthenticationResponse) {
        if response.requiresTwoFactor {
            pendingAuth = response
            twoFactorSessionId = response.twoFactorSessionId ?? ""
            twoFactorMethods = response.availableTwoFactorMethods ?? []
            selectedTwoFactorMethod = response.defaultTwoFactorMethod ?? ""
            view = .twoFactor
            return
        }

        if response.requiresPasswordReset {
            pendingAuth = response
            view = .passwordReset
            return
        }

        if response.requiresDisclaimerAcceptance, !(response.pendingDisclaimers ?? []).isEmpty {
            pendingAuth = response
            view = .disclaimers
            return
        }

        completeAuth(response)
    }

    // MARK: - Login / registration

    public func handleLogin() async {
        clearMessages()
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.auth.login(
                LoginRequest(
                    username: username,
                    email: username,
                    password: password,
                    appId: appId,
                    rememberMe: rememberMe,
                    platform: platform,
                    deviceInfo: deviceInfo
                )
            )
            processAuthResponse(response)
        } catch {
            handleError(error)
        }
    }

    public func handleRegister() async {
        clearMessages()
        guard regPassword == regConfirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.auth.register(
                RegistrationRequest(
                    email: regEmail,
                    username: regUsername.isEmpty ? regEmail : regUsername,
                    firstName: regFirstName,
                    lastName: regLastName,
                    password: regPassword,
                    appId: appId ?? "",
                    platform: platform,
                    deviceInfo: deviceInfo
                )
            )
            processAuthResponse(response)
        } catch {
            handleError(error)
        }
    }

    /// Complete an OAuth provider login with the token/code from the redirect.
    public func handleProviderLogin(providerName: String, providerToken: String) async {
        clearMessages()
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.auth.loginWithProvider(
                providerName: providerName,
                providerToken: providerToken,
                appId: appId ?? ""
            )
            processAuthResponse(response)
        } catch {
            handleError(error)
        }
    }

    /// Fetch the server-side OAuth authorization URL for a provider.
    public func providerAuthorizationUrl(providerName: String, state: String? = nil) async -> URL? {
        guard let appId else { return nil }
        guard let urlString = await client.auth.getProviderAuthorizationUrl(providerName: providerName, appId: appId, state: state) else {
            return nil
        }
        return URL(string: urlString)
    }

    // MARK: - Two-factor

    public func handleTwoFactorSubmit() async {
        clearMessages()
        isLoading = true
        defer { isLoading = false }
        let result = await client.auth.verifyTwoFactorCode(
            TwoFactorVerifyRequest(
                sessionId: twoFactorSessionId,
                code: twoFactorCode,
                providerType: selectedTwoFactorMethod,
                rememberDevice: rememberDevice,
                deviceFingerprint: deviceInfo,
                deviceName: deviceName
            )
        )
        if result.success, let authResponse = result.authResponse {
            processAuthResponse(authResponse)
        } else {
            errorMessage = result.errorMessage ?? "Verification failed"
        }
    }

    public func handleRecoverySubmit() async {
        clearMessages()
        isLoading = true
        defer { isLoading = false }
        let result = await client.auth.verifyTwoFactorRecoveryCode(
            sessionId: twoFactorSessionId,
            recoveryCode: recoveryCode,
            ipAddress: ""
        )
        if result.success, let authResponse = result.authResponse {
            processAuthResponse(authResponse)
        } else {
            errorMessage = result.errorMessage ?? "Recovery code verification failed"
        }
    }

    public func handleResendCode() async {
        clearMessages()
        isLoading = true
        defer { isLoading = false }
        let result = await client.auth.sendTwoFactorCode(sessionId: twoFactorSessionId)
        if result.success {
            successMessage = "Code sent to \(result.maskedDestination ?? "your device")"
        } else {
            errorMessage = result.errorMessage ?? "Failed to resend code"
        }
    }

    // MARK: - Password reset (forced after login)

    public func handlePasswordReset() async {
        clearMessages()
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await client.auth.resetPassword(
                newPassword: newPassword,
                confirmPassword: confirmPassword,
                appId: appId ?? ""
            )
            successMessage = "Password updated successfully"

            if let pendingAuth {
                let response = try await client.auth.login(
                    LoginRequest(
                        username: pendingAuth.email,
                        email: pendingAuth.email,
                        password: newPassword,
                        appId: appId,
                        platform: platform,
                        deviceInfo: deviceInfo
                    )
                )
                processAuthResponse(response)
            }
        } catch {
            handleError(error)
        }
    }

    // MARK: - Forgot password

    public func handleForgotPasswordSubmit() async {
        clearMessages()
        isLoading = true
        defer { isLoading = false }
        do {
            try await client.auth.requestPasswordReset(email: forgotEmail, appId: appId ?? "")
            successMessage = "If an account exists with that email, a temporary password has been sent."
        } catch {
            handleError(error)
        }
    }

    // MARK: - Disclaimers

    public func handleAcceptDisclaimers() async {
        guard let pendingAuth, let pendingDisclaimers = pendingAuth.pendingDisclaimers else { return }
        clearMessages()
        isLoading = true
        defer { isLoading = false }
        do {
            // Store the JWT first so the acceptance call is authenticated — the
            // API returns tokens alongside pending disclaimers.
            client.session.login(pendingAuth)

            _ = try await client.disclaimer.acceptAllDisclaimers(
                pendingDisclaimers.map {
                    DisclaimerAcceptanceInput(disclaimerId: $0.disclaimerId, versionId: $0.versionId)
                },
                appId: appId
            )

            onAuthenticationSuccess?(pendingAuth)
        } catch {
            handleError(error)
        }
    }
}
