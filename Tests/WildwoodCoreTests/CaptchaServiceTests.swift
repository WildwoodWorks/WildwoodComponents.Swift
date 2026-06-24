// CaptchaService is pure in-memory config state (the WKWebView renders from it).
// CaptchaConfiguration has only a decoding init, so configs are built from JSON.

import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct CaptchaServiceTests {
    private func config(_ json: String) throws -> CaptchaConfiguration {
        try JSONDecoder().decode(CaptchaConfiguration.self, from: Data(json.utf8))
    }

    @Test func setAndGetConfigurationRoundtrips() throws {
        let service = CaptchaService()
        service.setConfiguration(try config(#"{"isEnabled":true,"providerType":"reCAPTCHA","siteKey":"sk-1"}"#))

        #expect(service.getConfiguration()?.siteKey == "sk-1")
    }

    @Test func isRequiredTrueWhenEnabledWithSiteKeyAndFlag() throws {
        let service = CaptchaService()
        service.setConfiguration(try config(#"{"isEnabled":true,"siteKey":"sk","requireForLogin":true}"#))

        #expect(service.isRequired(forLogin: true) == true)
        // The flag is per-flow: registration wasn't required.
        #expect(service.isRequired(forRegistration: true) == false)
    }

    @Test func isRequiredFalseWhenDisabled() throws {
        let service = CaptchaService()
        service.setConfiguration(try config(#"{"isEnabled":false,"siteKey":"sk","requireForLogin":true}"#))

        #expect(service.isRequired(forLogin: true) == false)
    }

    @Test func isRequiredFalseWhenNoSiteKey() throws {
        let service = CaptchaService()
        service.setConfiguration(try config(#"{"isEnabled":true,"requireForLogin":true}"#))

        #expect(service.isRequired(forLogin: true) == false)
    }

    @Test func isRequiredFalseWithoutConfiguration() {
        #expect(CaptchaService().isRequired(forLogin: true) == false)
    }
}
