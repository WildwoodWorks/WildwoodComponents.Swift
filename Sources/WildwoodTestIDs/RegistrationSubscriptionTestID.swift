// The web's test hooks, spelled the way SwiftUI can carry them.
//
// `@wildwood/react` hangs `data-ww-view="pricing"`, `data-ww-step="register"`, `data-ww-pack="<id>"`
// and `data-ww-group="<id>"` off its elements, and the live sites' end-to-end suites locate the
// component by exactly those strings. A SwiftUI view has ONE `accessibilityIdentifier` per element
// rather than a bag of attributes, so the STRINGS are carried over unchanged and this type decides
// which of them names an element — a test plan written against one stack then reads the same on the
// other. React Native reached the same arrangement in `testIds.ts`; these are its functions.
//
// Packs, groups, sections, modals and form fields are namespaced, because a flat identifier
// namespace cannot tell `data-ww-pack="core"` from `data-ww-group="core"` the way two different
// attributes can. The prefix is the attribute's own name, so `data-ww-modal="packs"` is
// `modal:packs` here and in React Native's `testIds.ts`.
//
// This is more than the three views' own spelling. The signup view mounts the registration form as
// a step of its own, so a bare `email` on one of that form's inputs would answer to the same string
// as a step of the flow around it; the form's hooks therefore live here too. The disclaimer
// component, which the same view also mounts, has its own prefixed namespace in ``DisclaimerTestID``.
//
// Deliberately NOT inside `#if os(iOS)`: a test on a macOS host asserts these strings, and there is
// nothing platform-specific about a string.

import Foundation

/// Which of the three registration-and-subscription views is on screen. The raw values are the
/// web's `data-ww-view` values.
public enum RegistrationSubscriptionViewKind: String, Sendable, Equatable, CaseIterable {
    case pricing
    case signup
    case manage
}

/// One input on the registration form, by the name its identifier is built from.
///
/// The first six are the web's `data-ww-field` values, unchanged. `registrationToken` is this
/// contract's own: REACT's token input carries an `id` and no `data-ww-field`, so there was no
/// string to match, and `registrationToken` is the name `RegistrationFormData` already uses for it.
///
/// Razor is the exception, and the reason this says React rather than "the web": it does name that
/// input, as `token`, and its own client script keys the collected form values off that spelling, so
/// it cannot simply be renamed to match. A plan asks Razor for `token` and every other stack for
/// `field:registrationToken`.
public enum RegistrationFieldName: String, Sendable, Equatable, CaseIterable {
    case firstName
    case lastName
    case username
    case email
    case password
    case confirmPassword
    case registrationToken
}

/// The accessibility identifiers the three views hang off their elements.
public enum RegistrationSubscriptionTestID {
    /// A view's root, or one step inside it.
    ///
    /// With a step, the step's own name is the hook (`register`, `packs`, `failed`, ...) — the same
    /// string the web puts in `data-ww-step`. With no step, the view names the element, as
    /// `data-ww-view` does.
    public static func view(_ view: RegistrationSubscriptionViewKind, step: String? = nil) -> String {
        if let step, !step.isEmpty { return step }
        return view.rawValue
    }

    /// One pack card, order-summary line or outcome row.
    public static func pack(_ addOnId: String) -> String {
        "pack:" + addOnId
    }

    /// One group of packs (`all` when ungrouped, `more` for the catch-all).
    public static func group(_ groupId: String) -> String {
        "group:" + groupId
    }

    /// One manage section: the stacked page's section, and the tab that opens it. The web's
    /// `data-ww-section`.
    public static func section(_ section: ManageSection) -> String {
        "section:" + section.rawValue
    }

    /// One of the two sheets the manage view puts over itself. The web's `data-ww-modal`.
    public static func modal(_ modal: String) -> String {
        "modal:" + modal
    }

    /// One input on the registration form. The web's `data-ww-field`.
    public static func field(_ field: RegistrationFieldName) -> String {
        "field:" + field.rawValue
    }

