#if os(iOS)
// The signup's pack step: everything the app sells that the visitor does not already have, ticked
// as many at a time as they like, then one Continue.
//
// The grid itself is ``PackGridView`` — the same one the pricing view renders, grouping rules,
// prices and cap included — so a pack reads identically whether it is met before signing up or
// during. What this view adds is the step's own frame: the heading, and the two ways out the web
// offers beside it ("Back", "Skip for now").
//
// NOTE for the manage view: the web has a second `PackPicker`, a MODAL that also runs the checkout
// and shows the outcomes. That one belongs to the manage view and is a different thing; it can
// compose this grid, but it is not this view.
//
// A step with nothing to offer is never rendered: an App-Store-exclusive app cannot buy a pack at
// all (Decision 5), and the driver skips the step outright rather than showing a grid whose
// Continue would go nowhere.

import SwiftUI
import WildwoodCore

public struct PackPickerView: View {
    /// The packs on offer — everything the app sells that a registration token did not grant.
    let addOns: [AppTierAddOnModel]
    /// The currency every price in the grid is quoted in.
    let currency: String
    /// The currently ticked pack ids.
    let selectedIds: [String]
    let labels: RegistrationSubscriptionSignupLabels
    /// The pricing slice, which is what the grid itself says ("Select", "Not yet available", ...).
    let pricingLabels: RegistrationSubscriptionPricingLabels
    /// Headings to file packs under.
    let groups: [WildwoodAddOnGroup]?
    /// Host marketing copy for one pack.
    let describeAddOn: ((AppTierAddOnModel) -> WildwoodAddOnPresentation?)?
    let onToggle: (String) -> Void
    let onContinue: () -> Void
    let onSkip: () -> Void
    /// Back to the registration form. Omitted, no back affordance is rendered.
    let onBack: (() -> Void)?

    public init(
        addOns: [AppTierAddOnModel],
        currency: String,
        selectedIds: [String] = [],
        labels: RegistrationSubscriptionSignupLabels = .defaults,
        pricingLabels: RegistrationSubscriptionPricingLabels = .defaults,
        groups: [WildwoodAddOnGroup]? = nil,
        describeAddOn: ((AppTierAddOnModel) -> WildwoodAddOnPresentation?)? = nil,
        onToggle: @escaping (String) -> Void,
        onContinue: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        onBack: (() -> Void)? = nil
    ) {
        self.addOns = addOns
        self.currency = currency
        self.selectedIds = selectedIds
        self.labels = labels
        self.pricingLabels = pricingLabels
        self.groups = groups
        self.describeAddOn = describeAddOn
        self.onToggle = onToggle
        self.onContinue = onContinue
        self.onSkip = onSkip
        self.onBack = onBack
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(labels.choosePacks)
                .font(.title3.weight(.semibold))

            PackGridView(
                addOns: addOns,
                currency: currency,
                groups: groups,
                describeAddOn: describeAddOn,
                affordance: .multi,
                selectedIds: selectedIds,
                labels: pricingLabels,
                onToggle: onToggle,
                // The grid's single-select call to action never fires in multi mode; wiring it to
                // Continue means a future grid that does fire it still does the right thing.
                onChoose: { _ in onContinue() },
                onContinue: onContinue
            )

            HStack {
                if let onBack {
                    Button(labels.back) { onBack() }
                        .font(.footnote)
                }
                Spacer()
                Button(labels.skipForNow) { onSkip() }
                    .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
