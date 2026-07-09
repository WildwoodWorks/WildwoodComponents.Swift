#if os(iOS)
// Multi-step signup: account info → tier selection → register + subscribe.
// Parity with SignupWithSubscriptionComponent: register (token or open flow),
// login when the registration response carries no tokens, link any payment
// transaction, then self-subscribe with the paymentTransactionId.

import SwiftUI
import WildwoodCore

public struct SignupWithSubscriptionComponent: View {
    @Environment(\.wildwoodClient) private var client

    public enum Step: Sendable {
        case accountInfo, tierSelection, processing, disclaimers, done
    }

    private let appId: String?
    /// Tier to preselect in the plans step (matched case-insensitively).
    private let preSelectedTierId: String?
    /// Pricing option to preselect within the pre-selected tier (e.g. the
    /// annual option chosen on a pricing page); falls back to the tier's
    /// default pricing, then its first.
    private let preSelectedPricingId: String?
    /// Show the optional registration-token field on the account step when
    /// tokens are optional (open registration allowed). Default true. When
    /// tokens are the only registration path the field always shows.
    private let showOptionalTokenEntry: Bool
    /// Called when the selected tier requires payment before subscribing.
    /// Return a payment transaction id (e.g. from PaymentComponent / StoreKit),
    /// or nil to cancel. When absent, paid tiers subscribe without a transaction
    /// (the backend may allow bypass or reject).
    private let onPaymentRequired: ((AppTierModel, AppTierPricingModel?) async -> String?)?
    private let onSignupComplete: ((AuthenticationResponse, AppTierChangeResultModel?) -> Void)?
    private let onSignupError: ((String) -> Void)?

    @State private var step: Step = .accountInfo
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var warningMessage = ""
    @State private var authConfig: AuthenticationConfiguration?
    @State private var tiers: [AppTierModel] = []
    @State private var selectedPricingByTier: [String: String] = [:]
    // Retry guards: a failed subscribe must not re-register or re-charge.
    @State private var establishedAuth: AuthenticationResponse?
    @State private var collectedTransactionId: String?
    // Login/registration can report disclaimers that must be accepted before the
    // account is usable. Kept in state so a retry (which reuses the established
    // session) still routes through the disclaimers step, and so the deferred
    // onSignupComplete fires with the correct subscribe result.
    @State private var disclaimersPending = false
    @State private var completedSubscribeResult: AppTierChangeResultModel?

    // Account form
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var registrationToken = ""

