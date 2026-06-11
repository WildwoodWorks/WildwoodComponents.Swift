#if os(iOS)
// Complete login/register UI with social providers, 2FA challenge, forced
// password reset, forgot password, and disclaimer acceptance — parity with
// AuthenticationComponent in the React Native package.

import SwiftUI
import AuthenticationServices
import WildwoodCore

public struct AuthenticationComponent: View {
    @Environment(\.wildwoodClient) private var client
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    private let appId: String?
    private let title: String?
    private let showDetailedErrors: Bool
    /// Custom URL scheme the backend OAuth flow redirects to (R3: requires
    /// backend support; provider buttons degrade gracefully without it).
    private let oauthCallbackScheme: String
    private let onAuthenticationSuccess: ((AuthenticationResponse) -> Void)?
    private let onAuthenticationError: ((String) -> Void)?

    @State private var model: WildwoodAuthModel?

    public init(
        appId: String? = nil,
        title: String? = nil,
        showDetailedErrors: Bool = true,
        oauthCallbackScheme: String = "wildwoodcomponents",
        onAuthenticationSuccess: ((AuthenticationResponse) -> Void)? = nil,
        onAuthenticationError: ((String) -> Void)? = nil
    ) {
        self.appId = appId
        self.title = title
        self.showDetailedErrors = showDetailedErrors
        self.oauthCallbackScheme = oauthCallbackScheme
        self.onAuthenticationSuccess = onAuthenticationSuccess
        self.onAuthenticationError = onAuthenticationError
    }

    public var body: some View {
        Group {
            if let model {
                AuthFlowView(model: model, oauthCallbackScheme: oauthCallbackScheme)
            } else {
                LoadingSpinnerView()
            }
        }
        .task {
            guard model == nil, let client = requireClient(client, component: "AuthenticationComponent") else { return }
            let created = WildwoodAuthModel(
                client: client,
                appId: appId,
                title: title,
                showDetailedErrors: showDetailedErrors,
                onAuthenticationSuccess: onAuthenticationSuccess,
                onAuthenticationError: onAuthenticationError
            )
            model = created
            await created.loadConfiguration()
        }
    }
}

