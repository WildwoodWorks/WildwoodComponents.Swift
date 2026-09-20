// Why a user's entitlements changed — the vocabulary of the JS `entitlementsChanged` event
// (events/eventEmitter.ts). A signal to re-read the subscription and feature map, not proof that
// the change has propagated.

import Foundation

/// The six reasons an entitlement mutation reports.
///
/// A closed enum is safe here, unlike the server's error codes and statuses: this value is
/// produced by the SDK when it emits the event, never decoded off the wire, so no server can
/// widen it behind the app's back.
public enum EntitlementsChangedReason: String, Sendable, Equatable, CaseIterable {
    case signup = "signup"
    case tierChange = "tierChange"
    case addOn = "addOn"
    case cancel = "cancel"
    case reactivate = "reactivate"
    case manual = "manual"
}
