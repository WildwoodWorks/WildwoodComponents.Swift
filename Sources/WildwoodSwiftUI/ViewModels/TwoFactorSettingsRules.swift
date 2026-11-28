// The two-factor settings screen's decisions, kept out of the iOS-gated view so they can be tested
// without a simulator (the same split as TierCardRules).

import Foundation
import WildwoodCore

public enum TwoFactorSettingsRules {
    /// The named app has no two-factor provider enabled, so its sign-in never asks for a second
    /// factor. Nil (the configuration could not be read) is NOT "does not enforce": the screen
    /// stays as it always was. Port of Blazor's `_appDoesNotEnforce => _appConfiguration is { IsEnabled: false }`.
    public static func appDoesNotEnforce(_ configuration: TwoFactorConfiguration?) -> Bool {
        configuration?.isEnabled == false
    }

    /// The notice's wording, identical to the web and React Native screens.
    public static func appNotEnforcingMessage(hasMethods: Bool) -> String {
        let base = "Two-factor authentication is not enabled for this application, so signing in will not ask for a code."
        return hasMethods ? base + " Your existing methods are listed below and can be removed." : base
    }
}
