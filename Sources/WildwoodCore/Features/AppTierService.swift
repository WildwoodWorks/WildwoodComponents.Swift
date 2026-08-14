// App tier service ported from @wildwood/core/src/features/appTierService.ts
// (itself a port of WildwoodComponents.Blazor/Services/AppTierComponentService.cs).

import Foundation

public final class AppTierService: Sendable {
    private let http: WildwoodHttpClient

    public init(http: WildwoodHttpClient) {
        self.http = http
    }

    private func encodePath(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func encodeQuery(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    // MARK: - Tier browsing

    /// Available tiers via the public endpoint (works unauthenticated).
    public func getTiers(appId: String) async -> [AppTierModel] {
        let data: [AppTierModel]? = try? await http.get("api/app-tiers/\(appId)/public", skipAuth: true)
        return data ?? []
    }

    /// All tiers including non-public ones (authenticated endpoint).
    public func getAllTiers(appId: String) async -> [AppTierModel] {
        let data: [AppTierModel]? = try? await http.get("api/app-tiers/\(appId)")
        return data ?? []
    }

    public func getTier(tierId: String) async -> AppTierModel? {
        try? await http.get("api/app-tiers/tier/\(tierId)")
    }

    /// Alias of getTiers — same public endpoint, kept for cross-stack API parity.
    public func getPublicTiers(appId: String) async -> [AppTierModel] {
        await getTiers(appId: appId)
    }

    public func getAvailableAddOns(appId: String) async -> [AppTierAddOnModel] {
        let data: [AppTierAddOnModel]? = try? await http.get("api/app-tier-addons/\(appId)/available")
        return data ?? []
    }

    public func getAllAddOns(appId: String) async -> [AppTierAddOnModel] {
        let data: [AppTierAddOnModel]? = try? await http.get("api/app-tier-addons/\(appId)")
        return data ?? []
    }

    /// The app's Active add-ons with their pricing options, via the public endpoint
    /// (works unauthenticated) — the add-on twin of getPublicTiers(), so a public
    /// pricing page can list the packs an app sells alongside its tiers.
    ///
    /// THROWS on failure, unlike the add-on getters above, which swallow and return [].
    /// That is deliberate and matches the JS core service: a public page has to be able
    /// to tell "this app sells no packs" from "the catalog failed to load", and an
    /// empty array cannot express the second.
    public func getPublicAddOns(appId: String) async throws -> [AppTierAddOnModel] {
        let data: [AppTierAddOnModel]? = try await http.get("api/app-tier-addons/\(appId)/public", skipAuth: true)
        return data ?? []
    }

    // MARK: - User subscription

    /// The user's active subscription, or nil ONLY when none exists
    /// (204/empty body, or 404 — the backend answers "no subscription" with
    /// 404). THROWS on every other transport/HTTP failure so callers can
    /// distinguish "no subscription" from a failed lookup — swallowing both
    /// as nil made subscribed users look unsubscribed during transient errors.
    public func getUserSubscription(appId: String?) async throws -> UserTierSubscriptionModel? {
        guard let appId, !appId.isEmpty else { return nil }
        do {
            return try await http.get("api/app-tiers/\(appId)/my-subscription")
        } catch let error as WildwoodError where error.status == 404 {
            // 404 = "no subscription" per backend behavior — a real answer,
            // not a failure. Transient failures (5xx/network/timeout) still throw.
            return nil
        }
    }

    public func getUserAddOns(appId: String) async -> [UserAddOnSubscriptionModel] {
        let data: [UserAddOnSubscriptionModel]? = try? await http.get("api/app-tier-addons/\(appId)/my-addons")
        return data ?? []
    }

    // MARK: - Tier subscription actions

    /// Self-service tier change. Pass `paymentTransactionId` when upgrading from
    /// a free tier to a paid tier.
    public func changeTier(
        appId: String,
        newTierId: String,
        newPricingId: String? = nil,
        immediate: Bool = true,
        paymentTransactionId: String? = nil
    ) async throws -> AppTierChangeResultModel {
        struct SelfChangeTierDto: Encodable {
            let NewAppTierId: String
            let NewAppTierPricingId: String?
            let Immediate: Bool
            let PaymentTransactionId: String?
        }
        return try await http.post(
            "api/app-tiers/\(appId)/my-subscription/change",
            body: SelfChangeTierDto(
                NewAppTierId: newTierId,
                NewAppTierPricingId: newPricingId,
                Immediate: immediate,
                PaymentTransactionId: paymentTransactionId
            )
        )
    }

    /// Admin tier change (requires Admin/CompanyAdmin role).
    public func changeTierAdvanced(
        appId: String,
        userId: String,
        newTierId: String,
        newPricingId: String? = nil,
        immediate: Bool = false
    ) async throws -> AppTierChangeResultModel {
        struct ChangeAppTierDto: Encodable {
            let AppId: String
            let UserId: String
            let NewAppTierId: String
            let NewAppTierPricingId: String?
            let Immediate: Bool
        }
        return try await http.post(
            "api/app-tiers/change-tier",
            body: ChangeAppTierDto(
                AppId: appId,
                UserId: userId,
                NewAppTierId: newTierId,
                NewAppTierPricingId: newPricingId,
                Immediate: immediate
            )
        )
    }

    /// Self-service cancellation. On 2xx the cancellation succeeded — the
    /// payload reports whether it is scheduled for the end of the billing
    /// period (isScheduled + effectiveDate) or immediate, and whether the
    /// user must also act in their store (requiresUserAction — App Store
    /// billing can't be stopped server-side). Failures are reported via
    /// success/errorMessage, never thrown.
    public func cancelSubscription(appId: String) async -> AppTierCancelResultModel {
        await cancelResult { try await self.http.post("api/app-tiers/\(appId)/my-subscription/cancel") }
    }

    /// Shared POST handling for the three cancel endpoints: 2xx → payload
    /// with success=true (an empty 2xx body still succeeds); failure →
    /// success=false + errorMessage instead of being silently swallowed.
    private func cancelResult(
        _ send: () async throws -> AppTierCancelResultModel?
    ) async -> AppTierCancelResultModel {
        do {
            var result = try await send() ?? AppTierCancelResultModel()
            result.success = true
            return result
        } catch {
            return AppTierCancelResultModel(
                success: false,
                errorMessage: (error as? WildwoodError)?.message ?? error.localizedDescription
            )
        }
    }

    /// Self-service subscribe during signup or plan selection.
    public func selfSubscribe(
        appId: String,
        appTierId: String,
        appTierPricingId: String? = nil,
        paymentTransactionId: String? = nil
    ) async throws -> AppTierChangeResultModel {
        struct SelfSubscribeDto: Encodable {
            let AppTierId: String
            let AppTierPricingId: String?
            let PaymentTransactionId: String?
        }
        return try await http.post(
            "api/app-tiers/\(appId)/my-subscription",
            body: SelfSubscribeDto(
                AppTierId: appTierId,
                AppTierPricingId: appTierPricingId,
                PaymentTransactionId: paymentTransactionId
            )
        )
    }

    public func previewTierChange(appId: String, newTierId: String, newPricingId: String? = nil) async throws -> TierChangePreviewModel {
        struct PreviewDto: Encodable {
            let NewAppTierId: String
            let NewAppTierPricingId: String?
        }
        return try await http.post(
            "api/app-tiers/\(appId)/my-subscription/preview-change",
            body: PreviewDto(NewAppTierId: newTierId, NewAppTierPricingId: newPricingId)
        )
    }

    public func previewTierChangeAdmin(
        appId: String,
        userId: String,
        newTierId: String,
        newPricingId: String? = nil
    ) async throws -> TierChangePreviewModel {
        struct PreviewDto: Encodable {
            let NewAppTierId: String
            let NewAppTierPricingId: String?
        }
        return try await http.post(
            "api/app-tiers/\(appId)/admin/preview-change/\(userId)",
            body: PreviewDto(NewAppTierId: newTierId, NewAppTierPricingId: newPricingId)
        )
    }

    // MARK: - Add-on subscription actions

    public func subscribeToAddOn(
        appId: String,
        addOnId: String,
        pricingId: String? = nil,
        paymentTransactionId: String? = nil
    ) async -> Bool {
        struct SubscribeAddOnDto: Encodable {
            let AppId: String
            let AppTierAddOnId: String
            let AppTierAddOnPricingId: String?
            let PaymentTransactionId: String?
        }
        do {
            try await http.postVoid(
                "api/app-tier-addons/\(appId)/subscribe",
                body: SubscribeAddOnDto(
                    AppId: appId,
                    AppTierAddOnId: addOnId,
                    AppTierAddOnPricingId: pricingId,
                    PaymentTransactionId: paymentTransactionId
                )
            )
            return true
        } catch {
            return false
        }
    }

    public func cancelAddOnSubscription(subscriptionId: String) async -> Bool {
        do {
            try await http.postVoid("api/app-tier-addons/subscriptions/\(subscriptionId)/cancel")
            return true
        } catch {
            return false
        }
    }

    // MARK: - Usage tracking

    public func getAllLimitStatuses(appId: String) async -> [AppTierLimitStatusModel] {
        let data: [AppTierLimitStatusModel]? = try? await http.get("api/app-tiers/\(appId)/limit-statuses")
        return data ?? []
    }

    // MARK: - Feature gating

    /// The user's feature entitlement map. THROWS on transport/HTTP failure:
    /// an empty map is a real "no access" answer, so failures must stay
    /// distinguishable from it — swallowing them made feature gates lock
    /// entitled users out during transient errors.
    public func getUserFeatures(appId: String) async throws -> [String: Bool] {
        let data: [String: Bool]? = try await http.get("api/app-tiers/\(appId)/user-features")
        return data ?? [:]
    }

    public func checkFeature(featureKey: String, appId: String) async throws -> AppFeatureCheckResultModel {
        try await http.get("api/app-tiers/\(appId)/check-feature/\(encodePath(featureKey))")
    }

    public func getLimitStatus(limitKey: String, appId: String) async throws -> AppTierLimitStatusModel {
        try await http.get("api/app-tiers/\(appId)/check-limit/\(encodePath(limitKey))")
    }

    public func incrementUsage(appId: String, limitCode: String) async -> AppTierLimitStatusModel? {
        try? await http.post("api/app-tiers/\(appId)/increment-usage/\(encodePath(limitCode))")
    }

    // MARK: - Feature definitions

    public func getFeatureDefinitions(appId: String) async -> [AppFeatureDefinitionModel] {
        let data: [AppFeatureDefinitionModel]? = try? await http.get("api/app-feature-definitions/\(appId)?activeOnly=true")
        return data ?? []
    }

    /// Active feature definitions for the current user (no admin role required).
    public func getActiveFeatureDefinitions(appId: String) async -> [AppFeatureDefinitionModel] {
        let data: [AppFeatureDefinitionModel]? = try? await http.get("api/app-feature-definitions/\(appId)/active")
        return data ?? []
    }

    // MARK: - Company-scoped subscription (admin)

    public func getCompanySubscription(appId: String, companyId: String) async -> UserTierSubscriptionModel? {
        try? await http.get("api/app-tiers/\(appId)/subscription/company/\(companyId)")
    }

    public func getCompanyAddOnSubscriptions(appId: String, companyId: String) async -> [UserAddOnSubscriptionModel] {
        let data: [UserAddOnSubscriptionModel]? = try? await http.get("api/app-tier-addons/\(appId)/company/\(companyId)/addon-subscriptions")
        return data ?? []
    }

    public func getCompanyLimitStatuses(appId: String, companyId: String) async -> [AppTierLimitStatusModel] {
        let data: [AppTierLimitStatusModel]? = try? await http.get("api/app-tiers/\(appId)/limits/company/\(companyId)")
        return data ?? []
    }

    public func getCompanyFeatures(appId: String, companyId: String) async -> [String: Bool] {
        let data: [String: Bool]? = try? await http.get("api/app-tiers/\(appId)/admin/company-features/\(companyId)")
        return data ?? [:]
    }

    // MARK: - Company-scoped admin actions

    public func subscribeCompanyToTier(
        appId: String,
        companyId: String,
        tierId: String,
        pricingId: String? = nil
    ) async throws -> AppTierChangeResultModel {
        struct SubscribeCompanyDto: Encodable {
            let CompanyId: String
            let AppTierId: String
            let AppTierPricingId: String?
        }
        return try await http.post(
            "api/app-tiers/\(appId)/subscribe/company",
            body: SubscribeCompanyDto(CompanyId: companyId, AppTierId: tierId, AppTierPricingId: pricingId)
        )
    }

    public func changeCompanyTier(
        appId: String,
        companyId: String,
        newTierId: String,
        pricingId: String? = nil,
        immediate: Bool = false
    ) async throws -> AppTierChangeResultModel {
        struct ChangeCompanyTierDto: Encodable {
            let CompanyId: String
            let NewAppTierId: String
            let NewAppTierPricingId: String?
            let Immediate: Bool
        }
        return try await http.post(
            "api/app-tiers/\(appId)/change-tier/company",
            body: ChangeCompanyTierDto(CompanyId: companyId, NewAppTierId: newTierId, NewAppTierPricingId: pricingId, Immediate: immediate)
        )
    }

    public func cancelCompanySubscription(appId: String, companyId: String) async -> AppTierCancelResultModel {
        await cancelResult { try await self.http.post("api/app-tiers/\(appId)/cancel/company/\(companyId)") }
    }

    public func subscribeCompanyToAddOn(appId: String, companyId: String, addOnId: String) async -> Bool {
        struct SubscribeCompanyAddOnDto: Encodable {
            let CompanyId: String
            let AppTierAddOnId: String
        }
        do {
            try await http.postVoid(
                "api/app-tier-addons/\(appId)/subscribe/company",
                body: SubscribeCompanyAddOnDto(CompanyId: companyId, AppTierAddOnId: addOnId)
            )
            return true
        } catch {
            return false
        }
    }

    public func cancelCompanyAddOn(subscriptionId: String, immediate: Bool = false) async -> Bool {
        do {
            try await http.postVoid("api/app-tier-addons/subscriptions/\(subscriptionId)/cancel?immediate=\(immediate)")
            return true
        } catch {
            return false
        }
    }

    // MARK: - User-scoped admin queries

    public func getUserSubscriptionAdmin(appId: String, userId: String) async -> UserTierSubscriptionModel? {
        try? await http.get("api/app-tiers/\(appId)/subscriptions/\(userId)")
    }

    public func getUserFeaturesAdmin(appId: String, userId: String) async -> [String: Bool] {
        let data: [String: Bool]? = try? await http.get("api/app-tiers/\(appId)/admin/user-features/\(userId)")
        return data ?? [:]
    }

    public func getUserLimitStatuses(appId: String, userId: String) async -> [AppTierLimitStatusModel] {
        let data: [AppTierLimitStatusModel]? = try? await http.get("api/app-tiers/\(appId)/admin/user-limits/\(userId)")
        return data ?? []
    }

    public func getUserAddOnsAdmin(appId: String, userId: String) async -> [UserAddOnSubscriptionModel] {
        let data: [UserAddOnSubscriptionModel]? = try? await http.get("api/app-tier-addons/\(appId)/admin/user-addons/\(userId)")
        return data ?? []
    }

    // MARK: - User-scoped admin actions

    public func subscribeUserToTier(
        appId: String,
        userId: String,
        tierId: String,
        pricingId: String? = nil
    ) async throws -> AppTierChangeResultModel {
        struct SubscribeUserDto: Encodable {
            let AppId: String
            let UserId: String
            let AppTierId: String
            let AppTierPricingId: String?
        }
        return try await http.post(
            "api/app-tiers/subscribe",
            body: SubscribeUserDto(AppId: appId, UserId: userId, AppTierId: tierId, AppTierPricingId: pricingId)
        )
    }

    public func changeUserTier(
        appId: String,
        userId: String,
        newTierId: String,
        pricingId: String? = nil,
        immediate: Bool = false
    ) async throws -> AppTierChangeResultModel {
        try await changeTierAdvanced(appId: appId, userId: userId, newTierId: newTierId, newPricingId: pricingId, immediate: immediate)
    }

    public func cancelUserSubscription(appId: String, userId: String) async -> AppTierCancelResultModel {
        await cancelResult { try await self.http.post("api/app-tiers/\(appId)/cancel/\(userId)") }
    }

    public func subscribeUserToAddOn(appId: String, userId: String, addOnId: String) async -> Bool {
        struct AddOnDto: Encodable {
            let AppTierAddOnId: String
        }
        do {
            try await http.postVoid(
                "api/app-tier-addons/\(appId)/admin/subscribe-user/\(userId)",
                body: AddOnDto(AppTierAddOnId: addOnId)
            )
            return true
        } catch {
            return false
        }
    }

    public func cancelUserAddOn(appId: String, subscriptionId: String) async -> Bool {
        do {
            try await http.postVoid("api/app-tier-addons/\(appId)/admin/cancel-user-addon/\(subscriptionId)")
            return true
        } catch {
            return false
        }
    }

    // MARK: - Feature overrides (admin)

    public func getFeatureOverrides(appId: String, userId: String? = nil) async -> [AppFeatureOverrideModel] {
        let query = userId.map { "?userId=\(encodeQuery($0))" } ?? ""
        let data: [AppFeatureOverrideModel]? = try? await http.get("api/app-tiers/\(appId)/admin/feature-overrides\(query)")
        return data ?? []
    }

    public func setFeatureOverride(
        appId: String,
        userId: String?,
        featureCode: String,
        isEnabled: Bool,
        reason: String? = nil,
        expiresAt: Date? = nil
    ) async -> Bool {
        struct OverrideDto: Encodable {
            let UserId: String?
            let FeatureCode: String
            let IsEnabled: Bool
            let Reason: String?
            let ExpiresAt: Date?
        }
        do {
            try await http.postVoid(
                "api/app-tiers/\(appId)/admin/feature-overrides",
                body: OverrideDto(UserId: userId, FeatureCode: featureCode, IsEnabled: isEnabled, Reason: reason, ExpiresAt: expiresAt)
            )
            return true
        } catch {
            return false
        }
    }

    public func removeFeatureOverride(appId: String, featureCode: String, userId: String? = nil) async -> Bool {
        let query = userId.map { "?userId=\(encodeQuery($0))" } ?? ""
        do {
            try await http.deleteVoid("api/app-tiers/\(appId)/admin/feature-overrides/\(encodePath(featureCode))\(query)")
            return true
        } catch {
            return false
        }
    }

    // MARK: - Admin usage limit overrides

    public func updateUsageLimit(appId: String, limitCode: String, newMaxValue: Double) async -> Bool {
        struct LimitDto: Encodable {
            let NewMaxValue: Double
        }
        do {
            try await http.putVoid(
                "api/app-tiers/\(appId)/admin/usage-limits/\(encodePath(limitCode))",
                body: LimitDto(NewMaxValue: newMaxValue)
            )
            return true
        } catch {
            return false
        }
    }

    public func resetUsage(appId: String, limitCode: String) async -> Bool {
        do {
            try await http.postVoid("api/app-tiers/\(appId)/admin/usage-limits/\(encodePath(limitCode))/reset")
            return true
        } catch {
            return false
        }
    }

    public func updateUserUsageLimit(appId: String, userId: String, limitCode: String, newMaxValue: Double) async -> Bool {
        struct LimitDto: Encodable {
            let NewMaxValue: Double
        }
        do {
            try await http.putVoid(
                "api/app-tiers/\(appId)/admin/usage-limits/user/\(userId)/\(encodePath(limitCode))",
                body: LimitDto(NewMaxValue: newMaxValue)
            )
            return true
        } catch {
            return false
        }
    }

    public func resetUserUsage(appId: String, userId: String, limitCode: String) async -> Bool {
        do {
            try await http.postVoid("api/app-tiers/\(appId)/admin/usage-limits/user/\(userId)/\(encodePath(limitCode))/reset")
            return true
        } catch {
            return false
        }
    }

    public func updateCompanyUsageLimit(appId: String, companyId: String, limitCode: String, newMaxValue: Double) async -> Bool {
        struct LimitDto: Encodable {
            let NewMaxValue: Double
        }
        do {
            try await http.putVoid(
                "api/app-tiers/\(appId)/admin/usage-limits/company/\(companyId)/\(encodePath(limitCode))",
                body: LimitDto(NewMaxValue: newMaxValue)
            )
            return true
        } catch {
            return false
        }
    }

    public func resetCompanyUsage(appId: String, companyId: String, limitCode: String) async -> Bool {
        do {
            try await http.postVoid("api/app-tiers/\(appId)/admin/usage-limits/company/\(companyId)/\(encodePath(limitCode))/reset")
            return true
        } catch {
            return false
        }
    }

    // MARK: - Settings

    public func getTrackingMode(appId: String) async -> String {
        struct TrackingModeResponse: Decodable {
            var trackingMode: String?
        }
        let data: TrackingModeResponse? = try? await http.get("api/app-tiers/\(appId)/settings/tracking-mode")
        return data?.trackingMode ?? "User"
    }
}
