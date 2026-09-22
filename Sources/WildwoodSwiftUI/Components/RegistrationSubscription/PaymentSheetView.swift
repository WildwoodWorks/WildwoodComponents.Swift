#if os(iOS)
// The card an upgrade needs, in the component's own sheet — the native twin of
// @wildwood/react's registrationSubscription/parts/PaymentModal.
//
// Every app on the platform hand-built this: a sheet, a ``PaymentComponent`` inside it, and an
// answer carrying the transaction id. They all got the same three things right and one of them
// wrong at least once, so it lives here now:
//
//  · It answers EXACTLY once. A payment path that calls back twice, or a close after a success,
//    cannot cancel a charge that already went through.
//  · A refused card is not the end of it: the sheet stays put with ``PaymentComponent``'s own
//    message, so the customer can fix the card and try again without losing the priced change
//    behind it.
//  · A payment that succeeded with no id to complete the change with is REPORTED rather than
//    passed off as a cancel — money moved, and somebody has to know.
//
// What differs from the web is the card itself, and it is the same difference everywhere in this
// package: there is no Stripe Elements here. ``PaymentComponent`` asks the server which processor
// this device must use and completes the payment with whatever it has — StoreKit, the provider's
// own page, or a server-owned completion — so this sheet is worth mounting with or without a
// ``WildwoodPaymentActionHandler``.
//
// The transaction is attributed to the signed-in user afterwards, best effort and detached: the
// change must not wait on it, and `linkTransactionToUser` answers false rather than throwing.

import SwiftUI
import WildwoodCore
import WildwoodTestIDs

public struct PaymentSheetView: View {
    /// Resolved by the surface that presents this, rather than read from the environment: a sheet
    /// is its own presentation, and the change it is paying for must not depend on how SwiftUI
    /// chose to propagate values into it.
    let client: WildwoodClient
    let appId: String?
    /// What the plan change needs paying for: the plan, its pricing MODEL, the plan's price and
    /// its trial — never the prorated charge a preview quoted for today.
    let request: WildwoodPaymentRequiredArgs
    let labels: RegistrationSubscriptionLabels
    let paymentActionHandler: (any WildwoodPaymentActionHandler)?
    /// Called once: the transaction id to complete the change with, or nil if nothing was paid.
    let onSettled: (String?) -> Void
    let onError: ((RegistrationSubscriptionError) -> Void)?

    @State private var settled: Bool = false

    public init(
        client: WildwoodClient,
        appId: String? = nil,
        request: WildwoodPaymentRequiredArgs,
        labels: RegistrationSubscriptionLabels = .defaults,
        paymentActionHandler: (any WildwoodPaymentActionHandler)? = nil,
        onSettled: @escaping (String?) -> Void,
        onError: ((RegistrationSubscriptionError) -> Void)? = nil
    ) {
        self.client = client
        self.appId = appId
        self.request = request
        self.labels = labels
        self.paymentActionHandler = paymentActionHandler
        self.onSettled = onSettled
        self.onError = onError
    }

    public var body: some View {
        let title: String = ManageViewRules.paymentSheetTitle(labels: labels, tierName: request.tier.name)

        NavigationStack {
            ScrollView {
                PaymentComponent(
                    args: request,
                    appId: appId,
                    description: title,
                    customerId: client.session.userId,
                    customerEmail: client.session.userEmail,
                    paymentActionHandler: paymentActionHandler,
                    onPaymentSuccess: { result in succeeded(result) },
                    onPaymentFailure: { _ in
                        // Deliberate: PaymentComponent shows its own message and stays mounted for
                        // a retry on the same intent.
                    }
                )
                .padding(16)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(labels.closePayment) { settle(nil) }
                }
            }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier(RegistrationSubscriptionTestID.paymentModal)
    }

    // MARK: - Settling

    private func settle(_ paymentTransactionId: String?) {
        if settled { return }
        settled = true
        onSettled(paymentTransactionId)
    }

    private func succeeded(_ result: PaymentCompletionResult) {
        let paymentTransactionId: String? = firstNonEmpty(result.transactionId, result.paymentIntentId)
        guard let paymentTransactionId else {
            // The charge went through and nothing came back to finish the change with. Saying
            // "cancelled" here would leave a customer paid up on the plan they already had.
            onError?(
                RegistrationSubscriptionError(
                    code: RegistrationSubscriptionErrorCodes.paymentUnconfirmed,
                    message: labels.paymentUnconfirmed
                )
            )
            settle(nil)
            return
        }

        // Complete the change first: attribution must not gate it.
        settle(paymentTransactionId)

        guard let userId = client.session.userId, !userId.isEmpty else { return }
        // The server looks a transaction up by the provider's own id when there is one.
        let externalId: String = firstNonEmpty(result.paymentIntentId, paymentTransactionId) ?? paymentTransactionId
        Task {
            _ = await client.payment.linkTransactionToUser(
                externalTransactionId: externalId,
                userId: userId
            )
        }
    }

