// The manage view's section names — here rather than beside the rules that use them.
//
// ``RegistrationSubscriptionTestID/section(_:)`` builds `section:<name>` out of this enum, so the
// identifier vocabulary cannot be read without it. Everything else in this target is a string
// constant; this is the one type the constants are built FROM, and leaving it behind would mean a
// UI test target had to link the whole SwiftUI module to name a tab.
//
// It is still the manage view's own enum: ``ManageViewRules`` in `WildwoodSwiftUI` orders, filters
// and titles these cases, and `RegistrationSubscriptionManageView`'s `sections:` parameter takes
// them. `WildwoodSwiftUI` re-exports this module, so a host that only ever mounts the view never
// has to know the type moved.

import Foundation

/// One panel of the manage view. Raw values are the web's `data-ww-section` values.
public enum ManageSection: String, Sendable, Equatable, CaseIterable {
    case subscription
    case plans
    case features
    case addOns
    case usage
    case overrides
}
