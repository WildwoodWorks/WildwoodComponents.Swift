// Wire-shape tests for the registration/subscription model additions:
// camelCase decoding of every new response model, PascalCase encoding of every new request
// model, and the tolerant handling of server string unions.

import Foundation
import Testing
@testable import WildwoodCore

// MARK: - Additions to existing tier models

struct AppTierModelAdditionTests {
    @Test func tierCarriesTheCatalogCurrency() throws {
        let json = #"{"id":"t1","name":"Pro","currency":"EUR"}"#
        let tier = try WildwoodJSON.decoder().decode(AppTierModel.self, from: Data(json.utf8))

        #expect(tier.currency == "EUR")
    }

    @Test func tierCurrencyIsNilOnAnOlderServer() throws {
        let json = #"{"id":"t1","name":"Pro"}"#
        let tier = try WildwoodJSON.decoder().decode(AppTierModel.self, from: Data(json.utf8))

        #expect(tier.currency == nil)
    }

    @Test func bothPricingModelsCarryTrialDays() throws {
        let tierPricing = #"{"id":"p1","price":9.99,"billingFrequency":"Monthly","trialDays":14}"#
        let pricing = try WildwoodJSON.decoder().decode(AppTierPricingModel.self, from: Data(tierPricing.utf8))
        #expect(pricing.trialDays == 14)

        let addOnPricing = #"{"id":"ap1","price":4,"billingFrequency":"Monthly","trialDays":7,"isDefault":true}"#
        let addOn = try WildwoodJSON.decoder().decode(AppTierAddOnPricingModel.self, from: Data(addOnPricing.utf8))
        #expect(addOn.trialDays == 7)
        #expect(addOn.isDefault)

        // Absent on an older server, not zero — "no trial configured" and "trial unknown" have to
        // stay distinguishable.
        let bare = #"{"id":"ap2","price":4}"#
        let bareAddOn = try WildwoodJSON.decoder().decode(AppTierAddOnPricingModel.self, from: Data(bare.utf8))
        #expect(bareAddOn.trialDays == nil)
    }

    @Test func addOnCarriesTheCatalogCurrency() throws {
        let json = #"{"id":"a1","name":"Pack","currency":"GBP","trialDays":30}"#
        let addOn = try WildwoodJSON.decoder().decode(AppTierAddOnModel.self, from: Data(json.utf8))

        #expect(addOn.currency == "GBP")
        #expect(addOn.trialDays == 30)
    }

    @Test func addOnSubscriptionCarriesItsOwnerAndPaymentLinks() throws {
        let json = """
        {"id":"s1","userId":"u1","appId":"app-1","appTierAddOnId":"a1","appTierAddOnPricingId":"ap1",
         "status":"Active","paymentTransactionId":"txn-9","userPaymentProviderId":"upp-3","addOnName":"Pack"}
        """
        let sub = try WildwoodJSON.decoder().decode(UserAddOnSubscriptionModel.self, from: Data(json.utf8))

        #expect(sub.userId == "u1")
        #expect(sub.appId == "app-1")
        #expect(sub.appTierAddOnPricingId == "ap1")
        #expect(sub.paymentTransactionId == "txn-9")
        #expect(sub.userPaymentProviderId == "upp-3")
    }

    @Test func aGrantedAddOnRowHasNoPaymentTransaction() throws {
        // No paymentTransactionId means the row was granted (registration token or admin), not sold,
        // so nothing bills it and there is nothing to cancel at a provider.
        let json = #"{"id":"s2","userId":"u1","appId":"app-1","appTierAddOnId":"a1","status":"Active"}"#
        let sub = try WildwoodJSON.decoder().decode(UserAddOnSubscriptionModel.self, from: Data(json.utf8))

        #expect(sub.paymentTransactionId == nil)
        #expect(sub.userPaymentProviderId == nil)
        #expect(sub.appTierAddOnPricingId == nil)
    }