    /// The button that loads the catalog again after a failure.
    public static let retryButton: String = "pricing-retry"
    /// The placeholder shown while the catalog loads.
    public static let skeleton: String = "pricing-skeleton"
    /// The monthly/annual switch.
    public static let billingToggle: String = "billing-toggle"
    /// The multi-select pack grid's Continue.
    public static let packsContinue: String = "packs-continue"

    // MARK: Registration form

    /// The form's submit. The web's `data-ww-action="submit-register"`, carried over unchanged —
    /// the copy on the button is a caller-supplied parameter, so the copy cannot be the hook.
    public static let submitRegister: String = "submit-register"

    // MARK: Signup

    /// The "registration is closed" panel. Its own hook because a host may render it alone.
    public static let closedNotice: String = "regsub-closed"
    /// What a registration token grants, shown above every step it applies to.
    public static let tokenPlanSummary: String = "token-plan-summary"
    /// The plan a signup link already chose, shown above the registration form. The web's
    /// `.ww-plan-summary-card`.
    public static let planSummaryCard: String = "plan-summary-card"
    /// "Change plan" on that card.
    public static let planChange: String = "plan-change"
    /// Backing out of the plan's card step.
    public static let paymentLeave: String = "payment-leave"
    /// What the failed step SAID, as opposed to the fact that it failed.
    ///
    /// The other two web stacks read the reason from an element of its own rather than from the
    /// panel's copy, because the style the message carries there is shared with the processing
    /// steps' "please wait" - so a driver falling back to it reports boilerplate as the cause of a
    /// genuine failure. This stack has no such collision, but the hook is the same string in all
    /// three so one driver can ask the same question of any of them.
    public static let signupErrorMessage: String = "signup-error-message"
    /// Resumes a failed signup where it stopped.
    public static let signupRetry: String = "signup-retry"
    /// Throws the attempt away and returns to the form.
    public static let signupStartOver: String = "signup-start-over"
    /// Leaves the finished signup.
    public static let signupGetStarted: String = "signup-get-started"

    // MARK: Pack checkout

    /// The quoted basket.
    public static let orderSummary: String = "order-summary"
    /// The pack checkout panel.
    public static let packCheckout: String = "pack-checkout"
    /// Runs the failed checkout step again.
    public static let packCheckoutRetry: String = "pack-checkout-retry"
    /// Finishes the signup without the packs, reporting them as not bought.
    public static let packCheckoutSkip: String = "pack-checkout-skip"
    /// What became of each pack.
    public static let packOutcomes: String = "pack-outcomes"

    // MARK: Manage

    /// The card sheet a plan change opens when the host brought no sheet of its own. The web's
    /// `data-ww-modal="payment"`.
    public static let paymentModal: String = "modal:payment"
    /// The pack picker the packs panel opens. The web's `data-ww-modal="packs"`.
    public static let packsModal: String = "modal:packs"
    /// Opens that picker.
    public static let addPacks: String = "add-packs"
    /// The pack sheet's OWN call to action, the one over the outcomes.
    ///
    /// Not ``packsContinue``, which belongs to the grid ``PackGridView`` renders in the sheet's
    /// FIRST stage: one string for both would leave a test that pressed "the Continue" unable to
    /// say which stage of the sheet it was in. Not `modal:packs-continue` either — the `modal:`
    /// prefix names a sheet, and its value space is the web's two `data-ww-modal` values, so a third
    /// name there would assert a sheet that does not exist.
    ///
    /// The web's outcome Continue carries no hook at all, so there was no string to match. React
    /// Native coined this one; it is spelled the same on both stacks.
    public static let packsModalContinue: String = "packs-modal-continue"
    /// What a plan change says about itself while it is running, or after it failed.
    public static let planChangeNotice: String = "plan-change-notice"
    /// Runs the failed plan-change step again.
    public static let planChangeRetry: String = "plan-change-retry"
    /// Abandons a failed or unfinishable plan change.
    public static let planChangeDismiss: String = "plan-change-dismiss"
}
