// Everything PaymentComponent decides that is not a view: how the initiation request is built,
// when a previous initiation may be reused, and what the button and its note say.
//
// Ported from packages/wildwood-react-native/src/components/paymentSession.ts (the DOM-free twin
// of @wildwood/react's PaymentComponent, JS f8b095f / 05dd7cb) with the Stripe.js half left out:
// this package takes no payment SDK dependency of its own. What confirms a client secret is the
// host-injected ``WildwoodPaymentActionHandler``, and everything here turns on whether one exists.
// With NO handler the model never sends `supportsSetupIntent` and confirms nothing, because a
// SetupIntent nothing can confirm leaves a trial with no saved card and a plan that renews into a
// failed charge. With one, the flag goes up and the secret is routed by its TYPE: a `setup_intent`
// to `confirmCardSetup`, a payment intent to `confirmPayment`.

import Foundation
import Observation
import WildwoodCore

/// One press of the pay button, resolved from the component's parameters and the provider choice.
public struct WildwoodPaymentAttempt: Sendable, Equatable {
    public var providerId: String
    public var appId: String
    public var amount: Double
    public var currency: String?
    public var description: String?
    public var customerId: String?
    public var customerEmail: String?
    public var orderId: String?
    public var subscriptionId: String?
    /// The pricing MODEL id. Without it the server charges once and no subscription is created.
    public var pricingModelId: String?
    public var billingFrequency: String?
    public var returnUrl: String?
    public var cancelUrl: String?
    public var metadata: [String: String]?
    public var isSubscription: Bool
    /// Free-trial days the plan advertises, for the button copy.
    public var trialDays: Int?

    public init(
        providerId: String,
        appId: String,
        amount: Double,
        currency: String? = nil,
        description: String? = nil,
        customerId: String? = nil,
        customerEmail: String? = nil,
        orderId: String? = nil,
        subscriptionId: String? = nil,
        pricingModelId: String? = nil,
        billingFrequency: String? = nil,
        returnUrl: String? = nil,
        cancelUrl: String? = nil,
        metadata: [String: String]? = nil,
        isSubscription: Bool = false,
        trialDays: Int? = nil
    ) {
        self.providerId = providerId
        self.appId = appId
        self.amount = amount
        self.currency = currency
        self.description = description
        self.customerId = customerId
        self.customerEmail = customerEmail
        self.orderId = orderId
        self.subscriptionId = subscriptionId
        self.pricingModelId = pricingModelId
        self.billingFrequency = billingFrequency
        self.returnUrl = returnUrl
        self.cancelUrl = cancelUrl
        self.metadata = metadata
        self.isSubscription = isSubscription
        self.trialDays = trialDays
    }

    public static func == (lhs: WildwoodPaymentAttempt, rhs: WildwoodPaymentAttempt) -> Bool {
        lhs.providerId == rhs.providerId
            && lhs.appId == rhs.appId
            && lhs.amount == rhs.amount
            && lhs.currency == rhs.currency
            && lhs.description == rhs.description
            && lhs.customerId == rhs.customerId
            && lhs.customerEmail == rhs.customerEmail
            && lhs.orderId == rhs.orderId
            && lhs.subscriptionId == rhs.subscriptionId
            && lhs.pricingModelId == rhs.pricingModelId
            && lhs.billingFrequency == rhs.billingFrequency
            && lhs.returnUrl == rhs.returnUrl
            && lhs.cancelUrl == rhs.cancelUrl
            && lhs.metadata == rhs.metadata
            && lhs.isSubscription == rhs.isSubscription
            && lhs.trialDays == rhs.trialDays
    }
}

@MainActor
@Observable
public final class WildwoodPaymentModel {
    @ObservationIgnored private let payment: PaymentService
    /// What can put a bank's challenge or a card sheet in front of the customer, when the host
    /// supplied anything that can. Nil is the supported default.
    @ObservationIgnored private let handler: (any WildwoodPaymentActionHandler)?

    /// The initiation a previous press left behind, and the key it was made for.
    @ObservationIgnored private var pendingIntentKey: String?
    @ObservationIgnored private var pendingIntent: InitiatePaymentResponse?
    /// The plan the current pending initiation was made for.
    @ObservationIgnored private var currentPlanKey: String?

    public init(payment: PaymentService, paymentActionHandler: (any WildwoodPaymentActionHandler)? = nil) {
        self.payment = payment
        self.handler = paymentActionHandler
    }

    /// Whether the server may be asked for a trial's SetupIntent.
    ///
    /// Only a client that can CONFIRM one may ask for one: a SetupIntent nothing confirms leaves a
    /// trial with no saved card and a plan that renews into a failed charge. So this is the
    /// handler's own answer, not merely "is there a handler".
    public var supportsSetupIntent: Bool {
        RegistrationSubscriptionRules.mayCollectCardInApp(handler)
    }

    /// Whether a bank challenge on a charge can be answered at all.
    public var supportsPaymentAction: Bool {
        RegistrationSubscriptionRules.maySendSupportsPaymentAction(handler)
    }

    /// The initiation a retry may reuse. Keyed, because reusing it for a DIFFERENT plan or amount
    /// would charge the wrong thing — and creating a new one for the SAME plan starts a second
    /// subscription that nobody cancels, which is exactly what tapping Pay Now twice used to do.
    public static func intentKey(_ attempt: WildwoodPaymentAttempt) -> String {
        [
            attempt.providerId,
            attempt.pricingModelId ?? "",
            String(attempt.amount),
            attempt.isSubscription ? "sub" : "once",
        ].joined(separator: "|")
    }

