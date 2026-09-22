#if os(iOS)
// The six SubscriptionAdmin sub-panels — parity with SubscriptionStatusPanel,
// TierPlansPanel, FeaturesPanel, AddOnsPanel, UsageLimitsPanel, OverridesPanel.

import SwiftUI
import WildwoodCore
import WildwoodTestIDs

// MARK: - Status

public struct SubscriptionStatusPanel: View {
    @Bindable var model: WildwoodSubscriptionAdminModel
    /// False removes the cancel affordance entirely — a surface that does not let this viewer
    /// cancel (`allowCancel: false` on the manage view).
    private let allowCancel: Bool
    /// The host's own cancel, run INSTEAD of the panel's. The manage view supplies one so a refusal
    /// reaches `onError` with a code and a success refreshes everything the view shows; without one
    /// the panel cancels through the model, as it always has.
    private let onCancelRequested: (() -> Void)?

    // Statuses from which the user can still cancel. Excluding Trialing/
    // PastDue locked those subscribers out of cancelling entirely; Pending*
    // changes are cancelled via the Plans panel.
    private static let cancellableStatuses: Set<String> = ["Active", "Trialing", "PastDue"]

    public init(
        model: WildwoodSubscriptionAdminModel,
        allowCancel: Bool = true,
        onCancelRequested: (() -> Void)? = nil
    ) {
        self.model = model
        self.allowCancel = allowCancel
        self.onCancelRequested = onCancelRequested
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let subscription = model.subscription {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(subscription.tierName).font(.title3.weight(.bold))
                        Spacer()
                        Text(Self.statusLabel(subscription.status))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Self.statusColor(subscription.status).opacity(0.15), in: Capsule())
                            .foregroundStyle(Self.statusColor(subscription.status))
                        if subscription.isFreeTier {
                            Text("Free")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.gray.opacity(0.15), in: Capsule())
                        }
                    }
                    if !subscription.tierDescription.isEmpty {
                        Text(subscription.tierDescription).font(.subheadline).foregroundStyle(.secondary)
                    }
                    detailRow("Started", subscription.startDate)
                    detailRow("Current period ends", subscription.currentPeriodEnd)
                    // Only while the trial is actually running: the server keeps a finished
                    // trial's end date on the row, and showing it unconditionally put
                    // "Trial ends" on an Active, paid plan.
                    if SubscriptionAccess.isTrialRunning(
                        status: subscription.status,
                        trialEnd: subscription.trialEndDate
                    ) {
                        detailRow("Trial ends", subscription.trialEndDate)
                    }
                    if !subscription.pendingTierName.isEmpty {
                        Label("Pending change to \(subscription.pendingTierName)", systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let companyName = subscription.companyName {
                        detailTextRow("Company", companyName)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))

                // Scheduled cancellation notice.
                if subscription.status == "PendingCancellation" {
                    Label(pendingCancellationNotice(subscription), systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                // Store-billed subscriptions (App Store / Google Play) can't be
                // stopped server-side — surface the store instructions/link.
                if let cancel = model.lastCancelResult, cancel.success, cancel.requiresUserAction {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            cancel.userActionInstructions
                                ?? "Also cancel this subscription in your store settings — store billing can't be stopped from here.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        if let urlString = cancel.userActionUrl, let url = URL(string: urlString) {
                            Link("Open subscription settings", destination: url)
                                .font(.caption)
                        }
                    }
                    .padding(10)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }

                if allowCancel, !subscription.isFreeTier, Self.cancellableStatuses.contains(subscription.status) {
                    Button("Cancel Subscription", role: .destructive) {
                        if let onCancelRequested {
                            onCancelRequested()
                            return
                        }
                        Task { await model.cancelSubscription() }
                    }
                    .font(.subheadline)
                }
            } else {
                ContentUnavailableView(
                    "No subscription",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Choose a plan from the Plans panel.")
                )
            }
        }
    }

    private func pendingCancellationNotice(_ subscription: UserTierSubscriptionModel) -> String {
        var notice = "Your plan is cancelled"
        if let date = subscription.pendingChangeDate ?? subscription.endDate {
            notice += " and access continues until \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        notice += ". Choose a plan from the Plans tab to stay subscribed."
        return notice
    }

    static func statusLabel(_ status: String) -> String {
        switch status {
        case "PastDue": return "Past Due"
        case "PendingUpgrade": return "Upgrade Scheduled"
        case "PendingDowngrade": return "Downgrade Scheduled"
        case "PendingCancellation": return "Cancellation Scheduled"
        default: return status
        }
    }

    static func statusColor(_ status: String) -> Color {
        switch status {
        case "Active": return .green
        case "Trialing", "PendingUpgrade", "PendingDowngrade": return .blue
        case "PastDue", "PendingCancellation": return .orange
        case "Cancelled": return .red
        default: return .gray
        }
    }

    @ViewBuilder private func detailRow(_ label: String, _ date: Date?) -> some View {
        if let date {
            detailTextRow(label, date.formatted(date: .abbreviated, time: .omitted))
        }
    }

    @ViewBuilder private func detailTextRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption)
        }
    }
}

