// The four server calls that turn a filled-in registration form into a signed-in account on a
// plan: register, log in, attach the payment, start the subscription.
//
// This is JS's `runSignup` + `activatePlan`
// (packages/wildwood-react-shared/src/registrationSubscription/useSignupFlow.ts), and the .NET
// `SignupAccountCreator` — lifted OUT of `SignupWithSubscriptionComponent` rather than copied, so
// the old wizard and the new signup driver create accounts by exactly one route. Behaviour is the
// wizard's, unchanged.
//
// Three rules are load-bearing:
//
//  · A retry RESUMES, it does not re-register. What is already done lives on the caller's
//    ``SignupAccountAttempt``, which is handed back in on the next attempt, so a card that was
//    already charged is not charged again and an account that exists is not created again.
//
//  · A registration token that carries a plan ALREADY subscribed the account. Subscribing over it
//    REPLACES the subscription the token just created, so a grant suppresses the self-subscribe
//    entirely (``SignupPlanRules/activatePlan(tierId:pricingId:tokenGrant:paymentTransactionId:selfSubscribe:)``).
//
//  · Linking the payment and starting the plan are NEVER fatal. The account exists and the money
//    is taken; a plan can be activated from the dashboard, and the outcome says so.
//
// Split in two on purpose. The pay-first order runs the whole thing in one go
// (``create(client:request:attempt:onStep:)``); the account-first order — the native default, and
// what the old wizard already did — runs ``establishSession(client:request:attempt:onStep:)``,
// takes the card once there is an account to attach it to, and only then
// ``activatePlan(client:request:attempt:onStep:)``.

import Foundation
import WildwoodCore

/// Which call the creator is about to make, so a caller can word its own status line. A typed step
/// rather than a string keeps the copy with the view that shows it.
public enum SignupAccountStep: String, Sendable, Equatable, CaseIterable {
    case registering
    case signingIn
    case activatingPlan
}

/// What one signup attempt is asked to create.
public struct SignupAccountRequest: Sendable, Equatable {
    public var appId: String
    /// The registration form as the visitor filled it in.
    public var form: RegistrationFormData
    /// The plan to subscribe to, or nil when the signup chose none.
    public var tierId: String?
    /// The pricing option within that plan.
    public var pricingId: String?
    /// The transaction to subscribe with — what the plan's card produced.
    public var paymentTransactionId: String?
    /// The provider's own id for that payment, which is what the server looks a transaction up by
    /// when it is attached to the new user.
    public var paymentExternalId: String?
    /// The plan this app's registration token carries, when it carries one. Present, nothing is
    /// self-subscribed: the token's registration already did it.
    public var tokenGrant: RegistrationTokenAppGrant?
    /// What the registration is told it was made from.
    public var platform: String
    /// The device the registration is told about.
    public var deviceInfo: String

    public init(
        appId: String,
        form: RegistrationFormData,
        tierId: String? = nil,
        pricingId: String? = nil,
        paymentTransactionId: String? = nil,
        paymentExternalId: String? = nil,
        tokenGrant: RegistrationTokenAppGrant? = nil,
        platform: String = "ios",
        deviceInfo: String = ""
    ) {
        self.appId = appId
        self.form = form
        self.tierId = tierId
        self.pricingId = pricingId
        self.paymentTransactionId = paymentTransactionId
        self.paymentExternalId = paymentExternalId
        self.tokenGrant = tokenGrant
        self.platform = platform
        self.deviceInfo = deviceInfo
    }

    public static func == (lhs: SignupAccountRequest, rhs: SignupAccountRequest) -> Bool {
        lhs.appId == rhs.appId
            && lhs.form == rhs.form
            && lhs.tierId == rhs.tierId
            && lhs.pricingId == rhs.pricingId
            && lhs.paymentTransactionId == rhs.paymentTransactionId
            && lhs.paymentExternalId == rhs.paymentExternalId
            && lhs.tokenGrant == rhs.tokenGrant
            && lhs.platform == rhs.platform
            && lhs.deviceInfo == rhs.deviceInfo
    }
}

/// How far a signup got. A reference type, and held by the caller, so "Try Again" resumes rather
/// than registering the same person twice.
@MainActor
public final class SignupAccountAttempt {
    /// The account exists.
    public internal(set) var registered: Bool = false
    /// The session is stored.
    public internal(set) var loggedIn: Bool = false
    /// The plan could not be started. Never fatal; the success copy says so.
    public internal(set) var subscriptionFailed: Bool = false
    /// Whether the plan was activated (or deliberately left to a grant) at all.
    public internal(set) var planActivated: Bool = false
    /// The sign-in response, which carries the JWT and any pending disclaimers.
    public internal(set) var authResponse: AuthenticationResponse?
    /// The refusal the activation reported, in the server's own words.
    public internal(set) var activation: SignupPlanActivation = SignupPlanActivation()

