#if os(iOS)
// Buying the packs a new account asked for.
//
// The driving — one quote, at most one card, one purchase, then any pack the bank wants
// authenticated, one at a time, each claimed by the machine's step token — is
// ``WildwoodPackCheckoutModel``, which the signup driver owns and hands here. This view renders
// what that model is doing and offers the two ways out of a failure.
//
// The card is what differs from the web. The web mounts Stripe Elements and confirms the
// SetupIntent in its own form; this package ships no payment SDK, so either the host wired a
// ``WildwoodPaymentActionHandler`` that can confirm a SetupIntent — and the driver collects the
// card once, through it, for a basket of any size — or nothing here can take a card. In that last
// case no SetupIntent is asked for at all (a client secret nothing can confirm is worse than none)
// and the packs are reported as not bought, with the reason.
//
// Which is why a basket on the `finishOnWeb` branch is offered no "Try Again": it would fail again
// for exactly the same reason, and the only honest way on is to finish the signup without the
// packs. ``SignupViewRules/packCheckoutCanRetry(_:)`` owns that.

import SwiftUI
import WildwoodCore
import WildwoodTestIDs

public struct PackCheckoutView: View {
    @Environment(\.wildwoodTheme) private var theme

    /// The checkout in flight, owned by the signup driver.
    let model: WildwoodPackCheckoutModel
    let labels: RegistrationSubscriptionSignupLabels

    public init(model: WildwoodPackCheckoutModel, labels: RegistrationSubscriptionSignupLabels = .defaults) {
        self.model = model
        self.labels = labels
    }

    public var body: some View {
        let step: PackCheckoutStep = model.step
        let quote: AddOnCheckoutQuoteModel? = model.quote
        let branch: PackCheckoutCardBranch = SignupViewRules.packCheckoutCardBranch(
            requiresPaymentMethod: quote?.requiresPaymentMethod == true,
            canConfirmCardSetup: model.canCollectCard
        )

        VStack(alignment: .leading, spacing: 12) {
            if let quote, quote.success {
                OrderSummaryView(quote: quote, labels: labels)
            }

            if SignupViewRules.packCheckoutWorking(step: step, busy: model.busy) {
                statusLine(step)
            }

            if step == .failed {
                failedPanel(branch)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(RegistrationSubscriptionTestID.packCheckout)
    }

    // MARK: - Pieces

    @ViewBuilder private func statusLine(_ step: PackCheckoutStep) -> some View {
        let text: String = SignupViewRules.packCheckoutStatusText(
            step: step,
            packName: model.authenticatingName,
            labels: labels
        )

        HStack(spacing: 8) {
            ProgressView()
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder private func failedPanel(_ branch: PackCheckoutCardBranch) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ErrorBannerView(message: model.error ?? labels.packsUnavailable)

            HStack(spacing: 16) {
                if SignupViewRules.packCheckoutCanRetry(branch) {
                    Button(labels.tryAgain) { model.retry() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(RegistrationSubscriptionTestID.packCheckoutRetry)
                }
                Button(labels.skipForNow) { model.skip() }
                    .font(.footnote)
                    .accessibilityIdentifier(RegistrationSubscriptionTestID.packCheckoutSkip)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Kept so a failure panel and a working panel cannot be told apart only by their words.
        .background(theme.danger.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}
#endif