    /// The plan a form is currently offering. Changing it drops the reusable initiation.
    public static func planKey(_ attempt: WildwoodPaymentAttempt) -> String {
        [attempt.pricingModelId ?? "", String(attempt.trialDays ?? 0), String(attempt.amount)].joined(separator: "|")
    }

    /// The request the attempt posts, as THIS model would post it — which is the only form that
    /// may carry `supportsSetupIntent`, because only this model knows whether a handler exists.
    public func makeRequest(_ attempt: WildwoodPaymentAttempt) -> InitiatePaymentRequest {
        Self.makeRequest(attempt, supportsSetupIntent: supportsSetupIntent)
    }

    /// The request the attempt posts.
    ///
    /// `supportsSetupIntent` is left off entirely unless the caller can confirm one: asking for a
    /// SetupIntent nothing can confirm leaves a trial with no saved card and a plan that renews
    /// into a failed charge. It goes up only as `true`, never as an explicit `false` — an older
    /// server rejects an unknown property, and the server's own default is the old behaviour.
    public static func makeRequest(
        _ attempt: WildwoodPaymentAttempt,
        supportsSetupIntent: Bool = false
    ) -> InitiatePaymentRequest {
        InitiatePaymentRequest(
            providerId: attempt.providerId,
            appId: attempt.appId,
            amount: attempt.amount,
            currency: attempt.currency,
            description: attempt.description,
            customerId: attempt.customerId,
            customerEmail: attempt.customerEmail,
            orderId: attempt.orderId,
            subscriptionId: attempt.subscriptionId,
            pricingModelId: attempt.pricingModelId,
            isSubscription: attempt.isSubscription ? true : nil,
            billingFrequency: attempt.billingFrequency,
            returnUrl: attempt.returnUrl,
            cancelUrl: attempt.cancelUrl,
            metadata: attempt.metadata,
            billingAddress: nil,
            supportsSetupIntent: supportsSetupIntent ? true : nil
        )
    }

    /// Tell the model which plan the form is showing. A different plan invalidates the reusable
    /// initiation, so the next press prices the new plan.
    public func setPlan(_ attempt: WildwoodPaymentAttempt) {
        let key = Self.planKey(attempt)
        if currentPlanKey == key { return }
        currentPlanKey = key
        clearPendingIntent()
    }

    /// Start (or reuse) the payment. A second press for the same provider, plan, amount and
    /// subscription-ness confirms the intent the first press created instead of creating another.
    public func initiate(_ attempt: WildwoodPaymentAttempt) async throws -> InitiatePaymentResponse {
        let key = Self.intentKey(attempt)
        if pendingIntentKey == key, let pendingIntent {
            return pendingIntent
        }
        let response = try await payment.initiatePayment(makeRequest(attempt))
        if response.success {
            pendingIntentKey = key
            pendingIntent = response
        }
        return response
    }

    /// Put the initiation's client secret to the customer, when there is one and something here
    /// can answer it.
    ///
    /// The secret's TYPE decides which way it goes: a `setup_intent` saves a card for a trial and
    /// goes to ``WildwoodPaymentActionHandler/confirmCardSetup(clientSecret:publishableKey:)``, a
    /// payment intent is a charge and goes to
    /// ``WildwoodPaymentActionHandler/confirmPayment(clientSecret:publishableKey:)``. Confirming
    /// a SetupIntent as a payment charges nothing and saves nothing, which is why the type is read
    /// rather than assumed.
    ///
    /// Answers nil when there is nothing to confirm or nobody to confirm it — the caller then
    /// carries on with whatever path it had before a handler existed, which is what every host
    /// without one already does.
    public func confirmIntent(
        _ response: InitiatePaymentResponse,
        publishableKey: String?
    ) async -> PaymentActionOutcome? {
        guard let handler = self.handler else { return nil }
        let clientSecret: String = response.clientSecret ?? ""
        guard !clientSecret.isEmpty else { return nil }

        if response.clientSecretType == PaymentClientSecretTypes.setupIntent {
            guard handler.supportsCardSetup else { return nil }
            return await handler.confirmCardSetup(clientSecret: clientSecret, publishableKey: publishableKey)
        }
        return await handler.confirmPayment(clientSecret: clientSecret, publishableKey: publishableKey)
    }

    /// Drop the reusable initiation — after a completed payment, or when the plan changes.
    public func clearPendingIntent() {
        pendingIntentKey = nil
        pendingIntent = nil
    }

    /// Whether the form is offering a trial rather than a charge.
    public static func hasTrialOffer(trialDays: Int?) -> Bool {
        (trialDays ?? 0) > 0
    }

    /// The pay button: a trial is started, not bought.
    public static func payButtonLabel(amount: Double, currency: String?, trialDays: Int?) -> String {
        if hasTrialOffer(trialDays: trialDays) {
            return "Start \(WildwoodTrial.label(days: trialDays))"
        }
        if !(amount > 0) { return "Pay" }
        return "Pay \(WildwoodMoney.format(amount, currency: currency))"
    }

    /// The note under a trial's button: what is NOT happening today, and what happens later.
    public static func trialChargeNote(amount: Double, currency: String?) -> String {
        "You won't be charged today. \(WildwoodMoney.format(amount, currency: currency)) is due when the trial ends unless you cancel before then."
    }
}
