// Payment models ported from @wildwood/core/src/payment/types.ts
// (itself a port of WildwoodComponents.Shared/Models/PaymentProviderModels.cs).

import Foundation

public enum PaymentProviderType: Int, Codable, Sendable, CaseIterable {
    case stripe = 1
    case payPal = 2
    case square = 3
    case braintree = 4
    case authorizeNet = 5
    case appleAppStore = 10
    case googlePlayStore = 11
    case applePay = 20
    case googlePay = 21
    case klarna = 30
    case affirm = 31
    case afterpay = 32
    case razorpay = 40
    case adyen = 41
    case coinbase = 50
    case bitPay = 51
}

public enum PaymentProviderCategory: Int, Codable, Sendable {
    case cardProcessor = 1
    case appStore = 2
    case digitalWallet = 3
    case buyNowPayLater = 4
    case regional = 5
    case cryptocurrency = 6
}

public struct PaymentProviderDto: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var displayName: String?
    public var providerType: Int
    public var category: Int
    public var isEnabled: Bool
    public var isDefault: Bool
    public var isSandboxMode: Bool
    public var displayOrder: Int
    public var publishableKey: String?
    public var clientId: String?
    public var merchantId: String?
    public var supportsSubscriptions: Bool
    public var supportsRefunds: Bool
    public var supports3DSecure: Bool
    public var supportsSavedPaymentMethods: Bool
    public var supportsApplePay: Bool
    public var supportsGooglePay: Bool
    public var allowedPlatforms: Int
    public var isAppStoreExclusive: Bool
    public var supportedCurrencies: String?
    public var defaultCurrency: String?

    public var resolvedProviderType: PaymentProviderType? {
        PaymentProviderType(rawValue: providerType)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        providerType = try c.decodeIfPresent(Int.self, forKey: .providerType) ?? 0
        category = try c.decodeIfPresent(Int.self, forKey: .category) ?? 0
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        isSandboxMode = try c.decodeIfPresent(Bool.self, forKey: .isSandboxMode) ?? false
        displayOrder = try c.decodeIfPresent(Int.self, forKey: .displayOrder) ?? 0
        publishableKey = try c.decodeIfPresent(String.self, forKey: .publishableKey)
        clientId = try c.decodeIfPresent(String.self, forKey: .clientId)
        merchantId = try c.decodeIfPresent(String.self, forKey: .merchantId)
        supportsSubscriptions = try c.decodeIfPresent(Bool.self, forKey: .supportsSubscriptions) ?? false
        supportsRefunds = try c.decodeIfPresent(Bool.self, forKey: .supportsRefunds) ?? false
        supports3DSecure = try c.decodeIfPresent(Bool.self, forKey: .supports3DSecure) ?? false
        supportsSavedPaymentMethods = try c.decodeIfPresent(Bool.self, forKey: .supportsSavedPaymentMethods) ?? false
        supportsApplePay = try c.decodeIfPresent(Bool.self, forKey: .supportsApplePay) ?? false
        supportsGooglePay = try c.decodeIfPresent(Bool.self, forKey: .supportsGooglePay) ?? false
        allowedPlatforms = try c.decodeIfPresent(Int.self, forKey: .allowedPlatforms) ?? 0
        isAppStoreExclusive = try c.decodeIfPresent(Bool.self, forKey: .isAppStoreExclusive) ?? false
        supportedCurrencies = try c.decodeIfPresent(String.self, forKey: .supportedCurrencies)
        defaultCurrency = try c.decodeIfPresent(String.self, forKey: .defaultCurrency)
    }
}

public struct AppPaymentConfigurationDto: Codable, Sendable, Equatable {
    public var appId: String
    public var appName: String
    public var isPaymentEnabled: Bool
    public var defaultCurrency: String
    public var supportedCurrencies: String?
    public var allowSavedPaymentMethods: Bool
    public var requireBillingAddress: Bool
    public var require3DSecure: Bool
    public var providers: [PaymentProviderDto]
    public var defaultProviderId: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appId = try c.decodeIfPresent(String.self, forKey: .appId) ?? ""
        appName = try c.decodeIfPresent(String.self, forKey: .appName) ?? ""
        isPaymentEnabled = try c.decodeIfPresent(Bool.self, forKey: .isPaymentEnabled) ?? false
        defaultCurrency = try c.decodeIfPresent(String.self, forKey: .defaultCurrency) ?? "USD"
        supportedCurrencies = try c.decodeIfPresent(String.self, forKey: .supportedCurrencies)
        allowSavedPaymentMethods = try c.decodeIfPresent(Bool.self, forKey: .allowSavedPaymentMethods) ?? false
        requireBillingAddress = try c.decodeIfPresent(Bool.self, forKey: .requireBillingAddress) ?? false
        require3DSecure = try c.decodeIfPresent(Bool.self, forKey: .require3DSecure) ?? false
        providers = try c.decodeIfPresent([PaymentProviderDto].self, forKey: .providers) ?? []
        defaultProviderId = try c.decodeIfPresent(String.self, forKey: .defaultProviderId)
    }
}

