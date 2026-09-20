// Campaign Attribution models — mirrors @wildwood/core/src/attribution/types.ts and the
// WildwoodAPI attribution DTOs (camelCase JSON).

import Foundation

/// One campaign touch. Clients send host and path only; WildwoodAPI re-normalizes every value.
public struct AttributionTouch: Codable, Sendable, Equatable {
    /// `utm_source`, or the referrer host for a referral touch. Lowercased.
    public var source: String?
    /// `utm_medium`, or `referral`. Lowercased.
    public var medium: String?
    public var campaign: String?
    public var term: String?
    public var content: String?
    /// Click-id parameter name, e.g. `gclid` or `rdt_cid`.
    public var clickIdName: String?
    public var clickIdValue: String?
    /// External referrer host with a leading `www.` removed.
    public var referrerHost: String?
    public var landingHost: String?
    public var landingPath: String?
    /// Values of the app's allowlisted extra query parameters.
    public var extraParams: [String: String]?
    /// ISO-8601 capture time.
    public var occurredAt: String

    public init(
        source: String? = nil,
        medium: String? = nil,
        campaign: String? = nil,
        term: String? = nil,
        content: String? = nil,
        clickIdName: String? = nil,
        clickIdValue: String? = nil,
        referrerHost: String? = nil,
        landingHost: String? = nil,
        landingPath: String? = nil,
        extraParams: [String: String]? = nil,
        occurredAt: String
    ) {
        self.source = source
        self.medium = medium
        self.campaign = campaign
        self.term = term
        self.content = content
        self.clickIdName = clickIdName
        self.clickIdValue = clickIdValue
        self.referrerHost = referrerHost
        self.landingHost = landingHost
        self.landingPath = landingPath
        self.extraParams = extraParams
        self.occurredAt = occurredAt
    }
}

/// The attribution payload a registration request carries (the server's AttributionInput).
public struct AttributionPayload: Codable, Sendable, Equatable {
    public var version: Int
    public var visitorKey: String
    public var firstTouch: AttributionTouch?
    public var lastTouch: AttributionTouch?
    /// `web`, `ios`, `android`, or `unknown`.
    public var platform: String
    /// `js`, `dotnet`, or `swift`.
    public var sdk: String

    public init(
        version: Int = 1,
        visitorKey: String,
        firstTouch: AttributionTouch?,
        lastTouch: AttributionTouch?,
        platform: String,
        sdk: String = "swift"
    ) {
        self.version = version
        self.visitorKey = visitorKey
        self.firstTouch = firstTouch
        self.lastTouch = lastTouch
        self.platform = platform
        self.sdk = sdk
    }
}

/// Returned by GET api/attribution/config?appId=. Missing fields take the server defaults.
public struct PublicAttributionConfig: Codable, Sendable, Equatable {
    public var appId: String
    public var isEnabled: Bool
    public var captureFirstTouch: Bool
    public var captureLastTouch: Bool
    public var attributionWindowDays: Int
    /// Consent category name that must be granted before touches are persisted.
    public var persistenceConsentCategory: String
    public var captureClickIds: Bool
    public var captureReferrer: Bool
    public var extraAllowedParamNames: [String]
    public var beaconEnabled: Bool

