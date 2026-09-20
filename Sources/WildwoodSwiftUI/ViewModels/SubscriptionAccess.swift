// One rule for what "subscribed" means, and one for when a trial is still running.
//
// Ported from packages/wildwood-react-shared/src/subscription/statusDisplay.ts (`grantsAccess`)
// and packages/wildwood-react/src/components/subscription/admin/SubscriptionStatusPanel.tsx
// (JS 1eefaa1); the twin of WildwoodComponents.Shared/Utilities/SubscriptionAccess.cs. Pure, so
// both rules are unit-testable on macOS without rendering anything.

import Foundation

public enum SubscriptionAccess {
    /// Statuses in which a subscription still grants what it pays for. A row scheduled to cancel
    /// keeps access to the end of the period, so it counts; a Cancelled or Expired row grants
    /// nothing and the plan or pack behind it is on offer again.
    public static let accessGrantingStatuses: [String] = ["Active", "Trialing", "PendingCancellation"]

    /// True when the status is one of ``accessGrantingStatuses``.
    ///
    /// The comparison is exact, as the JS `includes` check is — the server sends these statuses in
    /// exactly this casing.
    public static func grantsAccess(_ status: String?) -> Bool {
        guard let status, !status.isEmpty else { return false }
        return accessGrantingStatuses.contains(status)
    }

    /// True when a subscription's trial is still running, which is the only time a trial end date
    /// is worth showing.
    ///
    /// The server keeps a finished trial's end date on the row — that is how it records that the
    /// account has already had its trial for the app. Showing it unconditionally put "Trial ends"
    /// with a stale date on an Active, paid plan. Two conditions rule that out: the plan must not
    /// be Active (a running trial reads Trialing), and the date must still be ahead of `now`.
    public static func isTrialRunning(status: String?, trialEnd: Date?, now: Date = Date()) -> Bool {
        guard let trialEnd else { return false }
        if status == "Active" { return false }
        return trialEnd > now
    }
}
