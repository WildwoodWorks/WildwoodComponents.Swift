#if os(iOS)
// The pricing view: what the app sells, at the price the server is quoting right now.
//
// Two rules shape this file, and they are the same two the web and React Native views keep.
//
//  · Every price comes off the live public catalog. There is no fallback price, no remembered
//    price and no "from" price anywhere under `Components/RegistrationSubscription/`. While the
//    catalog loads the visitor sees shapes; if it cannot be read they see "Pricing is unavailable
//    right now" and a Retry, never a number the server did not just say.
//
//  · The plan grid is this package's existing ``TierCard``, footer call to action and all, because
//    that is the card the other Wildwood surfaces already render and the one a host has themed.
//
// What the web view has and this one does not: an SSR `initialCatalog`, JSON-LD offers and a
// `className`. None of the three has a native meaning — there is no server render to seed from, no
// crawler to publish offers to, and no cascade to hang a class on. The web's `loadingFallback` /
// `errorFallback` NODES are omitted too: a `View`-typed slot means a generic parameter on this
// type and on the shell that will host it, and no sibling in this package pays that price for a
// panel a host can already replace by composing around the view.
//
// Every decision lives in ``PricingViewRules`` and the loading state in ``WildwoodPricingViewModel``,
// so the behaviour is tested on a machine with no simulator.

import SwiftUI
import WildwoodCore
import WildwoodTestIDs

public struct RegistrationSubscriptionPricingView: View {
    @Environment(\.wildwoodClient) private var client
    @Environment(\.wildwoodTheme) private var theme

    private let appId: String?
    private let currency: String?
    private let contactUrl: String?
    private let showPlans: Bool
    private let showAddOns: Bool
    private let offerFreeTierChoice: Bool
    private let packSelection: PricingPackSelection
    private let packPurchaseAvailable: Bool
    private let addOnGroups: [WildwoodAddOnGroup]?
    private let describeAddOn: ((AppTierAddOnModel) -> WildwoodAddOnPresentation?)?
    private let showBillingToggle: Bool
    private let defaultBilling: PricingBilling
    private let showFeatureComparison: Bool
    private let showLimits: Bool
    private let highlightTierId: String?
    private let labels: RegistrationSubscriptionPricingLabels
    private let onError: ((RegistrationSubscriptionError) -> Void)?
    private let onSelect: (PricingSelection) -> Void

    @State private var model: WildwoodPricingViewModel?

    /// - Parameters:
    ///   - appId: overrides the client's configured app.
    ///   - currency: display override. Wins over the currency the catalog names, which is itself
    ///     the server's answer rather than a guess.
    ///   - contactUrl: where a "contact us" plan with no URL of its own sends the visitor.
    ///   - showPlans: render the plan grid.
    ///   - showAddOns: render the pack grid.
    ///   - offerFreeTierChoice: false hides every free plan.
    ///   - packSelection: `.none` gives each pack its own Select; `.multi` ticks several and
    ///     offers one Continue.
    ///   - packPurchaseAvailable: false LISTS the packs and offers none of them. This is the
    ///     App-Store-exclusive case (Decision 5): pack checkout is a card purchase and Apple's
    ///     product mapping is tier-only. A pricing screen is anonymous and never asks the server
    ///     which processor an app uses, so the host — or the shell that already loaded the app's
    ///     platform-filtered providers — passes the answer in.
    ///   - addOnGroups: headings to file packs under, matched on an add-on's `category`.
    ///   - describeAddOn: host marketing copy for one pack.
    ///   - showBillingToggle: offer the monthly/annual switch. It still only appears when some
    ///     plan is actually priced by the year.
    ///   - defaultBilling: the cycle the grid opens on.
    ///   - showFeatureComparison: show each plan's feature list.
    ///   - showLimits: show each plan's usage limits.
    ///   - highlightTierId: marks one plan as already chosen (matched case-insensitively).
    ///   - labels: overridable copy.
    ///   - onError: told about every distinct catalog failure, as `catalog_unavailable`.
    ///   - onSelect: the plan or packs the visitor chose.
    public init(
        appId: String? = nil,
        currency: String? = nil,
        contactUrl: String? = nil,
        showPlans: Bool = true,
        showAddOns: Bool = false,
        offerFreeTierChoice: Bool = true,
        packSelection: PricingPackSelection = .none,
        packPurchaseAvailable: Bool = true,
        addOnGroups: [WildwoodAddOnGroup]? = nil,
        describeAddOn: ((AppTierAddOnModel) -> WildwoodAddOnPresentation?)? = nil,
        showBillingToggle: Bool = true,
        defaultBilling: PricingBilling = .monthly,
        showFeatureComparison: Bool = true,
        showLimits: Bool = true,
        highlightTierId: String? = nil,
        labels: RegistrationSubscriptionPricingLabels = .defaults,
        onError: ((RegistrationSubscriptionError) -> Void)? = nil,
        onSelect: @escaping (PricingSelection) -> Void
    ) {
        self.appId = appId
        self.currency = currency
        self.contactUrl = contactUrl
        self.showPlans = showPlans
        self.showAddOns = showAddOns
        self.offerFreeTierChoice = offerFreeTierChoice
        self.packSelection = packSelection
        self.packPurchaseAvailable = packPurchaseAvailable
        self.addOnGroups = addOnGroups
        self.describeAddOn = describeAddOn
        self.showBillingToggle = showBillingToggle
        self.defaultBilling = defaultBilling
        self.showFeatureComparison = showFeatureComparison
        self.showLimits = showLimits
        self.highlightTierId = highlightTierId
        self.labels = labels
        self.onError = onError
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(RegistrationSubscriptionTestID.view(.pricing))
        .task {
            // Built here rather than in `init`, because the client comes from the environment —
            // the same arrangement `SubscriptionAdminComponent` uses. A re-entered task (a
            // navigation pop, a state restore) finds the model already built and leaves the
            // selection and the reported-failure latch alone.
            guard model == nil,
                  let client = requireClient(client, component: "RegistrationSubscriptionPricingView")
            else { return }

            let created = WildwoodPricingViewModel(
                client: client,
                appId: appId,
                currency: currency,
                defaultBilling: defaultBilling,
                offerFreeTierChoice: offerFreeTierChoice
            )
            created.onError = onError
            model = created
            await created.load()
        }
    }

