// Campaign Attribution service — the Swift port of @wildwood/core's AttributionService (parity
// minimum). Captures UTM tags, an ad-platform click id and the referrer from deep links and universal
// links, keeps a first and a last touch, persists them only once the app's consent category is granted,
// beacons the landing when the app has the beacon on, and hands the payload to registration.
//
// Usage:
//   .onOpenURL { url in client.attribution.capture(url: url) }
//   var request = RegistrationRequest(..., attribution: client.attribution.getForRegistration())
//   // after a successful signup: client.attribution.clear()
//
// ConsentService has no change stream, so call `consentDidChange()` after the visitor's consent decision
// to persist (or remove) the touches. Nothing here throws.

import Foundation

@MainActor
public final class AttributionService {
    private let http: WildwoodHttpClient
    private let storage: any WildwoodStorageAdapter
    private let consent: ConsentService
    private let platform: String
    private var appId: String
    private var initialized = false
    private var beaconed = Set<String>()

    public private(set) var config: PublicAttributionConfig?
    public private(set) var visitorKey: String
    public private(set) var first: AttributionTouch?
    public private(set) var last: AttributionTouch?
    public private(set) var persisted = false

    /// The platform payloads report by default on this OS.
    nonisolated public static var defaultPlatform: String {
        #if os(iOS) || os(visionOS)
        return "ios"
        #else
        return "unknown"
        #endif
    }

    public init(
        http: WildwoodHttpClient,
        storage: any WildwoodStorageAdapter,
        consent: ConsentService,
        defaultAppId: String,
        platform: String = AttributionService.defaultPlatform
    ) {
        self.http = http
        self.storage = storage
        self.consent = consent
        self.appId = defaultAppId
        self.platform = platform
        self.visitorKey = UUID().uuidString.lowercased()
    }

    public var state: AttributionState {
        AttributionState(visitorKey: visitorKey, first: first, last: last, persisted: persisted, config: config)
    }

    /// Loads the app's attribution config, restores stored touches and applies the consent gate. Call once
    /// at launch; later calls only re-apply the consent gate. Never throws.
    @discardableResult
    public func initialize(appId: String? = nil) async -> AttributionState {
        if let appId, !appId.isEmpty { self.appId = appId }
        if initialized {
            persistIfAllowed()
            return state
        }
        initialized = true

        let stored = readStored()
        config = await fetchConfig()

        if let config, !config.isEnabled {
            // Attribution is off for this app: hold nothing, and remove what an earlier launch stored.
            first = nil
            last = nil
            persisted = false
            storage.removeItem(WildwoodStorageKeys.attribution)
            return state
        }

        if let stored {
            if AttributionRules.isValidVisitorKey(stored.visitorKey) { visitorKey = stored.visitorKey }
            if let anchor = stored.first ?? stored.last,
               !AttributionRules.isExpired(anchor, windowDays: windowDays, now: Date()) {
                // A touch captured while the config loaded is newer than anything stored.
                first = stored.first ?? first
                last = last ?? stored.last
            }
        }

        persistIfAllowed()
        return state
    }

    /// Parses a URL (a deep link or universal link, from `.onOpenURL`) and applies it as a touch. Returns
    /// nil for a direct visit, which never overwrites the stored touches.
    @discardableResult
    public func capture(url: URL, referrer: URL? = nil) -> AttributionTouch? {
        if let config, !config.isEnabled { return nil }
        let now = Date()
        guard let touch = AttributionRules.parseTouch(
            url: url,
            referrer: referrer,
            captureClickIds: config?.captureClickIds ?? true,
            captureReferrer: config?.captureReferrer ?? true,
            extraAllowedParamNames: config?.extraAllowedParamNames ?? [],
            now: now
        ) else { return nil }

        if let current = first, AttributionRules.isExpired(current, windowDays: windowDays, now: now) {
            first = nil
            last = nil
        }
        last = touch
        if first == nil { first = touch }
        persistIfAllowed()
        beacon(touch)
        return touch
    }

