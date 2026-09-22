#if os(iOS)
// Multi-step signup: account info → (token plan | tier selection) → register + subscribe.
// Parity with SignupWithSubscriptionComponent: register (token or open flow), login when the
// registration response carries no tokens, link any payment transaction, then self-subscribe
// with the paymentTransactionId.
//
// THE ONE RULE THAT IS NOT OPTIONAL: a registration token that carries a plan for this app has
// ALREADY subscribed the account. Subscribing again REPLACES that subscription, which cancels
// the plan the token just set up — so a grant skips both the plan step and the payment step, and
// nothing self-subscribes over it. The decision lives in `SignupPlanRules` so it is testable.

import SwiftUI
import WildwoodCore

/// The original signup wizard.
///
/// - Warning: Superseded by ``RegistrationSubscriptionSignupView``. The view keeps this wizard's
///   step copy and locators but reads the app's registration settings itself (no `requireToken` /
///   `allowOpenRegistration` / `showOptionalTokenEntry` to resolve), validates a registration
///   token's plan before anything is charged, buys packs after the login on the card already
///   taken, reports a structured `SignupOutcome`, and handles invite redemption
///   (`tokenMode: .required`). This component stays public and behaves exactly as before; nothing
///   has been removed.
@available(*, deprecated, message: "Use RegistrationAndSubscriptionComponent(.signup(...)) or RegistrationSubscriptionSignupView, which reads the app's registration settings itself, validates a token's plan before anything is charged, buys packs on the card already taken and reports a SignupOutcome. Still supported and unchanged.")
public struct SignupWithSubscriptionComponent: View {
    @Environment(\.wildwoodClient) private var client

    public enum Step: Sendable {
        case accountInfo, tokenPlan, tierSelection, processing, disclaimers, done
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
    /// (the backend may allow bypass or reject). The args carry the pricing MODEL id, the plan's
    /// own price and its trial days, so a host forwarding them to `PaymentComponent` gets a
    /// recurring subscription rather than a one-off charge.
    private let onPaymentRequired: ((WildwoodPaymentRequiredArgs) async -> String?)?
    private let onSignupComplete: ((AuthenticationResponse, AppTierChangeResultModel?) -> Void)?
    private let onSignupError: ((String) -> Void)?

    @State private var step: Step = .accountInfo
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var warningMessage = ""
    @State private var successMessage = ""
    @State private var statusMessage = ""
    @State private var authConfig: AuthenticationConfiguration?
    @State private var tiers: [AppTierModel] = []
    @State private var selectedPricingByTier: [String: String] = [:]
    // Retry guards: a failed subscribe must not re-register or re-charge.
    @State private var establishedAuth: AuthenticationResponse?
    @State private var collectedTransactionId: String?
    /// The plan the collected transaction was collected FOR. A transaction taken for tier A must
    /// never be reused when the user goes back and picks tier B.
    @State private var collectedPlanKey: String?
    @State private var subscriptionFailed = false
    /// What the registration token grants this app, when it grants anything.
    @State private var tokenGrant: RegistrationTokenAppGrant?
    /// Trial days on the plan that was actually bought, for the success copy.
    @State private var completedTrialDays: Int?
    // Login/registration can report disclaimers that must be accepted before the
    // account is usable. Kept in state so a retry (which reuses the established
    // session) still routes through the disclaimers step, and so the deferred
    // onSignupComplete fires with the correct subscribe result.
    @State private var disclaimersPending = false
    @State private var completedSubscribeResult: AppTierChangeResultModel?

    /// The account form as last submitted. Held here rather than as seven separate fields because
    /// the fields themselves live in ``SignupRegistrationFormView``, which this screen and the
    /// newer `RegistrationSubscriptionSignupView` share so their validation cannot drift. Kept
    /// across a step back so the visitor does not retype anything.
    @State private var submittedForm: RegistrationFormData?

    public init(
        appId: String? = nil,
        preSelectedTierId: String? = nil,
        preSelectedPricingId: String? = nil,
        showOptionalTokenEntry: Bool = true,
        onPaymentRequired: ((WildwoodPaymentRequiredArgs) async -> String?)? = nil,
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
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            switch step {
            case .accountInfo: accountForm
            case .tokenPlan: tokenPlanStep
            case .tierSelection: tierSelection
            case .processing: LoadingSpinnerView(label: "Creating your account…")
            case .disclaimers: disclaimersStep
            case .done: doneStep
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
        case .tokenPlan, .tierSelection: return "Step 2 of 2"
        // The disclaimers step is a gate, not a numbered step in the indicator.
        case .processing, .disclaimers, .done: return ""
        }
    }

    @ViewBuilder private var doneStep: some View {
        ContentUnavailableView(
            "Welcome aboard!",
            systemImage: warningMessage.isEmpty ? "checkmark.seal.fill" : "checkmark.seal",
            description: Text(warningMessage.isEmpty ? successMessage : warningMessage)
        )
    }

