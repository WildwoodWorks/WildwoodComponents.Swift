// Add-on checkout, trial eligibility and structured action results, ported from
// @wildwood/core/src/features/types.ts (and mirrored by
// WildwoodComponents.Shared/Models/AppTierCheckoutModels.cs).
//
// Request models carry explicit PascalCase CodingKeys so the body is byte-compatible with what
// the JS SDK posts; optional properties are omitted when nil, which is how JS `undefined`
// behaves. Response models use the default camelCase keys and decode every field leniently, so a
// sparse or older server never fails decoding.
//
// Server error codes and statuses stay `String` on the wire. The closed sets below are constant
// namespaces to compare against, never enums to switch exhaustively on: a value the server adds
// tomorrow must decode today.

import Foundation

// MARK: - Tier change options

/// Options form of a self-service tier change. The JSON names are what WildwoodAPI's
/// SelfChangeTierDto binds; the positional `changeTier` keeps posting the old body without
/// `SupportsPaymentAction`, because an older server rejects an unknown property.
public struct SelfChangeTierOptions: Codable, Sendable, Equatable {
    public var newTierId: String
    public var newPricingId: String?
    /// Apply now rather than at the end of the billing period. Defaults to true.
    public var immediate: Bool
    /// A payment that has already been made, to pay for the new plan.
    public var paymentTransactionId: String?
    /// The caller can confirm a payment (it has a payment handler) and will call the tier-change
    /// completion endpoint afterwards. Left false, a change whose proration needs 3-D Secure is
    /// refused rather than parked.
    public var supportsPaymentAction: Bool

    enum CodingKeys: String, CodingKey {
        case newTierId = "NewAppTierId"
        case newPricingId = "NewAppTierPricingId"
        case immediate = "Immediate"
        case paymentTransactionId = "PaymentTransactionId"
        case supportsPaymentAction = "SupportsPaymentAction"
    }

    public init(
        newTierId: String,
        newPricingId: String? = nil,
        immediate: Bool = true,
        paymentTransactionId: String? = nil,
        supportsPaymentAction: Bool = false
    ) {
        self.newTierId = newTierId
        self.newPricingId = newPricingId
        self.immediate = immediate
        self.paymentTransactionId = paymentTransactionId
        self.supportsPaymentAction = supportsPaymentAction
    }
}

/// Refusal reasons a tier change can report (the server's `TierChangeErrorCodes`). String
/// constants (not an enum) to match the API payload verbatim and mirror the JS union — the wire
/// value is open-ended, so compare against these rather than switching exhaustively.
public enum TierChangeErrorCodes {
    public static let pendingChangeNotFound = "pending_change_not_found"
    public static let pendingChangeExpired = "pending_change_expired"
    public static let pendingChangePaymentFailed = "pending_change_payment_failed"
    public static let pendingChangeSuperseded = "pending_change_superseded"
    public static let tierChangeAlreadyInProgress = "tier_change_already_in_progress"
}

// MARK: - Trial eligibility

/// What `GET api/app-tiers/{appId}/trial-eligibility` answers. A failed lookup defaults to
/// eligible with an empty map, so a transient error never hides an advertised trial.
public struct TrialEligibilityModel: Codable, Sendable, Equatable {
    /// Whether this account may still start a free trial on a tier.
    public var tierTrialEligible: Bool
    /// The same answer per active add-on, keyed by add-on id. A missing key means "unknown".
    public var addOns: [String: Bool]

    public init(tierTrialEligible: Bool = true, addOns: [String: Bool] = [:]) {
        self.tierTrialEligible = tierTrialEligible
        self.addOns = addOns
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tierTrialEligible = try c.decodeIfPresent(Bool.self, forKey: .tierTrialEligible) ?? true
        addOns = try c.decodeIfPresent([String: Bool].self, forKey: .addOns) ?? [:]
    }
}

// MARK: - Add-on checkout requests

/// One pack in a checkout basket. Leave ``pricingId`` out to take the pack's default pricing.
public struct AddOnCheckoutItemInput: Codable, Sendable, Equatable {
    public var addOnId: String
    public var pricingId: String?

    enum CodingKeys: String, CodingKey {
        case addOnId = "AddOnId"
        case pricingId = "PricingId"
    }

