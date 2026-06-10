#if os(iOS)
// Payment component driven entirely by the backend's platform-filtered
// provider configuration — parity with PaymentComponent. The Wildwood config
// decides the processor: when requiresAppStorePayment (or the selected
// provider is AppleAppStore) the purchase runs through StoreKit 2 and is
// validated with the backend; other providers use the generic
// initiatePayment/confirmPayment flow with external web checkout.

import SwiftUI
import WildwoodCore

public struct PaymentComponent: View {
    @Environment(\.wildwoodClient) private var client
    @Environment(\.openURL) private var openURL

    private let appId: String?
    private let amount: Double
    private let currency: String?
    private let descriptionText: String?
    private let customerId: String?
    private let customerEmail: String?
    private let subscriptionId: String?
    private let isSubscription: Bool
    private let showAmount: Bool
    /// Force the App Store path during development/TestFlight (StoreKit sandbox).
    private let treatDevelopmentAsAppStore: Bool
    private let onPaymentSuccess: ((PaymentCompletionResult) -> Void)?
    private let onPaymentFailure: ((String) -> Void)?
    private let onCancel: (() -> Void)?

    @State private var isLoading = true
    @State private var isProcessing = false
    @State private var errorMessage = ""
    @State private var providerInfo: PlatformFilteredProvidersDto?
    @State private var selectedProviderId: String?
    @State private var pendingRedirectPayment: InitiatePaymentResponse?
    @State private var purchaseManager: StoreKitPurchaseManager?

