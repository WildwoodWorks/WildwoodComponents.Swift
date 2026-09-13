// Campaign Attribution normalization — a port of @wildwood/core/src/attribution/attributionRules.ts
// (the client half of WildwoodAPI's AttributionRules). Clients pre-reduce (host only, path only, no
// query string); the server re-normalizes and never trusts these values. Keep the ports in step.

import Foundation

enum AttributionRules {
    static let sourceMediumMaxLength = 100
    static let campaignTermContentMaxLength = 200
    static let hostMaxLength = 253
    static let pathMaxLength = 500
    static let extraParamsJsonMaxLength = 2000
    static let maxExtraParamNames = 10
    static let defaultWindowDays = 30

    /// Ad-platform click ids in priority order: the first one present with a well-formed value wins.
    static let clickIdParams = ["gclid", "gbraid", "wbraid", "fbclid", "msclkid", "ttclid", "li_fat_id", "twclid", "rdt_cid"]

    // MARK: - Tokens

    /// Trims, rejects a value containing control or format characters, optionally lowercases, and caps the
    /// length in UTF-16 code units (as the JS and .NET SDKs do) without splitting a scalar. Nil when empty.
    static func normalizeToken(_ value: String?, maxLength: Int, lowercase: Bool) -> String? {
        guard let value else { return nil }
        var token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty { return nil }
        let hasControlOrFormat = token.unicodeScalars.contains {
            $0.properties.generalCategory == .control || $0.properties.generalCategory == .format
        }
        if hasControlOrFormat { return nil }
        if lowercase { token = token.lowercased() }
        token = truncate(token, maxUTF16: maxLength)
        while let last = token.last, last.isWhitespace { token.removeLast() }
        return token.isEmpty ? nil : token
    }

    static func truncate(_ value: String, maxUTF16: Int) -> String {
        guard value.utf16.count > maxUTF16 else { return value }
        var scalars = String.UnicodeScalarView()
        var units = 0
        for scalar in value.unicodeScalars {
            let width = scalar.utf16.count
            if units + width > maxUTF16 { break }
            scalars.append(scalar)
            units += width
        }
        return String(scalars)
    }

