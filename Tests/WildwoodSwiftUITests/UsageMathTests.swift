// Usage threshold rules — the Swift twin of the React getBarClass /
// anyAtWarning / anyOverage helpers used by UsageDashboardComponent.

import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct UsageMathTests {
    private func status(
        _ limitCode: String,
        percent: Double,
        isExceeded: Bool = false,
        isHardBlocked: Bool = false
    ) -> AppTierLimitStatusModel {
        AppTierLimitStatusModel(
            limitCode: limitCode,
            usagePercent: percent,
            isExceeded: isExceeded,
            isHardBlocked: isHardBlocked
        )
    }

    @Test func barStateUsesTheThresholdNotTheServerFlag() {
        #expect(UsageMath.barState(status("a", percent: 79.9), warningThreshold: 80) == .ok)
        #expect(UsageMath.barState(status("a", percent: 80), warningThreshold: 80) == .warning)
        #expect(UsageMath.barState(status("a", percent: 50), warningThreshold: 40) == .warning)
    }

    @Test func exceededOutranksThePercentage() {
        #expect(UsageMath.barState(status("a", percent: 0, isExceeded: true), warningThreshold: 80) == .exceeded)
        #expect(UsageMath.barState(status("a", percent: 250, isExceeded: true), warningThreshold: 80) == .exceeded)
    }

    @Test func anyAtWarningCountsThresholdAndExceededLimits() {
        #expect(UsageMath.anyAtWarning([status("a", percent: 10), status("b", percent: 80)], warningThreshold: 80))
        #expect(UsageMath.anyAtWarning([status("a", percent: 10), status("b", percent: 5, isExceeded: true)], warningThreshold: 80))
        #expect(!UsageMath.anyAtWarning([status("a", percent: 10), status("b", percent: 79)], warningThreshold: 80))
        #expect(!UsageMath.anyAtWarning([], warningThreshold: 80))
    }

    @Test func anyOverageIgnoresHardBlockedLimits() {
        #expect(UsageMath.anyOverage([status("a", percent: 120, isExceeded: true)]))
        #expect(!UsageMath.anyOverage([status("a", percent: 120, isExceeded: true, isHardBlocked: true)]))
        #expect(!UsageMath.anyOverage([status("a", percent: 120)]))
    }
}