// MARK: - Tier plans

public struct TierPlansPanel: View {
    @Bindable var model: WildwoodSubscriptionAdminModel
    /// Collect payment for a plan change. The args carry the pricing MODEL id, the PLAN's price
    /// (never the prorated charge) and the option's trial days, so a host wiring this into
    /// `PaymentComponent` gets a recurring subscription rather than a one-off charge.
    ///
    /// Read only on the LEGACY path — the one where this panel drives the change itself. A host
    /// that supplies ``onSelectTier`` owns the flow, and the same seam lives on that flow.
    let onPaymentRequired: ((WildwoodPaymentRequiredArgs) async -> String?)?
    /// The currency the cards quote in. Nil takes the catalog's own, as it always has.
    private let currency: String?
    /// Where a "contact us" plan with no URL of its own sends the viewer.
    private let contactUrl: String?
    /// The plan the viewer picked, handed to whoever owns the change.
    ///
    /// Supplied, this panel PRICES nothing and confirms nothing: the host's
    /// ``WildwoodPlanChangeModel`` previews, confirms, takes the card and completes, and this panel
    /// is a grid again. Omitted, the panel keeps its own preview and confirmation sheet, so a host
    /// that has always mounted it alone still works.
    private let onSelectTier: ((PlanChangeSelection) -> Void)?

    @State private var selectedPricingByTier: [String: String] = [:]
    @State private var pendingChange: (tier: AppTierModel, pricing: AppTierPricingModel?)?

    public init(
        model: WildwoodSubscriptionAdminModel,
        onPaymentRequired: ((WildwoodPaymentRequiredArgs) async -> String?)? = nil,
        currency: String? = nil,
        contactUrl: String? = nil,
        onSelectTier: ((PlanChangeSelection) -> Void)? = nil
    ) {
        self.model = model
        self.onPaymentRequired = onPaymentRequired
        self.currency = currency
        self.contactUrl = contactUrl
        self.onSelectTier = onSelectTier
    }

    public var body: some View {
        VStack(spacing: 16) {
            ForEach(model.tiers) { tier in
                TierCard(
                    tier: tier,
                    selectedPricing: selectedPricing(for: tier),
                    isCurrentTier: tier.id == model.subscription?.appTierId,
                    currency: currency ?? model.catalogCurrency,
                    enterpriseContactUrl: contactUrl,
                    onSelectPricing: { pricing in
                        selectedPricingByTier[tier.id] = pricing.id
                    },
                    onSubscribe: { tier, pricing in
                        if let onSelectTier {
                            onSelectTier(
                                ManageViewRules.planChangeSelection(
                                    tier: tier,
                                    pricing: pricing,
                                    hasSubscription: model.subscription != nil
                                )
                            )
                            return
                        }
                        pendingChange = (tier, pricing)
                        Task { await model.previewChange(to: tier, pricing: pricing) }
                    }
                )
            }
        }
        // The host's flow previews through the same model, so its preview must NOT raise this
        // panel's own confirmation as well — one change, one confirmation.
        .sheet(isPresented: Binding(
            get: { onSelectTier == nil && model.tierChangePreview != nil },
            set: { if !$0 { model.clearPreview() } }
        )) {
            if let preview = model.tierChangePreview, let pending = pendingChange {
                // Written with explicit argument labels rather than trailing closures: the sheet
                // gained two non-function parameters ahead of these, and a reader should not have
                // to run the trailing-closure matching rules to see which is which.
                TierChangeConfirmationSheet(
                    preview: preview,
                    tierName: pending.tier.name,
                    onConfirm: { immediate in
                        Task {
                            var transactionId: String?
                            if preview.paymentRequired, !preview.paymentBypassAllowed, let onPaymentRequired {
                                transactionId = await onPaymentRequired(
                                    WildwoodPaymentRequiredArgs(
                                        tier: pending.tier,
                                        pricing: pending.pricing,
                                        fallbackCurrency: model.catalogCurrency ?? preview.currency
                                    )
                                )
                                if transactionId == nil {
                                    model.clearPreview()
                                    return
                                }
                            }
                            await model.changeTier(
                                to: pending.tier,
                                pricing: pending.pricing,
                                immediate: immediate,
                                paymentTransactionId: transactionId
                            )
                        }
                    },
                    onCancel: { model.clearPreview() }
                )
            }
        }
    }

