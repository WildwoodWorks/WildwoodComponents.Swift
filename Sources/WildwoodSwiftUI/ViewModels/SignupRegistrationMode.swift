// How a signup screen may offer registration, read from the app's live Wildwood authentication
// settings so the screen offers exactly what the server will accept:
//
//   open + token registration -> open sign-up, plus the optional "Have a registration token?" card
//   open registration only    -> open sign-up, no token card
//   token registration only   -> the token step is required
//   neither                   -> sign-up is closed
//
// When the settings can't be read (network error, older API), fall back to open sign-up with the
// optional token card. The server still enforces its own settings, so the fallback can only offer a
// path that is refused with a clear message, never grant one the server wouldn't.
//
// Ported from packages/wildwood-react-shared/src/authentication/registrationMode.ts and mirroring
// WildwoodComponents.Shared/Utilities/SignupRegistrationMode.cs.
//
// Not to be confused with ``RegistrationAccess`` next door, which is a different decision: whether
// the LOGIN component shows a sign-up affordance at all. This one decides how the signup screen
// itself works.

import Foundation
import WildwoodCore

/// Whether the visitor is signing up freely or redeeming an invite.
public enum SignupTokenMode: String, Sendable, Equatable, CaseIterable {
    /// Follow the app's configuration (the host sites' original behaviour).
    case auto
    /// Invite redemption: the visitor arrived with a token, so the token step is the only way in
    /// regardless of what the configuration says.
    case required
}

/// Where a resolved registration mode came from.
public enum SignupRegistrationModeSource: String, Sendable, Equatable, CaseIterable {
    /// Decided by the app's live settings.
    case config
    /// The settings could not be read, so open sign-up plus the optional token entry.
    case fallback
    /// The caller asked for invite redemption, which overrides the settings.
    case tokenMode
}

/// The two flags the decision reads, mapped out of the authentication configuration the caller
/// holds. JS gets this structurally from
/// `Pick<AuthenticationConfiguration, 'allowOpenRegistration' | 'allowTokenRegistration'>`; Swift's
/// `AuthenticationConfiguration` carries both as non-optional `Bool`s (defaulting to false when the
/// server omits them), so the mapping is a straight copy.
public struct SignupRegistrationSettings: Sendable, Equatable {
    /// Anyone may register without a token.
    public var allowOpenRegistration: Bool
    /// A registration token may be redeemed to create an account.
    public var allowTokenRegistration: Bool

    public init(allowOpenRegistration: Bool = false, allowTokenRegistration: Bool = false) {
        self.allowOpenRegistration = allowOpenRegistration
        self.allowTokenRegistration = allowTokenRegistration
    }

    /// Read the two flags off a live authentication configuration.
    public init(configuration: AuthenticationConfiguration) {
        self.allowOpenRegistration = configuration.allowOpenRegistration
        self.allowTokenRegistration = configuration.allowTokenRegistration
    }

    public static func == (lhs: SignupRegistrationSettings, rhs: SignupRegistrationSettings) -> Bool {
        lhs.allowOpenRegistration == rhs.allowOpenRegistration
            && lhs.allowTokenRegistration == rhs.allowTokenRegistration
    }
}

/// The registration paths a signup screen may offer, and where the answer came from.
public struct SignupRegistrationMode: Sendable, Equatable {
    /// No registration path is open: render the "sign-up is closed" panel.
    public var closed: Bool
    /// A registration token must be supplied before an account can be created.
    public var requireToken: Bool
    /// Anyone may sign up without a token.
    public var allowOpenRegistration: Bool
    /// Offer the optional "Have a registration token?" entry alongside open sign-up.
    public var showOptionalTokenEntry: Bool
    /// Which rule produced this answer.
    public var source: SignupRegistrationModeSource

    public init(
        closed: Bool,
        requireToken: Bool,
        allowOpenRegistration: Bool,
        showOptionalTokenEntry: Bool,
        source: SignupRegistrationModeSource
    ) {
        self.closed = closed
        self.requireToken = requireToken
        self.allowOpenRegistration = allowOpenRegistration
        self.showOptionalTokenEntry = showOptionalTokenEntry
        self.source = source
    }

    public static func == (lhs: SignupRegistrationMode, rhs: SignupRegistrationMode) -> Bool {
        lhs.closed == rhs.closed
            && lhs.requireToken == rhs.requireToken
            && lhs.allowOpenRegistration == rhs.allowOpenRegistration
            && lhs.showOptionalTokenEntry == rhs.showOptionalTokenEntry
            && lhs.source == rhs.source
    }

    /// Resolve how a signup screen should offer registration.
    ///
    /// - Parameters:
    ///   - config: the app's authentication settings, or nil while they are unknown.
    ///   - tokenMode: ``SignupTokenMode/required`` forces the token path — the visitor is redeeming
    ///     an invite, and the server validates the token itself, so a closed configuration does not
    ///     block it.
    public static func resolve(
        _ config: SignupRegistrationSettings?,
        tokenMode: SignupTokenMode = .auto
    ) -> SignupRegistrationMode {
        // Invite redemption wins over everything: the link carries a token the server will
        // validate, and an app that has turned open registration off still honours its own
        // invitations.
        if tokenMode == .required {
            return SignupRegistrationMode(
                closed: false,
                requireToken: true,
                allowOpenRegistration: false,
                showOptionalTokenEntry: false,
                source: .tokenMode
            )
        }

        let source: SignupRegistrationModeSource = config != nil ? .config : .fallback
        let open: Bool = config?.allowOpenRegistration ?? true
        let token: Bool = config?.allowTokenRegistration ?? true

        if open {
            return SignupRegistrationMode(
                closed: false,
                requireToken: false,
                allowOpenRegistration: true,
                showOptionalTokenEntry: token,
                source: source
            )
        }
        if token {
            return SignupRegistrationMode(
                closed: false,
                requireToken: true,
                allowOpenRegistration: false,
                showOptionalTokenEntry: false,
                source: source
            )
        }
        return SignupRegistrationMode(
            closed: true,
            requireToken: true,
            allowOpenRegistration: false,
            showOptionalTokenEntry: false,
            source: source
        )
    }

    /// Resolve straight off a live authentication configuration, or nil while it is unknown.
    public static func resolve(
        configuration: AuthenticationConfiguration?,
        tokenMode: SignupTokenMode = .auto
    ) -> SignupRegistrationMode {
        let settings: SignupRegistrationSettings? = configuration.map { SignupRegistrationSettings(configuration: $0) }
        return resolve(settings, tokenMode: tokenMode)
    }
}
