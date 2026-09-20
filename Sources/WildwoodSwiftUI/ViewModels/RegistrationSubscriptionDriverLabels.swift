// The handful of strings the drivers themselves produce.
//
// The full overridable copy set — every heading, button and status line the views say — is
// `RegistrationSubscriptionLabels`, which ships with the views. This is the subset a DRIVER puts
// into a state field or an `onError` message, which is why it exists ahead of them: a message the
// driver stores has to be worded before any view is on screen.
//
// Values are the JS defaults byte for byte
// (packages/wildwood-react-shared/src/registrationSubscription/labels.ts), so the three stacks say
// the same words. Internal on purpose: when the full labels type lands, the drivers' `labels`
// property changes type and nothing else about them moves, because they only ever read these
// members by name.

import Foundation

struct RegistrationSubscriptionDriverLabels: Sendable, Equatable {
    /// Said when a purchase needs a card challenge nothing on this device can answer.
    var finishOnWeb: String
    /// Said in place of the preview's proration figures when a device store owns the billing.
    var storeManagesBilling: String
    /// Said when a pack purchase was refused and no message came back.
    var packsUnavailable: String

    /// The parked change's payment window closed before it was finished.
    var planChangeExpired: String
    /// The prorated charge was refused.
    var planChangePaymentFailed: String
    /// Another change replaced the one being finished.
    var planChangeSuperseded: String
    /// The parked change is no longer on the server.
    var planChangeNotFound: String
    /// A change is already under way on this subscription.
    var planChangeInProgress: String

    /// Success copy when the account exists but the plan could not be activated.
    var signupCompletePending: String
    /// Status while the account is being registered.
    var statusCreatingAccount: String
    /// Status while the new account is being signed in.
    var statusSigningIn: String
    /// Status while the plan is being activated.
    var statusActivatingPlan: String

    static let defaults = RegistrationSubscriptionDriverLabels(
        finishOnWeb: "This purchase has to be finished on the web.",
        storeManagesBilling: "Your app store manages billing for this change.",
        packsUnavailable: "Your packs could not be bought.",
        planChangeExpired: "The payment window closed - please start the change again",
        planChangePaymentFailed:
            "That payment was not completed, so your plan has not changed. Please try again.",
        planChangeSuperseded: "This plan was changed somewhere else. Refresh and try again.",
        planChangeNotFound: "That plan change is no longer available. Please start it again.",
        planChangeInProgress: "A change to this plan is already under way. Give it a moment and refresh.",
        signupCompletePending:
            "Your account is ready! Plan activation is pending - you can select a plan from your dashboard.",
        statusCreatingAccount: "Creating your account...",
        statusSigningIn: "Signing you in...",
        statusActivatingPlan: "Activating your plan..."
    )
}

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
}
