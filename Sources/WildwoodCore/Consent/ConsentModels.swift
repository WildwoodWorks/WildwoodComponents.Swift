// Consent Management models — ported from @wildwood/core/src/consent/types.ts and mirrored by
// WildwoodComponents.Shared/Models/ConsentModels.cs.
//
// Field names are camelCase to match the WildwoodAPI wire format (the default Codable key strategy);
// enum *values* serialize as PascalCase string names (e.g. "Analytics", "AcceptAll").

import Foundation

/// A consent category. `StrictlyNecessary` is always granted; the rest are opt-in.
public enum ConsentCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case strictlyNecessary = "StrictlyNecessary"
    case functional = "Functional"
    case analytics = "Analytics"
    case advertising = "Advertising"
    case sensitive = "Sensitive"

    /// Non-necessary categories the visitor can opt into, in display order.
    public static let nonNecessary: [ConsentCategory] = [.functional, .analytics, .advertising, .sensitive]

    /// Categories that GPC forces to opted-out.
    public static let gpcForcedOff: [ConsentCategory] = [.advertising, .sensitive]

    /// Human-readable label for the preferences UI.
    public var displayName: String {
        switch self {
        case .strictlyNecessary: return "Strictly necessary"
        case .functional: return "Functional"
        case .analytics: return "Analytics"
        case .advertising: return "Advertising"
        case .sensitive: return "Sensitive"
        }
    }
}

/// How a consent decision was reached. Recorded with each decision as evidence.
public enum ConsentMethod: String, Codable, Sendable {
    case acceptAll = "AcceptAll"
    case rejectAll = "RejectAll"
    case custom = "Custom"
    case gpc = "Gpc"
    case nonTargetDefault = "NonTargetDefault"
}

/// A consent-gated third-party script from the registry. Decoded for completeness; on Apple
/// platforms there is no DOM, so scripts are never injected (mirrors the React Native engine).
public struct ConsentScript: Codable, Sendable, Equatable {
    public var id: String
    public var providerType: String
    public var category: String
    public var injectionMode: String

    public init(id: String = "", providerType: String = "", category: String = "", injectionMode: String = "") {
        self.id = id
        self.providerType = providerType
        self.category = category
        self.injectionMode = injectionMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        providerType = try c.decodeIfPresent(String.self, forKey: .providerType) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        injectionMode = try c.decodeIfPresent(String.self, forKey: .injectionMode) ?? ""
    }
}

/// The server's geo decision for this visitor.
public struct GeoDecision: Codable, Sendable, Equatable {
    public var aware: Bool
    public var inTarget: Bool
    public var resolvedTags: [String]

    public init(aware: Bool = false, inTarget: Bool = false, resolvedTags: [String] = []) {
        self.aware = aware
        self.inTarget = inTarget
        self.resolvedTags = resolvedTags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aware = try c.decodeIfPresent(Bool.self, forKey: .aware) ?? false
        inTarget = try c.decodeIfPresent(Bool.self, forKey: .inTarget) ?? false
        resolvedTags = try c.decodeIfPresent([String].self, forKey: .resolvedTags) ?? []
    }
}

/// Banner appearance hints.
public struct ConsentAppearance: Codable, Sendable, Equatable {
    public var position: String?
    public var theme: String?

    public init(position: String? = nil, theme: String? = nil) {
        self.position = position
        self.theme = theme
    }
}

/// Localizable banner copy.
public struct ConsentBannerText: Codable, Sendable, Equatable {
    public var title: String?
    public var body: String?
    public var acceptAll: String?
    public var rejectAll: String?
    public var manage: String?

    public init(
        title: String? = nil,
        body: String? = nil,
        acceptAll: String? = nil,
        rejectAll: String? = nil,
        manage: String? = nil
    ) {
        self.title = title
        self.body = body
        self.acceptAll = acceptAll
        self.rejectAll = rejectAll
        self.manage = manage
    }
}

/// The merged public consent config returned by `GET /api/consent/config`.
public struct PublicConsentConfig: Codable, Sendable, Equatable {
    public var appId: String
    public var enabled: Bool
    public var version: Int
    public var geo: GeoDecision
    public var honorGpc: Bool
    public var showDoNotSell: Bool
    public var showLimitSensitive: Bool
    /// "LoadAll" or "NecessaryOnly" — kept as a string to tolerate future values (matches the .NET model).
    public var nonTargetDefault: String
    public var categories: [ConsentCategory]
    public var appearance: ConsentAppearance?
    public var bannerText: ConsentBannerText?
    public var privacyPolicyUrl: String?
    public var accessibilityUrl: String?
    public var scripts: [ConsentScript]

