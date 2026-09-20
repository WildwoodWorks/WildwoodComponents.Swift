// The decisions the signup wizard makes about a plan: what a registration token already granted,
// whether the wizard activates a plan itself, and what the success step says.
//
// Ported from packages/wildwood-react-native/src/components/signupPlan.ts (the DOM-free twin of
// the rules @wildwood/react's SignupWithSubscriptionComponent makes inline, JS f8b095f). They live
// here rather than inside the view so they can be tested without rendering.

import Foundation
import WildwoodCore

/// What happened to the plan the wizard was asked to activate.
public struct SignupPlanActivation: Sendable, Equatable {
    /// Whether the server was asked to subscribe at all.
    public var attempted: Bool
    /// True when the subscribe was refused or failed. Non-fatal: the account exists either way.
    public var failed: Bool
    /// The refusal, as the server worded it.
    public var errorMessage: String?
    /// The change the server recorded, on the one path that produces one (a successful
    /// subscribe). Carried here rather than fished out of a captured variable so the caller can
    /// hand it to its completion callback.
    public var result: AppTierChangeResultModel?

    public init(
        attempted: Bool = false,
        failed: Bool = false,
        errorMessage: String? = nil,
        result: AppTierChangeResultModel? = nil
    ) {
        self.attempted = attempted
        self.failed = failed
        self.errorMessage = errorMessage
        self.result = result
    }

    public static func == (lhs: SignupPlanActivation, rhs: SignupPlanActivation) -> Bool {
        lhs.attempted == rhs.attempted
            && lhs.failed == rhs.failed
            && lhs.errorMessage == rhs.errorMessage
            && lhs.result == rhs.result
    }
}

public enum SignupPlanRules {
    /// The plan a registration token gives THIS app, if any.
    ///
    /// `details` is nil when the token's details could not be READ (a server older than the
    /// detailed route, a transport failure) — which is not the same as an invalid token, so a nil
    /// simply means "no grant to honour" and the wizard carries on with its normal flow and the
    /// plain validity check. App ids are compared case-insensitively: the server returns them in
    /// whichever casing it stored.
    public static func findTokenPlanGrant(
        _ details: RegistrationTokenDetails?,
        appId: String
    ) -> RegistrationTokenAppGrant? {
        guard let details, !appId.isEmpty else { return nil }
        let wanted = appId.lowercased()
        return details.appGrants.first { $0.appId.lowercased() == wanted }
    }

    /// Activate the plan the wizard chose.
    ///
    /// Two rules, both of them bugs when they were missing:
    ///
    /// 1. **Never subscribe over a token's plan.** Registering with a token that carries a plan
    ///    already subscribed the account to it; subscribing again REPLACES that subscription,
    ///    which cancels the plan the token just set up. A grant means there is nothing for the
    ///    wizard to activate.
    /// 2. **A refusal is not a failed signup.** The server answers a refused subscribe with a 4xx,
    ///    which the client throws — so a rejection is treated exactly like a `success == false`
    ///    result, and the server's own words survive. The account exists and the plan can be
    ///    activated later; the wizard says so instead of stranding the user on "Activating your
    ///    plan...".
    @MainActor
    public static func activatePlan(
        tierId: String?,
        pricingId: String?,
        tokenGrant: RegistrationTokenAppGrant?,
        paymentTransactionId: String?,
        selfSubscribe: @MainActor (String, String?, String?) async throws -> AppTierChangeResultModel
    ) async -> SignupPlanActivation {
        if tokenGrant != nil { return SignupPlanActivation() }
        guard let tierId, !tierId.isEmpty else { return SignupPlanActivation() }

        do {
            let result = try await selfSubscribe(tierId, pricingId, paymentTransactionId)
            if result.success { return SignupPlanActivation(attempted: true, result: result) }
            return SignupPlanActivation(
                attempted: true,
                failed: true,
                errorMessage: nonBlank(result.errorMessage)
            )
        } catch {
            let message = (error as? WildwoodError)?.message ?? error.localizedDescription
            return SignupPlanActivation(attempted: true, failed: true, errorMessage: nonBlank(message))
        }
    }

    /// The success step's copy, in the order the web wizard resolves it.
    ///
    /// - Parameters:
    ///   - tokenGrant: the plan a registration token set up, when the signup ran on one.
    ///   - accountOnly: true when the wizard never offered a plan at all.
    ///   - subscriptionFailed: true when ``activatePlan(tierId:pricingId:tokenGrant:paymentTransactionId:selfSubscribe:)``
    ///     reported a refusal.
    ///   - trialDays: free-trial days on the plan that was paid for, if any.
    public static func successMessage(
        tokenGrant: RegistrationTokenAppGrant?,
        accountOnly: Bool,
        subscriptionFailed: Bool,
        trialDays: Int? = nil
    ) -> String {
        if let tokenGrant {
            let planName = nonBlank(tokenGrant.appTierName) ?? "plan"
            return "Your account has been created with the \(planName) from your registration token."
        }
        if accountOnly { return "Your account has been created successfully." }
        if subscriptionFailed {
            return "Your account is ready! Plan activation is pending \u{2014} you can select a plan from your dashboard."
        }
        if let trialDays, trialDays > 0 {
            return "Your account has been created and your \(trialDays)-day free trial has started."
        }
        return "Your account has been created and your plan is active."
    }

    /// The warning shown alongside the success step when the plan could not be activated. The
    /// server's reason is kept — a generic sentence hides "that tier is closed to new signups".
    public static func activationWarning(_ activation: SignupPlanActivation) -> String {
        let base = "Your account is ready! Plan activation is pending \u{2014} you can select a plan from your dashboard."
        guard let reason = nonBlank(activation.errorMessage) else { return base }
        return base + " (\(reason))"
    }

    static func nonBlank(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}
