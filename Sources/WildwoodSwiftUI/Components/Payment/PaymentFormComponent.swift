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
        onPaymentSuccess: ((InitiatePaymentResponse) -> Void)? = nil,
        onPaymentError: ((String) -> Void)? = nil
    ) {
        self.providerId = providerId
        self.appId = appId
        self.amount = amount
        self.currency = currency
        self.descriptionText = description
        self.customerId = customerId
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
                    Text("Continue to Secure Checkout").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessing)

            if pendingPayment != nil {
                Text("Complete the payment in your browser. Your receipt will be emailed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                pendingPayment = initiation
                openURL(url)
            }
            onPaymentSuccess?(initiation)
        } catch {
            let message = (error as? WildwoodError)?.message ?? error.localizedDescription
            errorMessage = message
            onPaymentError?(message)
        }
    }
}
#endif
