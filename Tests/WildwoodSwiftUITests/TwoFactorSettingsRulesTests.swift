import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

// The "app-not-enforcing" notice on the two-factor settings screen (Blazor parity).
struct TwoFactorSettingsRulesTests {
    private func configuration(isEnabled: Bool) throws -> TwoFactorConfiguration {
        try WildwoodJSON.decoder().decode(
            TwoFactorConfiguration.self,
            from: Data(#"{"isEnabled":\#(isEnabled),"isRequired":false,"availableMethods":[],"codeValiditySeconds":300,"maxAttempts":5,"lockoutMinutes":15,"allowRememberDevice":true,"rememberDeviceDays":30}"#.utf8)
        )
    }

    @Test func anAppWithNoProviderDoesNotEnforceTwoFactor() throws {
        #expect(TwoFactorSettingsRules.appDoesNotEnforce(try configuration(isEnabled: false)))
    }

    @Test func anEnforcingAppOrAnUnreadableConfigurationShowsNoNotice() throws {
        #expect(!TwoFactorSettingsRules.appDoesNotEnforce(try configuration(isEnabled: true)))
        #expect(!TwoFactorSettingsRules.appDoesNotEnforce(nil))
    }

    @Test func theNoticeMentionsExistingMethodsOnlyWhenThereAreSome() {
        #expect(!TwoFactorSettingsRules.appNotEnforcingMessage(hasMethods: false).contains("can be removed"))
        #expect(TwoFactorSettingsRules.appNotEnforcingMessage(hasMethods: true).contains("can be removed"))
    }
}