    public init(
        appId: String = "",
        enabled: Bool = false,
        version: Int = 0,
        geo: GeoDecision = GeoDecision(),
        honorGpc: Bool = false,
        showDoNotSell: Bool = false,
        showLimitSensitive: Bool = false,
        nonTargetDefault: String = "LoadAll",
        categories: [ConsentCategory] = [],
        appearance: ConsentAppearance? = nil,
        bannerText: ConsentBannerText? = nil,
        privacyPolicyUrl: String? = nil,
        accessibilityUrl: String? = nil,
        scripts: [ConsentScript] = []
    ) {
        self.appId = appId
        self.enabled = enabled
        self.version = version
        self.geo = geo
        self.honorGpc = honorGpc
        self.showDoNotSell = showDoNotSell
        self.showLimitSensitive = showLimitSensitive
        self.nonTargetDefault = nonTargetDefault
        self.categories = categories
        self.appearance = appearance
        self.bannerText = bannerText
        self.privacyPolicyUrl = privacyPolicyUrl
        self.accessibilityUrl = accessibilityUrl
        self.scripts = scripts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appId = try c.decodeIfPresent(String.self, forKey: .appId) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        geo = try c.decodeIfPresent(GeoDecision.self, forKey: .geo) ?? GeoDecision()
        honorGpc = try c.decodeIfPresent(Bool.self, forKey: .honorGpc) ?? false
        showDoNotSell = try c.decodeIfPresent(Bool.self, forKey: .showDoNotSell) ?? false
        showLimitSensitive = try c.decodeIfPresent(Bool.self, forKey: .showLimitSensitive) ?? false
        nonTargetDefault = try c.decodeIfPresent(String.self, forKey: .nonTargetDefault) ?? "LoadAll"
        // Tolerate unknown category names from the server rather than failing the whole decode.
        let rawCategories = try c.decodeIfPresent([String].self, forKey: .categories) ?? []
        categories = rawCategories.compactMap(ConsentCategory.init(rawValue:))
        appearance = try c.decodeIfPresent(ConsentAppearance.self, forKey: .appearance)
        bannerText = try c.decodeIfPresent(ConsentBannerText.self, forKey: .bannerText)
        privacyPolicyUrl = try c.decodeIfPresent(String.self, forKey: .privacyPolicyUrl)
        accessibilityUrl = try c.decodeIfPresent(String.self, forKey: .accessibilityUrl)
        scripts = try c.decodeIfPresent([ConsentScript].self, forKey: .scripts) ?? []
    }
}

/// Posted to `POST /api/consent/record`.
public struct ConsentRecordRequest: Codable, Sendable, Equatable {
    public var appId: String
    public var visitorKey: String
    public var consentString: String
    public var method: ConsentMethod
    public var gpcPresent: Bool
    public var configVersion: Int

    public init(
        appId: String,
        visitorKey: String,
        consentString: String,
        method: ConsentMethod,
        gpcPresent: Bool,
        configVersion: Int
    ) {
        self.appId = appId
        self.visitorKey = visitorKey
        self.consentString = consentString
        self.method = method
        self.gpcPresent = gpcPresent
        self.configVersion = configVersion
    }
}

/// The visitor's current consent state.
public struct ConsentState: Sendable, Equatable {
    public var visitorKey: String
    /// Per-category granted flags (`.strictlyNecessary` is always true).
    public var categories: [ConsentCategory: Bool]
    public var configVersion: Int
    /// True once the visitor (or GPC / the non-target default) has produced a decision.
    public var decided: Bool
    public var gpcPresent: Bool

    public init(
        visitorKey: String,
        categories: [ConsentCategory: Bool],
        configVersion: Int,
        decided: Bool,
        gpcPresent: Bool
    ) {
        self.visitorKey = visitorKey
        self.categories = categories
        self.configVersion = configVersion
        self.decided = decided
        self.gpcPresent = gpcPresent
    }

    /// Current granted state for a category.
    public func isGranted(_ category: ConsentCategory) -> Bool {
        if category == .strictlyNecessary { return true }
        return categories[category] == true
    }

    /// Fresh category map with only `.strictlyNecessary` granted.
    public static func emptyCategories() -> [ConsentCategory: Bool] {
        [
            .strictlyNecessary: true,
            .functional: false,
            .analytics: false,
            .advertising: false,
            .sensitive: false,
        ]
    }
}

/// Result of `ConsentService.initialize()`: what the UI needs to render.
public struct ConsentInitResult: Sendable {
    public var config: PublicConsentConfig
    public var state: ConsentState
    /// Whether the banner should be shown to this visitor.
    public var shouldShowBanner: Bool

    public init(config: PublicConsentConfig, state: ConsentState, shouldShowBanner: Bool) {
        self.config = config
        self.state = state
        self.shouldShowBanner = shouldShowBanner
    }
}