/// Platform-filtered provider list — the backend-driven payment auto-detect.
/// When `requiresAppStorePayment` is true, `requiredProviderId` is the only
/// permitted provider (App Store / Play Store exclusivity).
public struct PlatformFilteredProvidersDto: Codable, Sendable, Equatable {
    public var appId: String
    public var platform: String
    public var requiresAppStorePayment: Bool
    public var requiredProviderId: String?
    public var availableProviders: [PaymentProviderDto]
    public var defaultProvider: PaymentProviderDto?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appId = try c.decodeIfPresent(String.self, forKey: .appId) ?? ""
        platform = try c.decodeIfPresent(String.self, forKey: .platform) ?? ""
        requiresAppStorePayment = try c.decodeIfPresent(Bool.self, forKey: .requiresAppStorePayment) ?? false
        requiredProviderId = try c.decodeIfPresent(String.self, forKey: .requiredProviderId)
        availableProviders = try c.decodeIfPresent([PaymentProviderDto].self, forKey: .availableProviders) ?? []
        defaultProvider = try c.decodeIfPresent(PaymentProviderDto.self, forKey: .defaultProvider)
    }
}

public struct InitiatePaymentRequest: Codable, Sendable, Equatable {
    public var providerId: String
    public var appId: String
    public var amount: Double
    public var currency: String?
    public var description: String?
    public var customerId: String?
    public var customerEmail: String?
    public var orderId: String?
    public var subscriptionId: String?
    public var pricingModelId: String?
    public var isSubscription: Bool?
    public var billingFrequency: String?
    public var returnUrl: String?
    public var cancelUrl: String?
    public var metadata: [String: String]?

    public init(
        providerId: String,
        appId: String,
        amount: Double,
        currency: String? = nil,
        description: String? = nil,
        customerId: String? = nil,
        customerEmail: String? = nil,
        orderId: String? = nil,
        subscriptionId: String? = nil,
        pricingModelId: String? = nil,
        isSubscription: Bool? = nil,
        billingFrequency: String? = nil,
        returnUrl: String? = nil,
        cancelUrl: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.providerId = providerId
        self.appId = appId
        self.amount = amount
        self.currency = currency
        self.description = description
        self.customerId = customerId
        self.customerEmail = customerEmail
        self.orderId = orderId
        self.subscriptionId = subscriptionId
        self.pricingModelId = pricingModelId
        self.isSubscription = isSubscription
        self.billingFrequency = billingFrequency
        self.returnUrl = returnUrl
        self.cancelUrl = cancelUrl
        self.metadata = metadata
    }
}

public struct InitiatePaymentResponse: Codable, Sendable, Equatable {
    public var success: Bool
    public var paymentIntentId: String?
    public var clientSecret: String?
    public var redirectUrl: String?
    public var approvalUrl: String?
    public var orderId: String?
    public var subscriptionId: String?
    public var requiresClientConfirmation: Bool?
    public var errorMessage: String?
    public var errorCode: String?
    public var providerType: Int
    public var productIds: [String]?
    public var providerData: [String: JSONValue]?

    public var resolvedProviderType: PaymentProviderType? {
        PaymentProviderType(rawValue: providerType)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        paymentIntentId = try c.decodeIfPresent(String.self, forKey: .paymentIntentId)
        clientSecret = try c.decodeIfPresent(String.self, forKey: .clientSecret)
        redirectUrl = try c.decodeIfPresent(String.self, forKey: .redirectUrl)
        approvalUrl = try c.decodeIfPresent(String.self, forKey: .approvalUrl)
        orderId = try c.decodeIfPresent(String.self, forKey: .orderId)
        subscriptionId = try c.decodeIfPresent(String.self, forKey: .subscriptionId)
        requiresClientConfirmation = try c.decodeIfPresent(Bool.self, forKey: .requiresClientConfirmation)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        errorCode = try c.decodeIfPresent(String.self, forKey: .errorCode)
        providerType = try c.decodeIfPresent(Int.self, forKey: .providerType) ?? 0
        productIds = try c.decodeIfPresent([String].self, forKey: .productIds)
        providerData = try c.decodeIfPresent([String: JSONValue].self, forKey: .providerData)
    }
}

public struct PaymentCompletionResult: Codable, Sendable, Equatable {
    public var success: Bool
    public var transactionId: String?
    public var paymentIntentId: String?
    public var subscriptionId: String?
    public var amountPaid: Double?
    public var currency: String?
    public var status: String?
    public var errorMessage: String?
    public var errorCode: String?
    public var completedAt: Date?
    public var receiptUrl: String?
    public var metadata: [String: JSONValue]?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        transactionId = try c.decodeIfPresent(String.self, forKey: .transactionId)
        paymentIntentId = try c.decodeIfPresent(String.self, forKey: .paymentIntentId)
        subscriptionId = try c.decodeIfPresent(String.self, forKey: .subscriptionId)
        amountPaid = try c.decodeIfPresent(Double.self, forKey: .amountPaid)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        errorCode = try c.decodeIfPresent(String.self, forKey: .errorCode)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        receiptUrl = try c.decodeIfPresent(String.self, forKey: .receiptUrl)
        metadata = try c.decodeIfPresent([String: JSONValue].self, forKey: .metadata)
    }
}

public struct SavedPaymentMethodDto: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var customerId: String
    public var providerType: Int
    public var type: String
    public var last4: String?
    public var brand: String?
    public var expMonth: Int?
    public var expYear: Int?
    public var isDefault: Bool
    public var createdAt: Date?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        customerId = try c.decodeIfPresent(String.self, forKey: .customerId) ?? ""
        providerType = try c.decodeIfPresent(Int.self, forKey: .providerType) ?? 0
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        last4 = try c.decodeIfPresent(String.self, forKey: .last4)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        expMonth = try c.decodeIfPresent(Int.self, forKey: .expMonth)
        expYear = try c.decodeIfPresent(Int.self, forKey: .expYear)
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}
