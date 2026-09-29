// Campaign Attribution normalization — a port of @wildwood/core/src/attribution/attributionRules.ts
// (the client half of WildwoodAPI's AttributionRules). Clients pre-reduce (host only, path only, no
// query string); the server re-normalizes and never trusts these values. Keep the ports in step.

import Foundation
#if canImport(UIKit)
import UIKit
#endif

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
        result.funnelTrackingEnabled = config.isEnabled && config.funnelTrackingEnabled
        result.customEventNames = normalizeCustomEventNames(config.customEventNames)
        return result
    }

    // MARK: - Funnel events (mirrors @wildwood/core types.ts, funnelTracker.ts and signupFunnel.ts)

    /// Inactivity after which a funnel session ends and the next event starts a new one.
    static let sessionTimeout: TimeInterval = 30 * 60
    /// Seconds between timed flushes while events are queued.
    static let flushIntervalSeconds: Int = 5
    /// Most events one POST api/attribution/events request may carry.
    static let maxEventsPerRequest = 25
    /// Calls buffered while the config loads; later ones are dropped.
    static let maxPendingBeforeConfig = 50
    /// Events held for sending; later ones are dropped until a flush drains the queue.
    static let maxQueuedEvents = 200
    static let funnelLabelMaxLength = 100
    static let maxCustomEventNames = 50
    static let scrollMilestones: [Double] = [25, 50, 75, 100]
    static let maxTimeOnPageSeconds: Double = 86_400
    /// Keeps a request body well under the server's 32 KB cap.
    static let maxBodyBytes = 30_000

    /// Funnel events a client may send. Configured custom names are allowed on top of these.
    static let funnelClientEvents: Set<String> = [
        "page_view", "engaged", "scroll_depth", "time_on_page", "cta_click",
        "signup_view", "signup_start", "signup_submit", "signup_error", "plan_selected", "checkout_start",
    ]
    /// Funnel events only the server records. A client request carrying one is refused, so they are dropped.
    static let funnelServerOnlyEvents: Set<String> = ["signup_complete", "trial_started", "purchase"]
    /// Sent at most once per session per label (the server dedups these too).
    static let oneShotPerLabelEvents: Set<String> = [
        "signup_view", "signup_start", "signup_submit", "plan_selected", "checkout_start",
    ]
    /// The steps the app's "Track signup steps" switch gates.
    static let signupStepEvents: Set<String> = ["signup_view", "signup_start", "signup_submit", "signup_error"]

    /// Whether the value has the shape of a funnel event name (`^[a-z0-9_]{1,40}$`).
    static func isFunnelEventName(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return (1...40).contains(bytes.count)
            && bytes.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 95 }
    }

    /// A config's custom names: trimmed, lowercased, well formed, not a standard or server-only name,
    /// deduplicated, and at most ``maxCustomEventNames``.
    static func normalizeCustomEventNames(_ names: [String]) -> [String] {
        var kept: [String] = []
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard isFunnelEventName(name), !funnelClientEvents.contains(name),
                  !funnelServerOnlyEvents.contains(name), !kept.contains(name)
            else { continue }
            kept.append(name)
            if kept.count >= maxCustomEventNames { break }
        }
        return kept
    }

    /// A caller-supplied page or screen path: no query or fragment, a leading "/", capped. Nil when empty.
    static func funnelPath(_ raw: String) -> String? {
        let cut = raw.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first
            .map(String.init) ?? ""
        let beforeFragment = cut.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first
            .map(String.init) ?? ""
        let trimmed = beforeFragment.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let path = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        return truncate(path, maxUTF16: pathMaxLength)
    }

    /// A signup_error label reduced to the server's category shape (`^[a-z0-9_]{1,40}$`), `unknown`
    /// when nothing is left.
    static func signupErrorLabel(_ label: String?) -> String {
        var category = ""
        var lastWasSeparator = false
        for byte in (label ?? "").lowercased().utf8 {
            let keep = (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) || byte == 95
            if keep {
                category.append(Character(UnicodeScalar(byte)))
                lastWasSeparator = false
            } else if !lastWasSeparator {
                category.append("_")
                lastWasSeparator = true
            }
        }
        category = trimUnderscores(category)
        if category.count > 40 { category = String(category.prefix(40)) }
        while category.hasSuffix("_") { category.removeLast() }
        return category.isEmpty ? "unknown" : category
    }

    private static func trimUnderscores(_ value: String) -> String {
        var result = Substring(value)
        while result.hasPrefix("_") { result = result.dropFirst() }
        while result.hasSuffix("_") { result = result.dropLast() }
        return String(result)
    }

    // MARK: - Device class

    #if canImport(UIKit)
    /// A phone reports `mobile`, an iPad `tablet`, and an iPad app running on a Mac `desktop`.
    static func deviceClass(for idiom: UIUserInterfaceIdiom) -> String {
        switch idiom {
        case .pad:
            return "tablet"
        case .mac:
            return "desktop"
        default:
            return "mobile"
        }
    }

    @MainActor
    static func currentDeviceClass() -> String {
        deviceClass(for: UIDevice.current.userInterfaceIdiom)
    }
    #else
    @MainActor
    static func currentDeviceClass() -> String {
        "desktop"
    }
    #endif
}