    private func firstNonEmpty(_ first: String?, _ second: String?) -> String? {
        if let first, !first.isEmpty { return first }
        if let second, !second.isEmpty { return second }
        return nil
    }
}

// MARK: - The two sheets a plan change puts over its surface

extension View {
    /// The confirmation and the card sheet a plan change needs, applied ONCE for every surface
    /// that runs one.
    ///
    /// The manage view and ``SubscriptionAdminComponent`` both change plans, and they used to do
    /// it differently — one with a confirmation and a host callback, the other with neither a
    /// 3-D Secure completion nor a sheet of its own. Sharing this modifier is what stops them
    /// drifting again: a change confirmed in one is confirmed the same way in the other, and both
    /// take the card from the same two places in the same order.
    ///
    /// The setters are guarded on the step the sheet belongs to. SwiftUI dismisses a sheet when
    /// its binding reads false, and a dismissal that raced with the flow moving on would otherwise
    /// cancel a change that is already being posted.
    ///
    /// - Parameters:
    ///   - flow: the change in flight.
    ///   - client: resolved by the surface; the card sheet needs a session and the payment API.
    ///   - appId: the app the payment belongs to.
    ///   - labels: overridable copy.
    ///   - paymentActionHandler: the resolved seam, handed to ``PaymentComponent``.
    ///   - hasHostPaymentHandler: the host supplied its own `onPaymentRequired`, which wins over
    ///     the built-in sheet and whose answer is final.
    ///   - onError: told when a payment landed with nothing to complete the change with.
    @MainActor
    func wildwoodPlanChangeSheets(
        flow: WildwoodPlanChangeModel,
        client: WildwoodClient,
        appId: String?,
        labels: RegistrationSubscriptionLabels,
        paymentActionHandler: (any WildwoodPaymentActionHandler)?,
        hasHostPaymentHandler: Bool,
        onError: ((RegistrationSubscriptionError) -> Void)?
    ) -> some View {
        modifier(
            PlanChangeSheetsModifier(
                flow: flow,
                client: client,
                appId: appId,
                labels: labels,
                paymentActionHandler: paymentActionHandler,
                hasHostPaymentHandler: hasHostPaymentHandler,
                onError: onError
            )
        )
    }
}

struct PlanChangeSheetsModifier: ViewModifier {
    let flow: WildwoodPlanChangeModel
    let client: WildwoodClient
    let appId: String?
    let labels: RegistrationSubscriptionLabels
    let paymentActionHandler: (any WildwoodPaymentActionHandler)?
    let hasHostPaymentHandler: Bool
    let onError: ((RegistrationSubscriptionError) -> Void)?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: confirmPresented) { confirmSheet }
            .sheet(isPresented: paymentPresented) { paymentSheet }
    }

    // MARK: - Confirmation

    private var confirmPresented: Binding<Bool> {
        Binding(
            get: { flow.preview != nil },
            // Only a dismissal made WHILE the confirmation is the live step is the customer
            // backing out; anything else is the flow having moved on already.
            set: { if !$0 && flow.step == .confirm { flow.cancel() } }
        )
    }

    @ViewBuilder private var confirmSheet: some View {
        if let preview = flow.preview {
            TierChangeConfirmationSheet(
                preview: preview,
                tierName: flow.selectedTier?.name ?? preview.newTierName ?? "",
                // DD-4: a store-billed app is told who bills it instead of being quoted a
                // proration the store will not honour.
                storeBillingNotice: flow.storeBillingNotice,
                busy: flow.busy,
                onConfirm: { immediate in flow.confirm(immediate: immediate) },
                onCancel: { flow.cancel() }
            )
        }
    }

    // MARK: - The card

    private var cardSource: PlanChangeCardSource {
        ManageViewRules.planChangeCardSource(
            step: flow.step,
            hasHostHandler: hasHostPaymentHandler,
            paymentRequest: flow.paymentRequest,
            // This surface mounts the sheet, so the notice never has to speak for the card step.
            collectsPaymentInApp: true
        )
    }

    private var paymentPresented: Binding<Bool> {
        Binding(
            get: { cardSource == .builtIn },
            // Closing the built-in sheet returns to the CONFIRMATION with the priced change
            // intact — it is inside this flow, unlike a host's own sheet, whose dismissal
            // abandons the change.
            set: { if !$0 && flow.step == .collectingPayment { flow.providePayment(nil) } }
        )
    }

    @ViewBuilder private var paymentSheet: some View {
        if let request = flow.paymentRequest {
            PaymentSheetView(
                client: client,
                appId: appId,
                request: request,
                labels: labels,
                paymentActionHandler: paymentActionHandler,
                onSettled: { paymentTransactionId in flow.providePayment(paymentTransactionId) },
                onError: onError
            )
        }
    }
}
#endif