    /// The payload for `RegistrationRequest.attribution`, or nil when attribution is off or nothing was captured.
    public func getForRegistration() -> AttributionPayload? {
        if let config, !config.isEnabled { return nil }
        guard first != nil || last != nil else { return nil }
        return AttributionPayload(visitorKey: visitorKey, firstTouch: first, lastTouch: last, platform: platform)
    }

    /// Drops the touches from memory and storage (after a recorded signup). The visitor key is kept.
    public func clear() {
        first = nil
        last = nil
        persisted = false
        storage.removeItem(WildwoodStorageKeys.attribution)
    }

    /// Re-applies the consent gate. Call after the visitor accepts, rejects or withdraws consent.
    public func consentDidChange() {
        persistIfAllowed()
    }

    // MARK: - Private

    private var windowDays: Int {
        config?.attributionWindowDays ?? AttributionRules.defaultWindowDays
    }

    private func fetchConfig() async -> PublicAttributionConfig? {
        guard !appId.isEmpty else { return nil }
        do {
            let raw: PublicAttributionConfig = try await http.get(
                "api/attribution/config?appId=\(WildwoodURL.queryComponent(appId))",
                skipAuth: true
            )
            return AttributionRules.normalized(raw, fallbackAppId: appId)
        } catch {
            // Fail open for capture (registration still carries the touch) and closed for persistence.
            return nil
        }
    }

    private func persistIfAllowed() {
        guard let config, config.isEnabled else { return }
        let category = ConsentCategory(rawValue: config.persistenceConsentCategory) ?? .analytics
        let allowed = category == .strictlyNecessary || consent.isGranted(category)

        if allowed {
            if first != nil || last != nil {
                writeStored()
                persisted = true
            } else {
                storage.removeItem(WildwoodStorageKeys.attribution)
                persisted = false
            }
            return
        }

        if consent.getState() != nil {
            // Consent state exists and does not grant the category: declined, withdrawn, or not answered
            // since the consent config changed. Memory only, nothing left behind.
            storage.removeItem(WildwoodStorageKeys.attribution)
            persisted = false
        }
        // No consent state yet: stay memory-only until consentDidChange().
    }

    private func readStored() -> StoredAttribution? {
        guard let raw = storage.getItem(WildwoodStorageKeys.attribution), let data = raw.data(using: .utf8),
              var stored = try? JSONDecoder().decode(StoredAttribution.self, from: data),
              stored.v == 1
        else { return nil }
        if let touch = stored.first, AttributionRules.parseDate(touch.occurredAt) == nil { stored.first = nil }
        if let touch = stored.last, AttributionRules.parseDate(touch.occurredAt) == nil { stored.last = nil }
        return stored
    }

    private func writeStored() {
        let blob = StoredAttribution(
            v: 1,
            visitorKey: visitorKey,
            first: first,
            last: last,
            updatedAt: AttributionRules.iso8601(Date())
        )
        guard let data = try? JSONEncoder().encode(blob), let json = String(data: data, encoding: .utf8) else { return }
        storage.setItem(WildwoodStorageKeys.attribution, json)
    }

    private func beacon(_ touch: AttributionTouch) {
        guard let config, config.isEnabled, config.beaconEnabled, !appId.isEmpty else { return }
        let key = "\(visitorKey)|\(touch.landingPath ?? "")"
        guard beaconed.insert(key).inserted else { return }

        let body = AttributionTouchRequest(appId: appId, visitorKey: visitorKey, touch: touch, platform: platform)
        // appId rides in the query string too: the server's rate-limit partition reads it, and it must match the body.
        let path = "api/attribution/touch?appId=\(WildwoodURL.queryComponent(appId))"
        let http = self.http
        Task {
            try? await http.postVoid(path, body: body, skipAuth: true)
        }
    }
}
