// What the pricing view is holding at this moment: the live catalog, whether it is still coming,
// why it did not, the billing cycle in force and the packs that are ticked.
//
// The Swift analog of react-shared's `usePublicCatalog` + the pricing view's own `useState`s. Every
// DECISION it makes is a call into ``PricingViewRules``; this half owns the state and the one thing
// that touches the world — ``PublicCatalogStore``, which already shares one load per app, holds it
// for sixty seconds and NEVER caches a failure.
//
// Two rules it exists to keep:
//
//  · No price without a live catalog. Nothing is persisted, nothing is remembered between runs and
//    a failure blanks the quote rather than leaving yesterday's number on screen. While the first
//    catalog is on its way there is nothing to format, so there is nothing to read but shapes.
//  · A failure is reported ONCE per distinct message. A Retry that fails again is news; a re-render
//    is not, and a host that logs every report should not see the same sentence a hundred times.

import Foundation
import Observation
import WildwoodCore

@MainActor
@Observable
public final class WildwoodPricingViewModel {
    @ObservationIgnored private let client: WildwoodClient
    @ObservationIgnored private let appId: String?
    @ObservationIgnored private let currencyOverride: String?
    @ObservationIgnored private let offerFreeTierChoice: Bool

    // MARK: Host wiring

    /// Told about every distinct catalog failure, under
    /// ``RegistrationSubscriptionErrorCodes/catalogUnavailable``.
    @ObservationIgnored public var onError: ((RegistrationSubscriptionError) -> Void)?

    // MARK: State

    /// What the app sells, as the server last said it. Nil until the first load lands.
    public private(set) var catalog: PublicCatalog?
    /// True from construction, so the very first frame is the skeleton and not the failure panel.
    public private(set) var isLoading: Bool = true
    /// Why the catalog could not be read. Nil once a load succeeds.
    public private(set) var errorMessage: String?
    /// The cycle the plan grid is quoting.
    public private(set) var billing: PricingBilling
    /// The ticked packs, in catalog order.
    public private(set) var selectedPackIds: [String] = []

    /// The last message handed to ``onError``, so the same one is not reported twice.
    @ObservationIgnored private var reportedMessage: String?

    public init(
        client: WildwoodClient,
        appId: String? = nil,
        currency: String? = nil,
        defaultBilling: PricingBilling = .monthly,
        offerFreeTierChoice: Bool = true
    ) {
        self.client = client
        self.appId = appId
        self.currencyOverride = currency
        self.offerFreeTierChoice = offerFreeTierChoice
        self.billing = defaultBilling
    }

    // MARK: - What the view renders from

    /// Which of the three bodies applies.
    public var bodyKind: PricingBodyKind {
        PricingViewRules.bodyKind(catalog: catalog, isLoading: isLoading, errorMessage: errorMessage)
    }

    /// The currency every amount on the screen is quoted in. Empty before a catalog arrives.
    public var displayCurrency: String {
        PricingViewRules.currency(override: currencyOverride, catalog: catalog)
    }

    /// The plans to render. Empty before a catalog arrives — there is no plan without one.
    public var visiblePlans: [AppTierModel] {
        PricingViewRules.visibleTiers(catalog, offerFreeTierChoice: offerFreeTierChoice)
    }

    /// The packs to render, in catalog order. Empty before a catalog arrives.
    public var packs: [AppTierAddOnModel] {
        catalog?.addOns ?? []
    }

    /// Whether one pack is ticked.
    public func isPackSelected(_ addOnId: String) -> Bool {
        selectedPackIds.contains(addOnId)
    }

    // MARK: - Loading

    /// Load the catalog, served from the shared cache when it is fresh.
    public func load() async {
        await loadCatalog(forceRefresh: false)
    }

    /// Load it again, bypassing the cache — what the failure panel's Retry does. A retry that is
    /// answered from a sixty-second-old cache would look like a button that does nothing.
    public func retry() async {
        await loadCatalog(forceRefresh: true)
    }

    private func loadCatalog(forceRefresh: Bool) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded: PublicCatalog = try await client.catalog.catalog(
                appId: appId,
                currencyOverride: currencyOverride,
                forceRefresh: forceRefresh
            )
            catalog = loaded
            errorMessage = nil
            // A success clears the latch, so the NEXT failure is reported even when it says the
            // same thing this one did.
            reportedMessage = nil
        } catch {
            let raw: String = (error as? WildwoodError)?.message ?? error.localizedDescription
            let message: String = raw.isEmpty
                ? RegistrationSubscriptionDriverMessages.catalogUnavailable
                : raw
            errorMessage = message
            report(message)
        }
    }

    private func report(_ message: String) {
        if reportedMessage == message { return }
        reportedMessage = message
        onError?(
            RegistrationSubscriptionError(
                code: RegistrationSubscriptionErrorCodes.catalogUnavailable,
                message: message
            )
        )
    }

    // MARK: - Selection

    /// Switch the plan grid's billing cycle.
    public func setBilling(_ billing: PricingBilling) {
        self.billing = billing
    }

    /// Tick or untick one pack, capped and ordered by ``PricingViewRules/togglePackSelection(catalog:current:addOnId:)``.
    public func togglePack(_ addOnId: String) {
        selectedPackIds = PricingViewRules.togglePackSelection(
            catalog: catalog,
            current: selectedPackIds,
            addOnId: addOnId
        )
    }

    /// Forget every ticked pack.
    public func clearPackSelection() {
        selectedPackIds = []
    }

    // MARK: - What the host is handed

    /// The payload a plan's call to action raises: the plan, its option under the current cycle,
    /// and the ticked packs. Nil for a plan whose footer raises no selection — a "contact us"
    /// plan the operator gave a URL to sells nothing here, so no host is told it was bought.
    ///
    /// - Parameter contactUrl: the host's fallback contact URL, which the view also hands the
    ///   plan grid. The guard has to see the same value the card's footer does.
    public func planSelectionPayload(
        for tier: AppTierModel,
        contactUrl: String? = nil
    ) -> PricingSelection? {
        PricingViewRules.planSelectionPayload(
            tier: tier,
            billing: billing,
            selectedPackIds: selectedPackIds,
            contactUrl: contactUrl
        )
    }

    /// The payload one pack's call to action raises. No plan is implied.
    public func packSelectionPayload(forPack addOnId: String) -> PricingSelection {
        PricingViewRules.packSelectionPayload(addOnId: addOnId, billing: billing)
    }

    /// The payload the multi-select Continue raises.
    public func packsContinuePayload() -> PricingSelection {
        PricingViewRules.packsContinuePayload(billing: billing, selectedPackIds: selectedPackIds)
    }
}
