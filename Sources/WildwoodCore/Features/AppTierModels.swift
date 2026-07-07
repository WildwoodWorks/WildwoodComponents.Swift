// App tier models ported from @wildwood/core/src/features/types.ts
// (itself a port of WildwoodComponents.Shared/Models/AppTierModels.cs).

import Foundation

public struct AppTierModel: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var appId: String
    public var name: String
    public var description: String
    public var displayOrder: Int
    public var isDefault: Bool
    public var isFreeTier: Bool
    public var allowUpgrades: Bool
    public var allowDowngrades: Bool
    public var status: String
    public var badgeColor: String
    public var iconClass: String
    public var showSubscribeButton: Bool
    public var showContactButton: Bool
    public var contactButtonUrl: String?
    public var showPrice: Bool
    public var customBadgeText: String?
    public var pricingOptions: [AppTierPricingModel]
    public var features: [AppTierFeatureModel]
    public var limits: [AppTierLimitModel]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        appId = try c.decodeIfPresent(String.self, forKey: .appId) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        displayOrder = try c.decodeIfPresent(Int.self, forKey: .displayOrder) ?? 0
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        isFreeTier = try c.decodeIfPresent(Bool.self, forKey: .isFreeTier) ?? false
        allowUpgrades = try c.decodeIfPresent(Bool.self, forKey: .allowUpgrades) ?? true
        allowDowngrades = try c.decodeIfPresent(Bool.self, forKey: .allowDowngrades) ?? true
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        badgeColor = try c.decodeIfPresent(String.self, forKey: .badgeColor) ?? ""
        iconClass = try c.decodeIfPresent(String.self, forKey: .iconClass) ?? ""
        showSubscribeButton = try c.decodeIfPresent(Bool.self, forKey: .showSubscribeButton) ?? true
        showContactButton = try c.decodeIfPresent(Bool.self, forKey: .showContactButton) ?? false
        contactButtonUrl = try c.decodeIfPresent(String.self, forKey: .contactButtonUrl)
        showPrice = try c.decodeIfPresent(Bool.self, forKey: .showPrice) ?? true
        customBadgeText = try c.decodeIfPresent(String.self, forKey: .customBadgeText)
        pricingOptions = try c.decodeIfPresent([AppTierPricingModel].self, forKey: .pricingOptions) ?? []
        features = try c.decodeIfPresent([AppTierFeatureModel].self, forKey: .features) ?? []
        limits = try c.decodeIfPresent([AppTierLimitModel].self, forKey: .limits) ?? []
    }
}

public struct AppTierPricingModel: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var appTierId: String
    public var pricingModelId: String
    public var isDefault: Bool
    public var displayOrder: Int
    public var pricingModelName: String
    public var price: Double
    public var billingFrequency: String
    public var billingFrequencyLabel: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        appTierId = try c.decodeIfPresent(String.self, forKey: .appTierId) ?? ""
        pricingModelId = try c.decodeIfPresent(String.self, forKey: .pricingModelId) ?? ""
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        displayOrder = try c.decodeIfPresent(Int.self, forKey: .displayOrder) ?? 0
        pricingModelName = try c.decodeIfPresent(String.self, forKey: .pricingModelName) ?? ""
        price = try c.decodeIfPresent(Double.self, forKey: .price) ?? 0
        billingFrequency = try c.decodeIfPresent(String.self, forKey: .billingFrequency) ?? ""
        billingFrequencyLabel = try c.decodeIfPresent(String.self, forKey: .billingFrequencyLabel)
    }
}

public struct AppTierFeatureModel: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var featureCode: String
    public var displayName: String
    public var description: String
    public var isEnabled: Bool
    public var category: String

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        featureCode = try c.decodeIfPresent(String.self, forKey: .featureCode) ?? ""
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
    }
}

public struct AppTierLimitModel: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var limitCode: String
    public var displayName: String
    public var maxValue: Double
    public var limitType: String
    public var unit: String
    public var isUnlimited: Bool
    public var maxValueDisplay: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        limitCode = try c.decodeIfPresent(String.self, forKey: .limitCode) ?? ""
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        maxValue = try c.decodeIfPresent(Double.self, forKey: .maxValue) ?? 0
        limitType = try c.decodeIfPresent(String.self, forKey: .limitType) ?? ""
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        isUnlimited = try c.decodeIfPresent(Bool.self, forKey: .isUnlimited) ?? false
        maxValueDisplay = try c.decodeIfPresent(String.self, forKey: .maxValueDisplay)
    }
}

