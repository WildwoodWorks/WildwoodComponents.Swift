// Shared registration gate — port of @wildwood/react-shared
// authentication/registrationAccess.ts. The component-level `allowRegistration`
// override beats the server configuration in both directions; nil leaves the
// configuration in charge. Pure so it is unit-testable without rendering.

import Foundation

public struct RegistrationAccess: Sendable, Equatable {
    /// Whether the sign-up affordance should be rendered.
    public var showRegistration: Bool
    /// The view to render: `.register` collapses to `.login` when registration is off.
    public var view: AuthView

    public init(showRegistration: Bool, view: AuthView) {
        self.showRegistration = showRegistration
        self.view = view
    }

    /// - Parameters:
    ///   - allowRegistrationProp: the component's `allowRegistration` parameter; when
    ///     non-nil it wins over the server configuration in both directions.
    ///   - configAllowsRegistration: `WildwoodAuthModel.allowRegistration`.
    ///   - view: the model's current view.
    public static func resolve(allowRegistrationProp: Bool?, configAllowsRegistration: Bool, view: AuthView) -> RegistrationAccess {
        let showRegistration = allowRegistrationProp ?? configAllowsRegistration
        // Collapse here (not by writing model state during render) so the register
        // view stays unreachable even if it was active when the override flipped.
        return RegistrationAccess(
            showRegistration: showRegistration,
            view: !showRegistration && view == .register ? .login : view
        )
    }
}
