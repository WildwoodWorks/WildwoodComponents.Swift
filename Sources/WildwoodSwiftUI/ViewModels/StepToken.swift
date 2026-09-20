// Step tokens: what makes the registration/subscription machines safe to drive from a UI.
//
// Every state that starts async work is issued a fresh token when it is entered, and the token is
// stored on the state. The result event carries the token it was started with, and the reducer
// ignores any result whose token is not the one the state is currently waiting on.
//
// That single rule covers three real hazards at once:
//   - A `.task` that re-runs starts the work twice; the second start re-enters the same state with
//     a NEW token, and the first result is dropped as stale.
//   - A StoreKit/payment callback that fires twice cannot advance the machine twice — the second
//     copy carries a token the machine has already moved past.
//   - A retry supersedes the attempt it replaced instead of racing it.
//
// Ported from packages/wildwood-react-shared/src/registrationSubscription/stepTokens.ts, where a
// token is the string `step-${++counter}`, and mirroring
// WildwoodComponents.Shared/RegistrationSubscription/StepToken.cs. The same shape is kept here so a
// token logged by one stack reads the same as a token logged by another.
//
// JS keeps a module-level counter. A mutable global is a Swift 6 strict-concurrency error, so the
// counter lives inside a `Mutex` on an issuer object — the same idiom `AuthService` uses for its
// mutable handlers — and the reducers take an issuer so a test can hold its own and get literal,
// deterministic values (`step-1`, `step-2`, ...) rather than sharing the process-wide counter with
// every other test running in parallel.

import Foundation
import Synchronization

/// An opaque handle for one async step. Compare with `==`; never parse it.
public struct StepToken: Sendable, Hashable, CustomStringConvertible {
    /// The wire-identical value, `step-<n>`.
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public var description: String { value }

    /// TS tests the token with `Boolean(stateToken)`, so an empty token is as good as none.
    public var isEmpty: Bool { value.isEmpty }

    /// Issue a token from the process-wide issuer (TS `issueStepToken()`).
    public static func issue() -> StepToken {
        StepTokenIssuer.shared.issue()
    }

    /// Whether a result event belongs to the step the state is currently waiting on.
    ///
    /// A missing or empty token on either side means "not waiting" / "no token", which is never a
    /// match: a result that arrives after the machine stopped waiting is stale by definition.
    public static func isCurrentStep(_ stateToken: StepToken?, _ eventToken: StepToken?) -> Bool {
        guard let stateToken, !stateToken.value.isEmpty else { return false }
        guard let eventToken else { return false }
        return stateToken.value == eventToken.value
    }

    public static func == (lhs: StepToken, rhs: StepToken) -> Bool {
        lhs.value == rhs.value
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

/// Issues step tokens. Monotonic within the issuer, so a token is never reused and a late result
/// can always be told apart from the attempt that replaced it.
///
/// Tokens are unique within ONE issuer; never mix issuers inside one flow.
public final class StepTokenIssuer: Sendable {
    private let counter = Mutex<Int>(0)

    public init() {}

    /// Issue a token for a new async step. Safe to call from any thread.
    public func issue() -> StepToken {
        let next: Int = counter.withLock { value in
            value += 1
            return value
        }
        return StepToken("step-\(next)")
    }

    /// The issuer the reducers use when none is supplied. The only mutable state in this file.
    public static let shared = StepTokenIssuer()
}

/// What a reducer answers: the next state, and whether the event was applied at all.
///
/// TypeScript returns the SAME state OBJECT for an event it ignores, so a React `useReducer`
/// re-renders nothing. Swift states are value types with no identity, so the reducers say so
/// outright: ``applied`` is false exactly where TS would have returned the original object, and a
/// driver can skip re-rendering on that. The ported "returns the same state" assertions become
/// `applied == false` together with `state == before`.
public struct MachineTransition<StateValue: Sendable & Equatable>: Sendable, Equatable {
    /// The state after the event — identical to the one passed in when ``applied`` is false.
    public let state: StateValue
    /// Whether the event changed anything at all.
    public let applied: Bool

    public init(state: StateValue, applied: Bool) {
        self.state = state
        self.applied = applied
    }

    public static func == (lhs: MachineTransition<StateValue>, rhs: MachineTransition<StateValue>) -> Bool {
        lhs.state == rhs.state && lhs.applied == rhs.applied
    }
}