    private func selectedPricing(for tier: AppTierModel) -> AppTierPricingModel? {
        if let id = selectedPricingByTier[tier.id] {
            return tier.pricingOptions.first { $0.id == id }
        }
        return tier.pricingOptions.first(where: \.isDefault) ?? tier.pricingOptions.first
    }
}

struct TierChangeConfirmationSheet: View {
    let preview: TierChangePreviewModel
    let tierName: String
    /// Said INSTEAD of the server's proration figures when a device store owns the billing
    /// (Decision 5 / Appendix C DD-4). The store prices and bills its own subscriptions, so a
    /// prorated charge quoted here is a number nobody can honour.
    var storeBillingNotice: String? = nil
    /// A change is being posted: the buttons stop taking taps so one confirmation cannot be sent
    /// twice.
    var busy: Bool = false
    let onConfirm: (Bool) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(preview.isUpgrade ? "Upgrade to \(tierName)" : "Change to \(tierName)")
                    .font(.title3.weight(.bold))

                if let current = preview.currentTierName {
                    row("Current plan", "\(current) (\(formatted(preview.currentPrice)))")
                }
                row("New plan", "\(preview.newTierName ?? tierName) (\(formatted(preview.newPrice)))")
                if let storeBillingNotice {
                    Label(storeBillingNotice, systemImage: "applelogo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    if let prorated = preview.proratedChargeToday, prorated > 0 {
                        row("Charged today", formatted(prorated))
                    }
                    if let credit = preview.creditAmount, credit > 0 {
                        row("Credit applied", formatted(credit))
                    }
                    if let nextAmount = preview.nextBillingAmount, let nextDate = preview.nextBillingDate {
                        row("Next billing", "\(formatted(nextAmount)) on \(nextDate.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
                if !preview.featuresGained.isEmpty {
                    Label("Gains: \(preview.featuresGained.joined(separator: ", "))", systemImage: "plus.circle")
                        .font(.caption).foregroundStyle(.green)
                }
                if !preview.featuresLost.isEmpty {
                    Label("Loses: \(preview.featuresLost.joined(separator: ", "))", systemImage: "minus.circle")
                        .font(.caption).foregroundStyle(.red)
                }
                if preview.paymentRequired {
                    Label(
                        preview.paymentBypassAllowed ? "Payment required (bypass allowed)" : "Payment required",
                        systemImage: "creditcard"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                Spacer()

                if preview.allowImmediateChange {
                    Button {
                        onConfirm(true)
                    } label: {
                        Text("Change Now").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)
                }
                if preview.allowScheduledChange {
                    Button {
                        onConfirm(false)
                    } label: {
                        Text("Change at Period End").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(busy)
                }
                Button("Cancel") { onCancel() }
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
                    .disabled(busy)
            }
            .padding()
            .navigationTitle("Confirm Change")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline)
        }
    }

    /// Through the shared formatter: a missing amount reads as the currency's zero rather than a
    /// hard-coded "$0.00", and an ISO code outside the symbol table renders as itself instead of
    /// a dollar sign.
    private func formatted(_ amount: Double?) -> String {
        WildwoodMoney.format(amount ?? 0, currency: preview.currency)
    }
}

// MARK: - Features

public struct FeaturesPanel: View {
    @Bindable var model: WildwoodSubscriptionAdminModel
    /// Badge on a feature the account has outside its plan.
    private let includedLabel: String

    public init(model: WildwoodSubscriptionAdminModel, includedLabel: String = "Included") {
        self.model = model
        self.includedLabel = includedLabel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.featureDefinitions.isEmpty, model.features.isEmpty {
                ContentUnavailableView("No features defined", systemImage: "switch.2")
            } else {
                ForEach(definitions) { definition in
                    featureRow(definition)
                }
            }
        }
    }

    @ViewBuilder private func featureRow(_ definition: AppFeatureDefinitionModel) -> some View {
        let hasAccess = model.features[definition.featureCode] ?? false
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(definition.displayName).font(.subheadline.weight(.medium))
                    // An enabled feature granted by an override is not part of the plan — say so,
                    // to everyone and not only to admins.
                    if hasAccess, isGrantedByOverride(definition.featureCode) {
                        Text(includedLabel)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15), in: Capsule())
                    }
                }
                if !definition.description.isEmpty {
                    Text(definition.description).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: hasAccess ? "checkmark.circle.fill" : "lock.fill")
                .foregroundStyle(hasAccess ? .green : .secondary)
        }
        .padding(.vertical, 4)
    }

    /// NOTE: the self-service scope has no override list — the server exposes overrides to admin
    /// callers only (`loadOverrides` returns [] for `.currentUser`), so the badge appears in the
    /// admin scopes. Nothing is invented for the self scope.
    private func isGrantedByOverride(_ featureCode: String) -> Bool {
        model.overrides.contains { $0.featureCode == featureCode && $0.isEnabled }
    }

    private var definitions: [AppFeatureDefinitionModel] {
        if !model.featureDefinitions.isEmpty {
            return model.featureDefinitions.sorted { $0.displayOrder < $1.displayOrder }
        }
        // Fall back to raw feature codes when no definitions are exposed.
        return []
    }
}

