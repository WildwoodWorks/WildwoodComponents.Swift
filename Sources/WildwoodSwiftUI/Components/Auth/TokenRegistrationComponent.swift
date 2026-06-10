#if os(iOS)
// Registration with an invitation/registration token — parity with
// TokenRegistrationComponent in the React Native package. Handles the dual
// backend response: a token response starts a session; a token-less success
// prompts the user to sign in with their new credentials.

import SwiftUI
import WildwoodCore

public struct TokenRegistrationComponent: View {
    @Environment(\.wildwoodClient) private var client

    private let appId: String?
    private let prefilledToken: String?
    private let onRegistrationSuccess: ((AuthenticationResponse) -> Void)?
    private let onRegistrationError: ((String) -> Void)?

    @State private var token = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var tokenValid: Bool?

    public init(
        appId: String? = nil,
        prefilledToken: String? = nil,
        onRegistrationSuccess: ((AuthenticationResponse) -> Void)? = nil,
        onRegistrationError: ((String) -> Void)? = nil
    ) {
        self.appId = appId
        self.prefilledToken = prefilledToken
        self.onRegistrationSuccess = onRegistrationSuccess
        self.onRegistrationError = onRegistrationError
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Register with Token")
                .font(.title2.weight(.bold))

            if !errorMessage.isEmpty {
                ErrorBannerView(message: errorMessage) { errorMessage = "" }
            }
            if !successMessage.isEmpty {
                Label(successMessage, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }

            HStack {
                TextField("Registration token", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: token) { tokenValid = nil }
                if let tokenValid {
                    Image(systemName: tokenValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(tokenValid ? .green : .red)
                }
            }

            TextField("First name", text: $firstName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.givenName)
            TextField("Last name", text: $lastName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.familyName)
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Username (optional)", text: $username)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.newPassword)
            SecureField("Confirm password", text: $confirmPassword)
                .textFieldStyle(.roundedBorder)
                .textContentType(.newPassword)

            Button {
                Task { await register() }
            } label: {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Register").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || token.isEmpty || email.isEmpty || password.isEmpty)
        }
        .onAppear {
            if let prefilledToken, token.isEmpty {
                token = prefilledToken
            }
        }
    }

    private func register() async {
        guard let client = requireClient(client, component: "TokenRegistrationComponent") else { return }
        errorMessage = ""
        successMessage = ""

        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }

        isLoading = true
        defer { isLoading = false }

        let isValid = await client.auth.validateRegistrationToken(token)
        tokenValid = isValid
        guard isValid else {
            errorMessage = "This registration token is not valid."
            onRegistrationError?("Invalid registration token")
            return
        }

        do {
            let response = try await client.auth.registerWithToken(
                RegistrationRequest(
                    email: email,
                    username: username.isEmpty ? email : username,
                    firstName: firstName,
                    lastName: lastName,
                    password: password,
                    appId: appId ?? client.config.appId ?? "",
                    platform: "ios",
                    deviceInfo: PlatformDetection.deviceInfo(),
                    registrationToken: token
                )
            )

            if !response.jwtToken.isEmpty {
                client.session.login(response)
                onRegistrationSuccess?(response)
            } else {
                successMessage = "Registration successful. Sign in with your new credentials."
                onRegistrationSuccess?(response)
            }
        } catch {
            let message = (error as? WildwoodError)?.message ?? error.localizedDescription
            errorMessage = message
            onRegistrationError?(message)
        }
    }
}
#endif
