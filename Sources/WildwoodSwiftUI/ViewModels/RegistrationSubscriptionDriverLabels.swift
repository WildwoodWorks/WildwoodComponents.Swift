// The copy the drivers themselves produce — now a name for the full set.
//
// A driver puts a handful of these strings into a state field or an `onError` message, which is
// why this type existed before any view did: a message the driver stores has to be worded before
// anything is on screen. The views then arrived with a slice each, and all of them merged into
// ``RegistrationSubscriptionLabels`` — so this is that type, under the name the drivers use.
//
// Internal on purpose: a host overrides copy through a VIEW's `labels` parameter, which hands the
// whole set down to whichever drivers that view owns.

import Foundation

/// The drivers' overridable copy: ``RegistrationSubscriptionLabels`` under the name the drivers
/// use.
typealias RegistrationSubscriptionDriverLabels = RegistrationSubscriptionLabels

/// The sentences the drivers fall back to when neither the server nor a label says anything. JS
/// keeps these as module constants next to the flow that raises them; they are not host-overridable
/// there either.
enum RegistrationSubscriptionDriverMessages {
    /// A pack's own 3-D Secure could not be put to the customer at all.
    static let packUnconfirmed = "This pack could not be confirmed with your bank."
    /// It was put to them and came back refused.
    static let cardUnconfirmed = "Your card was not confirmed."
    /// The server would not hand out a SetupIntent.
    static let cardUnavailable = "A card could not be collected right now."
    /// The plan change could not be priced.
    static let previewRefused = "The plan change could not be priced."
    /// The plan change was refused and no reason came with it.
    static let changeRefused = "The plan change was refused."
    /// The completion threw rather than answering.
    static let completionRefused = "The plan change could not be completed."
    /// The bank challenge could not be put to the customer, or came back refused.
    static let chargeUnconfirmed = "The charge could not be confirmed with your bank. Your plan has not changed."
    /// The host's own payment handler threw.
    static let paymentNotTaken = "The payment could not be taken."
    /// The catalog could not be read.
    static let catalogUnavailable = "Pricing is unavailable right now"
    /// A registration token the server rejected without saying why.
    static let tokenRejected = "Invalid or expired registration token"
    /// The signup stopped and nothing named a reason.
    static let signupFailed = "Signup failed. Please try again."
    /// The server refused the registration without saying why.
    static let registrationRefused = "Registration failed. Please try again."
    /// The sign-in after a registration answered no token.
    static let loginFailed = "Login failed after registration. Please try logging in manually."
    /// The subscription could not be cancelled, and nothing more specific came back.
    static let cancelRefused = "The subscription could not be cancelled."
    /// A pack could not be cancelled, and nothing more specific came back.
    static let packCancelRefused = "The pack could not be cancelled."
    /// A scheduled pack cancellation could not be taken back.
    static let packReactivateRefused = "The pack could not be reactivated."
}