    @Test func tierChangeResultCarriesThePaymentActionFields() throws {
        let json = """
        {"success":false,"errorMessage":"","isScheduled":false,"requiresAction":true,
         "clientSecret":"pi_1_secret","pendingChangeId":"pc-1","paymentIntentId":"pi_1",
         "expiresAt":"2026-10-01T12:00:00Z","amountDue":12.5,"currency":"USD","errorCode":null}
        """
        let result = try WildwoodJSON.decoder().decode(AppTierChangeResultModel.self, from: Data(json.utf8))

        // requiresAction arrives WITH success:false and means "not yet", not a refusal.
        #expect(result.success == false)
        #expect(result.requiresAction == true)
        #expect(result.clientSecret == "pi_1_secret")
        #expect(result.pendingChangeId == "pc-1")
        #expect(result.paymentIntentId == "pi_1")
        #expect(result.expiresAt != nil)
        #expect(result.amountDue == 12.5)
        #expect(result.currency == "USD")
        #expect(result.processing == nil)
        #expect(result.errorCode == nil)
    }

    @Test func tierChangeResultKeepsAnUnknownErrorCode() throws {
        let json = #"{"success":false,"errorMessage":"Nope","errorCode":"some_code_added_later"}"#
        let result = try WildwoodJSON.decoder().decode(AppTierChangeResultModel.self, from: Data(json.utf8))

        #expect(result.errorCode == "some_code_added_later")
        #expect(TierChangeErrorCodes.pendingChangeExpired == "pending_change_expired")
    }

    @Test func tierChangeResultCanBeBuiltForARefusal() {
        // The never-throwing completion path builds one of these itself.
        let refusal = AppTierChangeResultModel(
            errorMessage: "Failed to complete the plan change",
            errorCode: AppTierActionErrorCodes.requestFailed
        )

        #expect(refusal.success == false)
        #expect(refusal.isScheduled == false)
        #expect(refusal.errorCode == "RequestFailed")
    }
}

// MARK: - Request encoding (PascalCase bodies)

struct AppTierCheckoutRequestEncodingTests {
    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try WildwoodJSON.encoder().encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func selfChangeTierOptionsEncodePascalCase() throws {
        let body = try jsonObject(
            SelfChangeTierOptions(
                newTierId: "tier-2",
                newPricingId: "pricing-7",
                immediate: true,
                paymentTransactionId: "txn-9",
                supportsPaymentAction: true
            )
        )

        #expect(body["NewAppTierId"] as? String == "tier-2")
        #expect(body["NewAppTierPricingId"] as? String == "pricing-7")
        #expect(body["Immediate"] as? Bool == true)
        #expect(body["PaymentTransactionId"] as? String == "txn-9")
        #expect(body["SupportsPaymentAction"] as? Bool == true)
    }

    @Test func selfChangeTierOptionsOmitNilsAndDefaultTheFlags() throws {
        let body = try jsonObject(SelfChangeTierOptions(newTierId: "tier-2"))

        #expect(body["NewAppTierId"] as? String == "tier-2")
        #expect(body.keys.contains("NewAppTierPricingId") == false)
        #expect(body.keys.contains("PaymentTransactionId") == false)
        // Both flags are always sent: Immediate defaults to true, SupportsPaymentAction to false.
        #expect(body["Immediate"] as? Bool == true)
        #expect(body["SupportsPaymentAction"] as? Bool == false)
    }

    @Test func quoteRequestEncodesItemsPascalCase() throws {
        let body = try jsonObject(
            AddOnCheckoutQuoteRequestModel(items: [
                AddOnCheckoutItemInput(addOnId: "a1", pricingId: "ap1"),
                AddOnCheckoutItemInput(addOnId: "a2"),
            ])
        )

        let items = try #require(body["Items"] as? [[String: Any]])
        #expect(items.count == 2)
        #expect(items[0]["AddOnId"] as? String == "a1")
        #expect(items[0]["PricingId"] as? String == "ap1")
        #expect(items[1]["AddOnId"] as? String == "a2")
        // Omitted pricing means "the pack's default", so the key must not be sent at all.
        #expect(items[1].keys.contains("PricingId") == false)
    }

    @Test func paymentMethodRequestEncodesProviderId() throws {
        let body = try jsonObject(AddOnCheckoutPaymentMethodRequestModel(providerId: "prov-1"))

        #expect(body["ProviderId"] as? String == "prov-1")
        #expect(body.count == 1)
    }

