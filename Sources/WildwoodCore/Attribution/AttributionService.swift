// Campaign Attribution service — the Swift port of @wildwood/core's AttributionService (parity
// minimum). Captures UTM tags, an ad-platform click id and the referrer from deep links and universal
// links, keeps a first and a last touch, persists them only once the app's consent category is granted,
// beacons the landing when the app has the beacon on, and hands the payload to registration.
//
// Usage: `.wildwoodClient(_:)` calls `initialize()` and captures every opened URL for you. A host
// that wires the client by hand does:
//   await client.attribution.initialize()
//   .onOpenURL { url in client.attribution.capture(url: url) }   // or .wildwoodAttributionCapture(client)
// Registration carries the payload automatically (AuthService.setAttributionProvider, wired by
// WildwoodClient) and clears the touches after a successful signup; pass an explicit
// `RegistrationRequest.attribution` only to override that.
//
// Persistence follows consent: the service subscribes to ConsentService's change hook, so accepting
// Analytics later persists the touches and declining removes them. `consentDidChange()` remains for
// a host that runs its own consent engine. Nothing here throws.
//
// Funnel tracking (the port of @wildwood/core's FunnelTracker, native half): when the app's config
// turns it on, the service keeps a funnel session (30 minutes of inactivity ends it), accepts
// `track(_:label:value:)` and `trackScreen(_:)` events, and posts them to api/attribution/events in
// batches of at most 25: 5 seconds after the first queued event, and when the app goes to the
// background. There is no DOM, so scroll depth, engagement and CTA auto-tracking do not run here.
//
// @Observable so SwiftUI re-renders on `first`/`last`/`persisted` — the idiomatic `useAttribution`.

import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// The funnel session: its key, when it was last active, and how many sessions the visitor has had.
private struct FunnelSession {
    var sessionKey: String
    var lastActivityAt: Date
    var sessionCount: Int
}

/// A `track` call, as made (buffered until the config loads).
private struct FunnelCall {
    let name: String
    let label: String?
    let value: Double?
    let at: Date
    let path: String?
}

private struct QueuedFunnelEvent {
    let sessionKey: String
    let event: AttributionFunnelEvent
}

@MainActor
@Observable
public final class AttributionService {
    @ObservationIgnored private let http: WildwoodHttpClient
    @ObservationIgnored private let storage: any WildwoodStorageAdapter
    @ObservationIgnored private let consent: ConsentService
    @ObservationIgnored private let events: WildwoodEventEmitter?
    @ObservationIgnored private let platform: String
    /// Host kill switch (`WildwoodConfig.attributionEnabled`). When false nothing is captured,
    /// persisted, beaconed or handed to registration — the app-level config is never even fetched.
    @ObservationIgnored private let enabled: Bool
    @ObservationIgnored private var appId: String
    @ObservationIgnored private var initialized = false
    @ObservationIgnored private var beaconed = Set<String>()
    @ObservationIgnored private var consentSubscription: WildwoodSubscription?

    // MARK: Funnel state

