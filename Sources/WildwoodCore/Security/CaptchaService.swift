// CAPTCHA service. The JS SDK injects provider scripts into the page; on iOS
// the widget runs inside a WKWebView (CaptchaWebView in WildwoodSwiftUI). This
// core service holds the active configuration the web view renders from.

import Foundation
import Synchronization

public final class CaptchaService: Sendable {
    private let configuration = Mutex<CaptchaConfiguration?>(nil)

    public init() {}

    public func setConfiguration(_ config: CaptchaConfiguration) {
        configuration.withLock { $0 = config }
    }

    public func getConfiguration() -> CaptchaConfiguration? {
        configuration.withLock { $0 }
    }

    /// Whether a captcha challenge is required for the given flow.
    public func isRequired(forLogin: Bool = false, forRegistration: Bool = false, forPasswordReset: Bool = false) -> Bool {
        guard let config = getConfiguration(), config.isEnabled, config.siteKey?.isEmpty == false else { return false }
        if forLogin { return config.requireForLogin }
        if forRegistration { return config.requireForRegistration }
        if forPasswordReset { return config.requireForPasswordReset }
        return false
    }
}
