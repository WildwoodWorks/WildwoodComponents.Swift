// The registration-mode resolver that replaced the copy each host site carried. The four
// configuration combinations, the unknown-config fallback, and the invite override.
//
// Ported case for case from
// packages/wildwood-react/src/__tests__/registrationMode.test.ts (7 cases), with the TypeScript
// titles kept.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct SignupRegistrationModeTests {
    private func config(_ allowOpenRegistration: Bool, _ allowTokenRegistration: Bool) -> SignupRegistrationSettings {
        SignupRegistrationSettings(
            allowOpenRegistration: allowOpenRegistration,
            allowTokenRegistration: allowTokenRegistration
        )
    }

    @Test("open + token: open sign-up with the optional token entry")
    func openPlusToken() {
        #expect(
            SignupRegistrationMode.resolve(config(true, true))
                == SignupRegistrationMode(
                    closed: false,
                    requireToken: false,
                    allowOpenRegistration: true,
                    showOptionalTokenEntry: true,
                    source: .config
                )
        )
    }

    @Test("open only: open sign-up, no token card")
    func openOnly() {
        #expect(
            SignupRegistrationMode.resolve(config(true, false))
                == SignupRegistrationMode(
                    closed: false,
                    requireToken: false,
                    allowOpenRegistration: true,
                    showOptionalTokenEntry: false,
                    source: .config
                )
        )
    }

    @Test("token only: the token is required")
    func tokenOnly() {
        #expect(
            SignupRegistrationMode.resolve(config(false, true))
                == SignupRegistrationMode(
                    closed: false,
                    requireToken: true,
                    allowOpenRegistration: false,
                    showOptionalTokenEntry: false,
                    source: .config
                )
        )
    }

    @Test("neither: sign-up is closed")
    func neither() {
        #expect(
            SignupRegistrationMode.resolve(config(false, false))
                == SignupRegistrationMode(
                    closed: true,
                    requireToken: true,
                    allowOpenRegistration: false,
                    showOptionalTokenEntry: false,
                    source: .config
                )
        )
    }

    @Test("falls back to open sign-up plus the optional token when the settings are unknown")
    func unknownSettingsFallBack() {
        let mode = SignupRegistrationMode.resolve(nil)
        #expect(
            mode
                == SignupRegistrationMode(
                    closed: false,
                    requireToken: false,
                    allowOpenRegistration: true,
                    showOptionalTokenEntry: true,
                    source: .fallback
                )
        )
        // TypeScript distinguishes `null` from `undefined`; Swift has one "unknown", reached here
        // through the configuration overload as well.
        #expect(SignupRegistrationMode.resolve(configuration: nil) == mode)
    }

    @Test("tokenMode 'required' forces the token path, even for a closed app")
    func requiredTokenModeOverridesTheConfiguration() {
        let expected = SignupRegistrationMode(
            closed: false,
            requireToken: true,
            allowOpenRegistration: false,
            showOptionalTokenEntry: false,
            source: .tokenMode
        )
        // The server validates the invite token itself, so a closed configuration must not block it.
        #expect(SignupRegistrationMode.resolve(config(false, false), tokenMode: .required) == expected)
        #expect(SignupRegistrationMode.resolve(config(true, true), tokenMode: .required) == expected)
        #expect(SignupRegistrationMode.resolve(nil, tokenMode: .required) == expected)
    }

    @Test("tokenMode 'auto' is the configuration's own answer")
    func autoTokenModeIsTheConfigurationsAnswer() {
        #expect(
            SignupRegistrationMode.resolve(config(true, false), tokenMode: .auto)
                == SignupRegistrationMode.resolve(config(true, false))
        )
    }
}
