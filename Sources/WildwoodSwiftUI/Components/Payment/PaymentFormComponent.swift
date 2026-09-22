#if os(iOS)
// Single-provider payment form — parity with PaymentFormComponent (a dedicated
// form for one pre-selected provider and fixed amount). Routes through the same
// processor-agnostic pipeline as PaymentComponent.

import SwiftUI
import WildwoodCore

public struct PaymentFormComponent: View {
    @Environment(\.wildwoodClient) private var client
    @Environment(\.openURL) private var openURL

    private let providerId: String
    private let appId: String?
    private let amount: Double
    private let currency: String?
    private let descriptionText: String?
    private let customerId: String?
    /// The pricing MODEL id the subscription attaches to. Omitting it is what turned a plan
    /// purchase into a one-off charge with no renewal and no trial (JS 05dd7cb).
    private let pricingModelId: String?
    private let billingFrequency: String?
    private let isSubscription: Bool
    /// Free-trial days the plan advertises, for the button copy.
    private let trialDays: Int?
    private let onPaymentSuccess: ((InitiatePaymentResponse) -> Void)?
    private let onPaymentError: ((String) -> Void)?

    @State private var cardholderName = ""
    @State private var email = ""
    @State private var isProcessing = false
    @State private var errorMessage = ""
    @State private var pendingPayment: InitiatePaymentResponse?

    public init(
        providerId: String,
        appId: String? = nil,
        amount: Double,
        currency: String? = nil,
        description: String? = nil,
        customerId: String? = nil,
        pricingModelId: String? = nil,
        billingFrequency: String? = nil,
        isSubscription: Bool = false,
        trialDays: Int? = nil,
        onPaymentSuccess: ((InitiatePaymentResponse) -> Void)? = nil,
        onPaymentError: ((String) -> Void)? = nil
    ) {
        self.providerId = providerId
        self.appId = appId
        self.amount = amount
        self.currency = currency
        self.descriptionText = description
        self.customerId = customerId
        self.pricingModelId = pricingModelId
        self.billingFrequency = billingFrequency
        self.isSubscription = isSubscription
        self.trialDays = trialDays
        self.onPaymentSuccess = onPaymentSuccess
        self.onPaymentError = onPaymentError
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !errorMessage.isEmpty {
                ErrorBannerView(message: errorMessage) { errorMessage = "" }
            }

            HStack {
                Text(descriptionText ?? "Payment")
                    .font(.headline)
                Spacer()
                Text(amount, format: .currency(code: currency ?? "USD"))
                    .font(.headline)
            }

            TextField("Cardholder name", text: $cardholderName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)
            TextField("Email for receipt", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            // Card details are entered on the provider's secure checkout page —
            // no raw card fields in-app (PCI scope stays with the processor).
            Button {
                Task { await pay() }
            } label: {
                if isProcessing {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text(checkoutButtonLabel).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessing)

            if WildwoodPaymentModel.hasTrialOffer(trialDays: trialDays) {
                Text(WildwoodPaymentModel.trialChargeNote(amount: amount, currency: currency))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let pending = pendingPayment {
                VStack(spacing: 8) {
                    Text("Complete the payment in your browser, then return here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await checkStatus(pending) }
                    } label: {
                        if isProcessing {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("I've completed the payment").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing)
                }
            }
        }
    }

    /// A trial is started, not bought — the same wording the payment screen uses.
    private var checkoutButtonLabel: String {
        if WildwoodPaymentModel.hasTrialOffer(trialDays: trialDays) {
            return "Start \(WildwoodTrial.label(days: trialDays))"
        }
        return "Continue to Secure Checkout"
    }

    private func checkStatus(_ pending: InitiatePaymentResponse) async {
        guard let client, let intentId = pending.paymentIntentId else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            // Same identifier caveat as PaymentComponent.checkRedirectPaymentStatus:
            // verify the status endpoint resolves provider intent ids.
            let result = try await client.payment.getPaymentStatus(transactionId: intentId)
            if result.success {
                pendingPayment = nil
                onPaymentSuccess?(pending)
            } else {
                errorMessage = result.errorMessage ?? "Payment is not complete yet."
            }
        } catch {
            errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
        }
    }

    private func pay() async {
        guard let client = requireClient(client, component: "PaymentFormComponent") else { return }
        guard let resolvedAppId = appId ?? client.config.appId else {
            errorMessage = "PaymentFormComponent requires an appId."
            return
        }
        errorMessage = ""
        isProcessing = true
        defer { isProcessing = false }
        do {
            var metadata: [String: String] = [:]
            if !cardholderName.isEmpty { metadata["cardholderName"] = cardholderName }

            let initiation = try await client.payment.initiatePayment(
                InitiatePaymentRequest(
                    providerId: providerId,
                    appId: resolvedAppId,
                    amount: amount,
                    currency: currency,
                    description: descriptionText,
                    customerId: customerId,
                    customerEmail: email.isEmpty ? nil : email,
                    pricingModelId: pricingModelId,
                    isSubscription: isSubscription ? true : nil,
                    billingFrequency: billingFrequency,
                    metadata: metadata.isEmpty ? nil : metadata
                )
            )

            guard initiation.success else {
                let message = initiation.errorMessage ?? "Payment could not be started."
                errorMessage = message
                onPaymentError?(message)
                return
            }

            if let urlString = initiation.redirectUrl ?? initiation.approvalUrl, let url = URL(string: urlString) {
                // Redirect checkout: success is reported only after the user
                // returns and the completion check confirms (JS parity — the
                // web component navigates away instead of signaling success).
                pendingPayment = initiation
                openURL(url)
            } else {
                onPaymentSuccess?(initiation)
            }
        } catch {
            let message = (error as? WildwoodError)?.message ?? error.localizedDescription
            errorMessage = message
            onPaymentError?(message)
        }
    }
}
#endif