public struct AppTierAddOnModel: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var appId: String
    public var name: String
    public var description: String
    public var category: String
    public var status: String
    public var displayOrder: Int
    public var iconClass: String
    public var badgeColor: String
    public var trialDays: Int?
    public var features: [AppTierAddOnFeatureModel]
    public var pricingOptions: [AppTierAddOnPricingModel]
    public var bundledInTierIds: [String]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        appId = try c.decodeIfPresent(String.self, forKey: .appId) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        displayOrder = try c.decodeIfPresent(Int.self, forKey: .displayOrder) ?? 0
        iconClass = try c.decodeIfPresent(String.self, forKey: .iconClass) ?? ""
        badgeColor = try c.decodeIfPresent(String.self, forKey: .badgeColor) ?? ""
        trialDays = try c.decodeIfPresent(Int.self, forKey: .trialDays)
        features = try c.decodeIfPresent([AppTierAddOnFeatureModel].self, forKey: .features) ?? []
        pricingOptions = try c.decodeIfPresent([AppTierAddOnPricingModel].self, forKey: .pricingOptions) ?? []
        bundledInTierIds = try c.decodeIfPresent([String].self, forKey: .bundledInTierIds) ?? []
    }
}

public struct AppTierAddOnFeatureModel: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var featureCode: String
    public var displayName: String
    public var description: String

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        featureCode = try c.decodeIfPresent(String.self, forKey: .featureCode) ?? ""
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}

public struct AppTierAddOnPricingModel: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var pricingModelId: String
    public var pricingModelName: String
    public var price: Double
    public var billingFrequency: String
    public var isDefault: Bool

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        pricingModelId = try c.decodeIfPresent(String.self, forKey: .pricingModelId) ?? ""
        pricingModelName = try c.decodeIfPresent(String.self, forKey: .pricingModelName) ?? ""
        price = try c.decodeIfPresent(Double.self, forKey: .price) ?? 0
        billingFrequency = try c.decodeIfPresent(String.self, forKey: .billingFrequency) ?? ""
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }
}

public struct UserTierSubscriptionModel: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var userId: String
    public var appId: String
    public var appTierId: String
    public var appTierPricingId: String?
    public var status: String
    public var paymentTransactionId: String?
    public var startDate: Date?
    public var endDate: Date?
    public var currentPeriodStart: Date?
    public var currentPeriodEnd: Date?
    public var trialEndDate: Date?
    public var gracePeriodEndDate: Date?
    public var pendingTierId: String?
    public var tierName: String
    public var tierDescription: String
    public var isFreeTier: Bool
    public var pendingTierName: String
    public var pendingChangeDate: Date?
    public var companyId: String?
    public var companyName: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
        appId = try c.decodeIfPresent(String.self, forKey: .appId) ?? ""
        appTierId = try c.decodeIfPresent(String.self, forKey: .appTierId) ?? ""
        appTierPricingId = try c.decodeIfPresent(String.self, forKey: .appTierPricingId)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        paymentTransactionId = try c.decodeIfPresent(String.self, forKey: .paymentTransactionId)
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        currentPeriodStart = try c.decodeIfPresent(Date.self, forKey: .currentPeriodStart)
        currentPeriodEnd = try c.decodeIfPresent(Date.self, forKey: .currentPeriodEnd)
        trialEndDate = try c.decodeIfPresent(Date.self, forKey: .trialEndDate)
        gracePeriodEndDate = try c.decodeIfPresent(Date.self, forKey: .gracePeriodEndDate)
        pendingTierId = try c.decodeIfPresent(String.self, forKey: .pendingTierId)
        tierName = try c.decodeIfPresent(String.self, forKey: .tierName) ?? ""
        tierDescription = try c.decodeIfPresent(String.self, forKey: .tierDescription) ?? ""
        isFreeTier = try c.decodeIfPresent(Bool.self, forKey: .isFreeTier) ?? false
        pendingTierName = try c.decodeIfPresent(String.self, forKey: .pendingTierName) ?? ""
        pendingChangeDate = try c.decodeIfPresent(Date.self, forKey: .pendingChangeDate)
        companyId = try c.decodeIfPresent(String.self, forKey: .companyId)
        companyName = try c.decodeIfPresent(String.self, forKey: .companyName)
    }
}

