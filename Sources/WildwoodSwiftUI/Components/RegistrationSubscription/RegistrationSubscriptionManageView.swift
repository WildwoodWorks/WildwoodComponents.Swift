#if os(iOS)
// The manage view: what a customer already pays for, and every way of changing it.
//
// The panels are this package's own — the same status card, plan grid, features, packs, usage and
// overrides ``SubscriptionAdminComponent`` has always rendered — so an app swapping its hand-built
// subscription screen for this keeps its locators. What is new is the middle: the plan change runs
// through ``WildwoodPlanChangeModel``, so a preview is confirmed in EVERY layout, a card is asked
// for by the component itself when the host did not bring its own sheet, and a prorated charge the
// bank wants to see is authenticated and the parked change completed instead of being refused.
//
// Two things are native rather than copied from the web, and both are the platform talking:
//
//  · This package ships no payment SDK, so the 3-D Secure step is the host-injected
//    ``WildwoodPaymentActionHandler``. WITHOUT one the flow never tells the server this device can
//    answer a challenge, so the server refuses a change that needs one rather than parking it —
//    and the card sheet still works, because ``PaymentComponent`` completes a payment through
//    StoreKit, the provider's own page or a server-owned completion with no SDK at all.
//  · A store-billed app (`requiresAppStorePayment`) has no in-app-purchase product behind a pack,
//    so pack PURCHASE is not offered; owned, bundled and granted rows still render and can still
//    be cancelled. The confirmation drops the server's proration figures for the same reason: the
//    store prices its own subscriptions, and quoting a charge nobody here can honour is worse than
//    saying who bills it (Decision 5 / Appendix C DD-4).
//
// Packs are the other half. A pack is bought through the same card-once checkout the signup uses,
// cancelled at the end of the period it is paid up to, and a scheduled cancellation can be taken
// back. A pack nobody paid for — a registration token's, an admin's — says so, shows no renewal
// date and is simply removed when it is cancelled (``AddOnRowRules``).
//
// Every decision this file would otherwise make inside a `body` is a function in
// ``ManageViewRules``, because a rule inside a view cannot be tested on a machine with no
// simulator. What the web's props list has and this does not: `returnUrl`, which JS carries and
// never navigates to (Appendix C DD-5), and `className`.

import SwiftUI
import WildwoodCore

public struct RegistrationSubscriptionManageView: View {
    @Environment(\.wildwoodClient) private var client
    @Environment(\.wildwoodTheme) private var theme
    @Environment(\.wildwoodPaymentActionHandler) private var environmentPaymentActionHandler

    private let appId: String?
    private let layout: ManageLayout
    private let sections: [ManageSection]?
    private let showStatusAboveTabs: Bool
    private let isAdmin: Bool
    private let userId: String?
    private let companyId: String?
    private let allowPackSelfService: Bool
    private let allowCancel: Bool
    private let showAddOns: Bool
    private let paymentActionHandler: (any WildwoodPaymentActionHandler)?
    private let currency: String?
    private let contactUrl: String?
    private let labels: RegistrationSubscriptionLabels
    private let onMergeUsage: (@MainActor ([AppTierLimitStatusModel], UserTierSubscriptionModel?) async -> [AppTierLimitStatusModel])?
    private let onPaymentRequired: ((WildwoodPaymentRequiredArgs) async -> String?)?
    private let onSubscriptionChanged: (() -> Void)?
    private let onEntitlementsChanged: ((EntitlementsChangedReason) -> Void)?
    private let onError: ((RegistrationSubscriptionError) -> Void)?

    @State private var resolvedClient: WildwoodClient?
    @State private var admin: WildwoodSubscriptionAdminModel?
    @State private var flow: WildwoodPlanChangeModel?
    @State private var activeTab: ManageSection?
    @State private var pickingPacks: Bool = false
    @State private var mergedLimitStatuses: [AppTierLimitStatusModel] = []
    /// Neither the host nor the client named an app, so there is nothing to manage.
    @State private var appIdMissing: Bool = false
    /// The app and scope the models were built for. A host that swaps the user or company under a
    /// mounted view gets new models rather than the previous subscriber's data.
    @State private var loadedScope: String?