    static func isParamName(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return (1...32).contains(bytes.count)
            && bytes.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 95 }
    }

    static func isClickIdValue(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return (1...200).contains(bytes.count) && bytes.allSatisfy { isAlphanumeric($0) || $0 == 46 || $0 == 95 || $0 == 126 || $0 == 45 }
    }

    static func isValidVisitorKey(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return (8...100).contains(bytes.count) && bytes.allSatisfy { isAlphanumeric($0) || $0 == 95 || $0 == 45 }
    }

    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57)
    }

    // MARK: - Dates

    static func iso8601(_ date: Date) -> String {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
    }

    static func parseDate(_ value: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) { return date }
        return try? Date.ISO8601FormatStyle().parse(value)
    }

    /// True when the touch is older than the window, or its capture time cannot be read.
    static func isExpired(_ touch: AttributionTouch, windowDays: Int, now: Date) -> Bool {
        guard let at = parseDate(touch.occurredAt) else { return true }
        return at < now.addingTimeInterval(-Double(windowDays) * 86_400)
    }

    static func clampWindowDays(_ days: Int) -> Int {
        min(365, max(1, days))
    }

    // MARK: - URLs

    /// Query items with `+` read as a space and percent-decoding applied, as URLSearchParams does.
    static func queryItems(of url: URL) -> [(name: String, value: String)] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems else { return [] }
        return items.map { item in
            let name = item.name.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? item.name
            let value = (item.value ?? "").replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
            return (name, value)
        }
    }

    static func firstValue(_ items: [(name: String, value: String)], _ name: String) -> String? {
        items.first(where: { $0.name == name })?.value
    }

    static func hostName(_ url: URL, stripWww: Bool, includePort: Bool) -> String? {
        guard var host = url.host(percentEncoded: false)?.lowercased() else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        if host.isEmpty { return nil }
        if stripWww, host.hasPrefix("www."), host.count > 4 { host.removeFirst(4) }
        if includePort, let port = url.port { host += ":\(port)" }
        return host.utf16.count <= hostMaxLength ? host : nil
    }

    static func normalizePath(_ url: URL) -> String {
        var path = url.path(percentEncoded: true)
        if path.isEmpty { path = "/" }
        if !path.hasPrefix("/") { path = "/" + path }
        return truncate(path, maxUTF16: pathMaxLength)
    }

    static func extraParams(_ items: [(name: String, value: String)], allowedNames: [String]) -> [String: String]? {
        var kept: [String: String] = [:]
        for raw in allowedNames.prefix(maxExtraParamNames) {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard isParamName(name), kept[name] == nil,
                  let value = normalizeToken(firstValue(items, name), maxLength: campaignTermContentMaxLength, lowercase: false)
            else { continue }
            kept[name] = value
        }
        guard !kept.isEmpty else { return nil }
        if let data = try? JSONEncoder().encode(kept), data.count > extraParamsJsonMaxLength { return nil }
        return kept
    }

    /// One campaign touch from a URL (a deep link or universal link) and an optional referrer; nil for a
    /// direct visit (no UTM tag, click id, external referrer or allowlisted extra parameter).
    static func parseTouch(
        url: URL,
        referrer: URL?,
        captureClickIds: Bool,
        captureReferrer: Bool,
        extraAllowedParamNames: [String],
        now: Date
    ) -> AttributionTouch? {
        let items = queryItems(of: url)
        var source = normalizeToken(firstValue(items, "utm_source"), maxLength: sourceMediumMaxLength, lowercase: true)
        var medium = normalizeToken(firstValue(items, "utm_medium"), maxLength: sourceMediumMaxLength, lowercase: true)
        let campaign = normalizeToken(firstValue(items, "utm_campaign"), maxLength: campaignTermContentMaxLength, lowercase: false)
        let term = normalizeToken(firstValue(items, "utm_term"), maxLength: campaignTermContentMaxLength, lowercase: false)
        let content = normalizeToken(firstValue(items, "utm_content"), maxLength: campaignTermContentMaxLength, lowercase: false)

        var clickIdName: String?
        var clickIdValue: String?
        if captureClickIds {
            for name in clickIdParams {
                let value = (firstValue(items, name) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty, isClickIdValue(value) {
                    clickIdName = name
                    clickIdValue = value
                    break
                }
            }
        }

        let extras = extraParams(items, allowedNames: extraAllowedParamNames)

        var referrerHost: String?
        if captureReferrer, let referrer, let scheme = referrer.scheme?.lowercased(), scheme == "http" || scheme == "https",
           let host = hostName(referrer, stripWww: true, includePort: false),
           host != hostName(url, stripWww: true, includePort: false) {
            // A self-referral is not a campaign.
            referrerHost = host
        }

        let hasUtm = source != nil || medium != nil || campaign != nil || term != nil || content != nil
        if !hasUtm, let referrerHost {
            source = truncate(referrerHost, maxUTF16: sourceMediumMaxLength)
            medium = "referral"
        }

        if !hasUtm && clickIdName == nil && referrerHost == nil && extras == nil { return nil }

        return AttributionTouch(
            source: source,
            medium: medium,
            campaign: campaign,
            term: term,
            content: content,
            clickIdName: clickIdName,
            clickIdValue: clickIdValue,
            referrerHost: referrerHost,
            landingHost: hostName(url, stripWww: false, includePort: true),
            landingPath: normalizePath(url),
            extraParams: extras,
            occurredAt: iso8601(now)
        )
    }

    /// The config response normalized defensively: clamped window, known category, well-formed extra names,
    /// and no beacon while attribution itself is off.
    static func normalized(_ config: PublicAttributionConfig, fallbackAppId: String) -> PublicAttributionConfig {
        var result = config
        if result.appId.isEmpty { result.appId = fallbackAppId }
        result.attributionWindowDays = clampWindowDays(config.attributionWindowDays)
        // An unrecognized category falls back to Analytics: persistence then waits for opt-in, never the reverse.
        if ConsentCategory(rawValue: config.persistenceConsentCategory) == nil {
            result.persistenceConsentCategory = ConsentCategory.analytics.rawValue
        }
        result.extraAllowedParamNames = Array(
            config.extraAllowedParamNames
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter(isParamName)
                .prefix(maxExtraParamNames)
        )
        result.beaconEnabled = config.isEnabled && config.beaconEnabled
        return result
    }
}