public struct UserAddOnSubscriptionModel: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var companyId: String?
    public var appTierAddOnId: String
    public var status: String
    public var addOnName: String
    public var addOnDescription: String
    public var isBundled: Bool
    public var startDate: Date?
    public var endDate: Date?
    public var currentPeriodStart: Date?
    public var currentPeriodEnd: Date?
    public var trialEndDate: Date?
    public var gracePeriodEndDate: Date?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        companyId = try c.decodeIfPresent(String.self, forKey: .companyId)
        appTierAddOnId = try c.decodeIfPresent(String.self, forKey: .appTierAddOnId) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        addOnName = try c.decodeIfPresent(String.self, forKey: .addOnName) ?? ""
        addOnDescription = try c.decodeIfPresent(String.self, forKey: .addOnDescription) ?? ""
        isBundled = try c.decodeIfPresent(Bool.self, forKey: .isBundled) ?? false
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        currentPeriodStart = try c.decodeIfPresent(Date.self, forKey: .currentPeriodStart)
        currentPeriodEnd = try c.decodeIfPresent(Date.self, forKey: .currentPeriodEnd)
        trialEndDate = try c.decodeIfPresent(Date.self, forKey: .trialEndDate)
        gracePeriodEndDate = try c.decodeIfPresent(Date.self, forKey: .gracePeriodEndDate)
    }
}

public struct AppFeatureCheckResultModel: Codable, Sendable, Equatable {
    public var featureCode: String
    public var displayName: String
    public var hasAccess: Bool
    public var currentTierName: String
    public var requiredTierName: String
    public var upgradeMessage: String
    public var availableAsAddOn: Bool
    public var addOnId: String
    public var addOnName: String
    public var addOnPrice: Double?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        featureCode = try c.decodeIfPresent(String.self, forKey: .featureCode) ?? ""
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        hasAccess = try c.decodeIfPresent(Bool.self, forKey: .hasAccess) ?? false
        currentTierName = try c.decodeIfPresent(String.self, forKey: .currentTierName) ?? ""
        requiredTierName = try c.decodeIfPresent(String.self, forKey: .requiredTierName) ?? ""
        upgradeMessage = try c.decodeIfPresent(String.self, forKey: .upgradeMessage) ?? ""
        availableAsAddOn = try c.decodeIfPresent(Bool.self, forKey: .availableAsAddOn) ?? false
        addOnId = try c.decodeIfPresent(String.self, forKey: .addOnId) ?? ""
        addOnName = try c.decodeIfPresent(String.self, forKey: .addOnName) ?? ""
        addOnPrice = try c.decodeIfPresent(Double.self, forKey: .addOnPrice)
    }
}

public struct AppTierLimitStatusModel: Codable, Sendable, Equatable, Identifiable {
    public var limitCode: String
    public var displayName: String
    public var currentUsage: Double
    public var maxValue: Double
    public var isUnlimited: Bool
    public var usagePercent: Double
    public var isAtWarningThreshold: Bool
    public var isExceeded: Bool
    public var isHardBlocked: Bool
    public var unit: String
    public var statusMessage: String

    public var id: String { limitCode }