    /// - Parameters:
    ///   - appId: overrides the client's configured app.
    ///   - layout: `.tabs` shows one section at a time; `.stacked` puts them all down one page.
    ///   - sections: the sections to render, in order. Nil renders every one of them. The
    ///     `overrides` and `addOns` filters apply whether a section was named or defaulted.
    ///   - showStatusAboveTabs: lifts the subscription card out of the section list.
    ///   - isAdmin: shows the overrides section and the panels' admin affordances.
    ///   - userId: manage THIS user's subscription (an admin scope).
    ///   - companyId: manage this company's subscription (an admin scope).
    ///   - allowPackSelfService: offer "Add packs". Hidden anyway on an App-Store-exclusive app.
    ///   - allowCancel: offer cancelling the subscription and its packs.
    ///   - showAddOns: render the packs section at all.
    ///   - paymentActionHandler: this screen's own handler, which beats the subtree's
    ///     (`.wildwoodPaymentActionHandler(_:)`) and the client's. No handler anywhere is
    ///     supported and is the default: the change is then posted in the plain form, and the
    ///     server refuses a change needing 3-D Secure rather than parking one nobody can finish.
    ///   - currency: display override. Wins over the currency the plans are quoted in.
    ///   - contactUrl: where a "contact us" plan with no URL of its own sends the viewer.
    ///   - labels: overridable copy.
    ///   - onMergeUsage: the host's own real-time usage, overlaid on the server's statuses after
    ///     every refresh. The same two-argument seam ``UsageDashboardComponent`` takes.
    ///   - onPaymentRequired: the host's own card sheet. Supplied, it is used INSTEAD of the
    ///     built-in one and its answer is final: a transaction id completes the change, nothing
    ///     abandons it.
    ///   - onSubscriptionChanged: raised after every refresh this view runs.
    ///   - onEntitlementsChanged: raised after every mutation, with the reason the entitlement
    ///     cache was dropped for.
    ///   - onError: told about every failure, with a stable code.
    public init(
        appId: String? = nil,
        layout: ManageLayout = .tabs,
        sections: [ManageSection]? = nil,
        showStatusAboveTabs: Bool = false,
        isAdmin: Bool = false,
        userId: String? = nil,
        companyId: String? = nil,
        allowPackSelfService: Bool = false,
        allowCancel: Bool = true,
        showAddOns: Bool = true,
        paymentActionHandler: (any WildwoodPaymentActionHandler)? = nil,
        currency: String? = nil,
        contactUrl: String? = nil,
        labels: RegistrationSubscriptionLabels = .defaults,
        onMergeUsage: (@MainActor ([AppTierLimitStatusModel], UserTierSubscriptionModel?) async -> [AppTierLimitStatusModel])? = nil,
        onPaymentRequired: ((WildwoodPaymentRequiredArgs) async -> String?)? = nil,
        onSubscriptionChanged: (() -> Void)? = nil,
        onEntitlementsChanged: ((EntitlementsChangedReason) -> Void)? = nil,
        onError: ((RegistrationSubscriptionError) -> Void)? = nil
    ) {
        self.appId = appId
        self.layout = layout
        self.sections = sections
        self.showStatusAboveTabs = showStatusAboveTabs
        self.isAdmin = isAdmin
        self.userId = userId
        self.companyId = companyId
        self.allowPackSelfService = allowPackSelfService
        self.allowCancel = allowCancel
        self.showAddOns = showAddOns
        self.paymentActionHandler = paymentActionHandler
        self.currency = currency
        self.contactUrl = contactUrl
        self.labels = labels
        self.onMergeUsage = onMergeUsage
        self.onPaymentRequired = onPaymentRequired
        self.onSubscriptionChanged = onSubscriptionChanged
        self.onEntitlementsChanged = onEntitlementsChanged
        self.onError = onError
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // `.contain` before the identifier, as on the stacked sections below: a `ScrollView` is not
        // itself an accessibility element, and an identifier on one is free to propagate to its
        // descendants instead of naming a queryable element of its own. `.contain` asks for the
        // element, and children stay individually accessible.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            RegistrationSubscriptionTestID.view(.manage, step: ManageViewRules.stepIdentifier(flow?.step))
        )
        // Keyed on the scope, as the web keys its load effect: a host that swaps `userId` or
        // `companyId` is asking for a different subscriber, not for the same one again.
        .task(id: scopeToken) { await start() }
        // Never cancels money already in flight: `detach()` lets an authenticated change drain
        // through its completion and only silences the callbacks.
        .onDisappear { flow?.detach() }
    }

    // MARK: - Frame

    @ViewBuilder private var content: some View {
        if appIdMissing {
            ErrorBannerView(message: ManageViewRules.appIdRequiredMessage)
        } else if let admin, let flow, let resolvedClient {
            loaded(admin: admin, flow: flow, client: resolvedClient)
        } else {
            // No models yet: the client is still being resolved, which is the loading state by
            // any other name.
            LoadingSpinnerView(label: labels.loadingPlans)
        }
    }

    private func loaded(
        admin: WildwoodSubscriptionAdminModel,
        flow: WildwoodPlanChangeModel,
        client: WildwoodClient
    ) -> some View {
        let arrangement: ManageBodyLayout = ManageViewRules.layout(
            sections: sections,
            isAdmin: isAdmin,
            showAddOns: showAddOns,
            showStatusAboveTabs: showStatusAboveTabs
        )
        let tab: ManageSection? = ManageViewRules.currentTab(activeTab, body: arrangement.body)

        return VStack(alignment: .leading, spacing: 16) {
            dataError(admin, flow: flow)

            PlanChangeNoticeView(flow: flow, labels: labels, collectsPaymentInApp: true)

            if arrangement.statusAbove {
                statusPanel(admin)
            }

            if ManageViewRules.isTabbed(layout) {
                tabBar(arrangement.body, current: tab)
                if let tab {
                    panel(tab, admin: admin, flow: flow)
                }
            } else {
                stackedSections(arrangement.body, admin: admin, flow: flow)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wildwoodPlanChangeSheets(
            flow: flow,
            client: client,
            appId: admin.appId,
            labels: labels,
            paymentActionHandler: resolveHandler(client),
            hasHostPaymentHandler: onPaymentRequired != nil,
            onError: onError
        )
        .sheet(isPresented: $pickingPacks) {
            packSheet(admin: admin, client: client)
        }
    }

    /// The data layer's own message. Suppressed while the change has failed: the notice above
    /// already says it once, in the words the server chose.
    @ViewBuilder private func dataError(
        _ admin: WildwoodSubscriptionAdminModel,
        flow: WildwoodPlanChangeModel
    ) -> some View {
        if !admin.errorMessage.isEmpty, flow.step != .failed {
            ErrorBannerView(message: admin.errorMessage) { admin.errorMessage = "" }
        }
    }

    private func tabBar(_ body: [ManageSection], current: ManageSection?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(body, id: \.self) { section in
                    tabButton(section, isCurrent: section == current)
                }
            }
        }
    }

    private func tabButton(_ section: ManageSection, isCurrent: Bool) -> some View {
        let title: String = ManageViewRules.sectionTitle(section, labels: labels)

        return Button {
            activeTab = section
        } label: {
            Text(title)
                .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? theme.accent : Color.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier(RegistrationSubscriptionTestID.section(section))
    }

    private func stackedSections(
        _ body: [ManageSection],
        admin: WildwoodSubscriptionAdminModel,
        flow: WildwoodPlanChangeModel
    ) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(body, id: \.self) { section in
                VStack(alignment: .leading, spacing: 12) {
                    Text(ManageViewRules.sectionTitle(section, labels: labels))
                        .font(.headline)
                    panel(section, admin: admin, flow: flow)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(RegistrationSubscriptionTestID.section(section))
            }
        }
    }

    // MARK: - Panels

    @ViewBuilder private func panel(
        _ section: ManageSection,
        admin: WildwoodSubscriptionAdminModel,
        flow: WildwoodPlanChangeModel
    ) -> some View {
        switch section {
        case .subscription:
            statusPanel(admin)
        case .plans:
            plansPanel(admin, flow: flow)
        case .features:
            FeaturesPanel(model: admin, includedLabel: labels.featureIncluded)
        case .addOns:
            addOnsPanel(admin)
        case .usage:
            UsageLimitsPanel(model: admin, statuses: usageStatuses(admin))
        case .overrides:
            OverridesPanel(model: admin)
        }
    }

    private func statusPanel(_ admin: WildwoodSubscriptionAdminModel) -> some View {
        SubscriptionStatusPanel(
            model: admin,
            allowCancel: allowCancel,
            onCancelRequested: { cancelSubscription(admin) }
        )
    }

    private func plansPanel(
        _ admin: WildwoodSubscriptionAdminModel,
        flow: WildwoodPlanChangeModel
    ) -> some View {
        TierPlansPanel(
            model: admin,
            currency: ManageViewRules.currency(override: currency, tiers: admin.tiers),
            contactUrl: contactUrl,
            onSelectTier: { selection in flow.selectTier(selection) }
        )
    }

    private func addOnsPanel(_ admin: WildwoodSubscriptionAdminModel) -> some View {
        let selfService: Bool = ManageViewRules.packSelfServiceOffered(
            allowPackSelfService: allowPackSelfService,
            showAddOns: showAddOns,
            requiresAppStorePayment: admin.requiresAppStorePayment
        )
        // Spelled out rather than a ternary with a closure in one arm: the panel renders "Add
        // packs" on exactly the condition that this is non-nil.
        var openPicker: (() -> Void)?
        if selfService {
            openPicker = { pickingPacks = true }
        }

        return AddOnsPanel(
            model: admin,
            labels: labels.addOnsPanelLabels,
            allowCancel: allowCancel,
            // Packs are bought through the picker's quoted checkout here, exactly as the web's
            // manage view does by passing no `onSubscribe` — never through the panel's own
            // one-click subscribe, which prices the same pack a different way.
            allowDirectSubscribe: false,
            onAddPacks: openPicker,
            onChanged: { reason in packRowChanged(admin, reason: reason) },
            onError: onError
        )
    }

    /// The statuses the usage panel renders. Nil hands the panel back to the model's own list,
    /// which keeps it observing the server's answers; a host merge replaces them.
    private func usageStatuses(_ admin: WildwoodSubscriptionAdminModel) -> [AppTierLimitStatusModel]? {
        guard onMergeUsage != nil else { return nil }
        return ManageViewRules.effectiveLimitStatuses(
            merged: mergedLimitStatuses,
            fromServer: admin.limitStatuses,
            hasMerge: true
        )
    }

    // MARK: - The pack picker

    @ViewBuilder private func packSheet(
        admin: WildwoodSubscriptionAdminModel,
        client: WildwoodClient
    ) -> some View {
        ManagePackSheet(
            client: client,
            appId: admin.appId,
            addOns: ManageViewRules.availablePacks(
                admin.availableAddOns,
                subscriptions: admin.addOnSubscriptions,
                currentTierId: admin.currentTierId
            ),
            currency: ManageViewRules.currency(override: currency, tiers: admin.tiers),
            labels: labels,
            paymentActionHandler: resolveHandler(client),
            onBought: { packsBought(admin) },
            onError: onError,
            onClose: { pickingPacks = false }
        )
    }

    // MARK: - Actions

    /// Cancel the subscription, in whichever scope this view is showing. A refusal is REPORTED —
    /// the cancel endpoints answer `success: false` rather than throwing, and a failed cancel that
    /// says nothing looks exactly like one that worked.
    private func cancelSubscription(_ admin: WildwoodSubscriptionAdminModel) {
        Task {
            await admin.cancelSubscription()
            guard admin.lastCancelResult?.success == true else {
                onError?(
                    RegistrationSubscriptionError(
                        code: RegistrationSubscriptionErrorCodes.subscriptionCancelFailed,
                        message: admin.errorMessage.isEmpty
                            ? RegistrationSubscriptionDriverMessages.cancelRefused
                            : admin.errorMessage
                    )
                )
                return
            }
            // The MODEL ran this cancel, so the model settles it: it dropped the entitlement cache
            // once, and nothing here drops it again. The reload is the view's because the model
            // re-reads only the subscription while this screen also shows features, packs and
            // usage — one narrow read is repeated, the signal is not.
            await refresh(admin)
            onEntitlementsChanged?(.cancel)
        }
    }

    /// A pack row was cancelled or reactivated, and only on success. The panel ran the mutation
    /// through the model, so the model settled it — the entitlement cache is dropped there, once,
    /// never again here. What is left is reloading the rest of the screen, which the model's own
    /// pack re-read does not cover, and telling the host why.
    private func packRowChanged(_ admin: WildwoodSubscriptionAdminModel, reason: EntitlementsChangedReason) {
        Task {
            await refresh(admin)
            onEntitlementsChanged?(reason)
        }
    }

    /// Packs were bought through the picker. The checkout driver does not touch the entitlement
    /// cache — it has no admin model to do it through — so this is the one mutation the VIEW
    /// invalidates for.
    private func packsBought(_ admin: WildwoodSubscriptionAdminModel) {
        admin.invalidateEntitlements(.addOn)
        Task {
            await refresh(admin)
            onEntitlementsChanged?(.addOn)
        }
    }

    private func refresh(_ admin: WildwoodSubscriptionAdminModel) async {
        await admin.loadAll()
        await mergeUsage(admin)
        onSubscriptionChanged?()
    }

    /// A plan change landed. ``WildwoodPlanChangeModel`` OWNS settling it — the entitlement cache
    /// is already dropped and the subscription, features and limits already re-read by the time
    /// this runs — so all that is left is what only the view knows about: the host's usage merge
    /// over the limits that just arrived, and its changed notification. Reloading here as well
    /// would fetch every one of those a second time for one change.
    private func afterPlanChange(_ admin: WildwoodSubscriptionAdminModel) async {
        await mergeUsage(admin)
        onSubscriptionChanged?()
    }

    /// Overlay the host's real-time usage on the server's statuses. A merge that throws leaves the
    /// server's own list standing rather than blanking the panel.
    private func mergeUsage(_ admin: WildwoodSubscriptionAdminModel) async {
        guard let onMergeUsage else { return }
        mergedLimitStatuses = await onMergeUsage(admin.limitStatuses, admin.subscription)
    }

    private func resolveHandler(_ client: WildwoodClient) -> (any WildwoodPaymentActionHandler)? {
        WildwoodPaymentAction.resolve(
            parameter: paymentActionHandler,
            environment: environmentPaymentActionHandler,
            client: client
        )
    }

    /// What the loaded models were built for. Cheap to compare, which is all a `.task(id:)` needs.
    private var scopeToken: String {
        (appId ?? "") + "|" + (userId ?? "") + "|" + (companyId ?? "")
    }

    private func start() async {
        let token: String = scopeToken
        if loadedScope == token { return }
        guard let client = requireClient(client, component: "RegistrationSubscriptionManageView") else {
            return
        }

        guard let resolvedAppId = appId ?? client.config.appId, !resolvedAppId.isEmpty else {
            appIdMissing = true
            return
        }
        appIdMissing = false

        // A scope that changed under a mounted view: the previous flow stops reporting, and a
        // change it has already paid for still drains to its completion.
        flow?.detach()
        loadedScope = token
        mergedLimitStatuses = []

        let created = WildwoodSubscriptionAdminModel(
            client: client,
            appId: resolvedAppId,
            scope: ManageViewRules.scope(userId: userId, companyId: companyId)
        )
        let change = WildwoodPlanChangeModel(
            client: client,
            admin: created,
            paymentActionHandler: resolveHandler(client)
        )
        change.labels = labels
        change.onPaymentRequired = onPaymentRequired
        change.onChanged = { await afterPlanChange(created) }
        change.onEntitlementsChanged = onEntitlementsChanged
        change.onError = onError

        resolvedClient = client
        admin = created
        flow = change

        await created.loadAll()
        await mergeUsage(created)
    }
}

