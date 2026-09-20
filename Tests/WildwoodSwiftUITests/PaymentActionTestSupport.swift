// Fake payment-action handlers and the small waiting helper the driver suites share.
//
// The handlers RECORD what they were asked to confirm, because the binding rules of the seam are
// negative ones — a stack with no handler must never send `SupportsPaymentAction`, never send
// `supportsSetupIntent` and never create a checkout payment method — and the only way to pin a
// call that must not happen is to look at what was actually sent.

import Foundation
import Synchronization
import WildwoodCore
@testable import WildwoodSwiftUI

/// One confirmation the handler was asked for.
struct PaymentActionCall: Sendable, Equatable {
    enum Kind: String, Sendable, Equatable {
        case payment
        case cardSetup
    }

    var kind: Kind
    var clientSecret: String
    var publishableKey: String?
}

/// A handler that answers whatever the test told it to, and remembers every ask.
final class RecordingPaymentActionHandler: WildwoodPaymentActionHandler {
    private let calls = Mutex<[PaymentActionCall]>([])
    private let paymentOutcome: PaymentActionOutcome
    private let cardSetupOutcome: PaymentActionOutcome
    let supportsCardSetup: Bool
    /// Names one instance, so a precedence test can say WHICH handler it got back without
    /// comparing existentials by identity.
    let id: String

    init(
        id: String = "handler",
        payment: PaymentActionOutcome = .succeeded,
        cardSetup: PaymentActionOutcome = .succeeded,
        supportsCardSetup: Bool = true
    ) {
        self.id = id
        self.paymentOutcome = payment
        self.cardSetupOutcome = cardSetup
        self.supportsCardSetup = supportsCardSetup
    }

    func confirmPayment(clientSecret: String, publishableKey: String?) async -> PaymentActionOutcome {
        calls.withLock {
            $0.append(PaymentActionCall(kind: .payment, clientSecret: clientSecret, publishableKey: publishableKey))
        }
        return paymentOutcome
    }

    func confirmCardSetup(clientSecret: String, publishableKey: String?) async -> PaymentActionOutcome {
        calls.withLock {
            $0.append(PaymentActionCall(kind: .cardSetup, clientSecret: clientSecret, publishableKey: publishableKey))
        }
        return cardSetupOutcome
    }

    func recorded() -> [PaymentActionCall] {
        calls.withLock { $0 }
    }
}

/// A handler whose confirmation does not answer until the test lets it — the only way to have a
/// bank challenge genuinely in flight when the view is torn down.
final class GatedPaymentActionHandler: WildwoodPaymentActionHandler {
    private let opened = Mutex<Bool>(false)
    private let asked = Mutex<Bool>(false)

    func open() {
        opened.withLock { $0 = true }
    }

    var wasAsked: Bool { asked.withLock { $0 } }

    func confirmPayment(clientSecret: String, publishableKey: String?) async -> PaymentActionOutcome {
        asked.withLock { $0 = true }
        while !opened.withLock({ $0 }) {
            try? await Task.sleep(for: .milliseconds(2))
        }
        return .succeeded
    }

    func confirmCardSetup(clientSecret: String, publishableKey: String?) async -> PaymentActionOutcome {
        .failed(message: "not supported")
    }
}

/// A mutable counter an escaping main-actor callback can bump from a test.
@MainActor
final class CallCounter {
    private(set) var count: Int = 0

    func bump() {
        count += 1
    }
}

/// Everything an escaping main-actor callback handed the test, in order. A box rather than a
/// captured `var`, so nothing about the capture depends on how strict-concurrency reads it.
@MainActor
final class Recorder<Value> {
    private(set) var values: [Value] = []

    var count: Int { values.count }
    var last: Value? { values.last }
    var first: Value? { values.first }
    var isEmpty: Bool { values.isEmpty }

    func record(_ value: Value) {
        values.append(value)
    }

    func clear() {
        values = []
    }
}

/// Spin the main actor until `condition` holds, or give up. Everything under test is main-actor
/// isolated and driven by owned `Task`s, so yielding is what lets them run.
@MainActor
func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
    let deadline: Date = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() >= deadline { break }
        try? await Task.sleep(for: .milliseconds(2))
    }
}

/// The requests a backend saw, as decoded JSON bodies for one path.
@MainActor
func bodies(_ backend: TestBackend, path: String) -> [String] {
    var found: [String] = []
    for request in backend.requests() where request.path == path {
        found.append(String(data: request.body ?? Data(), encoding: .utf8) ?? "")
    }
    return found
}

@MainActor
func requestCount(_ backend: TestBackend, path: String) -> Int {
    var count: Int = 0
    for request in backend.requests() where request.path == path { count += 1 }
    return count
}

/// A client wired to a stub backend, with nothing persisted and no retries.
@MainActor
func makeTestClient(_ backend: TestBackend, appId: String = "app-1") -> WildwoodClient {
    WildwoodClient(
        config: WildwoodConfig(
            baseUrl: backend.baseUrl,
            appId: appId,
            enableRetry: false,
            storage: .memory,
            attributionEnabled: false
        ),
        urlSession: backend.makeSession()
    )
}