// MARK: - Add-ons

/// The packs panel.
///
/// One access-granting rule decides both lists (``AddOnRowRules``): a Cancelled or Expired row
/// grants nothing and its pack goes back on offer, while a row scheduled to cancel is still owned
/// and is not sold twice. A row with no payment behind it was granted rather than sold, so it
/// promises no renewal, offers no reactivate, and says something different before it is cancelled.
public struct AddOnsPanel: View {
    @Bindable var model: WildwoodSubscriptionAdminModel
    private let labels: AddOnsPanelLabels
    private let allowCancel: Bool
    /// The per-row one-click Subscribe, which buys a pack through the direct subscribe endpoint.
    ///
    /// False on the manage view, which buys packs through the pack picker's quoted checkout
    /// instead — the web's manage view passes no `onSubscribe` for exactly that reason, and two
    /// ways to buy the same pack, priced differently, is one too many. True everywhere else, so
    /// the admin container keeps the affordance it has always had.
    private let allowDirectSubscribe: Bool
    /// Opens the host's pack picker. Omitted, no "Add packs" is offered — which is also how an
    /// App-Store-exclusive app renders, since a pack has no in-app-purchase product behind it.
    private let onAddPacks: (() -> Void)?
    /// Raised after a row's mutation lands, with the reason the entitlement cache was dropped for.
    /// The model has already invalidated it; this is the host's own notification.
    private let onChanged: ((EntitlementsChangedReason) -> Void)?
    /// Raised when a row's mutation was refused, with a stable code.
    private let onError: ((RegistrationSubscriptionError) -> Void)?

    /// The last refused action, in the server's own words. Cleared when the next attempt starts,
    /// so a retry never shows a stale message.
    @State private var actionError = ""
    @State private var processingId: String?
    @State private var processingAction: AddOnAction = .cancel
    /// The row whose cancellation is being confirmed. Nothing is cancelled on the first tap.
    @State private var confirmingSubscription: UserAddOnSubscriptionModel?

