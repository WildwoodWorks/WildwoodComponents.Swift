// Registration funnel events, the SwiftUI twin of `signupFunnel.ts` in @wildwood/react-shared.
//
// The registration form and the signup flows report the funnel steps (signup_view, signup_start,
// signup_submit, signup_error, plan_selected, checkout_start) through the client's attribution
// service. WildwoodCore does the gating: nothing is sent while the app has funnel tracking or signup
// steps off, and the one-shot steps go out once per session, so a form and the flow around it can
// both report the same step without counting it twice.
//
// Two rules hold everywhere here: a funnel call never throws into the form, and a label never carries
// what the visitor typed or a server's message. signup_error carries a fixed category only.

import Foundation
import WildwoodCore

@MainActor
enum SignupFunnel {
    static func view(_ client: WildwoodClient?) {
        client?.attribution.track("signup_view")
    }

    static func start(_ client: WildwoodClient?) {
        client?.attribution.track("signup_start")
    }

    /// The account form was submitted, before the request goes out. A submit with no start before it
    /// (an autofilled form) still started the form, and the one-shot rule drops a repeated start.
    static func submit(_ client: WildwoodClient?) {
        client?.attribution.track("signup_start")
        client?.attribution.track("signup_submit")
    }

    /// A category from ``SignupFunnelRules/errorCategories``.
    static func error(_ client: WildwoodClient?, category: String) {
        client?.attribution.track("signup_error", label: category)
    }

    /// The category of anything a registration threw (its code and status, never its message).
    static func error(_ client: WildwoodClient?, _ error: any Error) {
        Self.error(client, category: SignupFunnelRules.errorCategory(for: error))
    }

    /// The category of a server or flow error code.
    static func error(_ client: WildwoodClient?, code: String?) {
        Self.error(client, category: SignupFunnelRules.errorCategory(code: code))
    }

    /// A plan was chosen: labelled with the tier id (else a slug of its name).
    static func planSelected(_ client: WildwoodClient?, tierId: String?, tierName: String? = nil) {
        guard let key = SignupFunnelRules.planKey(id: tierId, name: tierName) else { return }
        client?.attribution.track("plan_selected", label: key)
    }

    /// The payment step opened for a paid plan: labelled with the pricing option id, else the tier id.
    static func checkoutStart(_ client: WildwoodClient?, pricingId: String?, tierId: String?) {
        guard let key = SignupFunnelRules.planKey(id: pricingId) ?? SignupFunnelRules.planKey(id: tierId) else { return }
        client?.attribution.track("checkout_start", label: key)
    }
}
