// Payment service ported from @wildwood/core/src/payment/paymentService.ts
// (itself a port of WildwoodComponents.Blazor/Services/PaymentProviderService.cs).
//
// Provider selection is backend-driven: getAvailableProviders returns the
// platform-filtered list the Wildwood configuration enables. Components must
// never hardcode a processor.

import Foundation

public final class PaymentService: Sendable {
    private let http: WildwoodHttpClient

    public init(http: WildwoodHttpClient) {
        self.http = http
    }

    // MARK: - Configuration

    public func getAppPaymentConfiguration(appId: String) async -> AppPaymentConfigurationDto? {
        try? await http.get("api/payment/configuration/\(appId)")
    }

    public func getAvailableProviders(appId: String) async throws -> PlatformFilteredProvidersDto {
        try await http.get("api/payment/providers/\(appId)")
    }

    // MARK: - Payment operations

    public func initiatePayment(_ request: InitiatePaymentRequest) async throws -> InitiatePaymentResponse {
        try await http.post("api/payment/initiate", body: request)
    }

    public func confirmPayment(
        paymentIntentId: String,
        providerType: PaymentProviderType,
        confirmationData: [String: JSONValue]? = nil
    ) async throws -> PaymentCompletionResult {
        struct ConfirmDto: Encodable {
            let paymentIntentId: String
            let providerType: PaymentProviderType
            let confirmationData: [String: JSONValue]?
        }
        return try await http.post(
            "api/payment/confirm",
            body: ConfirmDto(paymentIntentId: paymentIntentId, providerType: providerType, confirmationData: confirmationData)
        )
    }

    /// Validate an App Store / Play Store receipt with the Wildwood backend.
    /// For Apple, `receiptData` is the StoreKit 2 JWS representation (or legacy
    /// receipt). The backend records the transaction so the purchase remains
    /// managed in Wildwood, and may return a linked `subscriptionId`.
    public func validateAppStoreReceipt(
        appId: String,
        receiptData: String,
        providerType: PaymentProviderType
    ) async throws -> PaymentCompletionResult {
        struct ReceiptDto: Encodable {
            let appId: String
            let receiptData: String
            let providerType: PaymentProviderType
        }
        let body = ReceiptDto(appId: appId, receiptData: receiptData, providerType: providerType)
        if providerType == .appleAppStore {
            return try await http.post("api/payment/validate-apple-receipt", body: body)
        }
        return try await http.post("api/payment/validate-google-receipt", body: body)
    }

    public func getPaymentStatus(transactionId: String) async throws -> PaymentCompletionResult {
        try await http.get("api/payment/status/\(transactionId)")
    }

    public func requestRefund(transactionId: String, amount: Double? = nil, reason: String? = nil) async throws -> PaymentCompletionResult {
        struct RefundDto: Encodable {
            let transactionId: String
            let amount: Double?
            let reason: String?
        }
        return try await http.post(
            "api/payment/refund",
            body: RefundDto(transactionId: transactionId, amount: amount, reason: reason)
        )
    }

    // MARK: - Saved payment methods

    public func getSavedPaymentMethods(customerId: String) async -> [SavedPaymentMethodDto] {
        let data: [SavedPaymentMethodDto]? = try? await http.get("api/payment/methods/\(customerId)")
        return data ?? []
    }

    public func deleteSavedPaymentMethod(paymentMethodId: String) async -> Bool {
        do {
            try await http.deleteVoid("api/payment/methods/\(paymentMethodId)")
            return true
        } catch {
            return false
        }
    }

    public func setDefaultPaymentMethod(paymentMethodId: String) async -> Bool {
        do {
            try await http.postVoid("api/payment/methods/\(paymentMethodId)/default")
            return true
        } catch {
            return false
        }
    }

    /// Link an external provider transaction (Stripe pi_xxx, App Store transaction
    /// id) to a Wildwood user, so the purchase feeds tier subscriptions.
    public func linkTransactionToUser(
        externalTransactionId: String,
        userId: String,
        companyClientId: String? = nil
    ) async -> Bool {
        struct LinkDto: Encodable {
            let externalTransactionId: String
            let userId: String
            let companyClientId: String?
        }
        do {
            try await http.postVoid(
                "api/paymenttransactions/link-by-external-id",
                body: LinkDto(externalTransactionId: externalTransactionId, userId: userId, companyClientId: companyClientId)
            )
            return true
        } catch {
            return false
        }
    }
}
