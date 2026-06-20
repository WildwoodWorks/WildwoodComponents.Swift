// Shared URL-encoding helpers for building WildwoodAPI request paths.

import Foundation

enum WildwoodURL {
    /// Percent-encodes a string for use as a query-parameter VALUE, matching JS `encodeURIComponent`
    /// semantics: it escapes reserved delimiters (`+ & = ? /` …) that `CharacterSet.urlQueryAllowed`
    /// would otherwise pass through unescaped. Use for appIds and other interpolated query values.
    static func queryComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? value
    }

    // RFC 3986 "unreserved" set — a safe subset of encodeURIComponent's allowed characters.
    private static let queryValueAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
}
