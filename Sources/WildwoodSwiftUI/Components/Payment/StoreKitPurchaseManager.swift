#if os(iOS)
// StoreKit 2 purchase pipeline for the AppleAppStore provider path. Purchases
// stay managed in Wildwood: every verified transaction's JWS is posted to
// api/payment/validate-apple-receipt so the backend records the transaction
// and links it into tier subscriptions.
//
// iOS 27 note: StoreKit 27 adds commitment billing plans (billingPlanType,
// commitmentInfo) and offer-code redemption with a verificationResult. Those
// surfaces are adopted behind @available(iOS 27, *) once the package builds
// with the Xcode 27 SDK — the validation flow below is unchanged by them.

import Foundation
import StoreKit
import WildwoodCore

public struct WildwoodPurchaseResult: Sendable {
    public let transactionId: String
    public let originalTransactionId: String
    public let productId: String
    public let validation: PaymentCompletionResult
}

public enum WildwoodPurchaseError: Error, Sendable {
    case productNotFound(String)
    case purchaseCancelled
    case purchasePending
    case verificationFailed
    case validationFailed(String)
}

public actor StoreKitPurchaseManager {
    private let payment: PaymentService
    private let appId: String
    private var updatesTask: Task<Void, Never>?

    public init(payment: PaymentService, appId: String) {
        self.payment = payment
        self.appId = appId
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Start observing Transaction.updates (renewals, Ask to Buy approvals,
    /// purchases from other devices). Each verified update is revalidated with
    /// the Wildwood backend so subscription state stays in sync.
    public func startObservingTransactions(onValidated: (@Sendable (PaymentCompletionResult) -> Void)? = nil) {
        guard updatesTask == nil else { return }
        updatesTask = Task { [payment, appId] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                let result = try? await payment.validateAppStoreReceipt(
                    appId: appId,
                    receiptData: update.jwsRepresentation,
                    providerType: .appleAppStore
                )
                await transaction.finish()
                if let result {
                    onValidated?(result)
                }
            }
        }
    }

    public func stopObservingTransactions() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    public func products(for identifiers: [String]) async throws -> [Product] {
        try await Product.products(for: identifiers)
    }

    /// Purchase a product and validate it with the Wildwood backend.
    public func purchase(productId: String) async throws -> WildwoodPurchaseResult {
        let products = try await Product.products(for: [productId])
        guard let product = products.first else {
            throw WildwoodPurchaseError.productNotFound(productId)
        }
        return try await purchase(product: product)
    }

    public func purchase(product: Product) async throws -> WildwoodPurchaseResult {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw WildwoodPurchaseError.verificationFailed
            }

            let validation = try await payment.validateAppStoreReceipt(
                appId: appId,
                receiptData: verification.jwsRepresentation,
                providerType: .appleAppStore
            )

            guard validation.success else {
                // Leave the transaction unfinished so Transaction.updates
                // retries validation later.
                throw WildwoodPurchaseError.validationFailed(validation.errorMessage ?? "Receipt validation failed")
            }

            await transaction.finish()
            return WildwoodPurchaseResult(
                transactionId: String(transaction.id),
                originalTransactionId: String(transaction.originalID),
                productId: transaction.productID,
                validation: validation
            )

        case .userCancelled:
            throw WildwoodPurchaseError.purchaseCancelled
        case .pending:
            throw WildwoodPurchaseError.purchasePending
        @unknown default:
            throw WildwoodPurchaseError.verificationFailed
        }
    }

    /// Restore purchases (App Store sync) and revalidate current entitlements
    /// with the backend.
    public func restorePurchases() async throws -> [PaymentCompletionResult] {
        try await AppStore.sync()
        var results: [PaymentCompletionResult] = []
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified = entitlement else { continue }
            if let result = try? await payment.validateAppStoreReceipt(
                appId: appId,
                receiptData: entitlement.jwsRepresentation,
                providerType: .appleAppStore
            ) {
                results.append(result)
            }
        }
        return results
    }
}
#endif