private struct AuthFlowView: View {
    @Bindable var model: WildwoodAuthModel
    let oauthCallbackScheme: String
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.resolveTitle())
                .font(.title2.weight(.bold))

            if !model.errorMessage.isEmpty {
                ErrorBannerView(message: model.errorMessage) { model.errorMessage = "" }
            }
            if !model.successMessage.isEmpty {
                Label(model.successMessage, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }

            switch model.view {
            case .login: loginView
            case .register: registerView
            case .twoFactor: twoFactorView
            case .passwordReset: passwordResetView
            case .forgotPassword: forgotPasswordView
            case .disclaimers: disclaimersView
            }
        }
    }

    // MARK: - Login

    @ViewBuilder private var loginView: some View {
        VStack(spacing: 12) {
            TextField("Username or email", text: $model.username)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $model.password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)

            Toggle("Remember me", isOn: $model.rememberMe)
                .font(.subheadline)

            if model.requiresLoginCaptcha {
                captchaSection
            }

            Button {
                Task { await model.handleLogin() }
            } label: {
                if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Sign In").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                model.isLoading || model.username.isEmpty || model.password.isEmpty
                    || (model.requiresLoginCaptcha && model.captchaToken == nil)
            )

            if !model.providers.isEmpty {
                providerButtons
            }

            HStack {
                if model.allowRegistration {
                    Button("Create account") { model.toggleMode() }
                        .font(.footnote)
                }
                Spacer()
                if model.allowPasswordReset {
                    Button("Forgot password?") { model.setView(.forgotPassword) }
                        .font(.footnote)
                }
            }
        }
    }

    @ViewBuilder private var providerButtons: some View {
        VStack(spacing: 8) {
            HStack {
                VStack { Divider() }
                Text("or continue with").font(.caption).foregroundStyle(.secondary)
                VStack { Divider() }
            }
            ForEach(model.providers) { provider in
                Button {
                    Task { await signIn(with: provider) }
                } label: {
                    Text(provider.displayName)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isLoading)
            }
        }
    }

    private func signIn(with provider: AuthProvider) async {
        guard let authUrl = await model.providerAuthorizationUrl(
            providerName: provider.name,
            state: "native=\(oauthCallbackScheme)"
        ) else {
            model.errorMessage = "Could not start \(provider.displayName) sign-in."
            return
        }
        do {
            // BACKEND DEPENDENCY (plan item R3): the server's OAuth callback
            // currently completes via window.postMessage for web popups. For
            // this session to complete natively, the backend must support
            // redirecting the callback to `<oauthCallbackScheme>://…` with the
            // provider token/code in the query (the `state` value below carries
            // the requested scheme as a hint). Until then the browser sheet
            // stays open on the callback page and the user has to cancel.
            let callbackURL = try await webAuthenticationSession.authenticate(
                using: authUrl,
                callbackURLScheme: oauthCallbackScheme
            )
            guard let token = Self.extractProviderToken(from: callbackURL) else {
                model.errorMessage = "Sign-in did not return a credential."
                return
            }
            await model.handleProviderLogin(providerName: provider.name, providerToken: token)
        } catch {
            // User cancelled or the session failed; cancellation is not an error.
            if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                model.errorMessage = "Sign-in failed: \(error.localizedDescription)"
            }
        }
    }

    /// CAPTCHA challenge host. Invisible providers (reCAPTCHA v3) run in a
    /// zero-height web view and post the token automatically; checkbox-style
    /// providers (hCaptcha, Turnstile) get visible space. The `.id` ties the
    /// widget to the attempt counter so a consumed token re-issues a challenge.
    @ViewBuilder private var captchaSection: some View {
        if let config = model.captchaConfig {
            let isInvisible = !["hcaptcha", "turnstile"].contains(config.providerType.lowercased())
            VStack(alignment: .leading, spacing: 4) {
                CaptchaWebView(configuration: config) { token in
                    model.captchaToken = token
                }
                .frame(height: isInvisible ? 1 : 90)
                .opacity(isInvisible ? 0 : 1)
                .id(model.captchaAttempt)

                if model.captchaToken != nil {
                    Label("Verification complete", systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if !isInvisible {
                    Text("Complete the verification above to continue.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Verifying…", systemImage: "shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    static func extractProviderToken(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let candidates = ["providerToken", "provider_token", "token", "access_token", "code"]
        for name in candidates {
            if let value = components?.queryItems?.first(where: { $0.name == name })?.value, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    // MARK: - Register

    @ViewBuilder private var registerView: some View {
        VStack(spacing: 12) {
            TextField("First name", text: $model.regFirstName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.givenName)
            TextField("Last name", text: $model.regLastName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.familyName)
            TextField("Email", text: $model.regEmail)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Username (optional)", text: $model.regUsername)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $model.regPassword)
                .textFieldStyle(.roundedBorder)
                .textContentType(.newPassword)
            SecureField("Confirm password", text: $model.regConfirmPassword)
                .textFieldStyle(.roundedBorder)
                .textContentType(.newPassword)

            if let config = model.authConfig {
                Text(AuthService.getPasswordRequirementsText(config: config))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.requiresRegistrationCaptcha {
                captchaSection
            }

            Button {
                Task { await model.handleRegister() }
            } label: {
                if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Create Account").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                model.isLoading || model.regEmail.isEmpty || model.regPassword.isEmpty
                    || (model.requiresRegistrationCaptcha && model.captchaToken == nil)
            )

            Button("Already have an account? Sign in") { model.toggleMode() }
                .font(.footnote)
        }
    }

    // MARK: - Two-factor challenge

    @ViewBuilder private var twoFactorView: some View {
        VStack(spacing: 12) {
            if model.twoFactorMethods.count > 1 {
                Picker("Method", selection: $model.selectedTwoFactorMethod) {
                    ForEach(model.twoFactorMethods, id: \.providerType) { method in
                        Text(method.name).tag(method.providerType)
                    }
                }
                .pickerStyle(.segmented)
            }

            if model.showRecoveryInput {
                TextField("Recovery code", text: $model.recoveryCode)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task { await model.handleRecoverySubmit() }
                } label: {
                    Text("Use Recovery Code").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isLoading || model.recoveryCode.isEmpty)
                Button("Back to verification code") { model.showRecoveryInput = false }
                    .font(.footnote)
            } else {
                TextField("Verification code", text: $model.twoFactorCode)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)

                Toggle("Remember this device", isOn: $model.rememberDevice)
                    .font(.subheadline)

                Button {
                    Task { await model.handleTwoFactorSubmit() }
                } label: {
                    if model.isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Verify").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isLoading || model.twoFactorCode.isEmpty)

                HStack {
                    Button("Resend code") {
                        Task { await model.handleResendCode() }
                    }
                    .font(.footnote)
                    Spacer()
                    Button("Use a recovery code") { model.showRecoveryInput = true }
                        .font(.footnote)
                }
            }

            Button("Cancel") { model.setView(.login) }
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Forced password reset

    @ViewBuilder private var passwordResetView: some View {
        VStack(spacing: 12) {
            Text("Your password must be updated before continuing.")
                .font(.callout)
                .foregroundStyle(.secondary)
            SecureField("New password", text: $model.newPassword)
                .textFieldStyle(.roundedBorder)
                .textContentType(.newPassword)
            SecureField("Confirm new password", text: $model.confirmPassword)
                .textFieldStyle(.roundedBorder)
                .textContentType(.newPassword)
            Button {
                Task { await model.handlePasswordReset() }
            } label: {
                if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Update Password").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isLoading || model.newPassword.isEmpty)
        }
    }

    // MARK: - Forgot password

    @ViewBuilder private var forgotPasswordView: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $model.forgotEmail)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button {
                Task { await model.handleForgotPasswordSubmit() }
            } label: {
                if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Send Reset Email").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isLoading || model.forgotEmail.isEmpty)
            Button("Back to sign in") { model.setView(.login) }
                .font(.footnote)
        }
    }

    // MARK: - Disclaimers gate

    @ViewBuilder private var disclaimersView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.pendingAuth?.pendingDisclaimers ?? []) { disclaimer in
                VStack(alignment: .leading, spacing: 6) {
                    Text(disclaimer.title).font(.headline)
                    ScrollView {
                        Text(disclaimer.content)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                }
                .padding()
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
            Button {
                Task { await model.handleAcceptDisclaimers() }
            } label: {
                if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Accept and Continue").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isLoading)
        }
    }
}
#endif