    @Test func checkoutRequestEncodesTheWholeBasket() throws {
        let body = try jsonObject(
            AddOnCheckoutRequestModel(
                checkoutId: "chk-1",
                providerId: "prov-1",
                paymentTransactionId: "txn-9",
                useSavedCard: false,
                items: [AddOnCheckoutItemInput(addOnId: "a1", pricingId: "ap1")]
            )
        )

        #expect(body["CheckoutId"] as? String == "chk-1")
        #expect(body["ProviderId"] as? String == "prov-1")
        #expect(body["PaymentTransactionId"] as? String == "txn-9")
        #expect(body["UseSavedCard"] as? Bool == false)
        let items = try #require(body["Items"] as? [[String: Any]])
        #expect(items[0]["AddOnId"] as? String == "a1")
    }

    @Test func checkoutRequestOmitsTheTransactionWhenReusingTheSavedCard() throws {
        let body = try jsonObject(
            AddOnCheckoutRequestModel(checkoutId: "chk-1", providerId: "prov-1", useSavedCard: true)
        )

        #expect(body.keys.contains("PaymentTransactionId") == false)
        #expect(body["UseSavedCard"] as? Bool == true)
        #expect((body["Items"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test func completeRequestEncodesThePaymentTransaction() throws {
        let body = try jsonObject(AddOnCheckoutCompleteRequestModel(paymentTransactionId: "txn-9"))

        #expect(body["PaymentTransactionId"] as? String == "txn-9")
        #expect(body.count == 1)
    }
}

// MARK: - Response decoding

struct AppTierCheckoutResponseDecodingTests {
    @Test func trialEligibilityDecodesAndDefaultsToEligible() throws {
        let json = #"{"tierTrialEligible":false,"addOns":{"a1":true,"a2":false}}"#
        let model = try WildwoodJSON.decoder().decode(TrialEligibilityModel.self, from: Data(json.utf8))

        #expect(model.tierTrialEligible == false)
        #expect(model.addOns["a1"] == true)
        #expect(model.addOns["a2"] == false)
        // A missing key means "unknown", never "no".
        #expect(model.addOns["a3"] == nil)

        let empty = try WildwoodJSON.decoder().decode(TrialEligibilityModel.self, from: Data("{}".utf8))
        #expect(empty.tierTrialEligible == true)
        #expect(empty.addOns.isEmpty)
    }

    @Test func quoteDecodesLinesSavedCardAndTotals() throws {
        let json = """
        {"success":true,"checkoutId":"chk-1","providerId":"prov-1","currency":"USD",
         "lines":[{"addOnId":"a1","pricingId":"ap1","name":"Pack","price":5,"billingFrequency":"Monthly",
                   "trialDays":7,"trialEligible":true,"dueToday":0,"trialEnd":"2026-10-08T00:00:00Z"}],
         "totalDueToday":0,"requiresPaymentMethod":false,
         "savedCard":{"brand":"visa","last4":"4242"}}
        """
        let quote = try WildwoodJSON.decoder().decode(AddOnCheckoutQuoteModel.self, from: Data(json.utf8))

        #expect(quote.success)
        #expect(quote.checkoutId == "chk-1")
        #expect(quote.providerId == "prov-1")
        #expect(quote.currency == "USD")
        #expect(quote.totalDueToday == 0)
        #expect(quote.requiresPaymentMethod == false)
        #expect(quote.savedCard?.brand == "visa")
        #expect(quote.savedCard?.last4 == "4242")

        let line = try #require(quote.lines.first)
        #expect(line.id == "a1")
        #expect(line.pricingId == "ap1")
        #expect(line.name == "Pack")
        #expect(line.price == 5)
        #expect(line.billingFrequency == "Monthly")
        #expect(line.trialDays == 7)
        #expect(line.trialEligible)
        #expect(line.dueToday == 0)
        #expect(line.trialEnd != nil)
    }

    @Test func aRefusedQuoteNamesNoCurrency() throws {
        let json = #"{"success":false,"checkoutId":"","currency":"","lines":[],"errorCode":"NoItems","errorMessage":"Nothing to price"}"#
        let quote = try WildwoodJSON.decoder().decode(AddOnCheckoutQuoteModel.self, from: Data(json.utf8))

        #expect(quote.success == false)
        // Blank on purpose: a refused quote priced nothing.
        #expect(quote.currency.isEmpty)
        #expect(quote.lines.isEmpty)
        #expect(quote.errorCode == AddOnCheckoutErrorCodes.noItems)
    }

