// What the registration and subscription drivers report when they give up on something, and the
// stable codes they report it under.
//
// The codes are the JS ones verbatim (`packages/wildwood-react-shared/src/registrationSubscription`
// and the React component's `onError`), because a host that routes on them must not have to learn a
// second vocabulary per stack. A server error code, when the server sent one, always wins over
// these — they are the fallback for a failure the server did not name.

import Foundation
import WildwoodCore

/// A failure, as a code a host can branch on and a message it can show.
public struct RegistrationSubscriptionError: Sendable, Equatable {
    /// The server's own `errorCode` when it sent one, else one of
    /// ``RegistrationSubscriptionErrorCodes``.
    public var code: String
    /// What to show the customer. Never empty by the time a host sees it.
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public static func == (lhs: RegistrationSubscriptionError, rhs: RegistrationSubscriptionError) -> Bool {
        lhs.code == rhs.code && lhs.message == rhs.message
    }
}

/// The codes the drivers supply when the server named no reason of its own.
public enum RegistrationSubscriptionErrorCodes {
    /// The public catalog could not be read, so no price may be shown.
    public static let catalogUnavailable = "catalog_unavailable"
    /// The server said the registration token is not valid.
    public static let registrationTokenRejected = "registration_token_rejected"
    /// The account could not be created, and nothing more specific came back.
    public static let signupFailed = "signup_failed"
    /// The server refused the registration itself.
    public static let registrationRefused = "registration_refused"
    /// The sign-in that follows a registration answered no token.
    public static let loginFailed = "login_failed"

    /// The basket could not be priced.
    public static let packQuoteFailed = "pack_quote_failed"
    /// A card could not be collected for the basket.
    public static let packCardFailed = "pack_card_failed"
    /// The basket could not be bought.
    public static let packCheckoutFailed = "pack_checkout_failed"

    /// The plan change could not be priced.
    public static let tierPreviewFailed = "tier_preview_failed"
    /// The prorated charge could not be confirmed with the bank.
    public static let tierChangeAuthenticationFailed = "tier_change_authentication_failed"
    /// The parked change could not be finished.
    public static let tierChangeCompletionFailed = "tier_change_completion_failed"
    /// Anything else that stopped a plan change.
    public static let tierChangeFailed = "tier_change_failed"
}
