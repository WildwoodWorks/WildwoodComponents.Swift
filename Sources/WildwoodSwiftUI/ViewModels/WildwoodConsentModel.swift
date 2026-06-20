// Consent view model — the SwiftUI analog of @wildwood/react-shared's useConsent hook.
// Wraps WildwoodCore's ConsentService so views can render the banner/preferences UI and gate
// first-party features on consent.

import Foundation
import Observation
import WildwoodCore

@MainActor
@Observable
public final class WildwoodConsentModel {
    @ObservationIgnored private let client: WildwoodClient
    @ObservationIgnored private let appId: String?

    public private(set) var config: PublicConsentConfig?
    public private(set) var state: ConsentState?
    public private(set) var isLoading = false
    /// Whether the banner should be shown to this visitor.
    public private(set) var shouldShowBanner = false
    public private(set) var errorMessage: String?

    public init(client: WildwoodClient, appId: String? = nil) {
        self.client = client
        self.appId = appId
    }

    /// Fetch config, read GPC + stored decision, and compute whether to show the banner.
    @discardableResult
    public func initialize() async -> ConsentInitResult? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await client.consent.initialize(appId: appId)
            config = result.config
            state = result.state
            shouldShowBanner = result.shouldShowBanner
            return result
        } catch {
            errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
            return nil
        }
    }

    public func acceptAll() async {
        do {
            _ = try await client.consent.acceptAll()
            state = client.consent.getState()
            shouldShowBanner = false
        } catch {
            errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
        }
    }

    public func rejectAll() async {
        do {
            _ = try await client.consent.rejectAll()
            state = client.consent.getState()
            shouldShowBanner = false
        } catch {
            errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
        }
    }

    public func setCategories(_ selection: [ConsentCategory: Bool]) async {
        do {
            _ = try await client.consent.setCategories(selection)
            state = client.consent.getState()
            shouldShowBanner = false
        } catch {
            errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
        }
    }

    public func withdraw() async {
        do {
            _ = try await client.consent.withdraw()
            state = client.consent.getState()
        } catch {
            errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
        }
    }

    /// Gate a first-party feature on consent for a category.
    public func isGranted(_ category: ConsentCategory) -> Bool {
        client.consent.isGranted(category)
    }

    /// The active non-necessary categories the visitor can toggle. Delegates to the core service so
    /// the derivation rule lives in exactly one place.
    public func activeCategories() -> [ConsentCategory] {
        client.consent.activeCategories()
    }
}