    public init() {}

    /// Throws the attempt away — what "Start Over" does.
    public func reset() {
        registered = false
        loggedIn = false
        subscriptionFailed = false
        planActivated = false
        authResponse = nil
        activation = SignupPlanActivation()
    }
}

/// What one signup attempt produced.
public struct SignupAccountResult: Sendable, Equatable {
    /// The account exists and is signed in.
    public var success: Bool
    /// The refusal, in the server's own words where it sent any.
    public var errorMessage: String?
    /// One of ``RegistrationSubscriptionErrorCodes``, when the attempt was refused.
    public var errorCode: String?
    /// The sign-in response, on success.
    public var authResponse: AuthenticationResponse?
    /// The new account's id, or an empty string when the sign-in carried none.
    public var userId: String
    /// The plan could not be started, so its activation is pending.
    public var subscriptionFailed: Bool
    /// The sign-in reported disclaimers the new account has to accept before it is finished.
    public var requiresDisclaimers: Bool

    public init(
        success: Bool = false,
        errorMessage: String? = nil,
        errorCode: String? = nil,
        authResponse: AuthenticationResponse? = nil,
        userId: String = "",
        subscriptionFailed: Bool = false,
        requiresDisclaimers: Bool = false
    ) {
        self.success = success
        self.errorMessage = errorMessage
        self.errorCode = errorCode
        self.authResponse = authResponse
        self.userId = userId
        self.subscriptionFailed = subscriptionFailed
        self.requiresDisclaimers = requiresDisclaimers
    }

    public static func == (lhs: SignupAccountResult, rhs: SignupAccountResult) -> Bool {
        lhs.success == rhs.success
            && lhs.errorMessage == rhs.errorMessage
            && lhs.errorCode == rhs.errorCode
            && lhs.authResponse == rhs.authResponse
            && lhs.userId == rhs.userId
            && lhs.subscriptionFailed == rhs.subscriptionFailed
            && lhs.requiresDisclaimers == rhs.requiresDisclaimers
    }
}

@MainActor
public enum SignupAccountCreator {
    /// Register, sign in, link the plan's payment and start the subscription, resuming at
    /// whichever of those `attempt` says is still outstanding.
    ///
    /// - Throws: whatever the transport threw. A refusal the server EXPLAINED comes back as an
    ///   unsuccessful ``SignupAccountResult`` instead, so a caller can tell "the server said no"
    ///   from "the call did not happen".
    @discardableResult
    public static func create(
        client: WildwoodClient,
        request: SignupAccountRequest,
        attempt: SignupAccountAttempt,
        onStep: ((SignupAccountStep) -> Void)? = nil
    ) async throws -> SignupAccountResult {
        if let refusal = try await establishSession(
            client: client, request: request, attempt: attempt, onStep: onStep
        ) {
            return refusal
        }
        await activatePlan(client: client, request: request, attempt: attempt, onStep: onStep)
        return settled(attempt)
    }

    /// The half that creates the account and the session. Answers nil when it worked, and the
    /// refusal otherwise.
    public static func establishSession(
        client: WildwoodClient,
        request: SignupAccountRequest,
        attempt: SignupAccountAttempt,
        onStep: ((SignupAccountStep) -> Void)? = nil
    ) async throws -> SignupAccountResult? {
        if !attempt.registered {
            if let refusal = try await register(client: client, request: request, attempt: attempt, onStep: onStep) {
                return refusal
            }
        }
        if !attempt.loggedIn {
            if let refusal = try await signIn(client: client, request: request, attempt: attempt, onStep: onStep) {
                return refusal
            }
        }
        return nil
    }

    /// The half that spends the money: attach the payment to the account that now exists, then
    /// start the plan. Never throws and never fatal — the account is already there.
    @discardableResult
    public static func activatePlan(
        client: WildwoodClient,
        request: SignupAccountRequest,
        attempt: SignupAccountAttempt,
        onStep: ((SignupAccountStep) -> Void)? = nil
    ) async -> SignupPlanActivation {
        await linkPayment(client: client, request: request, attempt: attempt)

        // A granted plan is already subscribed by the token's registration; a signup that chose no
        // plan has nothing to start. Neither raises the status line.
        let subscribes: Bool = request.tokenGrant == nil && !(request.tierId ?? "").isEmpty
        if subscribes { onStep?(.activatingPlan) }

        let appId: String = request.appId
        let paymentTransactionId: String? = request.paymentTransactionId
        let activation: SignupPlanActivation = await SignupPlanRules.activatePlan(
            tierId: request.tokenGrant == nil ? request.tierId : nil,
            pricingId: request.pricingId,
            tokenGrant: request.tokenGrant,
            paymentTransactionId: paymentTransactionId,
            selfSubscribe: { tierId, pricingId, transactionId in
                try await client.appTier.selfSubscribe(
                    appId: appId,
                    appTierId: tierId,
                    appTierPricingId: pricingId,
                    paymentTransactionId: transactionId
                )
            }
        )

        attempt.activation = activation
        attempt.planActivated = true
        if activation.failed { attempt.subscriptionFailed = true }
        return activation
    }