    public init(
        appId: String = "",
        isEnabled: Bool = false,
        captureFirstTouch: Bool = true,
        captureLastTouch: Bool = true,
        attributionWindowDays: Int = 30,
        persistenceConsentCategory: String = "Analytics",
        captureClickIds: Bool = true,
        captureReferrer: Bool = true,
        extraAllowedParamNames: [String] = [],
        beaconEnabled: Bool = false
    ) {
        self.appId = appId
        self.isEnabled = isEnabled
        self.captureFirstTouch = captureFirstTouch
        self.captureLastTouch = captureLastTouch
        self.attributionWindowDays = attributionWindowDays
        self.persistenceConsentCategory = persistenceConsentCategory
        self.captureClickIds = captureClickIds
        self.captureReferrer = captureReferrer
        self.extraAllowedParamNames = extraAllowedParamNames
        self.beaconEnabled = beaconEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appId = try c.decodeIfPresent(String.self, forKey: .appId) ?? ""
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        captureFirstTouch = try c.decodeIfPresent(Bool.self, forKey: .captureFirstTouch) ?? true
        captureLastTouch = try c.decodeIfPresent(Bool.self, forKey: .captureLastTouch) ?? true
        attributionWindowDays = try c.decodeIfPresent(Int.self, forKey: .attributionWindowDays) ?? 30
        persistenceConsentCategory = try c.decodeIfPresent(String.self, forKey: .persistenceConsentCategory) ?? "Analytics"
        captureClickIds = try c.decodeIfPresent(Bool.self, forKey: .captureClickIds) ?? true
        captureReferrer = try c.decodeIfPresent(Bool.self, forKey: .captureReferrer) ?? true
        extraAllowedParamNames = try c.decodeIfPresent([String].self, forKey: .extraAllowedParamNames) ?? []
        beaconEnabled = try c.decodeIfPresent(Bool.self, forKey: .beaconEnabled) ?? false
    }
}

/// The attribution service's current state.
public struct AttributionState: Sendable, Equatable {
    public var visitorKey: String
    public var first: AttributionTouch?
    public var last: AttributionTouch?
    /// True while the touches are held in storage (the consent category allowed it).
    public var persisted: Bool
    public var config: PublicAttributionConfig?
}

/// The persisted blob under `WildwoodStorageKeys.attribution` (same shape as the JS and .NET SDKs).
struct StoredAttribution: Codable, Sendable {
    var v: Int
    var visitorKey: String
    var first: AttributionTouch?
    var last: AttributionTouch?
    var updatedAt: String
}

/// Posted to POST api/attribution/touch?appId= (the anonymous landing beacon).
struct AttributionTouchRequest: Encodable, Sendable {
    let appId: String
    let visitorKey: String
    let touch: AttributionTouch
    let platform: String
}

/// Posted to POST api/attribution/claim?appId= (authenticated) after a provider signup. The wire
/// shape is the payload with `appId` alongside it, exactly as the JS SDK spreads it.
struct AttributionClaimRequest: Encodable, Sendable {
    let appId: String
    let version: Int
    let visitorKey: String
    let firstTouch: AttributionTouch?
    let lastTouch: AttributionTouch?
    let platform: String
    let sdk: String

    init(appId: String, payload: AttributionPayload) {
        self.appId = appId
        self.version = payload.version
        self.visitorKey = payload.visitorKey
        self.firstTouch = payload.firstTouch
        self.lastTouch = payload.lastTouch
        self.platform = payload.platform
        self.sdk = payload.sdk
    }
}

/// Result of a claim. `reason` is nil when the attribution was recorded; otherwise it is the
/// server's refusal (`Disabled`, `WindowExpired`, `AlreadyRecorded`, `Empty`, `NotAppUser`) —
/// a String, like every other server-defined code in this SDK, so a new one never fails decoding.
public struct AttributionClaimResponse: Codable, Sendable, Equatable {
    public var recorded: Bool
    public var reason: String?

    public init(recorded: Bool = false, reason: String? = nil) {
        self.recorded = recorded
        self.reason = reason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recorded = try c.decodeIfPresent(Bool.self, forKey: .recorded) ?? false
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
    }
}

/// The slice of ``AttributionService`` that registration needs; ``AuthService`` depends on nothing
/// else. Closures rather than a protocol because `AttributionService` is main-actor isolated while
/// `AuthService` is not: the hop is explicit, and a test can supply a fake in one line.
public struct AttributionRegistrationSource: Sendable {
    /// The payload for a registration request, or nil when there is nothing to send.
    public var payload: @Sendable () async -> AttributionPayload?
    /// Drops the captured touches after a recorded signup.
    public var clear: @Sendable () async -> Void

    public init(
        payload: @escaping @Sendable () async -> AttributionPayload?,
        clear: @escaping @Sendable () async -> Void
    ) {
        self.payload = payload
        self.clear = clear
    }
}
