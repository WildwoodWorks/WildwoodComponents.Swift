// The web's test hooks, spelled the way SwiftUI can carry them.
//
// `@wildwood/react` hangs `data-ww-view="pricing"`, `data-ww-step="register"`, `data-ww-pack="<id>"`
// and `data-ww-group="<id>"` off its elements, and the live sites' end-to-end suites locate the
// component by exactly those strings. A SwiftUI view has ONE `accessibilityIdentifier` per element
// rather than a bag of attributes, so the STRINGS are carried over unchanged and this type decides
// which of them names an element — a test plan written against one stack then reads the same on the
// other. React Native reached the same arrangement in `testIds.ts`; these are its functions.
//
// Packs and groups are namespaced, because a flat identifier namespace cannot tell
// `data-ww-pack="core"` from `data-ww-group="core"` the way two different attributes can.
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

    /// The button that loads the catalog again after a failure.
    public static let retryButton: String = "pricing-retry"
    /// The placeholder shown while the catalog loads.
    public static let skeleton: String = "pricing-skeleton"
    /// The monthly/annual switch.
    public static let billingToggle: String = "billing-toggle"
    /// The multi-select pack grid's Continue.
    public static let packsContinue: String = "packs-continue"

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
}
