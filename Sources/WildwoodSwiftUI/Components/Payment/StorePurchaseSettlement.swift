// The store-transaction finish rule shared by purchase, restore, and the
// Transaction.updates observer — port of the react-native useInAppPurchases rule
// (commit 2766f86). Platform-independent so `swift test` covers it on macOS.

import Foundation
import WildwoodCore

enum StorePurchaseSettlement {
    /// True only when the store transaction may be finished: the backend validated
    /// it AND, for a fresh purchase, returned the Wildwood transaction id that
    /// changeTier/selfSubscribe need. A restore only needs `success`. Anything else
    /// must stay UNFINISHED so the store re-delivers it and it is reprocessed.
    static func canFinish(_ result: PaymentCompletionResult, isRestore: Bool) -> Bool {
        guard result.success else { return false }
        if isRestore { return true }
        guard let id = result.transactionId, !id.isEmpty else { return false }
        return true
    }
}
