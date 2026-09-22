#if os(iOS)
// What a plan change says about itself while it is neither waiting on the customer nor finished.
//
// Three things, and all of them matter to somebody holding a card: the bank is being asked (or the
// server is still applying a change that HAS been paid for), a failure with the way back, and —
// the one the web does not need — a change that needs a card the SURFACE cannot collect. A surface
// that mounts the built-in payment sheet (the manage view, ``SubscriptionAdminComponent``) collects
// it there and this notice says nothing about the card step; one that does not would otherwise park
// in `collectingPayment` forever, so it is told where the purchase can be finished instead.
//
// Which of the two applies is ``ManageViewRules/planChangeCardSource(step:hasHostHandler:paymentRequest:collectsPaymentInApp:)``,
// so the notice and the surface that mounts the sheet cannot disagree about who is taking the card.
//
// A failed change is never silent: a customer whose card was declined mid-upgrade would otherwise
// be left looking at the plan they still have.

import SwiftUI
import WildwoodCore
import WildwoodTestIDs

public struct PlanChangeNoticeView: View {
    @Environment(\.wildwoodTheme) private var theme

    /// The change in flight, owned by the surface that renders this.
    let flow: WildwoodPlanChangeModel
    let labels: RegistrationSubscriptionLabels
    /// The surface mounts the built-in card sheet, so the notice stays out of the card step.
    let collectsPaymentInApp: Bool

    public init(
        flow: WildwoodPlanChangeModel,
        labels: RegistrationSubscriptionLabels = .defaults,
        collectsPaymentInApp: Bool = true
    ) {
        self.flow = flow
        self.labels = labels
        self.collectsPaymentInApp = collectsPaymentInApp
    }

    public var body: some View {
        let content: PlanChangeNoticeContent = ManageViewRules.planChangeNoticeContent(
            step: flow.step,
            paymentRequest: flow.paymentRequest,
            error: flow.error,
            canRetry: flow.canRetry,
            labels: labels,
            collectsPaymentInApp: collectsPaymentInApp
        )

        switch content.kind {
        case .none:
            EmptyView()
        case .progress:
            progress(content)
        case .payment:
            alert(content, danger: false)
        case .failed:
            alert(content, danger: true)
        }
    }

    // MARK: - Pieces

    private func progress(_ content: PlanChangeNoticeContent) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(content.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier(RegistrationSubscriptionTestID.planChangeNotice)
    }

    private func alert(_ content: PlanChangeNoticeContent, danger: Bool) -> some View {
        let tint: Color = danger ? theme.danger : theme.accent

        return VStack(alignment: .leading, spacing: 8) {
            if let title = content.title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            if !content.message.isEmpty {
                Text(content.message)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 16) {
                if content.canRetry {
                    Button(labels.tryAgain) { flow.retry() }
                        .buttonStyle(.bordered)
                        .font(.footnote)
                        .accessibilityIdentifier(RegistrationSubscriptionTestID.planChangeRetry)
                }
                if content.canDismiss {
                    Button(labels.cancel) { flow.reset() }
                        .font(.footnote)
                        .accessibilityIdentifier(RegistrationSubscriptionTestID.planChangeDismiss)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(RegistrationSubscriptionTestID.planChangeNotice)
    }
}
#endif
