#if os(iOS)
// The pack grid: what an app sells alongside a plan.
//
// The grouping rules are the web's, which had them first and got them right: an EMPTY group is
// dropped rather than rendered as a heading with nothing under it, and a pack whose category
// matches no group is NOT dropped — it lands in a trailing catch-all, because a pack the company
// sells and has priced going silently missing from the screen that sells it is the one failure this
// must not have. ``PricingViewRules/groupAddOns(_:groups:morePacksTitle:)`` holds that rule, so it
// can be tested without a simulator.
//
// Every price is the live one off the catalog. A pack the operator has defined but not priced says
// so instead of implying it is free.
//
// The third affordance has no web counterpart: an App-Store-exclusive app LISTS its packs and
// offers none of them, because pack checkout is a card purchase and Apple's in-app-purchase product
// mapping is tier-only (Decision 5 / Appendix C DD-4).

import SwiftUI
import WildwoodCore

public struct PackGridView: View {
    @Environment(\.wildwoodTheme) private var theme

    /// Active packs in catalog order.
    let addOns: [AppTierAddOnModel]
    /// The currency every price in the grid is quoted in.
    let currency: String
    /// Headings to file packs under. Omitted, the packs render as one flat grid.
    let groups: [WildwoodAddOnGroup]?
    /// Host copy for a pack.
    let describeAddOn: ((AppTierAddOnModel) -> WildwoodAddOnPresentation?)?
    let affordance: PricingPackAffordance
    /// The currently ticked pack ids (multi-select only).
    let selectedIds: [String]
    let labels: RegistrationSubscriptionPricingLabels
    /// Tick or untick one pack (multi-select only).
    let onToggle: (String) -> Void
    /// Take one pack straight through (single-select only).
    let onChoose: (AppTierAddOnModel) -> Void
    /// Continue with everything ticked (multi-select only).
    let onContinue: () -> Void

    public init(
        addOns: [AppTierAddOnModel],
        currency: String,
        groups: [WildwoodAddOnGroup]? = nil,
        describeAddOn: ((AppTierAddOnModel) -> WildwoodAddOnPresentation?)? = nil,
        affordance: PricingPackAffordance,
        selectedIds: [String] = [],
        labels: RegistrationSubscriptionPricingLabels = .defaults,
        onToggle: @escaping (String) -> Void,
        onChoose: @escaping (AppTierAddOnModel) -> Void,
        onContinue: @escaping () -> Void
    ) {
        self.addOns = addOns
        self.currency = currency
        self.groups = groups
        self.describeAddOn = describeAddOn
        self.affordance = affordance
        self.selectedIds = selectedIds
        self.labels = labels
        self.onToggle = onToggle
        self.onChoose = onChoose
        self.onContinue = onContinue
    }

    public var body: some View {
        let grouped: [PricingPackGroup] = PricingViewRules.groupAddOns(
            addOns,
            groups: groups,
            morePacksTitle: labels.morePacks
        )

        VStack(alignment: .leading, spacing: 16) {
            if !grouped.isEmpty {
                ForEach(grouped) { group in
                    groupSection(group)
                }
                if affordance == .multi {
                    continueButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pieces

    @ViewBuilder private func groupSection(_ group: PricingPackGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = group.title, !title.isEmpty {
                Text(title).font(.headline)
            }
            if let blurb = group.blurb, !blurb.isEmpty {
                Text(blurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(group.addOns) { addOn in
                packCard(addOn)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(RegistrationSubscriptionTestID.group(group.id))
    }

    @ViewBuilder private func packCard(_ addOn: AppTierAddOnModel) -> some View {
        let isSelected: Bool = selectedIds.contains(addOn.id)
        let selectLabel: String = PricingViewRules.packSelectLabel(name: addOn.name, labels: labels)

        switch affordance {
        case .multi:
            // The chrome goes INSIDE the label so the whole card is the tap target, not just the
            // text inside its padding.
            Button {
                onToggle(addOn.id)
            } label: {
                packBody(addOn)
                    .modifier(PackCardChrome(isSelected: isSelected, accent: theme.accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selectLabel)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
            .accessibilityIdentifier(RegistrationSubscriptionTestID.pack(addOn.id))

        case .single:
            VStack(alignment: .leading, spacing: 10) {
                packBody(addOn)
                Button(labels.packSelect) {
                    onChoose(addOn)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(selectLabel)
            }
            .modifier(PackCardChrome(isSelected: false, accent: theme.accent))
            .accessibilityIdentifier(RegistrationSubscriptionTestID.pack(addOn.id))

        case .informational:
            packBody(addOn)
                .modifier(PackCardChrome(isSelected: false, accent: theme.accent))
                .accessibilityIdentifier(RegistrationSubscriptionTestID.pack(addOn.id))
        }
    }

    private func packBody(_ addOn: AppTierAddOnModel) -> some View {
        let presentation: WildwoodAddOnPresentation? = describeAddOn?(addOn)
        let blurb: String = presentation?.blurb ?? addOn.description
        let pricing: AppTierAddOnPricingModel? = Catalog.resolvePriceOption(addOn)
        let trial: String = WildwoodTrial.label(days: pricing?.trialDays)
        let priceText: String = PricingViewRules.packPriceText(addOn, currency: currency, labels: labels)
        let priceFont: Font = pricing == nil ? Font.caption : Font.subheadline.weight(.bold)
        let priceColor: Color = pricing == nil ? Color.secondary : theme.accent

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let symbol = presentation?.systemImage, !symbol.isEmpty {
                    Image(systemName: symbol).font(.subheadline)
                }
                Text(addOn.name).font(.subheadline.weight(.bold))
            }

            if !blurb.isEmpty {
                Text(blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let meter = presentation?.meter, !meter.isEmpty {
                Text(meter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(priceText)
                .font(priceFont)
                .foregroundStyle(priceColor)

            if !trial.isEmpty {
                Text(trial)
                    .font(.caption)
                    .foregroundStyle(theme.success)
            }

            ForEach(addOn.features) { feature in
                Text(feature.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var continueButton: some View {
        let count: Int = selectedIds.count
        let title: String = PricingViewRules.continueWithPacksLabel(count: count, labels: labels)

        return Button(title) {
            onContinue()
        }
        .buttonStyle(.borderedProminent)
        .disabled(count == 0)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(RegistrationSubscriptionTestID.packsContinue)
    }
}

/// The card chrome every pack shares, so the three affordances differ only in what they offer.
private struct PackCardChrome: ViewModifier {
    let isSelected: Bool
    let accent: Color

    func body(content: Content) -> some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(accent, lineWidth: 2)
                }
            }
    }
}
#endif