    public init(
        limitCode: String,
        displayName: String = "",
        currentUsage: Double = 0,
        maxValue: Double = 0,
        isUnlimited: Bool = false,
        usagePercent: Double = 0,
        isAtWarningThreshold: Bool = false,
        isExceeded: Bool = false,
        isHardBlocked: Bool = false,
        unit: String = "",
        statusMessage: String = ""
    ) {
        self.limitCode = limitCode
        self.displayName = displayName
        self.currentUsage = currentUsage
        self.maxValue = maxValue
        self.isUnlimited = isUnlimited
        self.usagePercent = usagePercent
        self.isAtWarningThreshold = isAtWarningThreshold
        self.isExceeded = isExceeded
        self.isHardBlocked = isHardBlocked
        self.unit = unit
        self.statusMessage = statusMessage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        limitCode = try c.decodeIfPresent(String.self, forKey: .limitCode) ?? ""
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        currentUsage = try c.decodeIfPresent(Double.self, forKey: .currentUsage) ?? 0
        maxValue = try c.decodeIfPresent(Double.self, forKey: .maxValue) ?? 0
        isUnlimited = try c.decodeIfPresent(Bool.self, forKey: .isUnlimited) ?? false
        usagePercent = try c.decodeIfPresent(Double.self, forKey: .usagePercent) ?? 0
        isAtWarningThreshold = try c.decodeIfPresent(Bool.self, forKey: .isAtWarningThreshold) ?? false
        isExceeded = try c.decodeIfPresent(Bool.self, forKey: .isExceeded) ?? false
        isHardBlocked = try c.decodeIfPresent(Bool.self, forKey: .isHardBlocked) ?? false
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        statusMessage = try c.decodeIfPresent(String.self, forKey: .statusMessage) ?? ""
    }
}

public struct AppFeatureDefinitionModel: Codable, Sendable, Equatable, Identifiable {
    public var featureCode: String
    public var displayName: String
    public var description: String
    public var category: String
    public var iconClass: String
    public var displayOrder: Int
    public var isEnabled: Bool

    public var id: String { featureCode }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        featureCode = try c.decodeIfPresent(String.self, forKey: .featureCode) ?? ""
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        iconClass = try c.decodeIfPresent(String.self, forKey: .iconClass) ?? ""
        displayOrder = try c.decodeIfPresent(Int.self, forKey: .displayOrder) ?? 0
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
    }
}

public struct AppTierChangeResultModel: Codable, Sendable, Equatable {
    public var success: Bool
    public var errorMessage: String
    public var subscription: UserTierSubscriptionModel?
    public var isScheduled: Bool
    public var effectiveDate: Date?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage) ?? ""
        subscription = try c.decodeIfPresent(UserTierSubscriptionModel.self, forKey: .subscription)
        isScheduled = try c.decodeIfPresent(Bool.self, forKey: .isScheduled) ?? false
        effectiveDate = try c.decodeIfPresent(Date.self, forKey: .effectiveDate)
    }
}

/// Result of a subscription cancellation. isScheduled=true means access
/// continues until effectiveDate (the end of the current billing period);
/// false means access ended immediately. requiresUserAction is set for
/// store-billed subscriptions (Apple App Store / Google Play): the platform
/// cannot stop the store's billing — show userActionInstructions /
/// userActionUrl so the user cancels in their store settings too.
public struct AppTierCancelResultModel: Codable, Sendable, Equatable {
    public var success: Bool
    public var errorMessage: String?
    public var isScheduled: Bool
    public var effectiveDate: Date?
    public var requiresUserAction: Bool
    public var userActionUrl: String?
    public var userActionInstructions: String?

    public init(
        success: Bool = false,
        errorMessage: String? = nil,
        isScheduled: Bool = false,
        effectiveDate: Date? = nil,
        requiresUserAction: Bool = false,
        userActionUrl: String? = nil,
        userActionInstructions: String? = nil
    ) {
        self.success = success
        self.errorMessage = errorMessage
        self.isScheduled = isScheduled
        self.effectiveDate = effectiveDate
        self.requiresUserAction = requiresUserAction
        self.userActionUrl = userActionUrl
        self.userActionInstructions = userActionInstructions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        isScheduled = try c.decodeIfPresent(Bool.self, forKey: .isScheduled) ?? false
        effectiveDate = try c.decodeIfPresent(Date.self, forKey: .effectiveDate)
        requiresUserAction = try c.decodeIfPresent(Bool.self, forKey: .requiresUserAction) ?? false
        userActionUrl = try c.decodeIfPresent(String.self, forKey: .userActionUrl)
        userActionInstructions = try c.decodeIfPresent(String.self, forKey: .userActionInstructions)
    }
}

