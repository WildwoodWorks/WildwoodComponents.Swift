#if os(iOS)
// The six SubscriptionAdmin sub-panels — parity with SubscriptionStatusPanel,
// TierPlansPanel, FeaturesPanel, AddOnsPanel, UsageLimitsPanel, OverridesPanel.

import SwiftUI
import WildwoodCore

// MARK: - Status

public struct SubscriptionStatusPanel: View {
    @Bindable var model: WildwoodSubscriptionAdminModel

    // Statuses from which the user can still cancel. Excluding Trialing/
    // PastDue locked those subscribers out of cancelling entirely; Pending*
    // changes are cancelled via the Plans panel.
    private static let cancellableStatuses: Set<String> = ["Active", "Trialing", "PastDue"]

    public init(model: WildwoodSubscriptionAdminModel) {
        self.model = model
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
                    detailRow("Trial ends", subscription.trialEndDate)
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

                if !subscription.isFreeTier, Self.cancellableStatuses.contains(subscription.status) {
                    Button("Cancel Subscription", role: .destructive) {
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
    let onPaymentRequired: ((AppTierModel, AppTierPricingModel?) async -> String?)?

    @State private var selectedPricingByTier: [String: String] = [:]
    @State private var pendingChange: (tier: AppTierModel, pricing: AppTierPricingModel?)?

    public init(
        model: WildwoodSubscriptionAdminModel,
        onPaymentRequired: ((AppTierModel, AppTierPricingModel?) async -> String?)? = nil
    ) {
        self.model = model
        self.onPaymentRequired = onPaymentRequired
    }

    public var body: some View {
        VStack(spacing: 16) {
            ForEach(model.tiers) { tier in
                TierCard(
                    tier: tier,
                    selectedPricing: selectedPricing(for: tier),
                    isCurrentTier: tier.id == model.subscription?.appTierId,
                    onSelectPricing: { pricing in
                        selectedPricingByTier[tier.id] = pricing.id
                    },
                    onSubscribe: { tier, pricing in
                        pendingChange = (tier, pricing)
                        Task { await model.previewChange(to: tier, pricing: pricing) }
                    }
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { model.tierChangePreview != nil },
            set: { if !$0 { model.clearPreview() } }
        )) {
            if let preview = model.tierChangePreview, let pending = pendingChange {
                TierChangeConfirmationSheet(preview: preview, tierName: pending.tier.name) { immediate in
                    Task {
                        var transactionId: String?
                        if preview.paymentRequired, !preview.paymentBypassAllowed, let onPaymentRequired {
                            transactionId = await onPaymentRequired(pending.tier, pending.pricing)
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
                } onCancel: {
                    model.clearPreview()
                }
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
                if let prorated = preview.proratedChargeToday, prorated > 0 {
                    row("Charged today", formatted(prorated))
                }
                if let credit = preview.creditAmount, credit > 0 {
                    row("Credit applied", formatted(credit))
                }
                if let nextAmount = preview.nextBillingAmount, let nextDate = preview.nextBillingDate {
                    row("Next billing", "\(formatted(nextAmount)) on \(nextDate.formatted(date: .abbreviated, time: .omitted))")
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
                }
                if preview.allowScheduledChange {
                    Button {
                        onConfirm(false)
                    } label: {
                        Text("Change at Period End").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button("Cancel") { onCancel() }
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
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

    private func formatted(_ amount: Double?) -> String {
        (amount ?? 0).formatted(.currency(code: preview.currency))
    }
}

// MARK: - Features

public struct FeaturesPanel: View {
    @Bindable var model: WildwoodSubscriptionAdminModel

    public init(model: WildwoodSubscriptionAdminModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.featureDefinitions.isEmpty, model.features.isEmpty {
                ContentUnavailableView("No features defined", systemImage: "switch.2")
            } else {
                ForEach(definitions) { definition in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(definition.displayName).font(.subheadline.weight(.medium))
                            if !definition.description.isEmpty {
                                Text(definition.description).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        let hasAccess = model.features[definition.featureCode] ?? false
                        Image(systemName: hasAccess ? "checkmark.circle.fill" : "lock.fill")
                            .foregroundStyle(hasAccess ? .green : .secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
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

public struct AddOnsPanel: View {
    @Bindable var model: WildwoodSubscriptionAdminModel

    public init(model: WildwoodSubscriptionAdminModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.addOnSubscriptions.isEmpty {
                Text("Active Add-Ons").font(.headline)
                ForEach(model.addOnSubscriptions) { sub in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(sub.addOnName).font(.subheadline.weight(.medium))
                                if sub.isBundled {
                                    Text("Bundled")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.blue.opacity(0.15), in: Capsule())
                                }
                            }
                            Text(sub.status).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !sub.isBundled {
                            Button("Cancel", role: .destructive) {
                                Task { await model.cancelAddOn(sub) }
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            let active = Set(model.addOnSubscriptions.map(\.appTierAddOnId))
            let available = model.availableAddOns.filter { !active.contains($0.id) }
            if !available.isEmpty {
                Text("Available Add-Ons").font(.headline)
                ForEach(available) { addOn in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(addOn.name).font(.subheadline.weight(.medium))
                            Spacer()
                            if let pricing = addOn.pricingOptions.first(where: \.isDefault) ?? addOn.pricingOptions.first {
                                Text("\(pricing.price.formatted(.currency(code: "USD"))) / \(pricing.billingFrequency)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !addOn.description.isEmpty {
                            Text(addOn.description).font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Add") {
                            let pricing = addOn.pricingOptions.first(where: \.isDefault) ?? addOn.pricingOptions.first
                            Task { await model.subscribeToAddOn(addOn, pricing: pricing) }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                    .padding()
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                }
            }

            if model.addOnSubscriptions.isEmpty, model.availableAddOns.isEmpty {
                ContentUnavailableView("No add-ons", systemImage: "puzzlepiece.extension")
            }
        }
    }
}

// MARK: - Usage limits

public struct UsageLimitsPanel: View {
    @Bindable var model: WildwoodSubscriptionAdminModel
    @Environment(\.wildwoodTheme) private var theme

    @State private var editingLimit: AppTierLimitStatusModel?
    @State private var newMaxValue = ""

    public init(model: WildwoodSubscriptionAdminModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.limitStatuses.isEmpty {
                ContentUnavailableView("No usage limits", systemImage: "gauge")
            } else {
                ForEach(model.limitStatuses) { status in
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