    @ViewBuilder private var accountForm: some View {
        SignupRegistrationFormView(
            initialFormData: submittedForm,
            // The optional token entry is suppressible (showOptionalTokenEntry);
            // when tokens are the only registration path the field always shows.
            showTokenField: authConfig?.allowTokenRegistration == true
                && (showOptionalTokenEntry || authConfig?.allowOpenRegistration != true),
            // Settings that have NOT loaded are not "token only": a configuration fetch that
            // failed must not leave the form permanently unsubmittable. The server has the last
            // word on a missing token either way.
            tokenRequired: authConfig.map { !$0.allowOpenRegistration } ?? false,
            submitTitle: "Continue",
            isBusy: isLoading,
            onSubmit: { data in
                Task { await continueFromAccount(data) }
            }
        )
    }

    /// What the registration token sets up. Names only — a granted plan is not being sold here,
    /// so nothing on this step carries a price.
    @ViewBuilder private var tokenPlanStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your registration token includes").font(.headline)
            if let grant = tokenGrant {
                VStack(alignment: .leading, spacing: 6) {
                    Label(grantedPlanText(grant), systemImage: "checkmark.seal")
                        .font(.subheadline)
                    ForEach(grantedPackNames(grant), id: \.self) { name in
                        Label(name, systemImage: "shippingbox")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(grantedFeatureNames(grant), id: \.self) { name in
                        Label(name, systemImage: "sparkles")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            }

            Button {
                Task { await signUp(tier: nil, pricing: nil) }
            } label: {
                Text("Create Account").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            startOverButton
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
                        currency: catalogCurrency,
                        onSelectPricing: { pricing in
                            selectedPricingByTier[tier.id] = pricing.id
                            // A different option is a different price: the transaction collected
                            // for the previous one must not pay for this one.
                            discardStaleTransaction(planKey: planKey(tierId: tier.id, pricingId: pricing.id))
                        },
                        onSubscribe: { tier, pricing in
                            Task { await signUp(tier: tier, pricing: pricing) }
                        }
                    )
                }
            }
            startOverButton
        }
    }