    public init(addOnId: String, pricingId: String? = nil) {
        self.addOnId = addOnId
        self.pricingId = pricingId
    }
}

/// Body of `POST api/app-tier-addons/{appId}/checkout/quote`.
public struct AddOnCheckoutQuoteRequestModel: Codable, Sendable, Equatable {
    public var items: [AddOnCheckoutItemInput]

    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }

    public init(items: [AddOnCheckoutItemInput] = []) {
        self.items = items
    }
}

/// Body of `POST api/app-tier-addons/{appId}/checkout/payment-method`.
public struct AddOnCheckoutPaymentMethodRequestModel: Codable, Sendable, Equatable {
    public var providerId: String

    enum CodingKeys: String, CodingKey {
        case providerId = "ProviderId"
    }

    public init(providerId: String) {
        self.providerId = providerId
    }
}

/// The purchase. The card comes from exactly one of ``paymentTransactionId`` or ``useSavedCard``.
public struct AddOnCheckoutRequestModel: Codable, Sendable, Equatable {
    public var checkoutId: String
    public var providerId: String
    public var paymentTransactionId: String?
    public var useSavedCard: Bool
    public var items: [AddOnCheckoutItemInput]

    enum CodingKeys: String, CodingKey {
        case checkoutId = "CheckoutId"
        case providerId = "ProviderId"
        case paymentTransactionId = "PaymentTransactionId"
        case useSavedCard = "UseSavedCard"
        case items = "Items"
    }

    public init(
        checkoutId: String,
        providerId: String,
        paymentTransactionId: String? = nil,
        useSavedCard: Bool = false,
        items: [AddOnCheckoutItemInput] = []
    ) {
        self.checkoutId = checkoutId
        self.providerId = providerId
        self.paymentTransactionId = paymentTransactionId
        self.useSavedCard = useSavedCard
        self.items = items
    }
}

/// Body of `POST api/app-tier-addons/{appId}/checkout/complete`.
public struct AddOnCheckoutCompleteRequestModel: Codable, Sendable, Equatable {
    public var paymentTransactionId: String

    enum CodingKeys: String, CodingKey {
        case paymentTransactionId = "PaymentTransactionId"
    }

    public init(paymentTransactionId: String) {
        self.paymentTransactionId = paymentTransactionId
    }
}

// MARK: - Add-on checkout responses

/// One quoted pack. Every field is the server's own answer — never the client's ask.
/// `id` is the pack id: a basket refuses a duplicate pack, so it is unique within one quote.
public struct AddOnCheckoutQuoteLineModel: Codable, Sendable, Equatable, Identifiable {
    public var addOnId: String
    public var pricingId: String
    public var name: String
    public var price: Double
    public var billingFrequency: String
    public var trialDays: Int
    /// Whether THIS account may still use the pack's trial (one trial per account).
    public var trialEligible: Bool
    /// Zero when the pack starts a trial, else the full price.
    public var dueToday: Double
    public var trialEnd: Date?

    public var id: String { addOnId }

    public init(
        addOnId: String = "",
        pricingId: String = "",
        name: String = "",
        price: Double = 0,
        billingFrequency: String = "",
        trialDays: Int = 0,
        trialEligible: Bool = false,
        dueToday: Double = 0,
        trialEnd: Date? = nil
    ) {
        self.addOnId = addOnId
        self.pricingId = pricingId
        self.name = name
        self.price = price
        self.billingFrequency = billingFrequency
        self.trialDays = trialDays
        self.trialEligible = trialEligible
        self.dueToday = dueToday
        self.trialEnd = trialEnd
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        addOnId = try c.decodeIfPresent(String.self, forKey: .addOnId) ?? ""
        pricingId = try c.decodeIfPresent(String.self, forKey: .pricingId) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        price = try c.decodeIfPresent(Double.self, forKey: .price) ?? 0
        billingFrequency = try c.decodeIfPresent(String.self, forKey: .billingFrequency) ?? ""
        trialDays = try c.decodeIfPresent(Int.self, forKey: .trialDays) ?? 0
        trialEligible = try c.decodeIfPresent(Bool.self, forKey: .trialEligible) ?? false
        dueToday = try c.decodeIfPresent(Double.self, forKey: .dueToday) ?? 0
        trialEnd = try c.decodeIfPresent(Date.self, forKey: .trialEnd)
    }
}