    // MARK: - Bodies

    @ViewBuilder private var content: some View {
        if let model {
            switch model.bodyKind {
            case .loading:
                skeleton
            case .unavailable:
                unavailablePanel(model)
            case .content:
                grids(model)
            }
        } else {
            // No model yet: the client is still being resolved, which is the loading state by any
            // other name — and shapes are what the loading state shows.
            skeleton
        }
    }

    private var skeleton: some View {
        PricingSkeletonView(label: labels.loadingPlans)
    }

    private func unavailablePanel(_ model: WildwoodPricingViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(labels.pricingUnavailable, systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(theme.danger)

            Button(labels.retry) {
                Task { await model.retry() }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(RegistrationSubscriptionTestID.retryButton)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func grids(_ model: WildwoodPricingViewModel) -> some View {
        let sections: PricingSections = PricingViewRules.sections(
            showPlans: showPlans,
            showAddOns: showAddOns
        )

        if sections.plans {
            PlanGridView(
                tiers: model.visiblePlans,
                currency: model.displayCurrency,
                billing: model.billing,
                showBillingToggle: showBillingToggle,
                showFeatures: showFeatureComparison,
                showLimits: showLimits,
                highlightTierId: highlightTierId,
                contactUrl: contactUrl,
                labels: labels,
                onBillingChange: { cycle in model.setBilling(cycle) },
                onSelectTier: { tier in
                    // Nil for a plan that sells nothing here (a "contact us" plan with a URL):
                    // its footer opens that URL rather than raising a selection, and no host is
                    // handed a payload for a purchase that cannot be made.
                    if let payload = model.planSelectionPayload(for: tier, contactUrl: contactUrl) {
                        onSelect(payload)
                    }
                }
            )
        }

        if sections.packs {
            PackGridView(
                addOns: model.packs,
                currency: model.displayCurrency,
                groups: addOnGroups,
                describeAddOn: describeAddOn,
                affordance: affordance,
                selectedIds: model.selectedPackIds,
                labels: labels,
                onToggle: { addOnId in model.togglePack(addOnId) },
                onChoose: { addOn in onSelect(model.packSelectionPayload(forPack: addOn.id)) },
                onContinue: { onSelect(model.packsContinuePayload()) }
            )
        }
    }

    // MARK: - Derived state

    private var affordance: PricingPackAffordance {
        PricingViewRules.packAffordance(
            packSelection: packSelection,
            packPurchaseAvailable: packPurchaseAvailable
        )
    }
}
#endif
