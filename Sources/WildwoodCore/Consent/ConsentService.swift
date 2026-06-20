// Consent Management engine — native port of @wildwood/core ConsentService.
//
// Like the React Native wrapper, the native engine owns config fetch, the consent blob/state, the
// show/suppress decision table, gating (isGranted), and recording the decision. There is NO DOM and
// NO script injection on Apple platforms — "block-before-consent" for third-party *scripts* is a
// web-only concern; native SDKs gate features via `isGranted(_:)` before initializing them.
//
// Persistence: the consent blob is stored under `WildwoodStorageKeys.consent` (UserDefaults via
// CompositeStorage) — the native analog of the first-party `ww_consent` cookie. State is mutable, so
// the service is @MainActor-isolated (mirrors NotificationService / ThemeService).

import Foundation

@MainActor
public final class ConsentService {
    private let http: WildwoodHttpClient
    private let storage: any WildwoodStorageAdapter
    private let defaultAppId: String
    private let storageKey: String

    private var config: PublicConsentConfig?
    private var state: ConsentState?

    public init(
        http: WildwoodHttpClient,
        storage: any WildwoodStorageAdapter,
        defaultAppId: String,
        storageKey: String = WildwoodStorageKeys.consent
    ) {
        self.http = http
        self.storage = storage
        self.defaultAppId = defaultAppId
        self.storageKey = storageKey
    }

    // MARK: - Public API

    /// Fetch the merged consent config + enabled script registry for an app.
    public func fetchConfig(appId: String? = nil) async throws -> PublicConsentConfig {
        let targetAppId = appId ?? defaultAppId
        return try await http.get("api/consent/config?appId=\(WildwoodURL.queryComponent(targetAppId))", skipAuth: true)
    }

    /// Initialize consent: fetch config, read the stored blob + GPC, apply the decision table, and
    /// return what the UI needs to render. No scripts are injected (no DOM on Apple platforms).
    @discardableResult
    public func initialize(appId: String? = nil) async throws -> ConsentInitResult {
        let config = try await fetchConfig(appId: appId)
        self.config = config

        let gpcPresent = readGpc()
        let cookie = readCookie()
        let visitorKey = cookie?.visitorKey ?? Self.generateVisitorKey()
        // A stored decision is valid only if it matches the current config version.
        let hasValidCookie = cookie != nil && cookie!.configVersion == config.version && config.enabled

        var categories = ConsentState.emptyCategories()
        var decided = false
        if hasValidCookie {
            categories = decodeConsentString(cookie!.consentString)
            decided = true
        }
        // GPC forces Advertising + Sensitive off, even outside any geo target.
        if config.enabled, config.honorGpc, gpcPresent {
            applyGpcOptOut(&categories)
        }
        let initialState = ConsentState(
            visitorKey: visitorKey,
            categories: categories,
            configVersion: config.version,
            decided: decided,
            gpcPresent: gpcPresent
        )
        state = initialState

        if !config.enabled {
            // Consent experience is off for this app; the SDK stays inactive.
            return ConsentInitResult(config: config, state: initialState, shouldShowBanner: false)
        }

        if decided {
            return ConsentInitResult(config: config, state: initialState, shouldShowBanner: false)
        }

        // No stored decision yet — run the show/suppress decision table.
        if !shouldShowBanner(config) {
            // Geo-aware + outside target: apply the configured non-target default (GPC still honored).
            await applyNonTargetDefault(config, gpcPresent: gpcPresent)
            return ConsentInitResult(config: config, state: state ?? initialState, shouldShowBanner: false)
        }

        // Banner will show. GPC has already been applied to the in-memory state above; the decision is
        // recorded when the visitor acts. We deliberately do NOT persist here — doing so would mark the
        // visitor "decided" and suppress the banner on the next launch before they ever chose.
        return ConsentInitResult(config: config, state: initialState, shouldShowBanner: true)
    }

    /// Grant every active category (GPC still forces Advertising/Sensitive off).
    @discardableResult
    public func acceptAll() async throws -> ConsentState? {
        try requireInit()
        var cats = ConsentState.emptyCategories()
        grantAllActive(&cats)
        return await applyCategories(cats, method: .acceptAll)
    }

    /// Reject all — only StrictlyNecessary remains.
    @discardableResult
    public func rejectAll() async throws -> ConsentState? {
        try requireInit()
        return await applyCategories(ConsentState.emptyCategories(), method: .rejectAll)
    }

    /// Apply a custom per-category selection.
    @discardableResult
    public func setCategories(_ selection: [ConsentCategory: Bool]) async throws -> ConsentState? {
        try requireInit()
        var cats = ConsentState.emptyCategories()
        for category in activeCategories() { cats[category] = selection[category] == true }
        return await applyCategories(cats, method: .custom)
    }

    /// Withdraw consent: record a reject-all (evidence), clear the stored blob so the visitor is
    /// treated as undecided again on the next launch.
    @discardableResult
    public func withdraw() async throws -> ConsentState? {
        try requireInit()
        state?.categories = ConsentState.emptyCategories()
        state?.decided = false
        if let state {
            await record(method: .rejectAll, consentString: encodeConsentString(state.categories))
        }
        clearCookie()
        return state
    }

