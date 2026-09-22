// The consent banner's test hooks, spelled the way SwiftUI can carry them.
//
// Unlike the disclaimer component's, these are NOT carried over from a `data-ww-*` attribute: the
// web's banner has none. `@wildwood/react` renders `<div className="ww-consent-banner">` with its
// primary button classed `ww-consent-btn-primary`, and the web's own Playwright helper dismisses the
// banner by exactly those two classes. So there was no contract string to match: `consent-banner` is
// the web's class without the package prefix, and `consent-accept-all` is named for what the button
// does rather than after a class that only says how it looks. React Native coined both; these are
// its spellings.
//
// An identifier as well as the banner's `accessibilityLabel`: the label is accessibility copy and is
// meant to be translated, so a suite keyed on it stops finding the banner the moment it is.
//
// The namespace is FLAT and `consent-`-prefixed for the same reason ``DisclaimerTestID`` is: a
// SwiftUI element carries ONE `accessibilityIdentifier` rather than a bag of attributes, and
// `data-ww-view`/`data-ww-step` already own the unprefixed names in
// ``RegistrationSubscriptionTestID``.
//
// Like the other two, deliberately NOT inside `#if os(iOS)`: a test on a macOS host asserts these
// strings, and there is nothing platform-specific about a string.

import Foundation

/// The accessibility identifiers ``ConsentComponent`` hangs off its banner.
public enum ConsentTestID {
    /// The banner itself. The web's `ww-consent-banner` class without the package prefix.
    public static let banner: String = "consent-banner"
    /// "Accept all" — the banner's primary button. The web's `ww-consent-btn-primary`, named here
    /// for what it does so it reads beside ``DisclaimerTestID/acceptAll``.
    public static let acceptAll: String = "consent-accept-all"
}