    @Test func paymentMethodIntentDecodes() throws {
        let json = #"{"success":true,"clientSecret":"seti_1_secret","setupIntentId":"seti_1","paymentTransactionId":"txn-4"}"#
        let model = try WildwoodJSON.decoder().decode(AddOnCheckoutPaymentMethodModel.self, from: Data(json.utf8))

        #expect(model.success)
        #expect(model.clientSecret == "seti_1_secret")
        #expect(model.setupIntentId == "seti_1")
        #expect(model.paymentTransactionId == "txn-4")
        #expect(model.errorCode == nil)
    }

    @Test func itemResultDecodesEveryField() throws {
        let json = """
        {"addOnId":"a1","pricingId":"ap1","status":"requires_action","subscriptionId":null,
         "trialEnd":"2026-10-08T00:00:00Z","amountDueToday":5,"clientSecret":"pi_2_secret",
         "paymentIntentId":"pi_2","paymentTransactionId":"txn-5"}
        """
        let item = try WildwoodJSON.decoder().decode(AddOnCheckoutItemResultModel.self, from: Data(json.utf8))

        #expect(item.id == "a1")
        #expect(item.pricingId == "ap1")
        #expect(item.status == AddOnCheckoutItemStatuses.requiresAction)
        #expect(item.subscriptionId == nil)
        #expect(item.trialEnd != nil)
        #expect(item.amountDueToday == 5)
        #expect(item.clientSecret == "pi_2_secret")
        #expect(item.paymentIntentId == "pi_2")
        #expect(item.paymentTransactionId == "txn-5")
    }

    @Test func anUnknownStatusOrErrorCodeStillDecodes() throws {
        // The wire value is never narrowed to a closed set: a status or code the server adds
        // tomorrow must decode today, unchanged.
        let json = #"{"addOnId":"a1","pricingId":"ap1","status":"partially_refunded","errorCode":"SomethingNew"}"#
        let item = try WildwoodJSON.decoder().decode(AddOnCheckoutItemResultModel.self, from: Data(json.utf8))

        #expect(item.status == "partially_refunded")
        #expect(item.errorCode == "SomethingNew")
    }

    @Test func checkoutResultDecodesPerPackResults() throws {
        let json = """
        {"success":true,"checkoutId":"chk-1","results":[
          {"addOnId":"a1","pricingId":"ap1","status":"trialing","subscriptionId":"s1"},
          {"addOnId":"a2","pricingId":"ap2","status":"failed","errorCode":"ProcessorError","errorMessage":"Declined"}]}
        """
        let result = try WildwoodJSON.decoder().decode(AddOnCheckoutResultModel.self, from: Data(json.utf8))

        #expect(result.success)
        #expect(result.checkoutId == "chk-1")
        #expect(result.results.count == 2)
        #expect(result.results[0].status == AddOnCheckoutItemStatuses.trialing)
        #expect(result.results[1].errorCode == AddOnCheckoutErrorCodes.processorError)
        #expect(result.results[1].errorMessage == "Declined")
    }

    @Test func subscribeResultCarriesTheSubscriptionOrTheError() throws {
        let ok = #"{"success":true,"subscription":{"id":"s1","userId":"u1","appId":"app-1","appTierAddOnId":"a1","status":"Active"}}"#
        let okResult = try WildwoodJSON.decoder().decode(AddOnSubscribeResultModel.self, from: Data(ok.utf8))
        #expect(okResult.success)
        #expect(okResult.subscription?.id == "s1")
        #expect(okResult.error == nil)

        let failed = #"{"success":false,"error":{"code":"AlreadySubscribed","message":"Already on it","status":409}}"#
        let failedResult = try WildwoodJSON.decoder().decode(AddOnSubscribeResultModel.self, from: Data(failed.utf8))
        #expect(failedResult.success == false)
        #expect(failedResult.subscription == nil)
        #expect(failedResult.error?.code == AddOnCheckoutErrorCodes.alreadySubscribed)
        #expect(failedResult.error?.message == "Already on it")
        #expect(failedResult.error?.status == 409)
    }

    @Test func cancelResultDecodesTheScheduledShape() throws {
        let json = #"{"success":true,"isScheduled":true,"status":"PendingCancellation","effectiveDate":"2026-11-01T00:00:00Z"}"#
        let result = try WildwoodJSON.decoder().decode(AddOnSubscriptionCancelResultModel.self, from: Data(json.utf8))

        #expect(result.success)
        #expect(result.isScheduled == true)
        #expect(result.status == "PendingCancellation")
        #expect(result.effectiveDate != nil)
        #expect(result.errorCode == nil)
    }

