// Typed error mirroring @wildwood/core's WildwoodError.

import Foundation

public struct WildwoodError: Error, Sendable, Equatable {
    public enum Code: String, Sendable {
        case invalidCredentials = "InvalidCredentials"
        case unauthorized = "Unauthorized"
        case forbidden = "Forbidden"
        case notFound = "NotFound"
        case validationError = "ValidationError"
        case twoFactorRequired = "TwoFactorRequired"
        case sessionExpired = "SessionExpired"
        case rateLimited = "RateLimited"
        case serverError = "ServerError"
        case networkError = "NetworkError"
        case timeout = "Timeout"
        case unknown = "Unknown"
    }

    public let message: String
    /// HTTP status; 0 for network-level failures.
    public let status: Int
    public let code: Code
    /// Raw response body, when one was received.
    public let details: Data?

    public init(message: String, status: Int, code: Code? = nil, details: Data? = nil) {
        self.message = message
        self.status = status
        self.code = code ?? Self.code(fromStatus: status)
        self.details = details
    }

    private static func code(fromStatus status: Int) -> Code {
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 422: return .validationError
        case 429: return .rateLimited
        case 500...: return .serverError
        case 0: return .networkError
        default: return .unknown
        }
    }

    /// Build from an API error response body, extracting
    /// `message`/`errorMessage`/`error`/`title`, `errorCode`, and the
    /// `requiresTwoFactor` flag — same precedence as the JS SDK.
    ///
    /// The raw body stays on ``details``: the structured action results (add-on
    /// checkout, tier-change completion) read the server's own `errorCode` back
    /// out of it, because ``Code`` is a closed enum that drops unknown codes.
    public static func fromResponse(status: Int, body: Data?, fallbackMessage: String) -> WildwoodError {
        var message = fallbackMessage
        var code: Code?

        if let body,
           let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let m = object["message"] as? String {
                message = m
            } else if let em = object["errorMessage"] as? String {
                message = em
            } else if let e = object["error"] as? String {
                message = e
            } else if let t = object["title"] as? String {
                message = t
            }

            if let apiCode = object["errorCode"] as? String {
                code = mapApiCode(apiCode)
            }
            if code == nil, let apiError = object["error"] as? String {
                code = mapApiCode(apiError)
            }
            if object["requiresTwoFactor"] as? Bool == true {
                code = .twoFactorRequired
            }
        }

        // HTTP/2 responses carry no status text, so a body without a recognized message field
        // would otherwise produce an empty message — which callers that branch on "is there an
        // error message?" read as no error.
        if message.isEmpty {
            message = "Request failed (HTTP \(status))"
        }

        return WildwoodError(message: message, status: status, code: code, details: body)
    }

    private static func mapApiCode(_ apiError: String) -> Code? {
        switch apiError {
        case "InvalidCredentials": return .invalidCredentials
        case "Unauthorized": return .unauthorized
        case "Forbidden": return .forbidden
        case "NotFound": return .notFound
        case "ValidationError": return .validationError
        case "RateLimited": return .rateLimited
        default: return nil
        }
    }
}

extension WildwoodError: LocalizedError {
    public var errorDescription: String? { message }
}