/// The card already on file, named the way a UI shows it. Never carries a payment method id.
public struct AddOnCheckoutSavedCardModel: Codable, Sendable, Equatable {
    public var brand: String?
    public var last4: String?

    public init(brand: String? = nil, last4: String? = nil) {
        self.brand = brand
        self.last4 = last4
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        last4 = try c.decodeIfPresent(String.self, forKey: .last4)
    }
}

/// A priced basket. ``checkoutId`` is echoed back on the purchase and is what makes it
/// idempotent, so a double-clicked buy button cannot buy the same pack twice.
public struct AddOnCheckoutQuoteModel: Codable, Sendable, Equatable {
    public var success: Bool
    public var checkoutId: String
    /// The provider this quote's saved card and ``requiresPaymentMethod`` are about; echo it back.
    public var providerId: String?
    /// ISO currency of the quoted prices. Empty when the quote was refused before pricing
    /// anything — naming one there would invent a currency for prices that do not exist.
    public var currency: String
    public var lines: [AddOnCheckoutQuoteLineModel]
    public var totalDueToday: Double
    /// True when there is no card to reuse and one has to be collected first.
    public var requiresPaymentMethod: Bool
    public var savedCard: AddOnCheckoutSavedCardModel?
    public var errorCode: String?
    public var errorMessage: String?

