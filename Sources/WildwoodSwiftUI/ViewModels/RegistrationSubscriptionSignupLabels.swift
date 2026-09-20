// The signup view's copy — now a name for the full set.
//
// This started as the SIGNUP AND PACK-CHECKOUT SLICE of the overridable copy, written with the
// signup view. The manage view brought the last slice, and all three merged into
// ``RegistrationSubscriptionLabels``: one struct, one default per key, one place a cross-stack
// drift can be caught by a test.
//
// The name stays because every signup call site reads it. It is the same type, so
// `RegistrationSubscriptionSignupLabels(tryAgain: "Retry")` and `.defaults` work exactly as before.
//
// Two keys this slice carried are filed elsewhere in the merged set, and neither moved a word:
// `changePlan` is a manage key the signup's plan summary card also says, and `finishOnWeb` is
// shared — the one thing the native stacks say that the web never has to, because a card challenge
// needs a payment SDK this package does not ship.

import Foundation

/// The signup view's overridable copy: ``RegistrationSubscriptionLabels`` under the name the
/// signup surfaces use.
public typealias RegistrationSubscriptionSignupLabels = RegistrationSubscriptionLabels

extension RegistrationSubscriptionLabels {
    /// The copy a DRIVER stores in its state or puts in an `onError` message.
    ///
    /// The drivers were written before any view existed and carried their own small copy type; the
    /// merge made that type a name for this one, so handing a driver the host's words is now the
    /// whole set rather than the six members the old mapping could reach. Kept as a property
    /// because the views read it where they wire a driver up, and because it says WHY the
    /// assignment is there.
    var driverLabels: RegistrationSubscriptionDriverLabels { self }
}
