// Typed event emitter mirroring @wildwood/core's WildwoodEventEmitter.
// MainActor-isolated: events drive UI state. Closure subscriptions plus an
// AsyncStream accessor; no Combine.

import Foundation

public enum WildwoodEvent: Sendable {
    case authChanged(AuthenticationResponse?)
    /// Emitted once initialization completes; payload is `isAuthenticated`.
    case sessionInitialized(Bool)
    case sessionExpired
    case tokenRefreshed(String)
    case themeChanged(String)
    case error(service: String, message: String)
}

public struct WildwoodSubscription: Sendable {
    private let cancelHandler: @Sendable () -> Void

    init(cancel: @escaping @Sendable () -> Void) {
        self.cancelHandler = cancel
    }

    public func cancel() {
        cancelHandler()
    }
}

@MainActor
public final class WildwoodEventEmitter {
    public typealias Handler = @MainActor (WildwoodEvent) -> Void

    private var handlers: [UUID: Handler] = [:]
    private var continuations: [UUID: AsyncStream<WildwoodEvent>.Continuation] = [:]

    public init() {}

    /// Subscribe to all events. Returns a subscription whose `cancel()` unsubscribes.
    @discardableResult
    public func on(_ handler: @escaping Handler) -> WildwoodSubscription {
        let id = UUID()
        handlers[id] = handler
        return WildwoodSubscription { [weak self] in
            Task { @MainActor in self?.handlers[id] = nil }
        }
    }

    /// An async sequence of events for `for await` consumption.
    public var stream: AsyncStream<WildwoodEvent> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }

    public func emit(_ event: WildwoodEvent) {
        for handler in handlers.values {
            handler(event)
        }
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    public func removeAllListeners() {
        handlers.removeAll()
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }
}
