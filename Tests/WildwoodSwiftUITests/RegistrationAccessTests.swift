// Registration-gate rules — the Swift twin of react-native's
// registrationAccess.test.ts. The component's `allowRegistration` parameter is
// applied through this resolver, so the gate is exercised as the pure function
// the (iOS-only, unrenderable on the host) component calls.

import Testing
@testable import WildwoodSwiftUI

@MainActor
struct RegistrationAccessTests {
    @Test func followsTheServerConfigurationWhenTheOverrideIsOmitted() {
        #expect(RegistrationAccess.resolve(allowRegistrationProp: nil, configAllowsRegistration: true, view: .login).showRegistration == true)
        #expect(RegistrationAccess.resolve(allowRegistrationProp: nil, configAllowsRegistration: false, view: .login).showRegistration == false)
    }

    @Test func falseOverrideDeniesRegistrationTheConfigurationAllows() {
        #expect(RegistrationAccess.resolve(allowRegistrationProp: false, configAllowsRegistration: true, view: .login).showRegistration == false)
    }

    @Test func trueOverrideAllowsRegistrationTheConfigurationDenies() {
        #expect(RegistrationAccess.resolve(allowRegistrationProp: true, configAllowsRegistration: false, view: .login).showRegistration == true)
    }

    @Test func registerViewCollapsesToLoginWhenRegistrationIsOff() {
        #expect(RegistrationAccess.resolve(allowRegistrationProp: false, configAllowsRegistration: true, view: .register).view == .login)
        #expect(RegistrationAccess.resolve(allowRegistrationProp: nil, configAllowsRegistration: false, view: .register).view == .login)
    }

    @Test func registerViewSurvivesWhenRegistrationIsOn() {
        #expect(RegistrationAccess.resolve(allowRegistrationProp: true, configAllowsRegistration: false, view: .register).view == .register)
        #expect(RegistrationAccess.resolve(allowRegistrationProp: nil, configAllowsRegistration: true, view: .register).view == .register)
    }

    @Test func everyOtherViewPassesThroughUntouched() {
        for view in [AuthView.twoFactor, .passwordReset, .forgotPassword, .disclaimers] {
            #expect(RegistrationAccess.resolve(allowRegistrationProp: false, configAllowsRegistration: false, view: view).view == view)
        }
    }
}