public struct AppFeatureOverrideModel: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var appId: String
    public var companyId: String?
    public var userId: String?
    public var featureCode: String
    public var isEnabled: Bool
    public var reason: String?
    public var expiresAt: Date?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var createdBy: String?
    public var updatedBy: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        appId = try c.decodeIfPresent(String.self, forKey: .appId) ?? ""
        companyId = try c.decodeIfPresent(String.self, forKey: .companyId)
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
        featureCode = try c.decodeIfPresent(String.self, forKey: .featureCode) ?? ""
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy)
        updatedBy = try c.decodeIfPresent(String.self, forKey: .updatedBy)
    }
}

public struct TierChangePreviewModel: Codable, Sendable, Equatable {
    public var success: Bool
    public var errorMessage: String?
    public var isUpgrade: Bool
    public var isDowngrade: Bool
    public var isBillingFrequencyChange: Bool
    public var paymentRequired: Bool
    public var paymentBypassAllowed: Bool
    public var paymentProviderAvailable: Bool
    public var currentTierName: String?
    public var currentPrice: Double?
    public var currentBillingFrequency: String?
    public var newTierName: String?
    public var newPrice: Double?
    public var newBillingFrequency: String?
    public var monthlyEquivalentCurrent: Double?
    public var monthlyEquivalentNew: Double?
    public var proratedChargeToday: Double?
    public var creditAmount: Double?
    public var nextBillingAmount: Double?
    public var nextBillingDate: Date?
    public var effectiveDate: Date?
    public var featuresGained: [String]
    public var featuresLost: [String]
    public var currency: String
    public var daysRemainingInPeriod: Int
    public var allowImmediateChange: Bool
    public var allowScheduledChange: Bool

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        isUpgrade = try c.decodeIfPresent(Bool.self, forKey: .isUpgrade) ?? false
        isDowngrade = try c.decodeIfPresent(Bool.self, forKey: .isDowngrade) ?? false
        isBillingFrequencyChange = try c.decodeIfPresent(Bool.self, forKey: .isBillingFrequencyChange) ?? false
        paymentRequired = try c.decodeIfPresent(Bool.self, forKey: .paymentRequired) ?? false
        paymentBypassAllowed = try c.decodeIfPresent(Bool.self, forKey: .paymentBypassAllowed) ?? false
        paymentProviderAvailable = try c.decodeIfPresent(Bool.self, forKey: .paymentProviderAvailable) ?? false
        currentTierName = try c.decodeIfPresent(String.self, forKey: .currentTierName)
        currentPrice = try c.decodeIfPresent(Double.self, forKey: .currentPrice)
        currentBillingFrequency = try c.decodeIfPresent(String.self, forKey: .currentBillingFrequency)
        newTierName = try c.decodeIfPresent(String.self, forKey: .newTierName)
        newPrice = try c.decodeIfPresent(Double.self, forKey: .newPrice)
        newBillingFrequency = try c.decodeIfPresent(String.self, forKey: .newBillingFrequency)
        monthlyEquivalentCurrent = try c.decodeIfPresent(Double.self, forKey: .monthlyEquivalentCurrent)
        monthlyEquivalentNew = try c.decodeIfPresent(Double.self, forKey: .monthlyEquivalentNew)
        proratedChargeToday = try c.decodeIfPresent(Double.self, forKey: .proratedChargeToday)
        creditAmount = try c.decodeIfPresent(Double.self, forKey: .creditAmount)
        nextBillingAmount = try c.decodeIfPresent(Double.self, forKey: .nextBillingAmount)
        nextBillingDate = try c.decodeIfPresent(Date.self, forKey: .nextBillingDate)
        effectiveDate = try c.decodeIfPresent(Date.self, forKey: .effectiveDate)
        featuresGained = try c.decodeIfPresent([String].self, forKey: .featuresGained) ?? []
        featuresLost = try c.decodeIfPresent([String].self, forKey: .featuresLost) ?? []
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        daysRemainingInPeriod = try c.decodeIfPresent(Int.self, forKey: .daysRemainingInPeriod) ?? 0
        allowImmediateChange = try c.decodeIfPresent(Bool.self, forKey: .allowImmediateChange) ?? false
        allowScheduledChange = try c.decodeIfPresent(Bool.self, forKey: .allowScheduledChange) ?? false
    }
}