    public init(
        appId: String? = nil,
        amount: Double,
        currency: String? = nil,
        description: String? = nil,
        customerId: String? = nil,
        customerEmail: String? = nil,
        subscriptionId: String? = nil,
        isSubscription: Bool = false,
        showAmount: Bool = true,
        treatDevelopmentAsAppStore: Bool = false,
        onPaymentSuccess: ((PaymentCompletionResult) -> Void)? = nil,
        onPaymentFailure: ((String) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.appId = appId
        self.amount = amount
        self.currency = currency
        self.descriptionText = description
        self.customerId = customerId
        self.customerEmail = customerEmail
        self.subscriptionId = subscriptionId
        self.isSubscription = isSubscription
        self.showAmount = showAmount
        self.treatDevelopmentAsAppStore = treatDevelopmentAsAppStore
        self.onPaymentSuccess = onPaymentSuccess
        self.onPaymentFailure = onPaymentFailure
        self.onCancel = onCancel
    }

    public var body: some View {
        Group {
            if isLoading {
                LoadingSpinnerView(label: "Loading payment options…")
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if !errorMessage.isEmpty {
                        ErrorBannerView(message: errorMessage) { errorMessage = "" }
                    }

                    if showAmount {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Total")
                                .font(.headline)
                            Spacer()
                            Text(amount, format: .currency(code: currency ?? providerInfo?.defaultProvider?.defaultCurrency ?? "USD"))
                                .font(.title3.weight(.bold))
                        }
                    }

                    if let info = providerInfo {
                        if appStorePaymentRequired(info) {
                            appStoreSection
                        } else {
                            providerSelection(info)
                        }
                    } else {
                        ContentUnavailableView("Payments unavailable", systemImage: "creditcard.trianglebadge.exclamationmark")
                    }

                    if let pending = pendingRedirectPayment {
                        redirectPendingSection(pending)
                    }

                    if let onCancel {
                        Button("Cancel") { onCancel() }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Auto-detect

    private func appStorePaymentRequired(_ info: PlatformFilteredProvidersDto) -> Bool {
        if info.requiresAppStorePayment { return true }
        let platformInfo = PlatformDetection.detectPlatform(treatDevelopmentAsAppStore: treatDevelopmentAsAppStore)
        if platformInfo.requiresAppStorePayment,
           info.availableProviders.contains(where: { $0.resolvedProviderType == .appleAppStore }) {
            return true
        }
        return false
    }

    private func appStoreProvider(_ info: PlatformFilteredProvidersDto) -> PaymentProviderDto? {
        if let requiredId = info.requiredProviderId,
           let provider = info.availableProviders.first(where: { $0.id == requiredId }) {
            return provider
        }
        return info.availableProviders.first { $0.resolvedProviderType == .appleAppStore }
    }

    // MARK: - App Store path

    @ViewBuilder private var appStoreSection: some View {
        VStack(spacing: 12) {
            Label("Payment is processed through the App Store.", systemImage: "apple.logo")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                Task { await payWithAppStore() }
            } label: {
                if isProcessing {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Continue with App Store").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessing)

            Button("Restore Purchases") {
                Task { await restorePurchases() }
            }
            .font(.footnote)
            .disabled(isProcessing)
        }
    }

    private func payWithAppStore() async {
        guard let client, let info = providerInfo, let provider = appStoreProvider(info) else {
            fail("No App Store payment provider is configured for this app.")
            return
        }
        guard let resolvedAppId = appId ?? client.config.appId,
              let manager = purchaseManager else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            // Initiate with the Wildwood backend: it returns the App Store
            // product id(s) mapped to this purchase, keeping product
            // configuration in WildwoodAdmin rather than the app binary.
            let initiation = try await client.payment.initiatePayment(makeRequest(providerId: provider.id, appId: resolvedAppId))
            guard initiation.success, let productId = initiation.productIds?.first else {
                fail(initiation.errorMessage ?? "The backend did not return an App Store product for this purchase.")
                return
            }

            let result = try await manager.purchase(productId: productId)
            onPaymentSuccess?(result.validation)
        } catch WildwoodPurchaseError.purchaseCancelled {
            onCancel?()
        } catch WildwoodPurchaseError.purchasePending {
            // The Transaction.updates observer started in load() validates and
            // finishes the transaction when the approval lands.
            errorMessage = "Purchase is awaiting approval (Ask to Buy). It will complete automatically."
        } catch {
            fail((error as? WildwoodError)?.message ?? error.localizedDescription)
        }
    }

    private func restorePurchases() async {
        guard let manager = purchaseManager else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let results = try await manager.restorePurchases()
            if let success = results.first(where: \.success) {
                onPaymentSuccess?(success)
            } else if results.isEmpty {
                errorMessage = "No previous purchases were found."
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    // MARK: - Generic provider path (Stripe / PayPal / …)

    @ViewBuilder private func providerSelection(_ info: PlatformFilteredProvidersDto) -> some View {
        VStack(spacing: 12) {
            if info.availableProviders.isEmpty {
                ContentUnavailableView("No payment providers", systemImage: "creditcard.trianglebadge.exclamationmark")
            } else {
                if info.availableProviders.count > 1 {
                    Picker("Payment method", selection: Binding(
                        get: { selectedProviderId ?? info.defaultProvider?.id ?? info.availableProviders.first?.id ?? "" },
                        set: { selectedProviderId = $0 }
                    )) {
                        ForEach(info.availableProviders) { provider in
                            Text(provider.displayName ?? provider.name).tag(provider.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Button {
                    Task { await payWithSelectedProvider(info) }
                } label: {
                    if isProcessing {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Pay Now").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
            }
        }
    }

    private func payWithSelectedProvider(_ info: PlatformFilteredProvidersDto) async {
        guard let client else { return }
        guard let resolvedAppId = appId ?? client.config.appId else { return }
        let providerId = selectedProviderId ?? info.defaultProvider?.id ?? info.availableProviders.first?.id
        guard let providerId else { return }

        isProcessing = true
        defer { isProcessing = false }
        do {
            let initiation = try await client.payment.initiatePayment(makeRequest(providerId: providerId, appId: resolvedAppId))
            guard initiation.success else {
                fail(initiation.errorMessage ?? "Payment could not be started.")
                return
            }

            // Web checkout: open the provider-hosted page externally (Apple's
            // 2025+ US guidelines permit external payment links; EU DMA allows
            // alternative PSPs). Completion is confirmed against the backend.
            if let urlString = initiation.redirectUrl ?? initiation.approvalUrl, let url = URL(string: urlString) {
                pendingRedirectPayment = initiation
                openURL(url)
            } else if initiation.requiresClientConfirmation == true, let intentId = initiation.paymentIntentId {
                let result = try await client.payment.confirmPayment(
                    paymentIntentId: intentId,
                    providerType: initiation.resolvedProviderType ?? .stripe
                )
                if result.success {
                    onPaymentSuccess?(result)
                } else {
                    fail(result.errorMessage ?? "Payment confirmation failed.")
                }
            } else {
                fail("The provider did not return a checkout URL.")
            }
        } catch {
            fail((error as? WildwoodError)?.message ?? error.localizedDescription)
        }
    }

    @ViewBuilder private func redirectPendingSection(_ pending: InitiatePaymentResponse) -> some View {
        VStack(spacing: 8) {
            Text("Complete your payment in the browser, then return here.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                Task { await checkRedirectPaymentStatus(pending) }
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
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private func checkRedirectPaymentStatus(_ pending: InitiatePaymentResponse) async {
        guard let client, let intentId = pending.paymentIntentId else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            // NOTE (backend question): api/payment/status/{transactionId} is
            // polled here with the provider's paymentIntentId because the
            // initiate response carries no Wildwood transaction id. The web
            // stacks never poll (the return URL completes the flow). Verify
            // whether the status endpoint resolves external/provider ids; if
            // it is keyed only by internal transaction id, the backend needs
            // a lookup-by-external-id variant for mobile redirect checkouts.
            let result = try await client.payment.getPaymentStatus(transactionId: intentId)
            if result.success {
                pendingRedirectPayment = nil
                onPaymentSuccess?(result)
            } else {
                errorMessage = result.errorMessage ?? "Payment is not complete yet."
            }
        } catch {
            errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
        }
    }

    // MARK: - Shared

    private func makeRequest(providerId: String, appId: String) -> InitiatePaymentRequest {
        InitiatePaymentRequest(
            providerId: providerId,
            appId: appId,
            amount: amount,
            currency: currency,
            description: descriptionText,
            customerId: customerId,
            customerEmail: customerEmail,
            subscriptionId: subscriptionId,
            isSubscription: isSubscription ? true : nil
        )
    }

    private func fail(_ message: String) {
        errorMessage = message
        onPaymentFailure?(message)
    }

    private func load() async {
        guard let client = requireClient(client, component: "PaymentComponent") else { return }
        isLoading = true
        defer { isLoading = false }
        guard let resolvedAppId = appId ?? client.config.appId else {
            errorMessage = "PaymentComponent requires an appId."
            return
        }

        // One long-lived manager: observes Transaction.updates so renewals,
        // Ask to Buy approvals, purchases from other devices, and previously
        // failed validations are revalidated with Wildwood and finished.
        if purchaseManager == nil {
            let manager = StoreKitPurchaseManager(payment: client.payment, appId: resolvedAppId)
            purchaseManager = manager
            await manager.startObservingTransactions()
        }

        do {
            providerInfo = try await client.payment.getAvailableProviders(appId: resolvedAppId)
        } catch {
            errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
        }
    }
}
#endif
