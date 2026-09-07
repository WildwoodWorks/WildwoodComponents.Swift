// The StoreKit finish rule: a store transaction may be finished only after a
// successful validation that — for a fresh purchase — returned the Wildwood
// transaction id. Lives in an unguarded file so it is covered on the macOS host,
// where the iOS-guarded StoreKit pipeline cannot be built.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

struct StorePurchaseSettlementTests {
    private func result(_ json: String) throws -> PaymentCompletionResult {
        try WildwoodJSON.decoder().decode(PaymentCompletionResult.self, from: Data(json.utf8))
    }

    @Test func freshPurchaseFinishesWhenValidationReturnsATransactionId() throws {
        let validated = try result(#"{"success":true,"transactionId":"ww-txn-1"}"#)
        #expect(StorePurchaseSettlement.canFinish(validated, isRestore: false) == true)
    }

    @Test func freshPurchaseStaysUnfinishedWithoutATransactionId() throws {
        let validated = try result(#"{"success":true}"#)
        #expect(StorePurchaseSettlement.canFinish(validated, isRestore: false) == false)
    }

    @Test func freshPurchaseStaysUnfinishedOnAnEmptyTransactionId() throws {
        let validated = try result(#"{"success":true,"transactionId":""}"#)
        #expect(StorePurchaseSettlement.canFinish(validated, isRestore: false) == false)
    }

    @Test func restoreFinishesOnSuccessAlone() throws {
        let validated = try result(#"{"success":true}"#)
        #expect(StorePurchaseSettlement.canFinish(validated, isRestore: true) == true)
    }

    @Test func failedValidationNeverFinishes() throws {
        let failed = try result(#"{"success":false,"transactionId":"ww-txn-1","errorMessage":"bad receipt"}"#)
        #expect(StorePurchaseSettlement.canFinish(failed, isRestore: false) == false)
        #expect(StorePurchaseSettlement.canFinish(failed, isRestore: true) == false)
    }
}
