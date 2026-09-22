// Subscription administration state — view-model equivalent of react-shared's
// useSubscriptionAdmin. Supports three scopes: the current user (self-service),
// a specific user (admin), and a company (admin). Company-scope tier-change
// preview falls back to the self endpoint (no company preview endpoint exists —
// standing parity decision).

import Foundation
import Observation
import WildwoodCore

public enum SubscriptionAdminScope: Sendable, Equatable {
    case currentUser
    case user(id: String)
    case company(id: String)

    public var isAdmin: Bool {
        if case .currentUser = self { return false }
        return true
    }
}

@MainActor
@Observable
public final class WildwoodSubscriptionAdminModel {
    @ObservationIgnored private let client: WildwoodClient
    @ObservationIgnored public let appId: String
    public var scope: SubscriptionAdminScope

    public private(set) var isLoading = false
    public var errorMessage = ""
    public var successMessage = ""

    public private(set) var subscription: UserTierSubscriptionModel?
    public private(set) var tiers: [AppTierModel] = []
    public private(set) var features: [String: Bool] = [:]
    public private(set) var featureDefinitions: [AppFeatureDefinitionModel] = []
    public private(set) var availableAddOns: [AppTierAddOnModel] = []
    public private(set) var addOnSubscriptions: [UserAddOnSubscriptionModel] = []
    public private(set) var limitStatuses: [AppTierLimitStatusModel] = []
    public private(set) var overrides: [AppFeatureOverrideModel] = []
    public private(set) var tierChangePreview: TierChangePreviewModel?

    /// Whether this account may still start a free trial, on the tier and per pack. Loaded by
    /// ``loadTrialEligibility()`` once the user is signed in; until then the catalog's advertised
    /// trial days are all a screen can honestly show (DD-6).
    public private(set) var trialEligibility: TrialEligibilityModel?

    /// Result of the most recent cancel action. Surfaced so the status panel
    /// can show requiresUserAction store instructions (App Store billing
    /// can't be stopped server-side — the user must also cancel there).
    public private(set) var lastCancelResult: AppTierCancelResultModel?

    /// The app bills through the App Store only. Packs have no in-app-purchase product mapping
    /// (pack checkout is card-only), so a pack PURCHASE cannot be offered here — rows the account
    /// already owns, bundled rows and granted rows still render, and cancelling still surfaces the
    /// store instructions the tier cancel already does.
    public private(set) var requiresAppStorePayment = false

