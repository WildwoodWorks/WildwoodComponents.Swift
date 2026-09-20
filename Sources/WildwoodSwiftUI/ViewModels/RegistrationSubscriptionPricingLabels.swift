// The pricing view's copy — now a name for the full set.
//
// This started as the PRICING SLICE of the overridable copy, written with the pricing view before
// the signup and manage views existed. Those views landed, each with a slice of its own, and the
// three merged into ``RegistrationSubscriptionLabels``: one struct, one default per key, one place
// a cross-stack drift can be caught by a test.
//
// The name stays because every pricing call site reads it, and because it still says which slice of
// the copy a pricing surface cares about. It is the same type, so
// `RegistrationSubscriptionPricingLabels(retry: "Try again")` and `.defaults` work exactly as
// before; the members the other views use are simply also present.

import Foundation

/// The pricing view's overridable copy: ``RegistrationSubscriptionLabels`` under the name the
/// pricing surfaces use.
public typealias RegistrationSubscriptionPricingLabels = RegistrationSubscriptionLabels
