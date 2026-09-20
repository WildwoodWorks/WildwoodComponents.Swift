// The cross-stack signup outcome, ported from
// packages/wildwood-react-shared/src/registrationSubscription/signupMachine.ts
// (and mirrored by WildwoodComponents.Shared/Models/SignupOutcomeModels.cs).
//
// These are produced by the signup flow rather than read off the wire, but they are Codable on
// the same lenient terms as the response models so a host can persist or replay one.

import Foundation

/// What became of one pack. ``granted`` is a pack the registration token set up — there is a
/// subscription row but no payment transaction behind it, so nothing was charged. String
/// constants (not an enum) to match the checkout statuses verbatim.
public enum SignupPackStatuses {
    public static let trialing = "trialing"
    public static let active = "active"
    public static let failed = "failed"
    public static let granted = "granted"
}

/// `id` is the pack id: a signup buys a pack at most once, so it is unique within one outcome.
public struct SignupPackOutcome: Codable, Sendable, Equatable, Identifiable {
    public var addOnId: String
    public var name: String
    /// One of ``SignupPackStatuses``.
    public var status: String
    public var trialEnd: Date?
    public var errorMessage: String?

    public var id: String { addOnId }

    public init(
        addOnId: String = "",
        name: String = "",
        status: String = "",
        trialEnd: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.addOnId = addOnId
        self.name = name
        self.status = status
        self.trialEnd = trialEnd
        self.errorMessage = errorMessage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        addOnId = try c.decodeIfPresent(String.self, forKey: .addOnId) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        trialEnd = try c.decodeIfPresent(Date.self, forKey: .trialEnd)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

/// The plan the new account ended up on, or nil when the signup chose no plan.
public struct SignupOutcomeTier: Codable, Sendable, Equatable {
    public var tierId: String
    public var name: String
    public var pricingId: String?

    public init(tierId: String = "", name: String = "", pricingId: String? = nil) {
        self.tierId = tierId
        self.name = name
        self.pricingId = pricingId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tierId = try c.decodeIfPresent(String.self, forKey: .tierId) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        pricingId = try c.decodeIfPresent(String.self, forKey: .pricingId)
    }
}

/// What a registration token sets up, as the server's detailed validation reported it.
public struct SignupTokenGrant: Codable, Sendable, Equatable {
    public var tierId: String
    public var pricingId: String?
    public var addOnIds: [String]
    public var featureCodes: [String]

    public init(
        tierId: String = "",
        pricingId: String? = nil,
        addOnIds: [String] = [],
        featureCodes: [String] = []
    ) {
        self.tierId = tierId
        self.pricingId = pricingId
        self.addOnIds = addOnIds
        self.featureCodes = featureCodes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tierId = try c.decodeIfPresent(String.self, forKey: .tierId) ?? ""
        pricingId = try c.decodeIfPresent(String.self, forKey: .pricingId)
        addOnIds = try c.decodeIfPresent([String].self, forKey: .addOnIds) ?? []
        featureCodes = try c.decodeIfPresent([String].self, forKey: .featureCodes) ?? []
    }
}

/// What a finished signup produced, for the host app's completion callback. Granted packs are
/// listed first.
public struct SignupOutcome: Codable, Sendable, Equatable {
    public var userId: String
    public var tier: SignupOutcomeTier?
    public var packs: [SignupPackOutcome]
    public var tokenGrant: SignupTokenGrant?
    /// The account exists but its plan does not: an account-first signup whose payment step was
    /// abandoned. Set only when it happened, so a success screen can say "plan activation is
    /// pending" instead of "your plan is active".
    public var planActivationPending: Bool?

    public init(
        userId: String = "",
        tier: SignupOutcomeTier? = nil,
        packs: [SignupPackOutcome] = [],
        tokenGrant: SignupTokenGrant? = nil,
        planActivationPending: Bool? = nil
    ) {
        self.userId = userId
        self.tier = tier
        self.packs = packs
        self.tokenGrant = tokenGrant
        self.planActivationPending = planActivationPending
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
        tier = try c.decodeIfPresent(SignupOutcomeTier.self, forKey: .tier)
        packs = try c.decodeIfPresent([SignupPackOutcome].self, forKey: .packs) ?? []
        tokenGrant = try c.decodeIfPresent(SignupTokenGrant.self, forKey: .tokenGrant)
        planActivationPending = try c.decodeIfPresent(Bool.self, forKey: .planActivationPending)
    }
}
