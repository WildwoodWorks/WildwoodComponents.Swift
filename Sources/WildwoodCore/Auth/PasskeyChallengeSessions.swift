// The API accepts a passkey assertion only against the challenge it issued, identified by the options'
// `sessionId`. This remembers each issued challenge's session and finds it again from the challenge inside
// the assertion's signed clientDataJSON, so concurrent sign-ins through one AuthService never pick up each
// other's session (which would also burn the other challenge server-side). Mirrors @wildwood/core's
// passkeyChallengeSessions.ts.

import Foundation
import Synchronization

final class PasskeyChallengeSessions: Sendable {
    private static let capacity = 32
    private static let lifetime: TimeInterval = 5 * 60

    private struct Entry: Sendable {
        var sessionId: String
        var issuedAt: Date
    }

    private struct State: Sendable {
        var byChallenge: [String: Entry] = [:]
        var last: String?
    }

    private let state = Mutex(State())
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// Remembers the session of an authentication-options response (raw JSON).
    func remember(optionsJSON data: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sessionId = object["sessionId"] as? String, !sessionId.isEmpty else { return }
        let challenge = Self.normalize(object["challenge"] as? String)
        let issuedAt = now()

        state.withLock { state in
            state.last = sessionId
            guard let challenge else { return }
            state.byChallenge = state.byChallenge.filter { issuedAt.timeIntervalSince($0.value.issuedAt) <= Self.lifetime }
            while state.byChallenge.count >= Self.capacity,
                  let oldest = state.byChallenge.min(by: { $0.value.issuedAt < $1.value.issuedAt })?.key {
                state.byChallenge.removeValue(forKey: oldest)
            }
            state.byChallenge[challenge] = Entry(sessionId: sessionId, issuedAt: issuedAt)
        }
    }

    /// The session for the assertion's challenge; the most recent one when the client data cannot be read.
    func take(clientDataJSON: String?) -> String? {
        let challenge = Self.challenge(ofClientDataJSON: clientDataJSON)
        return state.withLock { state -> String? in
            if let challenge, let entry = state.byChallenge.removeValue(forKey: challenge) {
                if state.last == entry.sessionId { state.last = nil }
                return entry.sessionId
            }
            let fallback = state.last
            state.last = nil
            return fallback
        }
    }

    static func challenge(ofClientDataJSON clientDataJSON: String?) -> String? {
        guard let clientDataJSON, !clientDataJSON.isEmpty else { return nil }
        var base64 = clientDataJSON.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return normalize(object["challenge"] as? String)
    }

    // Base64url without padding, so the options' and the client data's spellings compare equal.
    private static func normalize(_ challenge: String?) -> String? {
        guard let challenge, !challenge.isEmpty else { return nil }
        var value = challenge.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        while value.hasSuffix("=") { value.removeLast() }
        return value
    }
}