    public init(
        appId: String? = nil,
        preSelectedTierId: String? = nil,
        preSelectedPricingId: String? = nil,
        showOptionalTokenEntry: Bool = true,
        onPaymentRequired: ((AppTierModel, AppTierPricingModel?) async -> String?)? = nil,
        onSignupComplete: ((AuthenticationResponse, AppTierChangeResultModel?) -> Void)? = nil,
        onSignupError: ((String) -> Void)? = nil
    ) {
        self.appId = appId
        self.preSelectedTierId = preSelectedTierId
        self.preSelectedPricingId = preSelectedPricingId
        self.showOptionalTokenEntry = showOptionalTokenEntry
        self.onPaymentRequired = onPaymentRequired
        self.onSignupComplete = onSignupComplete
        self.onSignupError = onSignupError
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader

            if !errorMessage.isEmpty {
                ErrorBannerView(message: errorMessage) { errorMessage = "" }
            }

            switch step {
            case .accountInfo: accountForm
            case .tierSelection: tierSelection
            case .processing: LoadingSpinnerView(label: "Creating your account…")
            case .disclaimers: disclaimersStep
            case .done:
                ContentUnavailableView(
                    "Welcome aboard!",
                    systemImage: warningMessage.isEmpty ? "checkmark.seal.fill" : "checkmark.seal",
                    description: Text(
                        warningMessage.isEmpty
                            ? "Your account and subscription are ready."
                            : warningMessage
                    )
                )
            }
        }
        .task { await load() }
    }

    @ViewBuilder private var stepHeader: some View {
        HStack {
            Text("Create Account").font(.title2.weight(.bold))
            Spacer()
            Text(stepLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var stepLabel: String {
        switch step {
        case .accountInfo: return "Step 1 of 2"
        case .tierSelection: return "Step 2 of 2"
        // The disclaimers step is a gate, not a numbered step in the indicator.
        case .processing, .disclaimers, .done: return ""
        }
    }

    @ViewBuilder private var accountForm: some View {
        VStack(spacing: 12) {
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

            // The optional token entry is suppressible (showOptionalTokenEntry);
            // when tokens are the only registration path the field always shows.
            if authConfig?.allowTokenRegistration == true,
               showOptionalTokenEntry || authConfig?.allowOpenRegistration != true {
                TextField(
                    authConfig?.allowOpenRegistration == true
                        ? "Registration token (optional)"
                        : "Registration token",
                    text: $registrationToken
                )
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            Button {
                continueToTiers()
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty || password.isEmpty || firstName.isEmpty)
        }
    }

    @ViewBuilder private var tierSelection: some View {
        VStack(spacing: 16) {
            if tiers.isEmpty {
                ContentUnavailableView("No plans available", systemImage: "rectangle.on.rectangle.slash")
            } else {
                ForEach(tiers) { tier in
                    TierCard(
                        tier: tier,
                        selectedPricing: selectedPricing(for: tier),
                        onSelectPricing: { pricing in
                            selectedPricingByTier[tier.id] = pricing.id
                        },
                        onSubscribe: { tier, pricing in
                            Task { await signUp(tier: tier, pricing: pricing) }
                        }
                    )
                }
            }
            Button("Back") {
                // Start-over path: recompute disclaimer gating on the next
                // subscribe attempt rather than carrying a stale flag.
                disclaimersPending = false
                step = .accountInfo
            }
            .font(.footnote)
        }
    }

    // Pending legal acceptance surfaced by the login/registration response.
    // The session JWT is already stored, so DisclaimerComponent's authenticated
    // accept calls succeed. Gating advances to success only once all are accepted
    // (or the scoped re-fetch finds none pending).
    @ViewBuilder private var disclaimersStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("One more step").font(.title3.weight(.semibold))
            Text("Please review and accept the following before continuing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            DisclaimerComponent(
                appId: appId,
                onAllAccepted: { finishAfterDisclaimers() },
                onLoaded: { count in
                    // Nothing pending (e.g. accepted meanwhile) — don't strand
                    // the user on the disclaimers step.
                    if count == 0 { finishAfterDisclaimers() }
                }
            )
        }
    }

    private func finishAfterDisclaimers() {
        step = .done
        if let establishedAuth {
            onSignupComplete?(establishedAuth, completedSubscribeResult)
        }
    }

    private func selectedPricing(for tier: AppTierModel) -> AppTierPricingModel? {
        if let id = selectedPricingByTier[tier.id] {
            return tier.pricingOptions.first { $0.id == id }
        }
        return tier.pricingOptions.first(where: \.isDefault) ?? tier.pricingOptions.first
    }

    private func continueToTiers() {
        errorMessage = ""
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }
        step = .tierSelection
    }

    // MARK: - Data

    private func load() async {
        guard let client = requireClient(client, component: "SignupWithSubscriptionComponent") else { return }
        guard let resolvedAppId = appId ?? client.config.appId else {
            errorMessage = "SignupWithSubscriptionComponent requires an appId."
            return
        }
        async let config = client.auth.getAuthenticationConfiguration(appId: resolvedAppId)
        async let loadedTiers = client.appTier.getTiers(appId: resolvedAppId)
        authConfig = await config
        tiers = await loadedTiers.sorted { $0.displayOrder < $1.displayOrder }

        // Preselect the requested tier's pricing: explicit pricing id →
        // the tier's default → its first option (ids matched case-insensitively).
        if let preSelectedTierId,
           let tier = tiers.first(where: { $0.id.lowercased() == preSelectedTierId.lowercased() }) {
            let pricing =
                preSelectedPricingId.flatMap { pricingId in
                    tier.pricingOptions.first { $0.id.lowercased() == pricingId.lowercased() }
                }
                ?? tier.pricingOptions.first(where: \.isDefault)
                ?? tier.pricingOptions.first
            if let pricing {
                selectedPricingByTier[tier.id] = pricing.id
            }
        }
    }

    // MARK: - Signup pipeline

    private func signUp(tier: AppTierModel, pricing: AppTierPricingModel?) async {
        guard let client else { return }
        guard let resolvedAppId = appId ?? client.config.appId else { return }
        errorMessage = ""
        warningMessage = ""
        step = .processing
        isLoading = true
        defer { isLoading = false }

        do {
            // Register + login once; a retry after a failed payment/subscribe
            // reuses the established session instead of re-registering.
            let auth: AuthenticationResponse
            if let establishedAuth {
                auth = establishedAuth
            } else {
                auth = try await registerAndLogin(client: client, appId: resolvedAppId)
                establishedAuth = auth
            }

            // Collect payment for paid tiers; reuse a previously collected
            // transaction on retry so the user isn't charged twice.
            let needsPayment = !tier.isFreeTier && (pricing?.price ?? 0) > 0
            if needsPayment, collectedTransactionId == nil, let onPaymentRequired {
                guard let txnId = await onPaymentRequired(tier, pricing) else {
                    step = .tierSelection
                    return
                }
                collectedTransactionId = txnId
                if let userId = client.session.userId {
                    _ = await client.payment.linkTransactionToUser(externalTransactionId: txnId, userId: userId)
                }
            }

            let subscribeResult = try? await client.appTier.selfSubscribe(
                appId: resolvedAppId,
                appTierId: tier.id,
                appTierPricingId: pricing?.id,
                paymentTransactionId: collectedTransactionId
            )

            // A subscribe failure is non-fatal (JS parity): the account exists
            // and a session is active — the tier can be chosen later.
            if subscribeResult?.success != true {
                let detail = subscribeResult?.errorMessage ?? "The subscription could not be completed."
                warningMessage = "Your account was created, but the subscription didn't go through: \(detail) You can choose a plan later."
                onSignupError?(detail)
            }

            // Gate success on disclaimer acceptance. The login/registration
            // response carries any pending disclaimers (mirrors the login flow);
            // the session JWT is stored, so the disclaimer accepts are authorized.
            let completedResult = subscribeResult?.success == true ? subscribeResult : nil
            if auth.requiresDisclaimerAcceptance, auth.pendingDisclaimers?.isEmpty == false {
                disclaimersPending = true
            }
            if disclaimersPending {
                completedSubscribeResult = completedResult
                step = .disclaimers
            } else {
                step = .done
                onSignupComplete?(auth, completedResult)
            }
        } catch {
            let message = (error as? WildwoodError)?.message ?? error.localizedDescription
            errorMessage = message
            step = .tierSelection
            onSignupError?(message)
        }
    }

    private func registerAndLogin(client: WildwoodClient, appId resolvedAppId: String) async throws -> AuthenticationResponse {
        let request = RegistrationRequest(
            email: email,
            username: username.isEmpty ? email : username,
            firstName: firstName,
            lastName: lastName,
            password: password,
            appId: resolvedAppId,
            platform: "ios",
            deviceInfo: PlatformDetection.deviceInfo(),
            registrationToken: registrationToken.isEmpty ? nil : registrationToken
        )

        // Register: token flow when a token was supplied, open flow otherwise.
        var auth: AuthenticationResponse
        if !registrationToken.isEmpty {
            auth = try await client.auth.registerWithToken(request)
        } else {
            let result = try await client.auth.registerOpen(request)
            guard result.success else {
                throw WildwoodError(message: result.message, status: 0, code: .validationError)
            }
            auth = AuthenticationResponse(id: result.userId ?? "", userId: result.userId ?? "", email: email)
        }

        // Token-less registration → authenticate with the new credentials.
        if auth.jwtToken.isEmpty {
            auth = try await client.auth.login(
                LoginRequest(
                    username: username.isEmpty ? email : username,
                    email: email,
                    password: password,
                    appId: resolvedAppId,
                    platform: "ios",
                    deviceInfo: PlatformDetection.deviceInfo()
                )
            )
        }
        client.session.login(auth)
        return auth
    }
}
#endif
