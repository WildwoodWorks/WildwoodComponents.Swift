#if os(iOS)
// What the packs in the basket cost, as the server just quoted them.
//
// Every figure is off the quote: its lines, its currency, its per-line trial and its total due
// today. Nothing is added up here — the server owns the arithmetic, because it is the one that
// will charge the card, and a total this view computed could disagree with the one that is
// actually taken.
//
// A trial line appears only where the quote says THIS account is still eligible for one
// (`trialEligible`): one trial per account, and the server is the only thing that knows.

import SwiftUI
import WildwoodCore
import WildwoodTestIDs

public struct OrderSummaryView: View {
    @Environment(\.wildwoodTheme) private var theme

    /// A successful quote.
    let quote: AddOnCheckoutQuoteModel
    let labels: RegistrationSubscriptionSignupLabels

    public init(quote: AddOnCheckoutQuoteModel, labels: RegistrationSubscriptionSignupLabels = .defaults) {
        self.quote = quote
        self.labels = labels
    }

    public var body: some View {
        let savedCard: String? = SignupViewRules.savedCardLine(quote.savedCard, labels: labels)

        VStack(alignment: .leading, spacing: 8) {
            Text(labels.orderSummary)
                .font(.headline)

            ForEach(quote.lines, id: \.addOnId) { line in
                lineRow(line)
            }

            Divider()

            HStack {
                Text(labels.dueToday)
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(WildwoodMoney.format(quote.totalDueToday, currency: quote.currency))
                    .font(.headline)
                    .foregroundStyle(theme.accent)
            }

            if let savedCard {
                Text(savedCard)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(RegistrationSubscriptionTestID.orderSummary)
    }

    // MARK: - Pieces

    @ViewBuilder private func lineRow(_ line: AddOnCheckoutQuoteLineModel) -> some View {
        let trial: String = line.trialEligible ? WildwoodTrial.label(days: line.trialDays) : ""

        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(line.name)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(WildwoodMoney.format(line.price, currency: quote.currency))
                    .font(.subheadline.weight(.semibold))
                if !trial.isEmpty {
                    Text(trial)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.success)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(RegistrationSubscriptionTestID.pack(line.addOnId))
    }
}
#endif