    @Test func cancelResultCanBeBuiltForARefusal() {
        let refusal = AddOnSubscriptionCancelResultModel(
            errorCode: AddOnSubscriptionErrorCodes.notFound,
            errorMessage: "Failed to cancel the pack"
        )

        #expect(refusal.success == false)
        #expect(refusal.isScheduled == nil)
        #expect(refusal.errorCode == "addon_subscription_not_found")
    }

    @Test func reactivateResultDecodesTheRestoredSubscription() throws {
        let json = """
        {"success":true,"status":"Active",
         "subscription":{"id":"s1","userId":"u1","appId":"app-1","appTierAddOnId":"a1","status":"Active"}}
        """
        let result = try WildwoodJSON.decoder().decode(AddOnSubscriptionReactivateResultModel.self, from: Data(json.utf8))

        #expect(result.success)
        #expect(result.status == "Active")
        #expect(result.subscription?.id == "s1")
    }

    @Test func actionErrorDecodesAndDefaults() throws {
        let error = try WildwoodJSON.decoder().decode(AppTierActionError.self, from: Data(#"{"code":"NotSupported","message":"No route"}"#.utf8))
        #expect(error.code == AppTierActionErrorCodes.notSupported)
        #expect(error.message == "No route")
        #expect(error.status == nil)

        let empty = try WildwoodJSON.decoder().decode(AppTierActionError.self, from: Data("{}".utf8))
        #expect(empty.code.isEmpty)
        #expect(empty.message.isEmpty)
    }
}

// MARK: - Signup outcome

struct SignupOutcomeModelTests {
    @Test func outcomeDecodesTierPacksAndTokenGrant() throws {
        let json = """
        {"userId":"u1","tier":{"tierId":"t1","name":"Pro","pricingId":"p1"},
         "packs":[{"addOnId":"a1","name":"Included pack","status":"granted"},
                  {"addOnId":"a2","name":"Bought pack","status":"trialing","trialEnd":"2026-10-08T00:00:00Z"},
                  {"addOnId":"a3","name":"Refused pack","status":"failed","errorMessage":"Declined"}],
         "tokenGrant":{"tierId":"t1","pricingId":"p1","addOnIds":["a1"],"featureCodes":["DOCUMENTS"]},
         "planActivationPending":true}
        """
        let outcome = try WildwoodJSON.decoder().decode(SignupOutcome.self, from: Data(json.utf8))

        #expect(outcome.userId == "u1")
        #expect(outcome.tier?.tierId == "t1")
        #expect(outcome.tier?.name == "Pro")
        #expect(outcome.tier?.pricingId == "p1")
        #expect(outcome.packs.count == 3)
        #expect(outcome.packs[0].id == "a1")
        #expect(outcome.packs[0].status == SignupPackStatuses.granted)
        #expect(outcome.packs[1].trialEnd != nil)
        #expect(outcome.packs[2].errorMessage == "Declined")
        #expect(outcome.tokenGrant?.addOnIds == ["a1"])
        #expect(outcome.tokenGrant?.featureCodes == ["DOCUMENTS"])
        #expect(outcome.planActivationPending == true)
    }

    @Test func aPlanlessSignupDecodesWithNoTierAndNoPendingFlag() throws {
        let outcome = try WildwoodJSON.decoder().decode(SignupOutcome.self, from: Data(#"{"userId":"u1"}"#.utf8))

        #expect(outcome.tier == nil)
        #expect(outcome.packs.isEmpty)
        #expect(outcome.tokenGrant == nil)
        // Set only when it happened, so nil is not the same as false here.
        #expect(outcome.planActivationPending == nil)
    }
}

// MARK: - Entitlements-changed reasons

struct EntitlementsChangedReasonTests {
    @Test func theSixReasonsMatchTheJsVocabulary() {
        #expect(EntitlementsChangedReason.signup.rawValue == "signup")
        #expect(EntitlementsChangedReason.tierChange.rawValue == "tierChange")
        #expect(EntitlementsChangedReason.addOn.rawValue == "addOn")
        #expect(EntitlementsChangedReason.cancel.rawValue == "cancel")
        #expect(EntitlementsChangedReason.reactivate.rawValue == "reactivate")
        #expect(EntitlementsChangedReason.manual.rawValue == "manual")
        #expect(EntitlementsChangedReason.allCases.count == 6)
    }
}
