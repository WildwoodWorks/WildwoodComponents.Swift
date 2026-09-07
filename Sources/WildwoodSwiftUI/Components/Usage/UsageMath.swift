// Pure usage-dashboard rules shared by the dashboard view and its tests — the
// React getBarClass / anyAtWarning / anyOverage logic. Threshold-driven, not
// the server's isAtWarningThreshold, so the 80% default matches every stack.

import Foundation
import WildwoodCore

enum UsageBarState: Equatable { case ok, warning, exceeded }

enum UsageMath {
    static func barState(_ status: AppTierLimitStatusModel, warningThreshold: Double) -> UsageBarState {
        if status.isExceeded { return .exceeded }
        if status.usagePercent >= warningThreshold { return .warning }
        return .ok
    }

    static func anyAtWarning(_ statuses: [AppTierLimitStatusModel], warningThreshold: Double) -> Bool {
        statuses.contains { $0.usagePercent >= warningThreshold || $0.isExceeded }
    }

    static func anyOverage(_ statuses: [AppTierLimitStatusModel]) -> Bool {
        statuses.contains { $0.isExceeded && !$0.isHardBlocked }
    }
}
