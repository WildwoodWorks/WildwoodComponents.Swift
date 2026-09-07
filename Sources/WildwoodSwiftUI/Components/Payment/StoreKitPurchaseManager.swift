#if os(iOS)
// StoreKit 2 purchase pipeline for the AppleAppStore provider path. Purchases
// stay managed in Wildwood: every verified transaction goes through
// PaymentService.validateStorePurchase (product id, store transaction id and
// restore flag alongside the JWS) to api/payment/validate-apple-receipt so the
// backend records the transaction and links it into tier subscriptions.
//
// Finish rule (shared by purchase, restore and Transaction.updates, see
// StorePurchaseSettlement): a StoreKit transaction is finished only after a
// successful validation that — for a fresh purchase — returned a Wildwood
// transactionId. A restore needs `success` alone. Anything else leaves the
// transaction UNFINISHED so StoreKit re-delivers it and it is reprocessed.
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

    /// The receipt hand-off payload for a verified StoreKit transaction.
    private static func storePurchase(for transaction: Transaction, jws: String, isRestore: Bool) -> StorePurchase {
        StorePurchase(
            providerType: .appleAppStore,
            productId: transaction.productID,
            purchaseToken: jws,
            transactionId: String(transaction.id),
            isRestore: isRestore ? true : nil   // RN sends the flag only on restore
        )
    }

    /// Start observing Transaction.updates (renewals, Ask to Buy approvals,
    /// purchases from other devices). Each verified update is revalidated with
    /// the Wildwood backend so subscription state stays in sync. `onValidated`
    /// fires only for updates that were validated and finished.
    public func startObservingTransactions(onValidated: (@Sendable (PaymentCompletionResult) -> Void)? = nil) {
        guard updatesTask == nil else { return }
        updatesTask = Task { [payment, appId] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                // A transport failure, or a failed / transaction-id-less validation,
                // leaves the transaction UNFINISHED so StoreKit re-delivers it.
                guard let result = try? await payment.validateStorePurchase(
                    appId: appId,
                    purchase: Self.storePurchase(for: transaction, jws: update.jwsRepresentation, isRestore: false)
                ) else { continue }
                guard StorePurchaseSettlement.canFinish(result, isRestore: false) else { continue }
                await transaction.finish()
                onValidated?(result)
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

            let validation = try await payment.validateStorePurchase(
                appId: appId,
                purchase: Self.storePurchase(for: transaction, jws: verification.jwsRepresentation, isRestore: false)
            )

            guard validation.success else {
                // Leave the transaction UNFINISHED so Transaction.updates
                // retries validation later.
                throw WildwoodPurchaseError.validationFailed(validation.errorMessage ?? "Receipt validation failed")
            }

            // Validated, but with nothing to hand to changeTier/selfSubscribe —
            // fail WITHOUT finishing so the store re-delivers the transaction.
            guard StorePurchaseSettlement.canFinish(validation, isRestore: false) else {
                throw WildwoodPurchaseError.validationFailed("Validation succeeded but returned no transaction id.")
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
            guard case .verified(let transaction) = entitlement else { continue }
            // A transport failure leaves the transaction UNFINISHED so the store
            // re-delivers it on the next restore or Transaction.updates pass.
            guard let result = try? await payment.validateStorePurchase(
                appId: appId,
                purchase: Self.storePurchase(for: transaction, jws: entitlement.jwsRepresentation, isRestore: true)
            ) else { continue }
            results.append(result)
            if StorePurchaseSettlement.canFinish(result, isRestore: true) {
                await transaction.finish()
            }
        }
        return results
    }
}
#endif
