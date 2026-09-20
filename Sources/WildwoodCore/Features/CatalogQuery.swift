// The `URLSearchParams` the JS SDK's catalog and signup helpers are written against, so the Swift
// port reads the same query keys and serialises the same query strings. The twin of
// WildwoodComponents.Shared/Utilities/QueryParameters.cs.
//
// WHY NOT `URLComponents`: its percent-encoding is the RFC 3986 *query* rule, not the WHATWG
// `application/x-www-form-urlencoded` rule the browser's `URLSearchParams.toString()` uses. A
// comma comes back as a literal `,` rather than `%2C`, and a space as `%20` rather than `+`, so a
// link written on iOS would not be byte-identical to one written by the web or .NET SDK. This
// type writes the WHATWG rule out by hand: a space is `+`, and only ASCII alphanumerics plus `*`,
// `-`, `.` and `_` survive unescaped.

import Foundation

/// One decoded `name=value` pair, in the order it appeared.
public struct CatalogQueryItem: Sendable, Equatable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// An ordered, decoded query string. Repeated names are kept, which is what makes the
/// `?addons=a&addons=b` form readable as the list it is.
public struct CatalogQuery: Sendable, Equatable {
    public private(set) var items: [CatalogQueryItem]

    public init() {
        items = []
    }

    public init(items: [CatalogQueryItem]) {
        self.items = items
    }

    /// Normalise anything URL-shaped into parameters: a full URL, a query string with or without
    /// its leading `?`, or an empty string (JS `asSearchParams`).
    public static func parse(_ searchOrUrl: String?) -> CatalogQuery {
        guard let searchOrUrl, !searchOrUrl.isEmpty else { return CatalogQuery() }

        var withoutFragment: String = searchOrUrl
        if let hash = withoutFragment.firstIndex(of: "#") {
            withoutFragment = String(withoutFragment[withoutFragment.startIndex..<hash])
        }

        let search: String
        if let mark = withoutFragment.firstIndex(of: "?") {
            search = String(withoutFragment[withoutFragment.index(after: mark)...])
        } else {
            search = withoutFragment
        }

        return parse(search: search)
    }

    /// Parse a URL's query component. Universal links and custom-scheme deep links
    /// (`myapp://signup?tier=…`) both land here, which is why the query is taken from
    /// `URLComponents` rather than from the raw text: a `?` inside a value must not re-split the
    /// string.
    public static func parse(url: URL) -> CatalogQuery {
        let components: URLComponents? = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let encoded = components?.percentEncodedQuery {
            return parse(search: encoded)
        }
        // An opaque URL (`myapp:signup?tier=…`) has no component query; fall back to the raw text,
        // which `parse(_:)` reduces to whatever follows the first `?` — but only when there is
        // one, so a query-less link does not read its own path as a parameter name.
        let text: String = url.absoluteString
        guard text.contains("?") else { return CatalogQuery() }
        return parse(text)
    }

    /// Parse a bare query string — no fragment handling, no `?` search. Everything above funnels
    /// here once it has isolated the query.
    static func parse(search: String) -> CatalogQuery {
        var query = CatalogQuery()
        guard !search.isEmpty else { return query }

        // Empty sequences are dropped (`split`'s default), so `a=1&&b=2` reads as two pairs.
        for sequence in search.split(separator: "&") {
            let piece: String = String(sequence)
            if piece.isEmpty { continue }

            if let equals = piece.firstIndex(of: "=") {
                let name: String = String(piece[piece.startIndex..<equals])
                let value: String = String(piece[piece.index(after: equals)...])
                query.items.append(CatalogQueryItem(name: decode(name), value: decode(value)))
            } else {
                // `?flag` is a name with an empty value, as URLSearchParams reads it.
                query.items.append(CatalogQueryItem(name: decode(piece), value: ""))
            }
        }

        return query
    }

    /// The first value under `name`, or nil when there is none.
    public func first(_ name: String) -> String? {
        for item in items where item.name == name {
            return item.value
        }
        return nil
    }

    /// Every value under `name`, so the repeated-parameter form reads as the list it is.
    public func all(_ name: String) -> [String] {
        var values: [String] = []
        for item in items where item.name == name {
            values.append(item.value)
        }
        return values
    }

    /// Set one value, replacing any existing ones — `URLSearchParams.set`.
    ///
    /// WHATWG: "set the value of the FIRST such name-value pair to value and remove the others",
    /// so the walk runs forward, the first match is replaced where it stands, and every later
    /// match is dropped. Walking backwards would keep the last occurrence's slot.
    public mutating func set(_ name: String, _ value: String) {
        var replaced = false
        var index = 0
        while index < items.count {
            if items[index].name != name {
                index += 1
                continue
            }
            if replaced {
                items.remove(at: index)
            } else {
                items[index] = CatalogQueryItem(name: name, value: value)
                replaced = true
                index += 1
            }
        }
        if !replaced {
            items.append(CatalogQueryItem(name: name, value: value))
        }
    }

    /// The query string, without a leading `?`.
    public var queryString: String {
        var out = ""
        for item in items {
            if !out.isEmpty { out.append("&") }
            out.append(Self.encode(item.name))
            out.append("=")
            out.append(Self.encode(item.value))
        }
        return out
    }

    // MARK: - WHATWG application/x-www-form-urlencoded

    private static let hexDigits: [Character] = Array("0123456789ABCDEF")

    static func decode(_ value: String) -> String {
        if value.isEmpty { return "" }
        let spaced: String = value.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }

    static func encode(_ value: String) -> String {
        var out = ""
        for byte in Array(value.utf8) {
            let character = Character(UnicodeScalar(byte))
            if character == " " {
                out.append("+")
            } else if (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 90)
                || (byte >= 97 && byte <= 122)
                || character == "*" || character == "-" || character == "." || character == "_" {
                out.append(character)
            } else {
                out.append("%")
                out.append(hexDigits[Int(byte >> 4)])
                out.append(hexDigits[Int(byte & 0x0F)])
            }
        }
        return out
    }
}
