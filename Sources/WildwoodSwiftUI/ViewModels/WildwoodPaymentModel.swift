// Everything PaymentComponent decides that is not a view: how the initiation request is built,
// when a previous initiation may be reused, and what the button and its note say.
//
// Ported from packages/wildwood-react-native/src/components/paymentSession.ts (the DOM-free twin
// of @wildwood/react's PaymentComponent, JS f8b095f / 05dd7cb) with the Stripe.js half left out:
// this package takes no payment SDK dependency, so there is nothing here that confirms a client
// secret. The host-injected payment-action seam that will confirm one is a later change; until it
// exists this model NEVER sends `supportsSetupIntent`, because a SetupIntent nothing can confirm
// leaves a trial with no saved card and the plan renews into a failed charge.

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

    /// The initiation a previous press left behind, and the key it was made for.
    @ObservationIgnored private var pendingIntentKey: String?
    @ObservationIgnored private var pendingIntent: InitiatePaymentResponse?
    /// The plan the current pending initiation was made for.
    @ObservationIgnored private var currentPlanKey: String?

    public init(payment: PaymentService) {
        self.payment = payment
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

    /// The request the attempt posts.
    ///
    /// `supportsSetupIntent` is deliberately never set: only a client that can confirm a
    /// SetupIntent may ask the server for one.
    public static func makeRequest(_ attempt: WildwoodPaymentAttempt) -> InitiatePaymentRequest {
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
            metadata: attempt.metadata
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
        let response = try await payment.initiatePayment(Self.makeRequest(attempt))
        if response.success {
            pendingIntentKey = key
            pendingIntent = response
        }
        return response
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
