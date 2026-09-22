#if os(iOS)
// What a registration token sets up, in the words the server used.
//
// Everything here comes from the token's detailed validation — the tier, the pricing option, the
// packs and the extra features, with the display names the server sent and the ids as the
// fallback. NOTHING is priced: the visitor is not paying for any of it, and a price beside a
// granted plan would say they were. That rule is why this is not the plan summary card with a
// different heading.
//
// Which steps it appears above is not this view's business:
// ``SignupViewRules/showsTokenPlanSummary(body:grant:)`` answers that once, for every body, so no
// step can quietly drop it.

import SwiftUI
import WildwoodCore
import WildwoodTestIDs

public struct TokenPlanSummaryView: View {
    @Environment(\.wildwoodTheme) private var theme

    /// The grant for THIS app, as `getRegistrationTokenDetails` reported it.
    let grant: RegistrationTokenAppGrant
    let labels: RegistrationSubscriptionSignupLabels

    public init(grant: RegistrationTokenAppGrant, labels: RegistrationSubscriptionSignupLabels = .defaults) {
        self.grant = grant
        self.labels = labels
    }

    public var body: some View {
        let packs: [SignupGrantEntry] = SignupViewRules.grantEntries(
            ids: grant.addOnIds,
            names: grant.addOnNames
        )
        let features: [SignupGrantEntry] = SignupViewRules.grantEntries(
            ids: grant.featureCodes,
            names: grant.featureNames
        )

        VStack(alignment: .leading, spacing: 8) {
            Text(labels.tokenPlanIncludes)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(theme.accent)

            Text(SignupViewRules.grantTierText(grant))
                .font(.headline)

            if !packs.isEmpty {
                group(title: labels.tokenPlanPacks, entries: packs, systemImage: "shippingbox")
            }
            if !features.isEmpty {
                group(title: labels.tokenPlanFeatures, entries: features, systemImage: "sparkles")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(RegistrationSubscriptionTestID.tokenPlanSummary)
    }

    // MARK: - Pieces

    @ViewBuilder private func group(
        title: String,
        entries: [SignupGrantEntry],
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(entries, id: \.id) { entry in
                Label(entry.name, systemImage: systemImage)
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