// MARK: - The pack picker sheet

/// Buying packs from the manage view: pick them, buy them, see what became of each.
///
/// The web's manage-view `PackPicker` is a modal that runs all three, and this is that modal: the
/// signup's ``PackPickerView`` grid, then the signup's ``PackCheckoutView`` over a
/// ``WildwoodPackCheckoutModel``, then the outcomes. It runs AS THE SIGNED-IN USER, because the
/// checkout controller is `[Authorize]` — the quote finds the customer the subscription's payment
/// already created, so a card on file is the card here and nothing is asked for twice.
private struct ManagePackSheet: View {
    let client: WildwoodClient
    let appId: String
    /// Everything the account can still buy: ``ManageViewRules/availablePacks(_:subscriptions:currentTierId:)``.
    let addOns: [AppTierAddOnModel]
    let currency: String
    let labels: RegistrationSubscriptionLabels
    let paymentActionHandler: (any WildwoodPaymentActionHandler)?
    /// The basket settled — some of it may have failed, which is what the outcomes say.
    let onBought: () -> Void
    let onError: ((RegistrationSubscriptionError) -> Void)?
    let onClose: () -> Void

    @State private var selectedIds: [String] = []
    @State private var checkout: WildwoodPackCheckoutModel?
    @State private var outcomes: [SignupPackOutcome] = []
    @State private var finished: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stage
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(labels.addPacksTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(labels.cancel) { onClose() }
                }
            }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier(RegistrationSubscriptionTestID.packsModal)
        // The checkout outlives this sheet only where money has already moved: `detach()` lets a
        // pack whose card was answered finish server-side and silences everything else.
        .onDisappear { checkout?.detach() }
    }

    @ViewBuilder private var stage: some View {
        if finished {
            PackOutcomeListView(packs: outcomes, labels: labels)
            // The sheet's own way out, over the outcomes. Not the Continue of the grid this sheet
            // opened on — that one is ``PackGridView``'s `packs-continue`.
            Button(labels.continueLabel) { onClose() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(RegistrationSubscriptionTestID.packsModalContinue)
        } else if let checkout {
            PackCheckoutView(model: checkout, labels: labels)
        } else {
            PackPickerView(
                addOns: addOns,
                currency: currency,
                selectedIds: selectedIds,
                labels: labels,
                pricingLabels: labels,
                onToggle: { addOnId in toggle(addOnId) },
                onContinue: { startCheckout() },
                onSkip: { onClose() }
            )
        }
    }

    private func toggle(_ addOnId: String) {
        if let index = selectedIds.firstIndex(of: addOnId) {
            selectedIds.remove(at: index)
            return
        }
        selectedIds.append(addOnId)
    }

    private func startCheckout() {
        guard checkout == nil else { return }
        let items: [AddOnCheckoutItemInput] = ManageViewRules.checkoutItems(ids: selectedIds, addOns: addOns)
        guard !items.isEmpty else { return }

        let model = WildwoodPackCheckoutModel(
            client: client,
            appId: appId,
            items: items,
            names: ManageViewRules.packNames(addOns),
            paymentActionHandler: paymentActionHandler
        )
        model.labels = labels
        model.onError = onError
        model.onFinished = { settled in
            outcomes = settled
            finished = true
            onBought()
        }
        checkout = model
        model.start()
    }
}
#endif