/// The registration funnel's shared rules: the `signup_error` categories and the plan keys the
/// `plan_selected` / `checkout_start` labels carry. A port of `signupFunnel.ts` in `@wildwood/react-shared`
/// (and `AttributionRules` in the .NET SDK). A category comes from an error CODE or HTTP status, never
/// from a message, so a label never carries what the visitor typed or what the server said.
public enum SignupFunnelRules {
    /// Every category a `signup_error` label is drawn from.
    public static let errorCategories: [String] = [
        "validation", "email_taken", "username_taken", "password_policy", "captcha", "invalid_token",
        "registration_closed", "rate_limited", "network", "server", "unknown",
    ]

    /// Codes compared with case and separators removed (`USERNAME_EXISTS` and `UsernameExists` match).
    private static let codeCategories: [String: String] = [
        "USERNAMEEXISTS": "username_taken",
        "USERNAMETAKEN": "username_taken",
        "USEREXISTS": "email_taken",
        "EMAILEXISTS": "email_taken",
        "EMAILTAKEN": "email_taken",
        "DUPLICATEEMAIL": "email_taken",
        "PASSWORDINVALID": "password_policy",
        "PASSWORDPOLICY": "password_policy",
        "INVALIDTOKEN": "invalid_token",
        "REGISTRATIONTOKENREJECTED": "invalid_token",
        "VALIDATIONERROR": "validation",
        "VALIDATION": "validation",
        "EMAILREQUIRED": "validation",
        "USERNAMEREQUIRED": "validation",
        "REGISTRATIONNOTALLOWED": "registration_closed",
        "FORBIDDEN": "registration_closed",
        "RATELIMITED": "rate_limited",
        "RATELIMITEXCEEDED": "rate_limited",
        "NETWORKERROR": "network",
        "TIMEOUT": "network",
        "SERVERERROR": "server",
        "INTERNALERROR": "server",
        "DATABASEERROR": "server",
        "EXECUTIONSTRATEGYERROR": "server",
        "USERCREATIONFAILED": "server",
    ]

    /// The category for a server or client error code (WildwoodAPI's `errorCode`, a
    /// ``WildwoodError/Code`` raw value, or a flow code such as `registration_token_rejected`), falling
    /// back on the HTTP status (0 for a request that never reached the server). Unrecognized is `unknown`.
    public static func errorCategory(code: String?, status: Int? = nil) -> String {
        var key = ""
        for scalar in (code ?? "").uppercased().unicodeScalars
        where (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 48 && scalar.value <= 57) {
            key.unicodeScalars.append(scalar)
        }
        if !key.isEmpty {
            if let known = codeCategories[key] { return known }
            if key.contains("CAPTCHA") { return "captcha" }
            if key.hasPrefix("TOKEN") { return "invalid_token" }
            if key.hasPrefix("PASSWORD") { return "password_policy" }
            if key.contains("REGISTRATIONDISABLED") || key.contains("NOTALLOWED") { return "registration_closed" }
        }
        if let status {
            if status == 0 { return "network" }
            if status == 429 { return "rate_limited" }
            if status >= 500 { return "server" }
            if status == 400 || status == 422 { return "validation" }
        }
        return "unknown"
    }

    /// The category for anything a registration can throw: a ``WildwoodError`` (the server's own
    /// `errorCode` from the response body first, then the client's code and status) or a transport
    /// failure (`URLError`). Messages are never read.
    public static func errorCategory(for error: any Error) -> String {
        if let wildwood = error as? WildwoodError {
            if let body = wildwood.details,
               let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let serverCode = object["errorCode"] as? String, !serverCode.isEmpty {
                let fromServer = errorCategory(code: serverCode)
                if fromServer != "unknown" { return fromServer }
            }
            return errorCategory(code: wildwood.code.rawValue, status: wildwood.status)
        }
        if error is URLError { return "network" }
        return "unknown"
    }

    /// A stable plan key for `plan_selected` / `checkout_start`: the tier's (or pricing option's) id,
    /// else a slug of its name, capped at 100 characters. Nil when there is neither.
    public static func planKey(id: String?, name: String? = nil) -> String? {
        let trimmed = (id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return String(trimmed.prefix(100)) }
        var slug = ""
        var lastWasSeparator = false
        for byte in (name ?? "").lowercased().utf8 {
            if (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) {
                slug.append(Character(UnicodeScalar(byte)))
                lastWasSeparator = false
            } else if !lastWasSeparator {
                slug.append("_")
                lastWasSeparator = true
            }
        }
        while slug.hasPrefix("_") { slug.removeFirst() }
        while slug.hasSuffix("_") { slug.removeLast() }
        if slug.count > 100 { slug = String(slug.prefix(100)) }
        return slug.isEmpty ? nil : slug
    }
}
