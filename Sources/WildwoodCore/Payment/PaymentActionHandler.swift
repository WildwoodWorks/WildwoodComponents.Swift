// The seam between a flow that has to get an intent confirmed and whatever can confirm it.
//
// This package takes NO payment SDK dependency — not Stripe's iOS SDK, not a web view wrapper,
// nothing. A card sheet and a bank's 3-D Secure challenge need a native module, merchant
// configuration and a rebuild, so they cannot be something every consumer inherits by adding one
// Swift package. The one thing the flows cannot do for themselves is therefore INJECTED, exactly
// as `FeedbackComponent`'s screenshot source and `AuthenticationComponent`'s provider sign-in are.
//
// A host that already ships the Stripe iOS SDK implements this in about twenty lines over
// `STPPaymentHandler`. A host that ships none supplies nothing, which is a supported state and the
// default: WITHOUT a handler the flows never tell the server they can confirm an intent
// (`SupportsPaymentAction` and `supportsSetupIntent` are not sent, and no checkout payment method
// is created), they offer an in-app pack purchase only when the server's quote says a card is
// already on file, and a `requires_action` answer that arrives anyway is reported as NOT COMPLETED
// with the "finish this purchase on the web" copy — never as a silent failure and never as a throw.
//
// Ported from packages/wildwood-react-shared/src/registrationSubscription/paymentActions.ts.

import Foundation

/// What became of one confirmation.
///
/// ``cancelled`` is the customer dismissing the sheet: not a failure, and it carries no message to
/// show them. ``failed`` always carries one, even the empty string, so a caller can fall back to
/// its own words.
public enum PaymentActionOutcome: Sendable, Equatable {
    case succeeded
    case failed(message: String)
    case cancelled

    /// The message to show, or nil when there is nothing to say (a success, or a deliberate
    /// cancel). An empty failure message reads as "nothing to say" too, so the caller's own copy
    /// wins rather than an empty alert.
    public var failureMessage: String? {
        guard case .failed(let message) = self, !message.isEmpty else { return nil }
        return message
    }

    public var isSucceeded: Bool {
        if case .succeeded = self { return true }
        return false
    }

    /// Written out rather than synthesised, so a payload that stops being Equatable is a compile
    /// error here rather than a silently dropped conformance.
    public static func == (lhs: PaymentActionOutcome, rhs: PaymentActionOutcome) -> Bool {
        switch (lhs, rhs) {
        case (.succeeded, .succeeded):
            return true
        case (.cancelled, .cancelled):
            return true
        case (.failed(let left), .failed(let right)):
            return left == right
        case (.succeeded, _), (.cancelled, _), (.failed, _):
            return false
        }
    }
}

/// What a host plugs in so the flows can have an intent confirmed.
///
/// `Sendable` with `async` requirements: a handler is read on the main actor and awaited from
/// there, but nothing about it is main-actor bound, so a handler that does its work off the main
/// actor is free to.
///
/// ## Handlers that can only confirm a payment
///
/// ``confirmCardSetup(clientSecret:publishableKey:)`` is a full requirement — every handler has to
/// write it, so nobody conforms without deciding what a SetupIntent should do. A host whose SDK
/// integration can only answer a 3-D Secure challenge returns
/// ``PaymentActionOutcome/failed(message:)`` from it AND overrides ``supportsCardSetup`` to false.
/// That flag is what the flows read before they ask the server for a SetupIntent at all: a saved
/// card nothing can confirm leaves a trial with no card and a renewal that fails, so it is never
/// requested speculatively.
public protocol WildwoodPaymentActionHandler: Sendable {
    /// Confirm a PaymentIntent — 3-D Secure on a prorated plan change, or on one pack of a
    /// checkout — for a card already on file.
    func confirmPayment(clientSecret: String, publishableKey: String?) async -> PaymentActionOutcome

    /// Confirm a SetupIntent that saves a card: the one-off card entry a pack checkout needs, and
    /// the card a free trial is set up with.
    func confirmCardSetup(clientSecret: String, publishableKey: String?) async -> PaymentActionOutcome

    /// Whether ``confirmCardSetup(clientSecret:publishableKey:)`` can really run. Defaults to
    /// true; a payment-only handler overrides it to false.
    var supportsCardSetup: Bool { get }
}

public extension WildwoodPaymentActionHandler {
    var supportsCardSetup: Bool { true }
}

/// Which Stripe account an intent belongs to.
///
/// Two lookups, because the two flows ask different questions, and both are the JS rule verbatim:
/// a plan change asks for the app's DEFAULT Stripe provider, while a pack checkout asks for the
/// provider the server's own quote named.
public enum WildwoodPublishableKey {
    /// The app's default Stripe provider's publishable key: the one `defaultProviderId` names,
    /// else the one flagged `isDefault`, else the first — considering only enabled Stripe
    /// providers that actually carry a key.
    public static func defaultStripe(_ configuration: AppPaymentConfigurationDto?) -> String? {
        guard let configuration else { return nil }

        var candidates: [PaymentProviderDto] = []
        for provider in configuration.providers where isUsableStripe(provider) {
            candidates.append(provider)
        }
        if candidates.isEmpty { return nil }

        if let defaultId = configuration.defaultProviderId, !defaultId.isEmpty {
            for provider in candidates where provider.id == defaultId {
                return provider.publishableKey
            }
        }
        for provider in candidates where provider.isDefault {
            return provider.publishableKey
        }
        return candidates[0].publishableKey
    }

    /// The publishable key of the provider a quote named, else the first enabled provider that
    /// carries one. Matches the JS pack-checkout lookup, which does not filter by provider type:
    /// the quote already chose the provider, so honouring it is the point.
    public static func forProvider(
        _ configuration: AppPaymentConfigurationDto?,
        providerId: String?
    ) -> String? {
        guard let configuration else { return nil }

        if let providerId, !providerId.isEmpty {
            for provider in configuration.providers where provider.id == providerId {
                return provider.publishableKey
            }
        }
        for provider in configuration.providers
        where provider.isEnabled && !(provider.publishableKey ?? "").isEmpty {
            return provider.publishableKey
        }
        return nil
    }

    private static func isUsableStripe(_ provider: PaymentProviderDto) -> Bool {
        guard provider.resolvedProviderType == PaymentProviderType.stripe else { return false }
        guard provider.isEnabled else { return false }
        return !(provider.publishableKey ?? "").isEmpty
    }
}