    public init(
        success: Bool = false,
        checkoutId: String = "",
        providerId: String? = nil,
        currency: String = "",
        lines: [AddOnCheckoutQuoteLineModel] = [],
        totalDueToday: Double = 0,
        requiresPaymentMethod: Bool = false,
        savedCard: AddOnCheckoutSavedCardModel? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.success = success
        self.checkoutId = checkoutId
        self.providerId = providerId
        self.currency = currency
        self.lines = lines
        self.totalDueToday = totalDueToday
        self.requiresPaymentMethod = requiresPaymentMethod
        self.savedCard = savedCard
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        checkoutId = try c.decodeIfPresent(String.self, forKey: .checkoutId) ?? ""
        providerId = try c.decodeIfPresent(String.self, forKey: .providerId)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? ""
        lines = try c.decodeIfPresent([AddOnCheckoutQuoteLineModel].self, forKey: .lines) ?? []
        totalDueToday = try c.decodeIfPresent(Double.self, forKey: .totalDueToday) ?? 0
        requiresPaymentMethod = try c.decodeIfPresent(Bool.self, forKey: .requiresPaymentMethod) ?? false
        savedCard = try c.decodeIfPresent(AddOnCheckoutSavedCardModel.self, forKey: .savedCard)
        errorCode = try c.decodeIfPresent(String.self, forKey: .errorCode)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

/// The card-collection intent: confirm ``clientSecret``, then hand ``paymentTransactionId`` to
/// the checkout, which reads the saved card off it.
public struct AddOnCheckoutPaymentMethodModel: Codable, Sendable, Equatable {
    public var success: Bool
    public var clientSecret: String?
    public var setupIntentId: String?
    public var paymentTransactionId: String?
    public var errorCode: String?
    public var errorMessage: String?

    public init(
        success: Bool = false,
        clientSecret: String? = nil,
        setupIntentId: String? = nil,
        paymentTransactionId: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.success = success
        self.clientSecret = clientSecret
        self.setupIntentId = setupIntentId
        self.paymentTransactionId = paymentTransactionId
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        clientSecret = try c.decodeIfPresent(String.self, forKey: .clientSecret)
        setupIntentId = try c.decodeIfPresent(String.self, forKey: .setupIntentId)
        paymentTransactionId = try c.decodeIfPresent(String.self, forKey: .paymentTransactionId)
        errorCode = try c.decodeIfPresent(String.self, forKey: .errorCode)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

/// What became of one pack: it is running (`trialing`/`active`), the customer still has to
/// authenticate the card (`requires_action`, with nothing subscribed yet), or it failed and
/// nothing was charged. String constants (not an enum) to match the API payload verbatim.
public enum AddOnCheckoutItemStatuses {
    public static let trialing = "trialing"
    public static let active = "active"
    public static let requiresAction = "requires_action"
    public static let failed = "failed"
}

/// `id` is the pack id: a basket refuses a duplicate pack, so it is unique within one result set.
public struct AddOnCheckoutItemResultModel: Codable, Sendable, Equatable, Identifiable {
    public var addOnId: String
    public var pricingId: String
    /// One of ``AddOnCheckoutItemStatuses``.
    public var status: String
    /// The add-on subscription row's id, once there is one.
    public var subscriptionId: String?
    public var trialEnd: Date?
    public var amountDueToday: Double?
    /// The 3-D Secure secret for a pack the bank wants authenticated. Secret — never log it.
    public var clientSecret: String?
    public var paymentIntentId: String?
    public var paymentTransactionId: String?
    public var errorCode: String?
    public var errorMessage: String?

    public var id: String { addOnId }

    public init(
        addOnId: String = "",
        pricingId: String = "",
        status: String = "",
        subscriptionId: String? = nil,
        trialEnd: Date? = nil,
        amountDueToday: Double? = nil,
        clientSecret: String? = nil,
        paymentIntentId: String? = nil,
        paymentTransactionId: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.addOnId = addOnId
        self.pricingId = pricingId
        self.status = status
        self.subscriptionId = subscriptionId
        self.trialEnd = trialEnd
        self.amountDueToday = amountDueToday
        self.clientSecret = clientSecret
        self.paymentIntentId = paymentIntentId
        self.paymentTransactionId = paymentTransactionId
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        addOnId = try c.decodeIfPresent(String.self, forKey: .addOnId) ?? ""
        pricingId = try c.decodeIfPresent(String.self, forKey: .pricingId) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        subscriptionId = try c.decodeIfPresent(String.self, forKey: .subscriptionId)
        trialEnd = try c.decodeIfPresent(Date.self, forKey: .trialEnd)
        amountDueToday = try c.decodeIfPresent(Double.self, forKey: .amountDueToday)
        clientSecret = try c.decodeIfPresent(String.self, forKey: .clientSecret)
        paymentIntentId = try c.decodeIfPresent(String.self, forKey: .paymentIntentId)
        paymentTransactionId = try c.decodeIfPresent(String.self, forKey: .paymentTransactionId)
        errorCode = try c.decodeIfPresent(String.self, forKey: .errorCode)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

/// One result per requested pack, or a refusal that stopped the whole basket.
public struct AddOnCheckoutResultModel: Codable, Sendable, Equatable {
    public var success: Bool
    public var checkoutId: String
    public var results: [AddOnCheckoutItemResultModel]
    /// Set when nothing was attempted — a bad basket, a foreign provider, no card.
    public var errorCode: String?
    public var errorMessage: String?

    public init(
        success: Bool = false,
        checkoutId: String = "",
        results: [AddOnCheckoutItemResultModel] = [],
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.success = success
        self.checkoutId = checkoutId
        self.results = results
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        checkoutId = try c.decodeIfPresent(String.self, forKey: .checkoutId) ?? ""
        results = try c.decodeIfPresent([AddOnCheckoutItemResultModel].self, forKey: .results) ?? []
        errorCode = try c.decodeIfPresent(String.self, forKey: .errorCode)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

/// Why a quote, a purchase or one pack was refused (the server's `AddOnCheckoutErrors`).
/// String constants: callers may see other values, so compare rather than switch.
public enum AddOnCheckoutErrorCodes {
    public static let noItems = "NoItems"
    public static let duplicateItem = "DuplicateItem"
    public static let appNotFound = "AppNotFound"
    public static let addOnNotFound = "AddOnNotFound"
    public static let addOnNotAvailable = "AddOnNotAvailable"
    public static let pricingNotFound = "PricingNotFound"
    public static let alreadySubscribed = "AlreadySubscribed"
    public static let bundledInTier = "BundledInTier"
    public static let tierTooLow = "TierTooLow"
    public static let dependencyMissing = "DependencyMissing"
    public static let providerNotAvailable = "ProviderNotAvailable"
    public static let paymentMethodRequired = "PaymentMethodRequired"
    public static let transactionNotFound = "TransactionNotFound"
    public static let transactionNotYours = "TransactionNotYours"
    public static let transactionProviderMismatch = "TransactionProviderMismatch"
    public static let paymentNotVerified = "PaymentNotVerified"
    public static let checkoutIdRequired = "CheckoutIdRequired"
    public static let processorError = "ProcessorError"
    public static let subscriptionNotCreated = "SubscriptionNotCreated"
}

// MARK: - Add-on subscription lifecycle

/// The `errorCode` values the pack lifecycle returns (the server's
/// `AddOnSubscriptionErrorCodes`).
public enum AddOnSubscriptionErrorCodes {
    public static let notFound = "addon_subscription_not_found"
    public static let forbidden = "addon_subscription_forbidden"
    public static let providerRefused = "addon_subscription_provider_refused"
    public static let notPendingCancellation = "addon_subscription_not_pending_cancellation"
    public static let notProviderBilled = "addon_subscription_not_provider_billed"
    public static let error = "addon_subscription_error"
}

/// Codes the SDK itself supplies when the server sent none.
public enum AppTierActionErrorCodes {
    /// The route is absent — a server older than this SDK.
    public static let notSupported = "NotSupported"
    /// The request never got a structured answer.
    public static let requestFailed = "RequestFailed"
}

/// A refusal an add-on/tier action reports instead of throwing.
///
/// ``code`` is the server's own error code when it sent one; otherwise
/// ``AppTierActionErrorCodes/notSupported`` or ``AppTierActionErrorCodes/requestFailed``.
public struct AppTierActionError: Codable, Sendable, Equatable {
    public var code: String
    public var message: String
    /// HTTP status, when the failure got that far.
    public var status: Int?

    public init(code: String = "", message: String = "", status: Int? = nil) {
        self.code = code
        self.message = message
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        status = try c.decodeIfPresent(Int.self, forKey: .status)
    }
}

/// Result of subscribing to a single pack. The JS union
/// (`{success:true, subscription?} | {success:false, error}`) flattens to one struct in the idiom
/// ``AppTierCancelResultModel`` already uses: on success ``error`` is nil, on failure
/// ``subscription`` is.
public struct AddOnSubscribeResultModel: Codable, Sendable, Equatable {
    public var success: Bool
    public var subscription: UserAddOnSubscriptionModel?
    public var error: AppTierActionError?

    public init(
        success: Bool = false,
        subscription: UserAddOnSubscriptionModel? = nil,
        error: AppTierActionError? = nil
    ) {
        self.success = success
        self.subscription = subscription
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        subscription = try c.decodeIfPresent(UserAddOnSubscriptionModel.self, forKey: .subscription)
        error = try c.decodeIfPresent(AppTierActionError.self, forKey: .error)
    }
}

/// Result of cancelling a pack. `isScheduled == true` means access continues until
/// ``effectiveDate`` (the end of the period already paid for); false means it ended now.
public struct AddOnSubscriptionCancelResultModel: Codable, Sendable, Equatable {
    public var success: Bool
    public var isScheduled: Bool?
    /// The row's status after the call.
    public var status: String?
    public var effectiveDate: Date?
    public var errorCode: String?
    public var errorMessage: String?

    public init(
        success: Bool = false,
        isScheduled: Bool? = nil,
        status: String? = nil,
        effectiveDate: Date? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.success = success
        self.isScheduled = isScheduled
        self.status = status
        self.effectiveDate = effectiveDate
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        isScheduled = try c.decodeIfPresent(Bool.self, forKey: .isScheduled)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        effectiveDate = try c.decodeIfPresent(Date.self, forKey: .effectiveDate)
        errorCode = try c.decodeIfPresent(String.self, forKey: .errorCode)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

/// Result of clearing a scheduled pack cancellation.
public struct AddOnSubscriptionReactivateResultModel: Codable, Sendable, Equatable {
    public var success: Bool
    public var status: String?
    /// The refreshed subscription, so a client can render the restored status without a re-read.
    public var subscription: UserAddOnSubscriptionModel?
    public var errorCode: String?
    public var errorMessage: String?

    public init(
        success: Bool = false,
        status: String? = nil,
        subscription: UserAddOnSubscriptionModel? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.success = success
        self.status = status
        self.subscription = subscription
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        status = try c.decodeIfPresent(String.self, forKey: .status)
        subscription = try c.decodeIfPresent(UserAddOnSubscriptionModel.self, forKey: .subscription)
        errorCode = try c.decodeIfPresent(String.self, forKey: .errorCode)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}