    /// Test seam: the clock sessions and event timestamps are measured against.
    @ObservationIgnored var clock: () -> Date = { Date() }
    /// Test seam: how long the first queued event waits before the timed flush.
    @ObservationIgnored var flushInterval: Duration = .seconds(AttributionRules.flushIntervalSeconds)
    /// Test seam: the device class reported with events and registration.
    @ObservationIgnored var deviceClassProvider: (() -> String)?
    @ObservationIgnored private var configResolved = false
    @ObservationIgnored private var session: FunnelSession?
    @ObservationIgnored private var returning = false
    @ObservationIgnored private var pending: [FunnelCall] = []
    @ObservationIgnored private var queue: [QueuedFunnelEvent] = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var currentPath: String?
    @ObservationIgnored private var oneShots = Set<String>()
    @ObservationIgnored private var engagedSession: String?
    @ObservationIgnored private var pageMilestones = Set<Double>()
    @ObservationIgnored private var backgroundObserver: (any NSObjectProtocol)?

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
        platform: String = AttributionService.defaultPlatform,
        events: WildwoodEventEmitter? = nil,
        enabled: Bool = true
    ) {
        self.http = http
        self.storage = storage
        self.consent = consent
        self.events = events
        self.appId = defaultAppId
        self.platform = platform
        self.enabled = enabled
        self.visitorKey = UUID().uuidString.lowercased()
    }

    public var state: AttributionState {
        AttributionState(visitorKey: visitorKey, first: first, last: last, persisted: persisted, config: config)
    }

    /// The current funnel session's key, or nil before a session started.
    public var sessionKey: String? { peekSession()?.sessionKey }

    /// Sessions this visitor has started, counting the current one (0 before the first).
    public var sessionCount: Int { session?.sessionCount ?? 0 }

    /// True for a visitor known from storage who is on their second session or later.
    public var isReturning: Bool { returning }

    /// `mobile` on a phone, `tablet` on an iPad, `desktop` on a Mac.
    public var deviceClass: String {
        deviceClassProvider?() ?? AttributionRules.currentDeviceClass()
    }

    /// Loads the app's attribution config, restores stored touches and applies the consent gate. Call once
    /// at launch; later calls only re-apply the consent gate. Never throws.
    @discardableResult
    public func initialize(appId: String? = nil) async -> AttributionState {
        guard enabled else { return state }
        if let appId, !appId.isEmpty { self.appId = appId }
        if initialized {
            persistIfAllowed()
            // Re-arm the background flush a dispose() may have removed.
            startFunnelIfEnabled()
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
            resolveFunnelConfig()
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
            restoreSession(stored)
        }
        // Returning = a visitor known from storage starting another session.
        let current = currentSession(at: clock(), bump: false)
        returning = stored != nil && current.sessionCount >= 2

        persistIfAllowed()
        // Replays the calls buffered while the config loaded, when funnel tracking is on.
        resolveFunnelConfig()
        return state
    }

    /// Parses a URL (a deep link or universal link, from `.onOpenURL`) and applies it as a touch. Returns
    /// nil for a direct visit, which never overwrites the stored touches. With funnel tracking on it also
    /// records a `page_view` for the URL's path when that path changed.
    @discardableResult
    public func capture(url: URL, referrer: URL? = nil) -> AttributionTouch? {
        guard enabled else { return nil }
        if let config, !config.isEnabled { return nil }
        let now = Date()
        let touch = AttributionRules.parseTouch(
            url: url,
            referrer: referrer,
            captureClickIds: config?.captureClickIds ?? true,
            captureReferrer: config?.captureReferrer ?? true,
            extraAllowedParamNames: config?.extraAllowedParamNames ?? [],
            now: now
        )

        if let touch {
            if let current = first, AttributionRules.isExpired(current, windowDays: windowDays, now: now) {
                first = nil
                last = nil
            }
            last = touch
            if first == nil { first = touch }
            persistIfAllowed()
            events?.emit(.attributionCaptured(touch))
            beacon(touch)
        }

        // A page_view when the path changed (a no-op until the config turns funnel tracking on).
        notifyPath(AttributionRules.normalizePath(url))
        return touch
    }

    /// The payload for `RegistrationRequest.attribution`, or nil when attribution is off or nothing was captured.
    public func getForRegistration() -> AttributionPayload? {
        guard enabled else { return nil }
        if let config, !config.isEnabled { return nil }
        guard first != nil || last != nil else { return nil }
        let current = currentSession(at: clock(), bump: true)
        return AttributionPayload(
            visitorKey: visitorKey,
            firstTouch: first,
            lastTouch: last,
            platform: platform,
            sessionKey: current.sessionKey,
            deviceClass: deviceClass,
            sessionCount: current.sessionCount
        )
    }

    /// Drops the touches from memory and storage (after a recorded signup). The visitor key is kept.
    public func clear() {
        first = nil
        last = nil
        persisted = false
        storage.removeItem(WildwoodStorageKeys.attribution)
        // With funnel tracking on, the visitor and session keys stay stored where consent allows.
        if config?.funnelTrackingEnabled == true { persistIfAllowed() }
    }

    /// Re-applies the consent gate. Called automatically for `ConsentService` decisions (the
    /// service subscribes to its change hook); call it by hand only with a host consent engine.
    public func consentDidChange() {
        guard enabled else { return }
        persistIfAllowed()
    }

    /// Stops listening for consent changes and for the app going to the background, cancels the
    /// timed flush and sends what is queued. State is kept; a later `initialize()` re-arms the
    /// listeners. `WildwoodClient.dispose()` calls this.
    public func dispose() {
        // Stops the funnel first: its final persist may (re)subscribe to consent, which is cancelled next.
        stopFunnel()
        consentSubscription?.cancel()
        consentSubscription = nil
    }

    // MARK: - Funnel tracking

    /// Tracks a funnel event: a standard client event (`cta_click`, `plan_selected`...) or one of the
    /// app's configured custom names. Buffered until the config loads; dropped when funnel tracking is
    /// off, the name is not allowed, or it is a one-shot already sent this session. The label is
    /// trimmed and capped at 100 characters. `path` names the page the event belongs to (query and
    /// fragment dropped, a leading `/` added), as `@wildwood/core`'s `track(name, { path })` does; nil
    /// means the current screen. A `page_view` naming its page is a navigation, exactly like
    /// ``trackScreen(_:)``. Never throws.
    public func track(_ name: String, label: String? = nil, value: Double? = nil, path: String? = nil) {
        guard enabled else { return }
        let explicitPath = path.flatMap { AttributionRules.funnelPath($0) }
        if name == "page_view", let explicitPath {
            notifyPath(explicitPath)
            return
        }
        record(FunnelCall(name: name, label: label, value: value, at: clock(), path: explicitPath ?? currentPath))
    }

    /// Tracks a `cta_click` with this label.
    public func trackCta(_ label: String) {
        track("cta_click", label: label)
    }

    /// Records a `page_view` for a screen, with the path `/<name>`, and makes it the current screen so
    /// later events carry it. The same screen twice in a row is ignored. Never throws.
    public func trackScreen(_ name: String) {
        guard enabled, let path = AttributionRules.funnelPath(name) else { return }
        notifyPath(path)
    }

    /// Sends the queued funnel events now. Network errors are swallowed.
    public func flush() async {
        cancelFlushTask()
        let batches = takeBatches()
        guard !batches.isEmpty else { return }
        // Keeps the session's last activity stored, where consent allows.
        if config != nil { persistIfAllowed() }
        let http = self.http
        for body in batches {
            try? await http.postVoid(Self.eventsPath(body.appId), body: body, skipAuth: true)
        }
    }

    /// Test seam: whether a timed flush is waiting.
    var isFlushScheduled: Bool { flushTask != nil }

    /// Test seam: events waiting to be sent.
    var queuedEventCount: Int { queue.count }

    private var funnelEnabled: Bool {
        guard let config else { return false }
        return config.isEnabled && config.funnelTrackingEnabled
    }

    /// The config has loaded (or could not be): replay the buffered calls when funnel tracking is on,
    /// otherwise drop them.
    private func resolveFunnelConfig() {
        configResolved = true
        let buffered = pending
        pending = []
        guard funnelEnabled else { return }
        for call in buffered { accept(call) }
        startFunnelIfEnabled()
    }

    /// Flushes whenever the app goes to the background, since a backgrounded app may be killed before
    /// the next timed flush (the native stand-in for the web's pagehide beacon).
    private func startFunnelIfEnabled() {
        guard funnelEnabled else { return }
        #if canImport(UIKit)
        guard backgroundObserver == nil else { return }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.flush() }
        }
        #endif
    }

    private func stopFunnel() {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
            self.backgroundObserver = nil
        }
        cancelFlushTask()
        let batches = takeBatches()
        guard !batches.isEmpty else { return }
        // Keeps the session's last activity stored, where consent allows, as flush() does.
        if config != nil { persistIfAllowed() }
        let http = self.http
        Task {
            for body in batches {
                try? await http.postVoid(Self.eventsPath(body.appId), body: body, skipAuth: true)
            }
        }
    }

    /// A navigation to `path` (already reduced): a page_view when it differs from the current one.
    private func notifyPath(_ path: String) {
        guard path != currentPath else { return }
        currentPath = path
        pageMilestones.removeAll()
        record(FunnelCall(name: "page_view", label: nil, value: nil, at: clock(), path: path))
    }

    private func record(_ call: FunnelCall) {
        if !configResolved {
            if pending.count < AttributionRules.maxPendingBeforeConfig { pending.append(call) }
            return
        }
        guard funnelEnabled else { return }
        accept(call)
    }

    private func accept(_ call: FunnelCall) {
        guard let config else { return }
        let name = call.name
        guard AttributionRules.isFunnelEventName(name),
              !AttributionRules.funnelServerOnlyEvents.contains(name)
        else { return }
        guard AttributionRules.funnelClientEvents.contains(name) || config.customEventNames.contains(name)
        else { return }
        if AttributionRules.signupStepEvents.contains(name) && !config.trackSignupSteps { return }

        var label: String? = call.label.flatMap {
            AttributionRules.normalizeToken($0, maxLength: AttributionRules.funnelLabelMaxLength, lowercase: false)
        }
        var value: Double? = call.value.flatMap { $0.isFinite ? $0 : nil }

        switch name {
        case "cta_click":
            if label == nil { return }
        case "signup_error":
            label = AttributionRules.signupErrorLabel(label)
        case "scroll_depth":
            guard let milestone = value,
                  AttributionRules.scrollMilestones.contains(milestone),
                  !pageMilestones.contains(milestone)
            else { return }
            pageMilestones.insert(milestone)
        case "time_on_page":
            guard let seconds = value, seconds >= 0 else { return }
            value = min(AttributionRules.maxTimeOnPageSeconds, seconds.rounded())
        default:
            break
        }

        // time_on_page closes out time already spent; it never starts or extends a session.
        let current: FunnelSession
        if name == "time_on_page", let held = peekSession() {
            current = held
        } else {
            current = currentSession(at: call.at, bump: name != "time_on_page")
        }

        if name == "engaged" {
            if engagedSession == current.sessionKey { return }
            engagedSession = current.sessionKey
        } else if AttributionRules.oneShotPerLabelEvents.contains(name) {
            let key = "\(name)|\(label ?? "")"
            if oneShots.contains(key) { return }
            oneShots.insert(key)
        }

        guard queue.count < AttributionRules.maxQueuedEvents else { return }
        let event = AttributionFunnelEvent(
            name: name,
            label: label,
            value: value,
            path: call.path,
            clientTimestamp: AttributionRules.iso8601(call.at)
        )
        queue.append(QueuedFunnelEvent(sessionKey: current.sessionKey, event: event))
        if queue.count >= AttributionRules.maxEventsPerRequest {
            Task { await self.flush() }
        } else {
            ensureFlushTask()
        }
    }

    /// The session as held, without starting one.
    private func peekSession() -> FunnelSession? {
        guard let session, !session.sessionKey.isEmpty else { return nil }
        return session
    }

    /// The current session, starting a new one when there is none or the last activity is 30+ minutes
    /// old. `bump` moves the last activity forward to `at`.
    private func currentSession(at: Date, bump: Bool) -> FunnelSession {
        if var current = session, !current.sessionKey.isEmpty,
           at.timeIntervalSince(current.lastActivityAt) <= AttributionRules.sessionTimeout {
            if bump && at > current.lastActivityAt {
                current.lastActivityAt = at
                session = current
            }
            return current
        }
        let next = FunnelSession(
            sessionKey: UUID().uuidString.lowercased(),
            lastActivityAt: at,
            sessionCount: (session?.sessionCount ?? 0) + 1
        )
        session = next
        oneShots.removeAll()
        engagedSession = nil
        if config != nil { persistIfAllowed() }
        return next
    }

    /// Restores a stored session. A stored visitor always counts as at least one earlier session.
    private func restoreSession(_ stored: StoredAttribution) {
        let storedCount = stored.sessionCount ?? 0
        let count = storedCount > 0 ? storedCount : 1
        if let key = stored.sessionKey, AttributionRules.isValidVisitorKey(key),
           let at = stored.lastActivityAt, at.isFinite {
            session = FunnelSession(
                sessionKey: key,
                lastActivityAt: Date(timeIntervalSince1970: at / 1000),
                sessionCount: count
            )
        } else {
            // Force a new session on next use, counting on from the stored one.
            session = FunnelSession(sessionKey: "", lastActivityAt: .distantPast, sessionCount: count)
        }
    }

    private func ensureFlushTask() {
        guard flushTask == nil else { return }
        let interval = flushInterval
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await self?.timedFlush()
        }
    }

    private func timedFlush() async {
        flushTask = nil
        await flush()
    }

    private func cancelFlushTask() {
        flushTask?.cancel()
        flushTask = nil
    }

    /// Drains the queue into requests: consecutive events of one session, at most 25 per request, and
    /// halved until the body fits under the size cap.
    private func takeBatches() -> [AttributionEventsRequest] {
        let queued = queue
        queue = []
        guard !queued.isEmpty, !appId.isEmpty else { return [] }

        let reportedDeviceClass = deviceClass
        let touch = last
        func request(_ slice: ArraySlice<QueuedFunnelEvent>, sessionKey: String) -> AttributionEventsRequest {
            AttributionEventsRequest(
                appId: appId,
                visitorKey: visitorKey,
                sessionKey: sessionKey,
                isReturning: returning,
                deviceClass: reportedDeviceClass,
                platform: platform,
                touch: touch,
                events: slice.map { $0.event }
            )
        }

        var batches: [AttributionEventsRequest] = []
        var index = 0
        while index < queued.count {
            let sessionKey = queued[index].sessionKey
            var size = 0
            while index + size < queued.count,
                  size < AttributionRules.maxEventsPerRequest,
                  queued[index + size].sessionKey == sessionKey {
                size += 1
            }
            var body = request(queued[index..<(index + size)], sessionKey: sessionKey)
            while size > 1, Self.encodedSize(body) > AttributionRules.maxBodyBytes {
                size = (size + 1) / 2
                body = request(queued[index..<(index + size)], sessionKey: sessionKey)
            }
            if Self.encodedSize(body) <= AttributionRules.maxBodyBytes { batches.append(body) }
            index += size
        }
        return batches
    }

    nonisolated private static func encodedSize(_ body: AttributionEventsRequest) -> Int {
        (try? JSONEncoder().encode(body).count) ?? Int.max
    }

    nonisolated private static func eventsPath(_ appId: String) -> String {
        // appId rides in the query too: the server's rate-limit partition reads it, and it must match the body.
        "api/attribution/events?appId=\(WildwoodURL.queryComponent(appId))"
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
        ensureConsentSubscription()
        guard let config, config.isEnabled else { return }
        let category = ConsentCategory(rawValue: config.persistenceConsentCategory) ?? .analytics
        let allowed = category == .strictlyNecessary || consent.isGranted(category)
        // With funnel tracking on, a direct visitor's visitor and session keys are worth keeping too.
        let hasData = first != nil || last != nil || config.funnelTrackingEnabled

        if allowed {
            if hasData {
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
        // No consent state yet: stay memory-only until the consent decision arrives.
    }

    /// Subscribes once to the consent engine, so a later accept persists the touches and a later
    /// decline removes them (JS `ensureConsentSubscription`). `dispose()` drops it; the next
    /// `persistIfAllowed()` re-arms it.
    private func ensureConsentSubscription() {
        guard consentSubscription == nil else { return }
        consentSubscription = consent.onConsentChange { [weak self] _ in
            self?.consentDidChange()
        }
    }

    private func readStored() -> StoredAttribution? {
        guard let raw = storage.getItem(WildwoodStorageKeys.attribution), let data = raw.data(using: .utf8),
              var stored = try? JSONDecoder().decode(StoredAttribution.self, from: data),
              stored.v == 1
        else { return nil }
        if let touch = stored.first, AttributionRules.parseDate(touch.occurredAt) == nil { stored.first = nil }
        if let touch = stored.last, AttributionRules.parseDate(touch.occurredAt) == nil { stored.last = nil }
        if let count = stored.sessionCount, count <= 0 { stored.sessionCount = nil }
        return stored
    }

    private func writeStored() {
        let held = peekSession()
        let blob = StoredAttribution(
            v: 1,
            visitorKey: visitorKey,
            first: first,
            last: last,
            updatedAt: AttributionRules.iso8601(Date()),
            sessionKey: held?.sessionKey,
            // Epoch milliseconds, as the web SDK stores it.
            lastActivityAt: held.map { ($0.lastActivityAt.timeIntervalSince1970 * 1000).rounded() },
            sessionCount: held?.sessionCount
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
