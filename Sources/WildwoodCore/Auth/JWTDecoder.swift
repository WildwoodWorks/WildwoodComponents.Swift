// JWT utilities mirroring @wildwood/core's tokenUtils: payload decode without
// signature verification (client-side scheduling only), expiry math, and the
// 80%-of-lifetime refresh point.

import Foundation

public struct JWTPayload: Sendable {
    public var sub: String?
    public var email: String?
    public var name: String?
    public var roles: [String]
    public var companyId: String?
    public var appId: String?
    public var exp: TimeInterval?
    public var iat: TimeInterval?
}

public enum JWTDecoder {
    /// Decode a JWT payload without verification (client-side only).
    public static func decodePayload(_ token: String) -> JWTPayload? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: padding)

        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var roles: [String] = []
        if let role = object["role"] as? String {
            roles = [role]
        } else if let roleArray = object["role"] as? [String] {
            roles = roleArray
        }

        return JWTPayload(
            sub: object["sub"] as? String,
            email: object["email"] as? String,
            name: object["name"] as? String,
            roles: roles,
            companyId: object["company_id"] as? String,
            appId: object["app_id"] as? String,
            exp: (object["exp"] as? NSNumber)?.doubleValue,
            iat: (object["iat"] as? NSNumber)?.doubleValue
        )
    }

    /// Expiration date of the token, or nil when it has no `exp`.
    public static func expiry(of token: String) -> Date? {
        guard let exp = decodePayload(token)?.exp else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    public static func isExpired(_ token: String, buffer: TimeInterval = 0, now: Date = Date()) -> Bool {
        guard let expiry = expiry(of: token) else { return true }
        return now.addingTimeInterval(buffer) >= expiry
    }

    public static func remainingLifetime(of token: String, now: Date = Date()) -> TimeInterval {
        guard let expiry = expiry(of: token) else { return 0 }
        return max(0, expiry.timeIntervalSince(now))
    }

    /// Delay until the refresh point: 80% of the token's lifetime past `iat`,
    /// falling back to 5 minutes before expiry when `iat` is missing.
    public static func refreshDelay(for token: String, now: Date = Date()) -> TimeInterval {
        guard let payload = decodePayload(token), let exp = payload.exp, let iat = payload.iat else {
            return max(0, remainingLifetime(of: token, now: now) - 5 * 60)
        }
        let refreshAt = iat + (exp - iat) * 0.8
        return max(0, refreshAt - now.timeIntervalSince1970)
    }
}