    /// Current granted state for a category. Delegates to the state's rule (StrictlyNecessary is
    /// always granted, even before initialize()).
    public func isGranted(_ category: ConsentCategory) -> Bool {
        state?.isGranted(category) ?? (category == .strictlyNecessary)
    }

    public func getState() -> ConsentState? { state }

    public func getConfig() -> PublicConsentConfig? { config }

    // MARK: - Decision logic

    private func shouldShowBanner(_ config: PublicConsentConfig) -> Bool {
        if !config.geo.aware { return true } // show to everyone
        return config.geo.inTarget // geo-aware: show only inside target
    }

    private func applyNonTargetDefault(_ config: PublicConsentConfig, gpcPresent: Bool) async {
        var cats = ConsentState.emptyCategories()
        if config.nonTargetDefault == "LoadAll" {
            grantAllActive(&cats)
        }
        // GPC always overrides toward opt-out.
        if config.honorGpc, gpcPresent {
            applyGpcOptOut(&cats)
        }
        state?.categories = cats
        state?.decided = true
        await persistDecision(method: gpcPresent ? .gpc : .nonTargetDefault)
    }

    @discardableResult
    private func applyCategories(_ categories: [ConsentCategory: Bool], method: ConsentMethod) async -> ConsentState? {
        var cats = categories
        // GPC always forces Advertising + Sensitive off.
        if config?.honorGpc == true, state?.gpcPresent == true {
            applyGpcOptOut(&cats)
        }
        state?.categories = cats
        state?.decided = true
        await persistDecision(method: method)
        return state
    }

    private func persistDecision(method: ConsentMethod) async {
        guard let state, let config else { return }
        let consentString = encodeConsentString(state.categories)
        writeCookie(ConsentCookie(visitorKey: state.visitorKey, consentString: consentString, configVersion: config.version))
        await record(method: method, consentString: consentString)
    }

    private func record(method: ConsentMethod, consentString: String) async {
        guard let state, let config else { return }
        let request = ConsentRecordRequest(
            appId: config.appId,
            visitorKey: state.visitorKey,
            consentString: consentString,
            method: method,
            gpcPresent: state.gpcPresent,
            configVersion: config.version
        )
        do {
            // appId is also sent as a query param so the server's per-app rate-limit partition applies.
            try await http.postVoid("api/consent/record?appId=\(WildwoodURL.queryComponent(config.appId))", body: request, skipAuth: true)
        } catch {
            // Recording is best-effort; never block the UI on it.
        }
    }

    // MARK: - GPC / persistence / encoding

    private func readGpc() -> Bool {
        // Global Privacy Control is a browser/DOM signal with no native Apple-platform equivalent, so
        // GPC is never present here (matches the React Native engine, where navigator is unavailable).
        false
    }

    private func readCookie() -> ConsentCookie? {
        guard let raw = storage.getItem(storageKey), !raw.isEmpty, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ConsentCookie.self, from: data)
    }

    private func writeCookie(_ cookie: ConsentCookie) {
        guard let data = try? JSONEncoder().encode(cookie), let json = String(data: data, encoding: .utf8) else { return }
        storage.setItem(storageKey, json)
    }

    private func clearCookie() {
        storage.removeItem(storageKey)
    }

    private static func generateVisitorKey() -> String {
        UUID().uuidString
    }

    private func encodeConsentString(_ categories: [ConsentCategory: Bool]) -> String {
        ConsentCategory.nonNecessary.filter { categories[$0] == true }.map(\.rawValue).joined(separator: ",")
    }

    private func decodeConsentString(_ consentString: String) -> [ConsentCategory: Bool] {
        var cats = ConsentState.emptyCategories()
        guard !consentString.isEmpty else { return cats }
        for part in consentString.split(separator: ",") {
            let trimmed = String(part).trimmingCharacters(in: .whitespaces)
            if let category = ConsentCategory(rawValue: trimmed), ConsentCategory.nonNecessary.contains(category) {
                cats[category] = true
            }
        }
        return cats
    }

    /// The active non-necessary categories the visitor can toggle, derived from the loaded config.
    /// Public so the view-model layer can surface it without re-deriving the rule.
    public func activeCategories() -> [ConsentCategory] {
        let active = config?.categories ?? []
        // Only offer non-necessary categories that the config marks active.
        return ConsentCategory.nonNecessary.filter { active.contains($0) }
    }

    private func requireInit() throws {
        if config == nil || state == nil {
            throw WildwoodError(
                message: "ConsentService.initialize() must be called before applying consent.",
                status: 0,
                code: .unknown
            )
        }
    }

    /// Force GPC's opted-out categories (Advertising + Sensitive) off in a category map.
    private func applyGpcOptOut(_ categories: inout [ConsentCategory: Bool]) {
        for category in ConsentCategory.gpcForcedOff { categories[category] = false }
    }

    /// Grant every active non-necessary category in a category map.
    private func grantAllActive(_ categories: inout [ConsentCategory: Bool]) {
        for category in activeCategories() { categories[category] = true }
    }

    /// The locally-stored consent blob (native analog of the first-party `ww_consent` cookie).
    private struct ConsentCookie: Codable {
        var visitorKey: String
        var consentString: String
        var configVersion: Int
    }
}
