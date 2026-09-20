// AddOnRowRules — the pack-row decisions the AddOnsPanel renders.
//
// The rules are covered over EVERY status, because the bug they fix was a Cancelled row being
// listed under "Active Add-Ons" with a Cancel button while its pack was never offered again.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct AddOnRowRulesTests {
    private static let allStatuses: [String] = [
        "Active", "Trialing", "PendingCancellation", "PendingUpgrade", "PendingDowngrade",
        "PastDue", "Cancelled", "Expired",
    ]

    // MARK: - Fixtures

    private func subscription(
        id: String = "sub-1",
        addOnId: String = "pack-1",
        name: String = "Analytics Pack",
        status: String = "Active",
        isBundled: Bool = false,
        paymentTransactionId: String? = "txn-1",
        endDate: String? = "2026-12-01T00:00:00Z",
        currentPeriodEnd: String? = nil
    ) throws -> UserAddOnSubscriptionModel {
        let txn = paymentTransactionId.map { "\"\($0)\"" } ?? "null"
        let end = endDate.map { "\"\($0)\"" } ?? "null"
        let period = currentPeriodEnd.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"id":"\(id)","userId":"u-1","appId":"app-1","appTierAddOnId":"\(addOnId)",\
        "addOnName":"\(name)","status":"\(status)","isBundled":\(isBundled),\
        "paymentTransactionId":\(txn),"endDate":\(end),"currentPeriodEnd":\(period),\
        "startDate":"2026-01-01T00:00:00Z"}
        """
        return try WildwoodJSON.decoder().decode(UserAddOnSubscriptionModel.self, from: Data(json.utf8))
    }

    private func addOn(
        id: String = "pack-1",
        name: String = "Analytics Pack",
        currency: String? = nil,
        trialDays: Int? = nil,
        pricingTrialDays: Int? = nil,
        price: Double = 9,
        billingFrequency: String = "Monthly",
        bundledInTierIds: [String] = []
    ) throws -> AppTierAddOnModel {
        let currencyJSON = currency.map { "\"\($0)\"" } ?? "null"
        let trialJSON = trialDays.map { String($0) } ?? "null"
        let pricingTrialJSON = pricingTrialDays.map { String($0) } ?? "null"
        let bundled = bundledInTierIds.map { "\"\($0)\"" }.joined(separator: ",")
        let json = """
        {"id":"\(id)","appId":"app-1","name":"\(name)","description":"","currency":\(currencyJSON),\
        "trialDays":\(trialJSON),"bundledInTierIds":[\(bundled)],\
        "pricingOptions":[{"id":"aop-1","pricingModelId":"pm-1","pricingModelName":"Monthly",\
        "price":\(price),"billingFrequency":"\(billingFrequency)","trialDays":\(pricingTrialJSON),\
        "isDefault":true}]}
        """
        return try WildwoodJSON.decoder().decode(AppTierAddOnModel.self, from: Data(json.utf8))
    }

    // MARK: - Ownership

    @Test func ownershipFollowsTheAccessGrantingStatuses() throws {
        for status in Self.allStatuses {
            let row = try subscription(status: status)
            let expected = SubscriptionAccess.grantsAccess(status)
            #expect(AddOnRowRules.ownsAddOn([row], addOnId: "pack-1") == expected, "status \(status)")
            #expect(AddOnRowRules.ownedRows([row]).count == (expected ? 1 : 0), "status \(status)")
        }
    }

    @Test func aCancelledPackIsOfferedAgainAndAScheduledOneIsNot() throws {
        let cancelled = try subscription(status: "Cancelled")
        let pending = try subscription(status: "PendingCancellation")
        let pack = try addOn()

        #expect(AddOnRowRules.availableRows([pack], subscriptions: [cancelled]).count == 1)
        #expect(AddOnRowRules.availableRows([pack], subscriptions: [pending]).isEmpty)
    }

    @Test func ownershipIgnoresIdCasing() throws {
        let row = try subscription(addOnId: "PACK-1", status: "Active")
        #expect(AddOnRowRules.ownsAddOn([row], addOnId: "pack-1"))
        #expect(AddOnRowRules.ownsAddOn([row], addOnId: "") == false)
    }

    @Test func bundlingIgnoresTierIdCasing() throws {
        let pack = try addOn(bundledInTierIds: ["TIER-A"])
        #expect(AddOnRowRules.isBundledInTier(pack, currentTierId: "tier-a"))
        #expect(AddOnRowRules.isBundledInTier(pack, currentTierId: "tier-b") == false)
        #expect(AddOnRowRules.isBundledInTier(pack, currentTierId: nil) == false)
    }

    // MARK: - Complimentary

    @Test func complimentaryIsNoPaymentAndNoBundle() throws {
        let granted = try subscription(paymentTransactionId: nil)
        let blankTransaction = try subscription(paymentTransactionId: "")
        let billed = try subscription(paymentTransactionId: "txn-1")
        let bundled = try subscription(isBundled: true, paymentTransactionId: nil)

        #expect(AddOnRowRules.isComplimentary(granted))
        #expect(AddOnRowRules.isComplimentary(blankTransaction))
        #expect(AddOnRowRules.isComplimentary(billed) == false)
        #expect(AddOnRowRules.isComplimentary(bundled) == false)
    }

    @Test func aGrantedRowPromisesNoRenewalAndOffersNoReactivate() throws {
        let row = try subscription(status: "Active", paymentTransactionId: nil)
        let rules = AddOnRowRules.describe(row)

        #expect(rules.complimentary)
        #expect(rules.showsIncludedBadge)
        #expect(rules.dateLine == AddOnDateLine.none)
        #expect(rules.endDate == nil)
        #expect(rules.offersReactivate == false)
        #expect(rules.offersCancel)
        #expect(rules.cancelMessage == AddOnsPanelLabels().cancelIncluded)
    }

    // MARK: - Row decisions

    @Test func aBilledRowRenews() throws {
        let row = try subscription(status: "Active")
        let rules = AddOnRowRules.describe(row)
        #expect(rules.statusLabel == "Active")
        #expect(rules.dateLine == AddOnDateLine.renews)
        #expect(rules.endDate != nil)
        #expect(rules.offersCancel)
        #expect(rules.offersReactivate == false)
        #expect(rules.cancelMessage == AddOnsPanelLabels().cancelBilled)
    }

    @Test func aScheduledCancellationSaysWhenAndOffersReactivate() throws {
        let row = try subscription(status: "PendingCancellation")
        let rules = AddOnRowRules.describe(row)
        #expect(rules.cancelling)
        #expect(rules.statusLabel == "Cancellation Scheduled")
        #expect(rules.dateLine == AddOnDateLine.cancels)
        #expect(rules.offersReactivate)
        // Nothing to cancel twice.
        #expect(rules.offersCancel == false)
    }

    @Test func aScheduledCancellationWithNoDateStillSaysSo() throws {
        let row = try subscription(status: "PendingCancellation", endDate: nil)
        let rules = AddOnRowRules.describe(row)
        #expect(rules.dateLine == AddOnDateLine.cancelsAtPeriodEnd)
        #expect(rules.endDate == nil)
    }

    @Test func theRenewalDateFallsBackToTheCurrentPeriodEnd() throws {
        let row = try subscription(status: "Active", endDate: nil, currentPeriodEnd: "2026-11-01T00:00:00Z")
        #expect(AddOnRowRules.rowEndDate(row) != nil)
        #expect(AddOnRowRules.describe(row).dateLine == AddOnDateLine.renews)
    }

    @Test func aBundledRowOffersNothing() throws {
        let row = try subscription(status: "Active", isBundled: true)
        let rules = AddOnRowRules.describe(row)
        #expect(rules.statusLabel == "Bundled")
        #expect(rules.offersCancel == false)
        #expect(rules.offersReactivate == false)
        #expect(rules.complimentary == false)
    }

    @Test func aSurfaceThatOffersNeitherActionSaysSo() throws {
        let activeRow = try subscription(status: "Active")
        let pendingRow = try subscription(status: "PendingCancellation")
        #expect(AddOnRowRules.describe(activeRow, canCancel: false).offersCancel == false)
        #expect(AddOnRowRules.describe(pendingRow, canReactivate: false).offersReactivate == false)
    }

    // MARK: - Copy

    @Test func failureMessageIsNeverEmpty() {
        #expect(
            AddOnRowRules.failureMessage(.subscribe, name: "Analytics Pack", serverMessage: nil)
                == "Could not subscribe to Analytics Pack. Please try again."
        )
        #expect(
            AddOnRowRules.failureMessage(.cancel, name: nil, serverMessage: nil)
                == "Could not cancel this pack. Please try again."
        )
        #expect(
            AddOnRowRules.failureMessage(.reactivate, name: "  ", serverMessage: "   ")
                == "Could not reactivate this pack. Please try again."
        )
        // The server's own words win: "you already own that pack" is not "please try again".
        #expect(
            AddOnRowRules.failureMessage(.subscribe, name: "Analytics Pack", serverMessage: "You already own this pack.")
                == "You already own this pack."
        )
    }

    @Test func theTrialComesFromThePricingOptionFirst() throws {
        let packOnly = try addOn(trialDays: 7)
        #expect(AddOnRowRules.trialLabel(addOn: packOnly, pricing: AddOnRowRules.defaultPricing(packOnly)) == "7-day free trial")

        let optionWins = try addOn(trialDays: 7, pricingTrialDays: 14)
        #expect(AddOnRowRules.trialLabel(addOn: optionWins, pricing: AddOnRowRules.defaultPricing(optionWins)) == "14-day free trial")

        let none = try addOn()
        #expect(AddOnRowRules.trialLabel(addOn: none, pricing: AddOnRowRules.defaultPricing(none)) == "")
    }

    @Test func priceUsesThePacksOwnCurrencyThenTheCatalogs() throws {
        let swissPack = try addOn(currency: "CHF", price: 79)
        #expect(
            AddOnRowRules.formatPrice(addOn: swissPack, pricing: AddOnRowRules.defaultPricing(swissPack), catalogCurrency: "USD")
                == "CHF\u{00A0}79.00"
        )

        let plainPack = try addOn(price: 79)
        #expect(
            AddOnRowRules.formatPrice(addOn: plainPack, pricing: AddOnRowRules.defaultPricing(plainPack), catalogCurrency: "EUR")
                == "\u{20AC}79.00"
        )
        // Nothing anywhere still prices in dollars rather than throwing.
        #expect(
            AddOnRowRules.formatPrice(addOn: plainPack, pricing: AddOnRowRules.defaultPricing(plainPack), catalogCurrency: nil)
                == "$79.00"
        )
    }

    @Test func billingSuffixIsLowercasedWithAMonthlyDefault() throws {
        let pack = try addOn(billingFrequency: "Yearly")
        #expect(AddOnRowRules.billingSuffix(AddOnRowRules.defaultPricing(pack)) == "yearly")
        #expect(AddOnRowRules.billingSuffix(nil) == "month")
    }
}
