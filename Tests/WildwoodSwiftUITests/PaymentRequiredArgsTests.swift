// WildwoodPaymentRequiredArgs — what a component hands a host when a plan needs paying for.
//
// The value carries the PLAN's price, not the prorated charge a preview quoted for today: a host
// that paid the proration and let the subscription renew at that amount would undercharge every
// period after the first (JS 05dd7cb).

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct PaymentRequiredArgsTests {
    private func tier(
        id: String = "tier-1",
        name: String = "Pro",
        isFreeTier: Bool = false,
        currency: String? = nil,
        price: Double = 79,
        trialDays: Int? = nil
    ) throws -> AppTierModel {
        let currencyJSON = currency.map { "\"\($0)\"" } ?? "null"
        let trialJSON = trialDays.map { String($0) } ?? "null"
        let json = """
        {"id":"\(id)","appId":"app-1","name":"\(name)","description":"","isFreeTier":\(isFreeTier),\
        "currency":\(currencyJSON),\
        "pricingOptions":[{"id":"tp-1","appTierId":"\(id)","pricingModelId":"pm-1",\
        "pricingModelName":"Monthly","price":\(price),"billingFrequency":"Monthly",\
        "trialDays":\(trialJSON),"isDefault":true}]}
        """
        return try WildwoodJSON.decoder().decode(AppTierModel.self, from: Data(json.utf8))
    }

    @Test func theArgsCarryThePlansOwnPriceAndPricingModel() throws {
        let plan = try tier(price: 79, trialDays: 14)
        let args = WildwoodPaymentRequiredArgs(tier: plan, pricing: plan.pricingOptions.first)

        // The pricing MODEL id, never the tier-pricing LINK id ("tp-1").
        #expect(args.pricingModelId == "pm-1")
        #expect(args.price == 79)
        #expect(args.trialDays == 14)
        #expect(args.isSubscription)
    }

    @Test func theTiersCurrencyBeatsTheCatalogFallback() throws {
        let swissPlan = try tier(currency: "CHF")
        #expect(WildwoodPaymentRequiredArgs(tier: swissPlan, pricing: swissPlan.pricingOptions.first, fallbackCurrency: "USD").currency == "CHF")

        let plainPlan = try tier()
        #expect(WildwoodPaymentRequiredArgs(tier: plainPlan, pricing: plainPlan.pricingOptions.first, fallbackCurrency: "EUR").currency == "EUR")
        #expect(WildwoodPaymentRequiredArgs(tier: plainPlan, pricing: plainPlan.pricingOptions.first).currency == nil)
    }

    @Test func aFreeOrUnpricedPlanIsNotASubscription() throws {
        let freePlan = try tier(isFreeTier: true, price: 0)
        #expect(WildwoodPaymentRequiredArgs(tier: freePlan, pricing: freePlan.pricingOptions.first).isSubscription == false)

        let zeroPriced = try tier(price: 0)
        #expect(WildwoodPaymentRequiredArgs(tier: zeroPriced, pricing: zeroPriced.pricingOptions.first).isSubscription == false)
    }

    @Test func noPricingOptionMeansNoModelAndNoPrice() throws {
        let plan = try tier()
        let args = WildwoodPaymentRequiredArgs(tier: plan, pricing: nil)
        #expect(args.pricingModelId == nil)
        #expect(args.price == 0)
        #expect(args.trialDays == nil)
        #expect(args.isSubscription == false)
    }
}
