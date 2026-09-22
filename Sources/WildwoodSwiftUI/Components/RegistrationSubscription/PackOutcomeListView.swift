#if os(iOS)
// What became of each pack. One row per pack, including the ones that failed.
//
// A basket is not a transaction: one pack can fail while the rest run, so this never collapses the
// list into a single "done" — the customer is told, per pack, what they ended up with. The packs a
// registration token granted come first and say "Included", because nothing was charged for them.
// That ordering is the machine's (``SignupMachine`` builds the outcome), not this view's.

import SwiftUI
import WildwoodCore
import WildwoodTestIDs

public struct PackOutcomeListView: View {
    @Environment(\.wildwoodTheme) private var theme

    let packs: [SignupPackOutcome]
    let labels: RegistrationSubscriptionSignupLabels

    public init(packs: [SignupPackOutcome], labels: RegistrationSubscriptionSignupLabels = .defaults) {
        self.packs = packs
        self.labels = labels
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !packs.isEmpty {
                ForEach(packs, id: \.addOnId) { pack in
                    row(pack)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(RegistrationSubscriptionTestID.packOutcomes)
    }

    // MARK: - Pieces

    @ViewBuilder private func row(_ pack: SignupPackOutcome) -> some View {
        let failed: Bool = SignupViewRules.packOutcomeFailed(pack.status)
        let status: String = SignupViewRules.packStatusLabel(pack.status, labels: labels)
        let trialEnd: String = SignupViewRules.trialEndText(pack.trialEnd)
        let message: String = pack.errorMessage ?? ""

        VStack(alignment: .leading, spacing: 2) {
            Text(pack.name)
                .font(.subheadline.weight(.semibold))
            Text(status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(failed ? theme.danger : theme.success)
            if !trialEnd.isEmpty {
                Text(trialEnd)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(theme.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(RegistrationSubscriptionTestID.pack(pack.addOnId))
    }
}
#endif