    /// The currency the catalog quotes in, for a pack or plan that carries none of its own:
    /// the first tier that names one, else nil (which formats as USD).
    public var catalogCurrency: String? {
        for tier in tiers {
            if let currency = tier.currency, !currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return currency
            }
        }
        return nil
    }

    /// The plan the account is on, for the "Included in Plan" rule on a bundled pack.
    public var currentTierId: String? {
        guard let id = subscription?.appTierId, !id.isEmpty else { return nil }
        return id
    }

    public init(client: WildwoodClient, appId: String, scope: SubscriptionAdminScope = .currentUser) {
        self.client = client
        self.appId = appId
        self.scope = scope
    }

    public func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        async let status: Void = loadStatus()
        async let plans: Void = loadTiers()
        async let feats: Void = loadFeatures()
        async let addOns: Void = loadAddOns()
        async let limits: Void = loadLimits()
        async let ovr: Void = loadOverrides()
        async let platform: Void = loadPaymentPlatform()
        _ = await (status, plans, feats, addOns, limits, ovr, platform)
    }

    /// Read the app's platform-filtered payment configuration, which is what says whether Apple
    /// owns billing here. A failed lookup leaves the flag false: hiding a purchase affordance is
    /// the safe answer only when the server actually said so.
    public func loadPaymentPlatform() async {
        let providers = try? await client.payment.getAvailableProviders(appId: appId)
        requiresAppStorePayment = providers?.requiresAppStorePayment ?? false
    }

    // MARK: - Loads

    public func loadStatus() async {
        switch scope {
        case .currentUser:
            do {
                // nil = genuinely no subscription (204); lookup failures throw
                // and keep the last-known subscription (stale beats
                // wrongly-unsubscribed).
                subscription = try await client.appTier.getUserSubscription(appId: appId)
            } catch {
                handleError(error)
            }
        case .user(let userId):
            subscription = await client.appTier.getUserSubscriptionAdmin(appId: appId, userId: userId)
        case .company(let companyId):
            subscription = await client.appTier.getCompanySubscription(appId: appId, companyId: companyId)
        }
    }

    public func loadTiers() async {
        let all = await client.appTier.getAllTiers(appId: appId)
        tiers = (all.isEmpty ? await client.appTier.getTiers(appId: appId) : all)
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    public func loadFeatures() async {
        featureDefinitions = await client.appTier.getActiveFeatureDefinitions(appId: appId)
        switch scope {
        case .currentUser:
            do {
                features = try await client.appTier.getUserFeatures(appId: appId)
            } catch {
                // Keep the stale map — a transient failure must not make
                // entitled features look revoked.
                handleError(error)
            }
        case .user(let userId):
            features = await client.appTier.getUserFeaturesAdmin(appId: appId, userId: userId)
        case .company(let companyId):
            features = await client.appTier.getCompanyFeatures(appId: appId, companyId: companyId)
        }
    }

    public func loadAddOns() async {
        availableAddOns = await client.appTier.getAvailableAddOns(appId: appId)
        switch scope {
        case .currentUser:
            addOnSubscriptions = await client.appTier.getUserAddOns(appId: appId)
        case .user(let userId):
            addOnSubscriptions = await client.appTier.getUserAddOnsAdmin(appId: appId, userId: userId)
        case .company(let companyId):
            addOnSubscriptions = await client.appTier.getCompanyAddOnSubscriptions(appId: appId, companyId: companyId)
        }
    }

    public func loadLimits() async {
        switch scope {
        case .currentUser:
            limitStatuses = await client.appTier.getAllLimitStatuses(appId: appId)
        case .user(let userId):
            limitStatuses = await client.appTier.getUserLimitStatuses(appId: appId, userId: userId)
        case .company(let companyId):
            limitStatuses = await client.appTier.getCompanyLimitStatuses(appId: appId, companyId: companyId)
        }
    }

    public func loadOverrides() async {
        switch scope {
        case .currentUser:
            overrides = []
        case .user(let userId):
            overrides = await client.appTier.getFeatureOverrides(appId: appId, userId: userId)
        case .company:
            overrides = await client.appTier.getFeatureOverrides(appId: appId)
        }
    }

    // MARK: - Tier changes

    public func previewChange(to tier: AppTierModel, pricing: AppTierPricingModel?) async {
        clearMessages()
        do {
            switch scope {
            case .user(let userId):
                tierChangePreview = try await client.appTier.previewTierChangeAdmin(
                    appId: appId, userId: userId, newTierId: tier.id, newPricingId: pricing?.id
                )
            default:
                // Company scope falls back to the self preview endpoint.
                tierChangePreview = try await client.appTier.previewTierChange(
                    appId: appId, newTierId: tier.id, newPricingId: pricing?.id
                )
            }
        } catch {
            handleError(error)
        }
    }

    public func clearPreview() {
        tierChangePreview = nil
    }

    /// Price a change by ids rather than by model — what a driver holds. Answers nil when the
    /// server would not price it, having already set ``errorMessage``.
    ///
    /// Company scope falls back to the self preview endpoint (no company preview endpoint
    /// exists — standing parity decision).
    @discardableResult
    public func previewTierChange(tierId: String, pricingId: String?) async -> TierChangePreviewModel? {
        do {
            let preview: TierChangePreviewModel
            switch scope {
            case .user(let userId):
                preview = try await client.appTier.previewTierChangeAdmin(
                    appId: appId, userId: userId, newTierId: tierId, newPricingId: pricingId
                )
            case .currentUser, .company:
                preview = try await client.appTier.previewTierChange(
                    appId: appId, newTierId: tierId, newPricingId: pricingId
                )
            }
            guard preview.success else {
                errorMessage = preview.errorMessage ?? "The plan change could not be priced."
                tierChangePreview = nil
                return nil
            }
            tierChangePreview = preview
            return preview
        } catch {
            handleError(error)
            tierChangePreview = nil
            return nil
        }
    }

    /// Post a plan change, for a driver that already knows whether this is a change or a first
    /// subscribe and whether anything here can answer a bank challenge.
    ///
    /// `supportsPaymentAction` reaches the wire ONLY on the self-service change, and only when the
    /// caller said so: without it the plain body goes up and the server refuses a change that
    /// needs 3-D Secure rather than parking one nobody could finish. Admin-scoped changes are
    /// authorised server-side and their endpoints carry neither a transaction id nor the flag.
    ///
    /// Never throws: a transport failure comes back as an unsuccessful result, so the caller's
    /// state machine reads one shape. `requiresAction` and `processing` mean "not yet", not
    /// "refused", and are NOT surfaced as errors.
    ///
    /// `settles` names who owns "the change landed" — see ``applyTierChangeSettlement()``. True,
    /// the default, is the direct path: this model drops the entitlement cache and reloads.
    /// ``WildwoodPlanChangeModel`` passes false because the change it posts is not necessarily
    /// finished — a bank challenge and a completion may still be to come — and it settles once,
    /// itself, when the change is really done.
    @discardableResult
    public func postTierChange(
        tierId: String,
        pricingId: String?,
        tierName: String? = nil,
        isChange: Bool,
        immediate: Bool,
        paymentTransactionId: String? = nil,
        supportsPaymentAction: Bool = false,
        settles: Bool = true
    ) async -> AppTierChangeResultModel {
        clearMessages()
        do {
            let result: AppTierChangeResultModel = try await sendTierChange(
                tierId: tierId,
                pricingId: pricingId,
                isChange: isChange,
                immediate: immediate,
                paymentTransactionId: paymentTransactionId,
                supportsPaymentAction: supportsPaymentAction
            )
            await settleTierChange(
                result,
                operation: "change the plan",
                tierName: tierName,
                settles: settles
            )
            return result
        } catch {
            let message: String = (error as? WildwoodError)?.message ?? error.localizedDescription
            errorMessage = message
            return AppTierChangeResultModel(success: false, errorMessage: message)
        }
    }

    /// Finish a plan change the server parked on a bank challenge. Safe to repeat — the server
    /// verifies the payment with the processor before it moves anything — and `processing` is
    /// answered as data, not as an error.
    ///
    /// `settles` is the same ownership switch `postTierChange` carries: false leaves the
    /// settlement to the driver that ran the change (see ``applyTierChangeSettlement()``).
    @discardableResult
    public func completeTierChange(
        pendingChangeId: String,
        settles: Bool = true
    ) async -> AppTierChangeResultModel {
        clearMessages()
        do {
            let result: AppTierChangeResultModel = try await client.appTier.completeTierChange(
                appId: appId, pendingChangeId: pendingChangeId
            )
            await settleTierChange(
                result,
                operation: "complete the plan change",
                tierName: nil,
                settles: settles
            )
            return result
        } catch {
            let message: String = (error as? WildwoodError)?.message ?? error.localizedDescription
            errorMessage = message
            return AppTierChangeResultModel(success: false, errorMessage: message)
        }
    }

    /// Whether this account may still start a free trial. Never throws: an unknown answer reads as
    /// eligible, which is what the catalog already advertises.
    @discardableResult
    public func loadTrialEligibility() async -> TrialEligibilityModel {
        let result: TrialEligibilityModel = (try? await client.appTier.trialEligibility(appId: appId))
            ?? TrialEligibilityModel()
        trialEligibility = result
        return result
    }

    /// The packs the app sells publicly, for a surface that has no session yet. Failures leave the
    /// list alone rather than emptying it.
    @discardableResult
    public func loadPublicAddOns() async -> [AppTierAddOnModel] {
        guard let packs = try? await client.appTier.getPublicAddOns(appId: appId) else {
            return availableAddOns
        }
        availableAddOns = packs
        return packs
    }

    private func sendTierChange(
        tierId: String,
        pricingId: String?,
        isChange: Bool,
        immediate: Bool,
        paymentTransactionId: String?,
        supportsPaymentAction: Bool
    ) async throws -> AppTierChangeResultModel {
        switch scope {
        case .currentUser:
            if !isChange {
                return try await client.appTier.selfSubscribe(
                    appId: appId,
                    appTierId: tierId,
                    appTierPricingId: pricingId,
                    paymentTransactionId: paymentTransactionId
                )
            }
            if supportsPaymentAction {
                return try await client.appTier.changeTier(
                    appId: appId,
                    options: SelfChangeTierOptions(
                        newTierId: tierId,
                        newPricingId: pricingId,
                        immediate: immediate,
                        paymentTransactionId: paymentTransactionId,
                        supportsPaymentAction: true
                    )
                )
            }
            return try await client.appTier.changeTier(
                appId: appId,
                newTierId: tierId,
                newPricingId: pricingId,
                immediate: immediate,
                paymentTransactionId: paymentTransactionId
            )

        case .user(let userId):
            if !isChange {
                return try await client.appTier.subscribeUserToTier(
                    appId: appId, userId: userId, tierId: tierId, pricingId: pricingId
                )
            }
            return try await client.appTier.changeTierAdvanced(
                appId: appId, userId: userId, newTierId: tierId, newPricingId: pricingId, immediate: immediate
            )

        case .company(let companyId):
            if !isChange {
                return try await client.appTier.subscribeCompanyToTier(
                    appId: appId, companyId: companyId, tierId: tierId, pricingId: pricingId
                )
            }
            return try await client.appTier.changeCompanyTier(
                appId: appId, companyId: companyId, newTierId: tierId, pricingId: pricingId, immediate: immediate
            )
        }
    }

    /// Read a change or completion answer: success refreshes, a "not yet" says nothing, and a real
    /// refusal keeps the server's own words. `settles` false keeps the message and drops the
    /// stale preview but leaves the settlement to the caller that owns the whole change.
    private func settleTierChange(
        _ result: AppTierChangeResultModel,
        operation: String,
        tierName: String?,
        settles: Bool
    ) async {
        if result.success {
            let planName: String = tierName ?? "your new plan"
            successMessage = result.isScheduled
                ? "Tier change scheduled for \(result.effectiveDate?.formatted(date: .abbreviated, time: .omitted) ?? "the next billing period")."
                : "Tier changed to \(planName)."
            tierChangePreview = nil
            if settles { await applyTierChangeSettlement() }
            return
        }

        // `requiresAction` and `processing` arrive with `success == false` and are the 3-D Secure
        // path, not a refusal: reporting them as errors tells a customer their plan failed while
        // the money is still moving. Nothing is settled either — the plan has not moved yet, so
        // dropping the entitlement cache here would announce a change that has not happened.
        if result.requiresAction == true || result.processing == true { return }
        errorMessage = Self.refusalMessage(operation, message: result.errorMessage, code: result.errorCode)
    }

    /// Everything "a tier change landed" means beyond the message: the shared entitlement cache is
    /// dropped and the state a plan move changes is re-read.
    ///
    /// ONE owner runs this per change. This model runs it for a change it was asked to make
    /// directly — `changeTier` and the two methods left at their default `settles`, which is the
    /// legacy path a host or the older panels take. `WildwoodPlanChangeModel` runs it instead for
    /// a change it drove, exactly once and even when that change drains after the view has gone,
    /// having posted the change with `settles: false`.
    ///
    /// Two owners for one change bump `FeatureStore`'s epoch twice and emit `entitlementsChanged`
    /// twice — so every other subscriber in the host app reacts twice to one plan move — and read
    /// the same three endpoints twice.
    ///
    /// Internal, not private: the plan-change driver is the other owner.
    func applyTierChangeSettlement() async {
        invalidateEntitlements(.tierChange)
        await loadStatus()
        await loadFeatures()
        await loadLimits()
    }

    public func changeTier(to tier: AppTierModel, pricing: AppTierPricingModel?, immediate: Bool, paymentTransactionId: String? = nil) async {
        clearMessages()
        do {
            let result: AppTierChangeResultModel
            switch scope {
            case .currentUser:
                if subscription == nil {
                    result = try await client.appTier.selfSubscribe(
                        appId: appId, appTierId: tier.id, appTierPricingId: pricing?.id, paymentTransactionId: paymentTransactionId
                    )
                } else {
                    result = try await client.appTier.changeTier(
                        appId: appId, newTierId: tier.id, newPricingId: pricing?.id,
                        immediate: immediate, paymentTransactionId: paymentTransactionId
                    )
                }
            case .user(let userId):
                if subscription == nil {
                    result = try await client.appTier.subscribeUserToTier(
                        appId: appId, userId: userId, tierId: tier.id, pricingId: pricing?.id
                    )
                } else {
                    result = try await client.appTier.changeTierAdvanced(
                        appId: appId, userId: userId, newTierId: tier.id, newPricingId: pricing?.id, immediate: immediate
                    )
                }
            case .company(let companyId):
                if subscription == nil {
                    result = try await client.appTier.subscribeCompanyToTier(
                        appId: appId, companyId: companyId, tierId: tier.id, pricingId: pricing?.id
                    )
                } else {
                    result = try await client.appTier.changeCompanyTier(
                        appId: appId, companyId: companyId, newTierId: tier.id, pricingId: pricing?.id, immediate: immediate
                    )
                }
            }

            if result.success {
                successMessage = result.isScheduled
                    ? "Tier change scheduled for \(result.effectiveDate?.formatted(date: .abbreviated, time: .omitted) ?? "the next billing period")."
                    : "Tier changed to \(tier.name)."
                tierChangePreview = nil
                // The legacy direct path: this model ran the change, so this model settles it —
                // once, exactly as it always has.
                await applyTierChangeSettlement()
            } else if result.requiresAction != true && result.processing != true {
                // `requiresAction`/`processing` arrive with `success == false` and mean "not yet",
                // not "refused" — surfacing them as errors tells a customer their plan failed
                // while the money is still moving. Only a real refusal reaches the banner.
                errorMessage = Self.refusalMessage(
                    "change the plan",
                    message: result.errorMessage,
                    code: result.errorCode
                )
            }
        } catch {
            handleError(error)
        }
    }

    public func cancelSubscription() async {
        clearMessages()
        let result: AppTierCancelResultModel
        switch scope {
        case .currentUser:
            result = await client.appTier.cancelSubscription(appId: appId)
        case .user(let userId):
            result = await client.appTier.cancelUserSubscription(appId: appId, userId: userId)
        case .company(let companyId):
            result = await client.appTier.cancelCompanySubscription(appId: appId, companyId: companyId)
        }
        lastCancelResult = result

        // The cancel endpoints report failures via success/errorMessage (they
        // never throw) — surface them, or a failed cancel looks successful.
        guard result.success else {
            errorMessage = result.errorMessage ?? "Failed to cancel the subscription."
            return
        }

        successMessage = result.isScheduled
            ? "Cancellation scheduled — access continues until \(result.effectiveDate?.formatted(date: .abbreviated, time: .omitted) ?? "the end of the billing period")."
            : "Subscription cancelled."
        invalidateEntitlements(.cancel)
        await loadStatus()
    }

    // MARK: - Add-ons

    /// Buy one pack, on the pricing option the row offered.
    ///
    /// The self-service path goes through the structured call so a refusal keeps the server's own
    /// words — "you already own that pack" has to read differently from "the card was declined".
    /// The two admin paths still answer a bare Bool, so they get the action's wording.
    @discardableResult
    public func subscribeToAddOn(_ addOn: AppTierAddOnModel, pricing: AppTierAddOnPricingModel?) async -> Bool {
        clearMessages()
        let refusal: String?
        switch scope {
        case .currentUser:
            let result = try? await client.appTier.subscribeToAddOnDetailed(
                appId: appId, addOnId: addOn.id, pricingId: pricing?.id
            )
            refusal = result?.success == true ? nil : AddOnRowRules.failureMessage(
                .subscribe, name: addOn.name, serverMessage: result?.error?.message
            )
        case .user(let userId):
            let ok = await client.appTier.subscribeUserToAddOn(appId: appId, userId: userId, addOnId: addOn.id)
            refusal = ok ? nil : AddOnRowRules.failureMessage(.subscribe, name: addOn.name, serverMessage: nil)
        case .company(let companyId):
            let ok = await client.appTier.subscribeCompanyToAddOn(appId: appId, companyId: companyId, addOnId: addOn.id)
            refusal = ok ? nil : AddOnRowRules.failureMessage(.subscribe, name: addOn.name, serverMessage: nil)
        }

        guard refusal == nil else {
            errorMessage = refusal ?? ""
            return false
        }
        successMessage = "Subscribed to \(addOn.name)."
        invalidateEntitlements(.addOn)
        await loadAddOns()
        return true
    }

    /// Cancel one pack. `immediate` is false by default, which is what the panel asks for: access
    /// continues to the end of the period already paid for, and the row can be reactivated until
    /// then.
    @discardableResult
    public func cancelAddOn(_ subscription: UserAddOnSubscriptionModel, immediate: Bool = false) async -> Bool {
        clearMessages()
        let refusal: String?
        switch scope {
        case .currentUser:
            let result = try? await client.appTier.cancelAddOnDetailed(
                subscriptionId: subscription.id, immediate: immediate
            )
            refusal = result?.success == true ? nil : AddOnRowRules.failureMessage(
                .cancel, name: subscription.addOnName, serverMessage: result?.errorMessage
            )
        case .user:
            let ok = await client.appTier.cancelUserAddOn(appId: appId, subscriptionId: subscription.id)
            refusal = ok ? nil : AddOnRowRules.failureMessage(.cancel, name: subscription.addOnName, serverMessage: nil)
        case .company:
            let ok = await client.appTier.cancelCompanyAddOn(subscriptionId: subscription.id)
            refusal = ok ? nil : AddOnRowRules.failureMessage(.cancel, name: subscription.addOnName, serverMessage: nil)
        }

        guard refusal == nil else {
            errorMessage = refusal ?? ""
            return false
        }
        successMessage = "Add-on cancelled."
        invalidateEntitlements(.cancel)
        await loadAddOns()
        return true
    }

    /// Take back a scheduled pack cancellation. Self-service only — the admin routes have no
    /// reactivate endpoint, so the panel never offers it in an admin scope.
    @discardableResult
    public func reactivateAddOn(_ subscription: UserAddOnSubscriptionModel) async -> Bool {
        clearMessages()
        let result = try? await client.appTier.reactivateAddOn(subscriptionId: subscription.id)
        guard result?.success == true else {
            errorMessage = AddOnRowRules.failureMessage(
                .reactivate, name: subscription.addOnName, serverMessage: result?.errorMessage
            )
            return false
        }
        successMessage = "\(subscription.addOnName) will continue."
        invalidateEntitlements(.reactivate)
        await loadAddOns()
        return true
    }

    // MARK: - Usage limits (admin)

    public func updateLimit(_ limitCode: String, newMaxValue: Double) async {
        clearMessages()
        let ok: Bool
        switch scope {
        case .currentUser:
            ok = await client.appTier.updateUsageLimit(appId: appId, limitCode: limitCode, newMaxValue: newMaxValue)
        case .user(let userId):
            ok = await client.appTier.updateUserUsageLimit(appId: appId, userId: userId, limitCode: limitCode, newMaxValue: newMaxValue)
        case .company(let companyId):
            ok = await client.appTier.updateCompanyUsageLimit(appId: appId, companyId: companyId, limitCode: limitCode, newMaxValue: newMaxValue)
        }
        if ok {
            successMessage = "Limit updated."
            invalidateEntitlements(.manual)
            await loadLimits()
        } else {
            errorMessage = Self.refusalMessage(Self.limitOperation(scope, reset: false))
        }
    }

    public func resetUsage(_ limitCode: String) async {
        clearMessages()
        let ok: Bool
        switch scope {
        case .currentUser:
            ok = await client.appTier.resetUsage(appId: appId, limitCode: limitCode)
        case .user(let userId):
            ok = await client.appTier.resetUserUsage(appId: appId, userId: userId, limitCode: limitCode)
        case .company(let companyId):
            ok = await client.appTier.resetCompanyUsage(appId: appId, companyId: companyId, limitCode: limitCode)
        }
        if ok {
            successMessage = "Usage reset."
            invalidateEntitlements(.manual)
            await loadLimits()
        } else {
            errorMessage = Self.refusalMessage(Self.limitOperation(scope, reset: true))
        }
    }

    // MARK: - Feature overrides (admin)

    public func setOverride(featureCode: String, isEnabled: Bool, reason: String?, expiresAt: Date?) async {
        clearMessages()
        let userId: String? = if case .user(let id) = scope { id } else { nil }
        let ok = await client.appTier.setFeatureOverride(
            appId: appId, userId: userId, featureCode: featureCode,
            isEnabled: isEnabled, reason: reason, expiresAt: expiresAt
        )
        if ok {
            successMessage = "Override saved."
            invalidateEntitlements(.manual)
            await loadOverrides()
            await loadFeatures()
        } else {
            errorMessage = Self.refusalMessage("set the feature override")
        }
    }

    public func removeOverride(_ override: AppFeatureOverrideModel) async {
        clearMessages()
        let ok = await client.appTier.removeFeatureOverride(
            appId: appId, featureCode: override.featureCode, userId: override.userId
        )
        if ok {
            successMessage = "Override removed."
            invalidateEntitlements(.manual)
            await loadOverrides()
            await loadFeatures()
        } else {
            errorMessage = Self.refusalMessage("remove the feature override")
        }
    }

    // MARK: - Helpers

    /// What a refused mutation says. The server's own words win; failing that the operation is
    /// named, with the server's code in brackets when it sent one.
    ///
    /// Word for word JS's `refusalMessage` in `useSubscriptionAdmin`, because a bare `false` read
    /// as success is the bug this replaced: "Failed to update the limit." told nobody that the
    /// limit belonged to another company.
    static func refusalMessage(_ operation: String, message: String? = nil, code: String? = nil) -> String {
        if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return message }
        if let code, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "The request was refused: could not \(operation) (\(code))."
        }
        return "The request was refused: could not \(operation)."
    }

    /// The JS operation strings for the four usage mutations, which name the scope they act on.
    static func limitOperation(_ scope: SubscriptionAdminScope, reset: Bool) -> String {
        switch scope {
        case .currentUser:
            return reset ? "reset the usage counter" : "update the usage limit"
        case .user:
            return reset ? "reset the user's usage counter" : "update the user's usage limit"
        case .company:
            return reset ? "reset the company's usage counter" : "update the company's usage limit"
        }
    }

    /// Entitlement-changing mutations must also invalidate the shared
    /// FeatureStore — otherwise FeatureGates elsewhere in the app serve the
    /// pre-mutation plan for the store's cache TTL (mirrors
    /// useSubscriptionAdmin's `wrapMutation`, which invalidates and THEN emits
    /// `entitlementsChanged` with the reason). Invalidation is lazy: gates
    /// reload on demand via the store's epoch, no eager refetch.
    /// Internal, not private: ``applyTierChangeSettlement()`` is shared with the plan-change
    /// driver, and the manage view's pack checkout — the one mutation no model here ran — drops
    /// the cache through it directly.
    func invalidateEntitlements(_ reason: EntitlementsChangedReason) {
        client.features.invalidateEntitlements(appId: appId, reason: reason)
    }

    public func clearMessages() {
        errorMessage = ""
        successMessage = ""
    }

    private func handleError(_ error: any Error) {
        errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
    }
}
