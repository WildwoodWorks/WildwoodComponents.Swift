// The disclaimer component's test hooks, spelled the way SwiftUI can carry them.
//
// `@wildwood/react` hangs `data-ww-disclaimer-action="retry" | "accept" | "accept-all"` off the
// three controls a visitor can press, and an end-to-end suite locates them by exactly those values.
// A SwiftUI element carries ONE `accessibilityIdentifier` rather than a bag of attributes, so the
// identifier namespace here is FLAT and the web's values are carried over with a `disclaimer-`
// prefix — `data-ww-view`/`data-ww-step` already own the unprefixed names in
// ``RegistrationSubscriptionTestID``, and the signup flow renders a disclaimer step inside itself.
//
// The mapping, and the one place the two stacks differ in shape:
//
// | Web attribute value | Here | The control |
// |---|---|---|
// | `retry` | ``retry`` | "Try again" after a failed load. |
// | `accept` | ``accept`` | The per-disclaimer acceptance control. On the web that is a button
// |   |   | that POSTs one acceptance; here it is the card's "I have read and accept" TOGGLE,
// |   |   | because this component accepts everything ticked in ONE submit. Same role — the
// |   |   | control that accepts THIS disclaimer — so it carries the same hook. |
// | `accept-all` | ``acceptAll`` | The submit: "Accept and Continue". |
//
// Like ``RegistrationSubscriptionTestID`` this is deliberately NOT inside `#if os(iOS)`: a test on
// a macOS host asserts these strings, and there is nothing platform-specific about a string.

import Foundation

/// The accessibility identifiers ``DisclaimerComponent`` hangs off its controls.
public enum DisclaimerTestID {
    /// Loads the pending disclaimers again after a failure. The web's
    /// `data-ww-disclaimer-action="retry"`.
    public static let retry: String = "disclaimer-retry"
    /// Accepts ONE disclaimer — a button on the web, this card's toggle here. The web's
    /// `data-ww-disclaimer-action="accept"`.
    public static let accept: String = "disclaimer-accept"
    /// Submits every disclaimer that has been accepted. The web's
    /// `data-ww-disclaimer-action="accept-all"`.
    public static let acceptAll: String = "disclaimer-accept-all"
}