    public init(
        model: WildwoodSubscriptionAdminModel,
        labels: AddOnsPanelLabels = AddOnsPanelLabels(),
        allowCancel: Bool = true,
        allowDirectSubscribe: Bool = true,
        onAddPacks: (() -> Void)? = nil,
        onChanged: ((EntitlementsChangedReason) -> Void)? = nil,
        onError: ((RegistrationSubscriptionError) -> Void)? = nil
    ) {
        self.model = model
        self.labels = labels
        self.allowCancel = allowCancel
        self.allowDirectSubscribe = allowDirectSubscribe
        self.onAddPacks = onAddPacks
        self.onChanged = onChanged
        self.onError = onError
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !actionError.isEmpty {
                ErrorBannerView(message: actionError) { actionError = "" }
            }

            if let onAddPacks {
                Button(labels.addPacks) { onAddPacks() }
                    .buttonStyle(.bordered)
                    .font(.subheadline)
                    .accessibilityIdentifier(RegistrationSubscriptionTestID.addPacks)
            }

            if !ownedRows.isEmpty {
                Text("Active Add-Ons").font(.headline)
                ForEach(ownedRows) { sub in
                    ownedRow(sub)
                }
            }

            if !availableRows.isEmpty {
                Text("Available Add-Ons").font(.headline)
                ForEach(availableRows) { addOn in
                    availableRow(addOn)
                }
            }

            if ownedRows.isEmpty, availableRows.isEmpty {
                ContentUnavailableView("No add-ons", systemImage: "puzzlepiece.extension")
            }
        }
        .confirmationDialog(
            confirmTitle,
            isPresented: Binding(
                get: { confirmingSubscription != nil },
                set: { if !$0 { confirmingSubscription = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmingSubscription
        ) { sub in
            Button(labels.cancelConfirm, role: .destructive) {
                confirmingSubscription = nil
                run(.cancel, on: sub)
            }
            Button(labels.cancelKeep, role: .cancel) {
                confirmingSubscription = nil
            }
        } message: { sub in
            Text(decision(for: sub).cancelMessage)
        }
    }

    /// Typed String so the dialog binds to the plain-text overload, not LocalizedStringKey.
    private var confirmTitle: String {
        "Cancel \(confirmingSubscription?.addOnName ?? "pack")"
    }

    // MARK: - Rows

    @ViewBuilder private func ownedRow(_ sub: UserAddOnSubscriptionModel) -> some View {
        let rules = decision(for: sub)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(sub.addOnName).font(.subheadline.weight(.medium))
                badge(rules.statusLabel, color: badgeColor(rules))
                if rules.showsIncludedBadge {
                    badge(labels.included, color: .blue)
                }
                Spacer()
            }
            if !sub.addOnDescription.isEmpty {
                Text(sub.addOnDescription).font(.caption).foregroundStyle(.secondary)
            }
            Text(dateLineText(sub, rules: rules))
                .font(.caption)
                .foregroundStyle(.secondary)

            if processingId == sub.id {
                // Typed String so the label binds to the plain-text overload, not
                // LocalizedStringKey.
                let busyLabel: String = processingAction == .reactivate ? "Reactivating\u{2026}" : "Cancelling\u{2026}"
                Text(busyLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    if rules.offersReactivate {
                        Button(labels.reactivate) { run(.reactivate, on: sub) }
                            .buttonStyle(.bordered)
                            .font(.caption)
                    }
                    if rules.offersCancel {
                        Button("Cancel", role: .destructive) { confirmingSubscription = sub }
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func availableRow(_ addOn: AppTierAddOnModel) -> some View {
        let pricing = AddOnRowRules.defaultPricing(addOn)
        let bundled = AddOnRowRules.isBundledInTier(addOn, currentTierId: model.currentTierId)
        let trial = AddOnRowRules.trialLabel(addOn: addOn, pricing: pricing)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(addOn.name).font(.subheadline.weight(.medium))
                Spacer()
                if pricing != nil {
                    Text(priceText(addOn, pricing: pricing))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !addOn.description.isEmpty {
                Text(addOn.description).font(.caption).foregroundStyle(.secondary)
            }
            if !trial.isEmpty {
                Text(trial).font(.caption).foregroundStyle(.secondary)
            }
            if bundled {
                badge("Included in Plan", color: .blue)
            } else if allowDirectSubscribe, !model.requiresAppStorePayment {
                // Apple owns billing in an App-Store-exclusive app and packs have no in-app
                // purchase product mapping, so there is nothing to offer here.
                let subscribeLabel: String = processingId == addOn.id ? "Subscribing\u{2026}" : "Subscribe"
                Button(subscribeLabel) {
                    run(subscribe: addOn, pricing: pricing)
                }
                .buttonStyle(.bordered)
                .font(.caption)
                .disabled(processingId == addOn.id)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Derived state

    private var ownedRows: [UserAddOnSubscriptionModel] {
        AddOnRowRules.ownedRows(model.addOnSubscriptions)
    }

    private var availableRows: [AppTierAddOnModel] {
        AddOnRowRules.availableRows(model.availableAddOns, subscriptions: model.addOnSubscriptions)
    }

    /// The admin routes have no reactivate endpoint, so an admin scope never offers it.
    private var canReactivate: Bool {
        !model.scope.isAdmin
    }

    private func decision(for sub: UserAddOnSubscriptionModel) -> AddOnRowDecision {
        AddOnRowRules.describe(sub, canCancel: allowCancel, canReactivate: canReactivate, labels: labels)
    }

    private func priceText(_ addOn: AppTierAddOnModel, pricing: AppTierAddOnPricingModel?) -> String {
        let money = AddOnRowRules.formatPrice(addOn: addOn, pricing: pricing, catalogCurrency: model.catalogCurrency)
        return "\(money) / \(AddOnRowRules.billingSuffix(pricing))"
    }

    private func dateLineText(_ sub: UserAddOnSubscriptionModel, rules: AddOnRowDecision) -> String {
        var line = "Started: \(Self.dateText(sub.startDate))"
        switch rules.dateLine {
        case .renews:
            line += " | Renews: \(Self.dateText(rules.endDate))"
        case .cancels:
            line += " | Cancels on: \(Self.dateText(rules.endDate))"
        case .cancelsAtPeriodEnd:
            line += " | Cancels at the end of the billing period"
        case .none:
            break
        }
        return line
    }

    private static func dateText(_ date: Date?) -> String {
        guard let date else { return "\u{2014}" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func badgeColor(_ rules: AddOnRowDecision) -> Color {
        if rules.statusLabel == "Bundled" { return .blue }
        return rules.cancelling ? .orange : .green
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Actions

    /// Cancel/reactivate. A refusal is SHOWN with whatever the server said — an invisible failure
    /// looked exactly like a purchase that went through.
    private func run(_ action: AddOnAction, on sub: UserAddOnSubscriptionModel) {
        actionError = ""
        processingAction = action
        processingId = sub.id
        Task {
            let ok: Bool
            if action == .reactivate {
                ok = await model.reactivateAddOn(sub)
            } else {
                // End of the paid period, not immediately: the row keeps access until then.
                ok = await model.cancelAddOn(sub, immediate: false)
            }
            if ok {
                onChanged?(action == .reactivate ? .reactivate : .cancel)
            } else {
                actionError = AddOnRowRules.failureMessage(
                    action,
                    name: sub.addOnName,
                    serverMessage: model.errorMessage.isEmpty ? nil : model.errorMessage
                )
                onError?(
                    RegistrationSubscriptionError(
                        code: action == .reactivate
                            ? RegistrationSubscriptionErrorCodes.packReactivateFailed
                            : RegistrationSubscriptionErrorCodes.packCancelFailed,
                        message: actionError
                    )
                )
            }
            processingId = nil
        }
    }

    private func run(subscribe addOn: AppTierAddOnModel, pricing: AppTierAddOnPricingModel?) {
        actionError = ""
        processingAction = .subscribe
        processingId = addOn.id
        Task {
            let ok = await model.subscribeToAddOn(addOn, pricing: pricing)
            if ok {
                onChanged?(.addOn)
            } else {
                actionError = AddOnRowRules.failureMessage(
                    .subscribe,
                    name: addOn.name,
                    serverMessage: model.errorMessage.isEmpty ? nil : model.errorMessage
                )
                onError?(
                    RegistrationSubscriptionError(
                        code: RegistrationSubscriptionErrorCodes.packCheckoutFailed,
                        message: actionError
                    )
                )
            }
            processingId = nil
        }
    }
}

// MARK: - Usage limits

public struct UsageLimitsPanel: View {
    @Bindable var model: WildwoodSubscriptionAdminModel
    @Environment(\.wildwoodTheme) private var theme
    /// The rows to render, when the host merged its own real-time usage over the server's
    /// (`onMergeUsage`). Nil — the default — renders the server's own statuses.
    private let statuses: [AppTierLimitStatusModel]?

    @State private var editingLimit: AppTierLimitStatusModel?
    @State private var newMaxValue = ""

    public init(model: WildwoodSubscriptionAdminModel, statuses: [AppTierLimitStatusModel]? = nil) {
        self.model = model
        self.statuses = statuses
    }

    public var body: some View {
        let rows: [AppTierLimitStatusModel] = statuses ?? model.limitStatuses

        VStack(alignment: .leading, spacing: 12) {
            if rows.isEmpty {
                ContentUnavailableView("No usage limits", systemImage: "gauge")
            } else {
                ForEach(rows) { status in
                    VStack(alignment: .leading, spacing: 4) {
                        UsageLimitRow(status: status, theme: theme)
                        if model.scope.isAdmin {
                            HStack {
                                Button("Adjust limit") {
                                    editingLimit = status
                                    newMaxValue = String(Int(status.maxValue))
                                }
                                .font(.caption)
                                Button("Reset usage") {
                                    Task { await model.resetUsage(status.limitCode) }
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .alert("Adjust \(editingLimit?.displayName ?? "limit")", isPresented: Binding(
            get: { editingLimit != nil },
            set: { if !$0 { editingLimit = nil } }
        )) {
            TextField("New maximum", text: $newMaxValue)
                .keyboardType(.numberPad)
            Button("Save") {
                if let limit = editingLimit, let value = Double(newMaxValue) {
                    Task { await model.updateLimit(limit.limitCode, newMaxValue: value) }
                }
                editingLimit = nil
            }
            Button("Cancel", role: .cancel) { editingLimit = nil }
        }
    }
}

// MARK: - Feature overrides

public struct OverridesPanel: View {
    @Bindable var model: WildwoodSubscriptionAdminModel

    @State private var showAddOverride = false
    @State private var overrideFeatureCode = ""
    @State private var overrideEnabled = true
    @State private var overrideReason = ""

    public init(model: WildwoodSubscriptionAdminModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Feature Overrides").font(.headline)
                Spacer()
                Button {
                    overrideFeatureCode = model.featureDefinitions.first?.featureCode ?? ""
                    overrideEnabled = true
                    overrideReason = ""
                    showAddOverride = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .font(.caption)
            }

            if model.overrides.isEmpty {
                ContentUnavailableView(
                    "No overrides",
                    systemImage: "slider.horizontal.3",
                    description: Text("Grant or revoke features outside the tier.")
                )
            } else {
                ForEach(model.overrides) { override in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(override.featureCode).font(.subheadline.weight(.medium))
                                Text(override.isEnabled ? "Granted" : "Revoked")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        (override.isEnabled ? Color.green : Color.red).opacity(0.15),
                                        in: Capsule()
                                    )
                            }
                            if let reason = override.reason, !reason.isEmpty {
                                Text(reason).font(.caption).foregroundStyle(.secondary)
                            }
                            if let expiresAt = override.expiresAt {
                                Text("Expires \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Button("Remove", role: .destructive) {
                            Task { await model.removeOverride(override) }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(isPresented: $showAddOverride) {
            NavigationStack {
                Form {
                    Picker("Feature", selection: $overrideFeatureCode) {
                        ForEach(model.featureDefinitions) { definition in
                            Text(definition.displayName).tag(definition.featureCode)
                        }
                    }
                    Toggle("Grant access", isOn: $overrideEnabled)
                    TextField("Reason", text: $overrideReason)
                }
                .navigationTitle("New Override")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                await model.setOverride(
                                    featureCode: overrideFeatureCode,
                                    isEnabled: overrideEnabled,
                                    reason: overrideReason.isEmpty ? nil : overrideReason,
                                    expiresAt: nil
                                )
                            }
                            showAddOverride = false
                        }
                        .disabled(overrideFeatureCode.isEmpty)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAddOverride = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}
#endif
