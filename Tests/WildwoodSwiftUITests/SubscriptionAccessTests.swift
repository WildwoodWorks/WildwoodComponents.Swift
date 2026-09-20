// The two shared subscription rules: what still grants access, and when a trial end date is
// worth showing (JS 1eefaa1). Both are pure, so every status is covered here rather than through
// a rendered panel.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct SubscriptionAccessTests {
    /// Every status the server sends, so a new one cannot quietly start granting access.
    private static let allStatuses: [String] = [
        "Active", "Trialing", "PendingCancellation", "PendingUpgrade", "PendingDowngrade",
        "PastDue", "Cancelled", "Expired",
    ]

    @Test func onlyThreeStatusesGrantAccess() {
        for status in Self.allStatuses {
            let expected = status == "Active" || status == "Trialing" || status == "PendingCancellation"
            #expect(SubscriptionAccess.grantsAccess(status) == expected, "status \(status)")
        }
    }

    @Test func aMissingStatusGrantsNothing() {
        #expect(SubscriptionAccess.grantsAccess(nil) == false)
        #expect(SubscriptionAccess.grantsAccess("") == false)
        // The comparison is exact, as the JS `includes` check is.
        #expect(SubscriptionAccess.grantsAccess("active") == false)
    }

    @Test func trialEndShowsOnlyWhileTheTrialIsRunning() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let future = now.addingTimeInterval(86_400)

        for status in Self.allStatuses {
            // An Active plan is being paid for: whatever date the row still carries, the trial
            // is over.
            let expected = status != "Active"
            #expect(
                SubscriptionAccess.isTrialRunning(status: status, trialEnd: future, now: now) == expected,
                "status \(status)"
            )
        }
    }

    @Test func aPastTrialEndNeverShows() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let past = now.addingTimeInterval(-86_400)
        for status in Self.allStatuses {
            #expect(
                SubscriptionAccess.isTrialRunning(status: status, trialEnd: past, now: now) == false,
                "status \(status)"
            )
        }
        // The boundary: exactly now is not still running.
        #expect(SubscriptionAccess.isTrialRunning(status: "Trialing", trialEnd: now, now: now) == false)
    }

    @Test func noTrialEndMeansNoLine() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(SubscriptionAccess.isTrialRunning(status: "Trialing", trialEnd: nil, now: now) == false)
    }
}