    /// The result an attempt whose session is established reports.
    public static func settled(_ attempt: SignupAccountAttempt) -> SignupAccountResult {
        let auth: AuthenticationResponse? = attempt.authResponse
        let pendingCount: Int = auth?.pendingDisclaimers?.count ?? 0
        let requiresDisclaimers: Bool = (auth?.requiresDisclaimerAcceptance ?? false) && pendingCount > 0
        // The two id fields carry the same value on a real response; the fallback is for a server
        // (or a fixture) that filled only one of them in.
        let resolvedUserId: String = SignupPlanRules.nonBlank(auth?.id) ?? auth?.userId ?? ""
        return SignupAccountResult(
            success: true,
            errorMessage: nil,
            errorCode: nil,
            authResponse: auth,
            userId: resolvedUserId,
            subscriptionFailed: attempt.subscriptionFailed,
            requiresDisclaimers: requiresDisclaimers
        )
    }

    // MARK: - Steps

    private static func register(
        client: WildwoodClient,
        request: SignupAccountRequest,
        attempt: SignupAccountAttempt,
        onStep: ((SignupAccountStep) -> Void)?
    ) async throws -> SignupAccountResult? {
        onStep?(.registering)

        let form: RegistrationFormData = request.form
        let token: String = form.registrationToken ?? ""
        let usesToken: Bool = form.useToken && !token.isEmpty
        let registration = RegistrationRequest(
            email: form.email,
            username: form.username.isEmpty ? form.email : form.username,
            firstName: form.firstName,
            lastName: form.lastName,
            password: form.password,
            appId: request.appId,
            platform: request.platform,
            deviceInfo: request.deviceInfo,
            registrationToken: usesToken ? token : nil
        )

        if usesToken {
            let response: AuthenticationResponse = try await client.auth.registerWithToken(registration)
            attempt.registered = true
            // Some token registrations answer with tokens; use them rather than signing in again.
            if !response.jwtToken.isEmpty {
                client.session.login(response)
                attempt.authResponse = response
                attempt.loggedIn = true
            }
            return nil
        }

        let result: OpenRegistrationResult = try await client.auth.registerOpen(registration)
        guard result.success else {
            let message: String = SignupPlanRules.nonBlank(result.message)
                ?? RegistrationSubscriptionDriverMessages.registrationRefused
            let code: String = SignupPlanRules.nonBlank(result.errorCode)
                ?? RegistrationSubscriptionErrorCodes.registrationRefused
            return SignupAccountResult(success: false, errorMessage: message, errorCode: code)
        }
        attempt.registered = true
        return nil
    }

    private static func signIn(
        client: WildwoodClient,
        request: SignupAccountRequest,
        attempt: SignupAccountAttempt,
        onStep: ((SignupAccountStep) -> Void)?
    ) async throws -> SignupAccountResult? {
        onStep?(.signingIn)

        let form: RegistrationFormData = request.form
        let response: AuthenticationResponse = try await client.auth.login(
            LoginRequest(
                username: form.username.isEmpty ? form.email : form.username,
                email: form.email,
                password: form.password,
                appId: request.appId,
                platform: request.platform,
                deviceInfo: request.deviceInfo
            )
        )

        guard !response.jwtToken.isEmpty else {
            return SignupAccountResult(
                success: false,
                errorMessage: RegistrationSubscriptionDriverMessages.loginFailed,
                errorCode: RegistrationSubscriptionErrorCodes.loginFailed
            )
        }

        // Only once a session is really stored: the disclaimer step's accepts are authenticated.
        client.session.login(response)
        attempt.authResponse = response
        attempt.loggedIn = true
        return nil
    }

    /// Attach the plan's payment to the account that now exists. The card may have been taken
    /// before there was an account, so the transaction belongs to nobody until now. Non-fatal: the
    /// payment succeeded and the link can be repaired later.
    private static func linkPayment(
        client: WildwoodClient,
        request: SignupAccountRequest,
        attempt: SignupAccountAttempt
    ) async {
        let linkId: String = request.paymentExternalId ?? request.paymentTransactionId ?? ""
        guard !linkId.isEmpty else { return }
        let userId: String = client.session.userId ?? attempt.authResponse?.id ?? ""
        guard !userId.isEmpty else { return }
        _ = await client.payment.linkTransactionToUser(externalTransactionId: linkId, userId: userId)
    }
}
