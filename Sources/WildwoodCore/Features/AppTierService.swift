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

    /// Options form of the self-service tier change, for a caller that can finish a payment.
    ///
    /// With ``SelfChangeTierOptions/supportsPaymentAction`` set, a change whose proration needs
    /// 3-D Secure comes back with `requiresAction`, a client secret and a `pendingChangeId` to
    /// confirm and then ``completeTierChange(appId:pendingChangeId:)``, instead of being refused
    /// outright.
    ///
    /// This overload is the ONLY form that sends `SupportsPaymentAction`: the positional
    /// ``changeTier(appId:newTierId:newPricingId:immediate:paymentTransactionId:)`` posts exactly
    /// what it always did, because an older server rejects an unknown property and a caller that
    /// never opted into finishing a payment must not appear to have.
    ///
    /// Throws on an HTTP failure, like the positional form — unlike the structured actions below,
    /// whose refusals are data.
    public func changeTier(appId: String, options: SelfChangeTierOptions) async throws -> AppTierChangeResultModel {
        // SelfChangeTierOptions' CodingKeys are the PascalCase names WildwoodAPI binds, so the
        // options value IS the request body.
        try await http.post("api/app-tiers/\(appId)/my-subscription/change", body: options)
    }

    /// Finish a plan change that came back `requiresAction`, once the prorated payment has been
    /// confirmed. Safe to call repeatedly: the server asks the processor whether the invoice
    /// really paid before it moves anything, and answers `processing` while it waits.
    ///
    /// IDIOM NOTE — this and the structured actions below are the one place in this package where
    /// a service reports an HTTP failure as DATA instead of throwing (see
    /// ``AppTierActionError/from(_:fallbackMessage:)``): a driver has to branch on WHY a change
    /// was refused, and a thrown error flattens "that change lapsed" into "something failed".
    /// Task cancellation is NOT a refusal and still propagates as `CancellationError`.
    ///
    /// `requiresAction` and `processing` arrive with `success == false` and mean "not yet", not
    /// "refused" — they come back as data, untouched.
    public func completeTierChange(appId: String, pendingChangeId: String) async throws -> AppTierChangeResultModel {
        do {
            let data: AppTierChangeResultModel? = try await http.post(
                "api/app-tiers/\(appId)/my-subscription/change/\(encodePath(pendingChangeId))/complete"
            )
            // An empty 2xx body means the server had nothing to report about a change it accepted
            // — the same reading ``cancelResult`` gives an empty cancellation response.
            return data ?? AppTierChangeResultModel(success: true)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let actionError = AppTierActionError.from(error, fallbackMessage: "Failed to complete the plan change")
            return AppTierChangeResultModel(
                success: false,
                errorMessage: actionError.message,
                isScheduled: false,
                errorCode: actionError.code
            )
        }
    }

    /// Whether this account may still start a free trial in the app — on a tier, and per add-on.
    ///
    /// Never reports an HTTP failure: it answers "eligible", which is what a signup screen
    /// already shows from the catalog's trial days, and an empty `addOns` map means "unknown" for
    /// the same reason. The checkout quote and the payment initiation re-decide authoritatively
    /// before any money moves, so the worst a failed lookup does is advertise a trial the
    /// checkout then prices in full. Cancellation still propagates.
    public func trialEligibility(appId: String) async throws -> TrialEligibilityModel {
        do {
            let data: TrialEligibilityModel? = try await http.get("api/app-tiers/\(appId)/trial-eligibility")
            return data ?? TrialEligibilityModel()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return TrialEligibilityModel()
        }
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

    /// One structured pack/checkout call: 2xx with a body → the body; 2xx with no body → a
    /// refusal (these endpoints' answer IS the result DTO, so nothing to report is not a
    /// success); an HTTP/transport failure → the refusal the server described, filled in from
    /// `empty` where it said nothing. Cancellation is rethrown, never folded into a refusal.
    ///
    /// `send` performs the request, keeping the endpoint literal at the verb call site for the
    /// Sync parity script — the same shape ``cancelResult(_:)`` uses.
    private func actionResult<T: Decodable & Sendable & AppTierRefusableResult>(
        fallbackMessage: String,
        empty: T,
        send: () async throws -> T?
    ) async throws -> T {
        do {
            guard let data = try await send() else {
                return AppTierActionMapping.refusal(
                    Self.emptyAnswer,
                    fallbackMessage: fallbackMessage,
                    empty: empty
                )
            }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return AppTierActionMapping.refusal(error, fallbackMessage: fallbackMessage, empty: empty)
        }
    }

    /// A 2xx that carried no body at all, from an endpoint whose answer is the result DTO.
    private static let emptyAnswer = WildwoodError(
        message: "The server returned an empty response.",
        status: 0,
        code: .unknown
    )

    /// Subscribe to a single pack. Returns the created subscription, or a structured refusal — a
    /// pack already owned, one bundled in the tier, and a payment the server would not accept are
    /// all different problems a UI has to word differently. Reports an HTTP refusal as data;
    /// cancellation still propagates.
    public func subscribeToAddOnDetailed(
        appId: String,
        addOnId: String,
        pricingId: String? = nil,
        paymentTransactionId: String? = nil
    ) async throws -> AddOnSubscribeResultModel {
        struct SubscribeAddOnDto: Encodable {
            let AppId: String
            let AppTierAddOnId: String
            let AppTierAddOnPricingId: String?
            let PaymentTransactionId: String?
        }
        do {
            let data: UserAddOnSubscriptionModel? = try await http.post(
                "api/app-tier-addons/\(appId)/subscribe",
                body: SubscribeAddOnDto(
                    AppId: appId,
                    AppTierAddOnId: addOnId,
                    AppTierAddOnPricingId: pricingId,
                    PaymentTransactionId: paymentTransactionId
                )
            )
            return AddOnSubscribeResultModel(success: true, subscription: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return AddOnSubscribeResultModel(
                success: false,
                error: AppTierActionError.from(error, fallbackMessage: "Failed to subscribe to the pack")
            )
        }
    }

    /// Cancel one of the calling user's own packs. By default access continues to the end of the
    /// period already paid for (`isScheduled`); `immediate` ends it now. Reports an HTTP refusal
    /// as data; cancellation still propagates.
    public func cancelAddOnDetailed(
        subscriptionId: String,
        immediate: Bool = false
    ) async throws -> AddOnSubscriptionCancelResultModel {
        do {
            // Bool interpolation writes lowercase true/false, byte-identical to the JS
            // `?immediate=${immediate}`.
            let data: AddOnSubscriptionCancelResultModel? = try await http.post(
                "api/app-tier-addons/subscriptions/\(subscriptionId)/cancel?immediate=\(immediate)"
            )
            return AddOnSubscriptionCancelResultModel(
                success: true,
                isScheduled: data?.isScheduled,
                status: data?.status,
                effectiveDate: data?.effectiveDate
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return AppTierActionMapping.refusal(
                error,
                fallbackMessage: "Failed to cancel the pack",
                empty: AddOnSubscriptionCancelResultModel()
            )
        }
    }

    /// Take back a scheduled cancellation: the provider stops cancelling at period end and the
    /// pack goes back to Active (or Trialing while its trial runs). Reports an HTTP refusal as
    /// data; cancellation still propagates.
    public func reactivateAddOn(subscriptionId: String) async throws -> AddOnSubscriptionReactivateResultModel {
        do {
            let data: UserAddOnSubscriptionModel? = try await http.post(
                "api/app-tier-addons/subscriptions/\(subscriptionId)/reactivate"
            )
            return AddOnSubscriptionReactivateResultModel(
                success: true,
                status: data?.status,
                subscription: data
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return AppTierActionMapping.refusal(
                error,
                fallbackMessage: "Failed to reactivate the pack",
                empty: AddOnSubscriptionReactivateResultModel()
            )
        }
    }

    @available(*, deprecated, message: "Use subscribeToAddOnDetailed(appId:addOnId:pricingId:paymentTransactionId:) — it reports WHY a subscription was refused, and returns the created subscription, instead of a bare false.")
    public func subscribeToAddOn(
        appId: String,
        addOnId: String,
        pricingId: String? = nil,
        paymentTransactionId: String? = nil
    ) async -> Bool {
        // A cancelled task has no caller left to answer, so the Bool wrappers report false
        // rather than growing a `throws` their existing callers never had.
        let result = try? await subscribeToAddOnDetailed(
            appId: appId,
            addOnId: addOnId,
            pricingId: pricingId,
            paymentTransactionId: paymentTransactionId
        )
        return result?.success ?? false
    }

    @available(*, deprecated, message: "Use cancelAddOnDetailed(subscriptionId:immediate:) — it says whether access continues to the end of the period, and why a cancellation was refused.")
    public func cancelAddOnSubscription(subscriptionId: String) async -> Bool {
        // Delegating also means this now sends `?immediate=false` explicitly, as the JS
        // deprecated wrapper does — the server's default, stated rather than assumed.
        let result = try? await cancelAddOnDetailed(subscriptionId: subscriptionId)
        return result?.success ?? false
    }

    // MARK: - Pack checkout (card once, any number of packs)

    /// Price a basket of packs. Server-authoritative: the price, billing frequency, trial length
    /// and trial eligibility of every line come from the catalog and the account, not from this
    /// request. The returned `checkoutId` is echoed back on ``checkoutAddOns(appId:request:)``
    /// and is what makes the purchase idempotent.
    ///
    /// Reports an HTTP refusal as data; cancellation still propagates. A refused quote priced
    /// nothing, so its `currency` stays blank rather than inventing one.
    public func quoteAddOnCheckout(
        appId: String,
        items: [AddOnCheckoutItemInput]
    ) async throws -> AddOnCheckoutQuoteModel {
        try await actionResult(
            fallbackMessage: "Failed to price the packs",
            empty: AddOnCheckoutQuoteModel()
        ) {
            let data: AddOnCheckoutQuoteModel? = try await self.http.post(
                "api/app-tier-addons/\(appId)/checkout/quote",
                body: AddOnCheckoutQuoteRequestModel(items: items)
            )
            return data
        }
    }

    /// Start the one-off card entry for an account with no card on file. Confirm the returned
    /// `clientSecret`, then pass `paymentTransactionId` to ``checkoutAddOns(appId:request:)``.
    /// Reports an HTTP refusal as data; cancellation still propagates.
    public func createCheckoutPaymentMethod(
        appId: String,
        providerId: String
    ) async throws -> AddOnCheckoutPaymentMethodModel {
        try await actionResult(
            fallbackMessage: "Failed to start card collection",
            empty: AddOnCheckoutPaymentMethodModel()
        ) {
            let data: AddOnCheckoutPaymentMethodModel? = try await self.http.post(
                "api/app-tier-addons/\(appId)/checkout/payment-method",
                body: AddOnCheckoutPaymentMethodRequestModel(providerId: providerId)
            )
            return data
        }
    }

    /// Buy the basket: one subscription per pack, charged to one card. One pack failing does not
    /// stop the others, so read `results` per pack rather than `success` alone — a
    /// `requires_action` line still has to be authenticated and then
    /// ``completeAddOnCheckout(appId:paymentTransactionId:)``d. Reports an HTTP refusal as data
    /// (keeping the checkout id it was about); cancellation still propagates.
    public func checkoutAddOns(
        appId: String,
        request: AddOnCheckoutRequestModel
    ) async throws -> AddOnCheckoutResultModel {
        try await actionResult(
            fallbackMessage: "Failed to buy the packs",
            empty: AddOnCheckoutResultModel(checkoutId: request.checkoutId)
        ) {
            // AddOnCheckoutRequestModel's CodingKeys are the PascalCase names the endpoint binds,
            // and `useSavedCard` is a non-optional Bool, so it always goes up (false by default).
            let data: AddOnCheckoutResultModel? = try await self.http.post(
                "api/app-tier-addons/\(appId)/checkout",
                body: request
            )
            return data
        }
    }

    /// Finish one pack whose card the customer has just authenticated: the payment is verified
    /// with the provider and, once it really paid, the pack's subscription is created.
    ///
    /// Reports an HTTP refusal as data; cancellation still propagates. A refusal here IS the
    /// per-item result DTO (the controller returns it with the 400/404), so the pack it was about
    /// is kept rather than answering about nothing.
    public func completeAddOnCheckout(
        appId: String,
        paymentTransactionId: String
    ) async throws -> AddOnCheckoutItemResultModel {
        do {
            let data: AddOnCheckoutItemResultModel? = try await http.post(
                "api/app-tier-addons/\(appId)/checkout/complete",
                body: AddOnCheckoutCompleteRequestModel(paymentTransactionId: paymentTransactionId)
            )
            guard let data else { return Self.failedItem(Self.emptyAnswer) }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return Self.failedItem(error)
        }
    }

    private static func failedItem(_ error: any Error) -> AddOnCheckoutItemResultModel {
        let actionError = AppTierActionError.from(error, fallbackMessage: "Failed to complete the pack purchase")
        var result = AppTierActionMapping.refusalItemBody(error, as: AddOnCheckoutItemResultModel.self)
            ?? AddOnCheckoutItemResultModel()
        result.status = AddOnCheckoutItemStatuses.failed
        result.errorCode = actionError.code
        result.errorMessage = actionError.message
        return result
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
