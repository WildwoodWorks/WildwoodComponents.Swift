// Typed event emitter mirroring @wildwood/core's WildwoodEventEmitter.
// MainActor-isolated: events drive UI state. Closure subscriptions plus an
// AsyncStream accessor; no Combine.

import Foundation

/// The events the SDK raises. Adding a case is source-breaking for a host that switches
/// exhaustively over this enum — handle unknown events with a `default:` clause.
public enum WildwoodEvent: Sendable {
    case authChanged(AuthenticationResponse?)
    /// Emitted once initialization completes; payload is `isAuthenticated`.
    case sessionInitialized(Bool)
    case sessionExpired
    case tokenRefreshed(String)
    case themeChanged(String)
    /// An entitlement mutation landed (tier change, cancel, add-on, override …): re-read the
    /// subscription and the feature map. A SIGNAL to refresh, not proof the change has
    /// propagated — emitted by `FeatureStore.invalidateEntitlements(appId:reason:)`.
    case entitlementsChanged(appId: String, reason: EntitlementsChangedReason)
    /// A campaign touch was captured from a deep link or universal link
    /// (`AttributionService.capture(url:referrer:)`).
    case attributionCaptured(AttributionTouch)
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