    /// Back to the account step with the previous attempt's payment and plan state dropped.
    /// `establishedAuth` deliberately survives — re-registering the same email would fail.
    @ViewBuilder private var startOverButton: some View {
        Button("Start Over") {
            collectedTransactionId = nil
            collectedPlanKey = nil
            subscriptionFailed = false
            tokenGrant = nil
            completedTrialDays = nil
            completedSubscribeResult = nil
            disclaimersPending = false
            errorMessage = ""
            warningMessage = ""
            statusMessage = ""
            step = .accountInfo
        }
        .font(.footnote)
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

    /// The currency the catalog quotes in, for a tier that carries none of its own.
    private var catalogCurrency: String? {
        for tier in tiers {
            if let currency = tier.currency, !currency.trimmingCharacters(in: .whitespaces).isEmpty {
                return currency
            }
        }
        return nil
    }

    // MARK: - Token grant presentation

    private func grantedPlanText(_ grant: RegistrationTokenAppGrant) -> String {
        let tierName = SignupPlanRules.nonBlank(grant.appTierName) ?? "Your plan"
        guard let pricingName = SignupPlanRules.nonBlank(grant.pricingName) else { return tierName }
        return "\(tierName) (\(pricingName))"
    }

    /// Names where the server sent them, ids as the fallback — never a price.
    private func grantedPackNames(_ grant: RegistrationTokenAppGrant) -> [String] {
        Self.displayNames(ids: grant.addOnIds, names: grant.addOnNames)
    }

    private func grantedFeatureNames(_ grant: RegistrationTokenAppGrant) -> [String] {
        Self.displayNames(ids: grant.featureCodes, names: grant.featureNames)
    }

    private static func displayNames(ids: [String], names: [String]?) -> [String] {
        var result: [String] = []
        for (index, id) in ids.enumerated() {
            if let names, index < names.count, !names[index].isEmpty {
                result.append(names[index])
            } else {
                result.append(id)
            }
        }
        return result
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

    // MARK: - Account step

    private func continueFromAccount(_ data: RegistrationFormData) async {
        errorMessage = ""
        statusMessage = ""
        // The form itself refuses a mismatched confirmation, so anything arriving here is already
        // internally consistent.
        submittedForm = data

        let registrationToken: String = data.registrationToken ?? ""
        guard let client, !registrationToken.isEmpty else {
            step = .tierSelection
            return
        }
        guard let resolvedAppId = appId ?? client.config.appId else {
            step = .tierSelection
            return
        }

        isLoading = true
        statusMessage = "Checking your registration token\u{2026}"
        defer {
            isLoading = false
            statusMessage = ""
        }

        // nil = the details could not be READ (an older server, a transport failure), which is
        // not the same as an invalid token: fall back to the plain flow rather than refusing a
        // token the registration endpoint would have accepted.
        let details = await client.auth.getRegistrationTokenDetails(token: registrationToken, appId: resolvedAppId)
        if let details, !details.isValid {
            errorMessage = SignupPlanRules.nonBlank(details.errorMessage)
                ?? "That registration token isn't valid. Check it and try again."
            return
        }

        tokenGrant = SignupPlanRules.findTokenPlanGrant(details, appId: resolvedAppId)
        step = tokenGrant == nil ? .tierSelection : .tokenPlan
    }

    // MARK: - Signup pipeline

    private func planKey(tierId: String?, pricingId: String?) -> String {
        "\(tierId ?? "")|\(pricingId ?? "")"
    }

    private func discardStaleTransaction(planKey newKey: String) {
        guard collectedPlanKey != newKey else { return }
        collectedTransactionId = nil
        collectedPlanKey = nil
    }

    private func signUp(tier: AppTierModel?, pricing: AppTierPricingModel?) async {
        guard let client else { return }
        guard let resolvedAppId = appId ?? client.config.appId else { return }
        // Nothing can be registered before the form has been filled in; the step order makes this
        // unreachable, and stating it keeps the details in one place.
        guard let form = submittedForm else { return }
        errorMessage = ""
        warningMessage = ""
        subscriptionFailed = false
        discardStaleTransaction(planKey: planKey(tierId: tier?.id, pricingId: pricing?.id))
        step = .processing
        isLoading = true
        defer { isLoading = false }

        // ONE implementation of register → sign in → link → subscribe, shared with
        // `WildwoodSignupFlowModel`: the two screens must not be able to drift on the order the
        // money and the account are created in. The attempt carries this wizard's own retry
        // cache, so a failed payment or subscribe still resumes instead of re-registering.
        let attempt = SignupAccountAttempt()
        if let establishedAuth {
            attempt.registered = true
            attempt.loggedIn = true
            attempt.authResponse = establishedAuth
        }
        var request = SignupAccountRequest(
            appId: resolvedAppId,
            form: form,
            tierId: tier?.id,
            pricingId: pricing?.id,
            paymentTransactionId: collectedTransactionId,
            paymentExternalId: nil,
            tokenGrant: tokenGrant,
            platform: "ios",
            deviceInfo: PlatformDetection.deviceInfo()
        )

        do {
            // Register + login once; a retry after a failed payment/subscribe
            // reuses the established session instead of re-registering.
            if let refusal = try await SignupAccountCreator.establishSession(
                client: client, request: request, attempt: attempt
            ) {
                let message = refusal.errorMessage ?? "Registration failed. Please try again."
                errorMessage = message
                step = tokenGrant == nil ? .tierSelection : .tokenPlan
                onSignupError?(message)
                return
            }
            guard let auth = attempt.authResponse else {
                let message = "Login failed after registration. Please try logging in manually."
                errorMessage = message
                step = tokenGrant == nil ? .tierSelection : .tokenPlan
                onSignupError?(message)
                return
            }
            establishedAuth = auth

            // A token that granted a plan already paid for it (or was granted it): no payment
            // step, and — below — no self-subscribe over the grant.
            if tokenGrant == nil, let tier {
                let needsPayment = !tier.isFreeTier && (pricing?.price ?? 0) > 0
                if needsPayment, collectedTransactionId == nil, let onPaymentRequired {
                    let args = WildwoodPaymentRequiredArgs(
                        tier: tier,
                        pricing: pricing,
                        fallbackCurrency: catalogCurrency
                    )
                    guard let txnId = await onPaymentRequired(args) else {
                        step = .tierSelection
                        return
                    }
                    collectedTransactionId = txnId
                    collectedPlanKey = planKey(tierId: tier.id, pricingId: pricing?.id)
                    request.paymentTransactionId = txnId
                }
            }

            // Links the transaction to the new account and self-subscribes — never over a grant.
            let activation = await SignupAccountCreator.activatePlan(
                client: client, request: request, attempt: attempt
            )

            // A subscribe failure is non-fatal (JS parity): the account exists
            // and a session is active — the tier can be chosen later. The server's own reason
            // survives instead of being swallowed by a `try?`.
            subscriptionFailed = activation.failed
            if activation.failed {
                warningMessage = SignupPlanRules.activationWarning(activation)
                onSignupError?(activation.errorMessage ?? "The subscription could not be completed.")
            }

            let trialDays = pricing?.trialDays
            completedTrialDays = trialDays
            successMessage = SignupPlanRules.successMessage(
                tokenGrant: tokenGrant,
                accountOnly: !activation.attempted && tokenGrant == nil,
                subscriptionFailed: activation.failed,
                trialDays: trialDays
            )

            // Gate success on disclaimer acceptance. The login/registration
            // response carries any pending disclaimers (mirrors the login flow);
            // the session JWT is stored, so the disclaimer accepts are authorized.
            let completedResult = activation.result
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
            step = tokenGrant == nil ? .tierSelection : .tokenPlan
            onSignupError?(message)
        }
    }

}
#endif
