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
}
