// The signup flow, as a pure reducer.
//
// The default order is pay-first, because the plan's card has to be taken BEFORE the account exists
// — otherwise a card that fails leaves a half-made account on a plan nobody paid for:
//
//   1 mode + catalog loaded
//   2 register form (mounted once the mode is known)
//   3 token check — a plan grant skips the plan and the payment, and removes granted packs;
//     invite redemption (`tokenMode: .required`) skips the plan and the packs entirely
//   4 plan
//   5 packs
//   6 plan payment (before the account exists)
//   7 register, log in, link, self-subscribe
//   8 disclaimers
//   9 pack checkout (after login, because packs are bought as the signed-in user)
//  10 success
//
// `paymentOrder: .afterAccount` swaps 6 and 7, and is what the store-billed stacks want: a
// StoreKit or Play purchase that succeeds before a registration that then fails strands a paid
// subscription with no account to attach it to, which is worse than an account with no plan. The
// payment step then sits between the account and the disclaimers, and a customer who walks away
// from it still finishes the signup — with the plan's activation pending, said in so many words.
// The REDUCER default stays `.beforeAccount`, exactly as TypeScript and C# ship it; the Swift
// driver passes `.afterAccount` in its options.
//
// Step 2 is a gate, not just an order: nothing past the form may run until it has been submitted.
// A signup link that preselects a plan offers "change plan" beside the form, so a visitor can be at
// the plan grid with an empty form — choosing there takes them back to the form with their new
// plan, never onward to a card form or an account creation that has no details to work with.
//
// No SwiftUI and no client here: the driver model that runs this performs the effects and feeds
// results back, and the views read `step`. Async steps carry a ``StepToken`` so a duplicated task
// or a callback that fires twice cannot advance the flow twice.
//
// Ported from packages/wildwood-react-shared/src/registrationSubscription/signupMachine.ts and
// mirroring WildwoodComponents.Shared/RegistrationSubscription/SignupMachine.cs.

import Foundation
import WildwoodCore

// MARK: - Steps

/// Where the signup flow is.
public enum SignupStep: String, Sendable, Equatable, CaseIterable {
    case loading
    case closed
    case register
    case token
    case plan
    case packs
    case payment
    case creating
    case disclaimers
    case packCheckout
    case done
    case failed
}

/// The steps the flow walks in order (TS `FORM_ORDER`). Everything before ``creating`` may be
/// skipped. The raw values ARE the order.
public enum SignupFormStep: Int, Sendable, Equatable, CaseIterable {
    case register = 0
    case token = 1
    case plan = 2
    case packs = 3
    case payment = 4
    case creating = 5

    /// The flow step this form step corresponds to.
    public var step: SignupStep {
        switch self {
        case .register: return .register
        case .token: return .token
        case .plan: return .plan
        case .packs: return .packs
        case .payment: return .payment
        case .creating: return .creating
        }
    }
}

/// The steps a view may navigate back to. TypeScript constrains the `GO_TO` payload with
/// `Extract<SignupStep, 'register' | 'token' | 'plan' | 'packs' | 'payment'>`; a dedicated enum is
/// the Swift spelling of the same constraint, so a non-form target cannot even be expressed.
public enum SignupGoToStep: String, Sendable, Equatable, CaseIterable {
    case register
    case token
    case plan
    case packs
    case payment

    /// The flow step this target corresponds to.
    public var step: SignupStep {
        switch self {
        case .register: return .register
        case .token: return .token
        case .plan: return .plan
        case .packs: return .packs
        case .payment: return .payment
        }
    }
}

// MARK: - Options

/// Whether the flow walks a plan step.
public enum SignupPlanSelection: String, Sendable, Equatable, CaseIterable {
    case choose
    /// Leave the plan to the app (a single-plan product, or a plan chosen elsewhere).
    case skip
}

/// Whether the flow walks a pack step.
public enum SignupPackSelection: String, Sendable, Equatable, CaseIterable {
    case choose
    /// Hide the pack step.
    case none
}

/// When the plan's card is taken. ``beforeAccount`` is the web order — nothing is created until the
/// money is in. ``afterAccount`` is the store-billed order — nothing is charged until there is an
/// account to attach it to.
public enum SignupPaymentOrder: String, Sendable, Equatable, CaseIterable {
    case beforeAccount
    case afterAccount
}

/// What the visitor is buying.
public struct SignupSelection: Sendable, Equatable {
    public var tierId: String?
    public var pricingId: String?
    public var addOnIds: [String]

    public init(tierId: String? = nil, pricingId: String? = nil, addOnIds: [String] = []) {
        self.tierId = tierId
        self.pricingId = pricingId
        self.addOnIds = addOnIds
    }

    public static func == (lhs: SignupSelection, rhs: SignupSelection) -> Bool {
        lhs.tierId == rhs.tierId && lhs.pricingId == rhs.pricingId && lhs.addOnIds == rhs.addOnIds
    }
}

/// Display names from the catalog, so an outcome can name a tier/pack without re-reading it.
public struct SignupCatalogNames: Sendable, Equatable {
    public var tiers: [String: String]
    public var addOns: [String: String]

    public init(tiers: [String: String] = [:], addOns: [String: String] = [:]) {
        self.tiers = tiers
        self.addOns = addOns
    }

    public static func == (lhs: SignupCatalogNames, rhs: SignupCatalogNames) -> Bool {
        lhs.tiers == rhs.tiers && lhs.addOns == rhs.addOns
    }
}

/// How one run of the signup flow is configured.
public struct SignupMachineOptions: Sendable, Equatable {
    /// ``SignupTokenMode/required`` is invite redemption: the token step is the only way in, and
    /// packs are skipped.
    public var tokenMode: SignupTokenMode
    public var planSelection: SignupPlanSelection
    public var packSelection: SignupPackSelection
    /// When the plan's card is taken. Default ``SignupPaymentOrder/beforeAccount``.
    public var paymentOrder: SignupPaymentOrder
    /// A selection the signup link already made.
    public var selection: SignupSelection?

    public init(
        tokenMode: SignupTokenMode = .auto,
        planSelection: SignupPlanSelection = .choose,
        packSelection: SignupPackSelection = .choose,
        paymentOrder: SignupPaymentOrder = .beforeAccount,
        selection: SignupSelection? = nil
    ) {
        self.tokenMode = tokenMode
        self.planSelection = planSelection
        self.packSelection = packSelection
        self.paymentOrder = paymentOrder
        self.selection = selection
    }

    public static func == (lhs: SignupMachineOptions, rhs: SignupMachineOptions) -> Bool {
        lhs.tokenMode == rhs.tokenMode
            && lhs.planSelection == rhs.planSelection
            && lhs.packSelection == rhs.packSelection
            && lhs.paymentOrder == rhs.paymentOrder
            && lhs.selection == rhs.selection
    }
}

/// The options with every default filled in, so the reducer never re-applies them.
public struct ResolvedSignupOptions: Sendable, Equatable {
    public var tokenMode: SignupTokenMode
    public var planSelection: SignupPlanSelection
    public var packSelection: SignupPackSelection
    public var paymentOrder: SignupPaymentOrder

    public init(
        tokenMode: SignupTokenMode = .auto,
        planSelection: SignupPlanSelection = .choose,
        packSelection: SignupPackSelection = .choose,
        paymentOrder: SignupPaymentOrder = .beforeAccount
    ) {
        self.tokenMode = tokenMode
        self.planSelection = planSelection
        self.packSelection = packSelection
        self.paymentOrder = paymentOrder
    }

    public static func == (lhs: ResolvedSignupOptions, rhs: ResolvedSignupOptions) -> Bool {
        lhs.tokenMode == rhs.tokenMode
            && lhs.planSelection == rhs.planSelection
            && lhs.packSelection == rhs.packSelection
            && lhs.paymentOrder == rhs.paymentOrder
    }
}

// MARK: - State

public struct SignupState: Sendable, Equatable {
    public var step: SignupStep
    /// The async step in flight, or nil. Results carrying another token are ignored.
    public var token: StepToken?
    public var options: ResolvedSignupOptions

    /// The registration mode, once the resolver has answered.
    public var mode: SignupRegistrationMode?
    public var modeReady: Bool
    public var catalogReady: Bool
    public var names: SignupCatalogNames

    public var selection: SignupSelection
    /// Whether the chosen plan has to be paid for before the account is created.
    public var planRequiresPayment: Bool
    /// The plan was decided before the form opened — a signup link's plan, or the app's default in
    /// a `skip` flow — so the plan step is not walked. The visitor is shown what they are getting
    /// and a way back to the grid (a ``SignupEvent/goTo(step:)`` to `plan`) rather than a grid they
    /// have already chosen from.
    public var planPreset: Bool

    /// Whether the registration form has actually been submitted.
    ///
    /// Everything after the form spends the visitor's money or creates their account, and both need
    /// the details the form collects. "Change plan" can send them to the grid before they have
    /// typed anything, so a plan or a pack chosen while this is false takes them back to the form
    /// rather than onward — nothing may run ahead of it.
    public var formSubmitted: Bool

    public var email: String
    public var userId: String
    public var paymentTransactionId: String?

    /// The `payment` step is the ACCOUNT-FIRST one: the account already exists, so completing it
    /// carries on to the disclaimers rather than to `creating`, and abandoning it is allowed.
    /// Always false in the pay-first order.
    public var paymentAfterAccount: Bool
    /// What ``SignupEvent/accountCreated(token:userId:requiresDisclaimers:)`` said about
    /// disclaimers, remembered across an account-first payment step so the machine still knows
    /// where to go once the card is done with.
    public var pendingDisclaimers: Bool
    /// The account was created but its plan was not paid for: the customer walked away from the
    /// card. Cleared again if they go back to the card and it goes through, so a retry that
    /// succeeds does not leave a paying customer being told their plan is still pending.
    public var planActivationPending: Bool

    /// The registration token as typed, once validated.
    public var tokenValue: String?
    public var tokenGrant: SignupTokenGrant?
    /// A token validation is in flight.
    public var tokenChecking: Bool
    /// A rejected token: a form-level message, not a failed flow.
    public var tokenError: String?

    /// Packs still to buy after login — what was chosen, minus anything the grant already covers.
    public var packsToBuy: [String]

    /// Whether the visitor was ALREADY signed in when the flow started. Latched at the first
    /// ``SignupEvent/initialize(signedIn:)``.
    public var alreadySignedInLatched: Bool
    public var initialized: Bool

    public var outcome: SignupOutcome?
    public var error: String?
    /// Which step a ``SignupEvent/retry`` goes back to.
    public var retryFrom: SignupStep?

    public init(
        step: SignupStep = .loading,
        token: StepToken? = nil,
        options: ResolvedSignupOptions = ResolvedSignupOptions(),
        mode: SignupRegistrationMode? = nil,
        modeReady: Bool = false,
        catalogReady: Bool = false,
        names: SignupCatalogNames = SignupCatalogNames(),
        selection: SignupSelection = SignupSelection(),
        planRequiresPayment: Bool = false,
        planPreset: Bool = false,
        formSubmitted: Bool = false,
        email: String = "",
        userId: String = "",
        paymentTransactionId: String? = nil,
        paymentAfterAccount: Bool = false,
        pendingDisclaimers: Bool = false,
        planActivationPending: Bool = false,
        tokenValue: String? = nil,
        tokenGrant: SignupTokenGrant? = nil,
        tokenChecking: Bool = false,
        tokenError: String? = nil,
        packsToBuy: [String] = [],
        alreadySignedInLatched: Bool = false,
        initialized: Bool = false,
        outcome: SignupOutcome? = nil,
        error: String? = nil,
        retryFrom: SignupStep? = nil
    ) {
        self.step = step
        self.token = token
        self.options = options
        self.mode = mode
        self.modeReady = modeReady
        self.catalogReady = catalogReady
        self.names = names
        self.selection = selection
        self.planRequiresPayment = planRequiresPayment
        self.planPreset = planPreset
        self.formSubmitted = formSubmitted
        self.email = email
        self.userId = userId
        self.paymentTransactionId = paymentTransactionId
        self.paymentAfterAccount = paymentAfterAccount
        self.pendingDisclaimers = pendingDisclaimers
        self.planActivationPending = planActivationPending
        self.tokenValue = tokenValue
        self.tokenGrant = tokenGrant
        self.tokenChecking = tokenChecking
        self.tokenError = tokenError
        self.packsToBuy = packsToBuy
        self.alreadySignedInLatched = alreadySignedInLatched
        self.initialized = initialized
        self.outcome = outcome
        self.error = error
        self.retryFrom = retryFrom
    }

    // Written out rather than synthesised so a member whose type stops being Equatable is a
    // compile error here rather than a silently dropped conformance.
    public static func == (lhs: SignupState, rhs: SignupState) -> Bool {
        lhs.step == rhs.step
            && lhs.token == rhs.token
            && lhs.options == rhs.options
            && lhs.mode == rhs.mode
            && lhs.modeReady == rhs.modeReady
            && lhs.catalogReady == rhs.catalogReady
            && lhs.names == rhs.names
            && lhs.selection == rhs.selection
            && lhs.planRequiresPayment == rhs.planRequiresPayment
            && lhs.planPreset == rhs.planPreset
            && lhs.formSubmitted == rhs.formSubmitted
            && lhs.email == rhs.email
            && lhs.userId == rhs.userId
            && lhs.paymentTransactionId == rhs.paymentTransactionId
            && lhs.paymentAfterAccount == rhs.paymentAfterAccount
            && lhs.pendingDisclaimers == rhs.pendingDisclaimers
            && lhs.planActivationPending == rhs.planActivationPending
            && lhs.tokenValue == rhs.tokenValue
            && lhs.tokenGrant == rhs.tokenGrant
            && lhs.tokenChecking == rhs.tokenChecking
            && lhs.tokenError == rhs.tokenError
            && lhs.packsToBuy == rhs.packsToBuy
            && lhs.alreadySignedInLatched == rhs.alreadySignedInLatched
            && lhs.initialized == rhs.initialized
            && lhs.outcome == rhs.outcome
            && lhs.error == rhs.error
            && lhs.retryFrom == rhs.retryFrom
    }
}

/// What a signup reducer call answers.
public typealias SignupTransitionResult = MachineTransition<SignupState>

// MARK: - Events

/// Every event name keeps its TypeScript spelling in the doc comment so the two tables can be
/// diffed line for line.
public enum SignupEvent: Sendable {
    /// TS `INIT`. The flow started. Only the FIRST one latches `alreadySignedInLatched`.
    case initialize(signedIn: Bool)
    /// TS `MODE_LOADED`.
    case modeLoaded(mode: SignupRegistrationMode)
    /// TS `CATALOG_LOADED`.
    case catalogLoaded(names: SignupCatalogNames?)
    /// TS `SELECTION_RESOLVED`.
    ///
    /// The live catalog decided what the signup starts with: the plan a signup link preselected, or
    /// the app's default plan in a `skip` flow, plus the packs the link asked for — all checked
    /// against the catalog by whoever dispatches this. A resolved plan takes the plan step out of
    /// the flow. Accepted only before the form is submitted; after that the plan and pack steps own
    /// the selection.
    case selectionResolved(tierId: String?, pricingId: String?, addOnIds: [String]?, requiresPayment: Bool?)
    /// TS `LOAD_FAILED`.
    case loadFailed(message: String)
    /// TS `REGISTER_SUBMITTED`.
    case registerSubmitted(email: String)
    /// TS `TOKEN_CHECK_STARTED`.
    case tokenCheckStarted
    /// TS `TOKEN_ACCEPTED`.
    case tokenAccepted(token: StepToken, value: String, grant: SignupTokenGrant?)
    /// TS `TOKEN_REJECTED`.
    case tokenRejected(token: StepToken, message: String)
    /// TS `TOKEN_SKIPPED`.
    case tokenSkipped
    /// TS `PLAN_CHOSEN`.
    case planChosen(tierId: String?, pricingId: String?, requiresPayment: Bool?)
    /// TS `PACKS_CHOSEN`.
    case packsChosen(addOnIds: [String])
    /// TS `PAYMENT_COMPLETED`.
    case paymentCompleted(paymentTransactionId: String)
    /// TS `PAYMENT_ABANDONED`.
    ///
    /// The customer walked away from the plan's card. Only ever valid on the ACCOUNT-FIRST payment
    /// step: there the account already exists, so the signup finishes with the plan unactivated
    /// rather than throwing away a registration that succeeded. Ignored in the pay-first order,
    /// where abandoning the card is simply a step back.
    case paymentAbandoned
    /// TS `ACCOUNT_CREATED`. A nil `requiresDisclaimers` means "yes" (TS `!== false`).
    case accountCreated(token: StepToken, userId: String, requiresDisclaimers: Bool?)
    /// TS `ACCOUNT_FAILED`.
    case accountFailed(token: StepToken, message: String)
    /// TS `DISCLAIMERS_ACCEPTED`.
    case disclaimersAccepted
    /// TS `PACK_CHECKOUT_FINISHED`.
    case packCheckoutFinished(token: StepToken, packs: [SignupPackOutcome])
    /// TS `PACK_CHECKOUT_FAILED`.
    case packCheckoutFailed(token: StepToken, message: String)
    /// TS `GO_TO`. Back-navigation from a view; only the form steps are reachable this way.
    case goTo(step: SignupGoToStep)
    /// TS `RETRY`.
    case retry
    /// TS `RESET`.
    case reset
}

// MARK: - Machine

/// The signup reducer. Pure apart from issuing step tokens.
public enum SignupMachine {
    // MARK: Entry points

    public static func initialState(_ options: SignupMachineOptions = SignupMachineOptions()) -> SignupState {
        let resolved = ResolvedSignupOptions(
            tokenMode: options.tokenMode,
            planSelection: options.planSelection,
            packSelection: options.packSelection,
            paymentOrder: options.paymentOrder
        )
        let addOnIds: [String] = dedupe(options.selection?.addOnIds)
        return SignupState(
            step: .loading,
            token: nil,
            options: resolved,
            mode: nil,
            modeReady: false,
            catalogReady: false,
            names: SignupCatalogNames(),
            selection: SignupSelection(
                tierId: options.selection?.tierId,
                pricingId: options.selection?.pricingId,
                addOnIds: addOnIds
            ),
            planRequiresPayment: false,
            planPreset: false,
            formSubmitted: false,
            email: "",
            userId: "",
            paymentTransactionId: nil,
            paymentAfterAccount: false,
            pendingDisclaimers: false,
            planActivationPending: false,
            tokenValue: nil,
            tokenGrant: nil,
            tokenChecking: false,
            tokenError: nil,
            packsToBuy: addOnIds,
            alreadySignedInLatched: false,
            initialized: false,
            outcome: nil,
            error: nil,
            retryFrom: nil
        )
    }

    /// Whether the plan still has to be paid for — the one question both payment positions ask, so
    /// the pay-first step and the account-first one can never disagree about whether there is a
    /// card to take. Public because a driver has to ask it too: its `creating` work must leave the
    /// plan's activation to an account-first payment step that is about to run.
    ///
    /// TS `signupPlanNeedsPayment`.
    public static func planNeedsPayment(_ state: SignupState) -> Bool {
        // A granted plan is paid for by whoever issued the token, and a free plan takes no card.
        let hasTier: Bool = !(state.selection.tierId ?? "").isEmpty
        return state.planRequiresPayment && state.tokenGrant == nil && hasTier
    }

    /// The signup reducer.
    ///
    /// - Parameter issuer: the step-token source. Tests pass their own so the tokens are literal
    ///   and deterministic under parallel execution.
    public static func transition(
        _ state: SignupState,
        _ event: SignupEvent,
        issuer: StepTokenIssuer = StepTokenIssuer.shared
    ) -> SignupTransitionResult {
        switch event {
        case .initialize(let signedIn):
            // Latched once: a mid-flow login must not look like "you were already signed in".
            if state.initialized { return ignored(state) }
            var next = state
            next.initialized = true
            next.alreadySignedInLatched = signedIn
            return applied(next)

        case .modeLoaded(let mode):
            var next = state
            next.mode = mode
            next.modeReady = true
            if state.step != .loading { return applied(next) }
            return applied(startForm(next, issuer: issuer))

        case .catalogLoaded(let names):
            var next = state
            if let names { next.names = names }
            next.catalogReady = true
            if state.step != .loading { return applied(next) }
            return applied(startForm(next, issuer: issuer))

        case .selectionResolved(let tierId, let pricingId, let addOnIds, let requiresPayment):
            // Only while the form is still ahead: once it has been submitted the plan and pack
            // steps own the selection, and a catalog that reloads underneath must not rewrite what
            // was chosen.
            if state.step != .loading && state.step != .register { return ignored(state) }
            let granted = Set(state.tokenGrant?.addOnIds ?? [])
            let resolvedAddOns: [String] = addOnIds != nil ? dedupe(addOnIds) : state.selection.addOnIds
            let plannedTier: Bool = tierId != nil
            var next = state
            next.planPreset = state.planPreset || plannedTier
            next.planRequiresPayment = plannedTier ? (requiresPayment ?? false) : state.planRequiresPayment
            next.selection = SignupSelection(
                tierId: tierId ?? state.selection.tierId,
                pricingId: pricingId ?? state.selection.pricingId,
                addOnIds: resolvedAddOns
            )
            next.packsToBuy = resolvedAddOns.filter { !granted.contains($0) }
            return applied(next)

        case .loadFailed(let message):
            if state.step != .loading { return ignored(state) }
            return applied(fail(state, message: message, retryFrom: .loading))

        case .registerSubmitted(let email):
            if state.step != .register { return ignored(state) }
            var next = state
            next.email = email
            next.formSubmitted = true
            return applied(advance(next, from: .register, issuer: issuer))

        case .tokenCheckStarted:
            if state.step != .token { return ignored(state) }
            var next = state
            next.token = issuer.issue()
            next.tokenChecking = true
            next.tokenError = nil
            return applied(next)

        case .tokenAccepted(let token, let value, let grant):
            if state.step != .token || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            // A grant covers its own packs, so they drop out of what still has to be bought.
            let granted = Set(grant?.addOnIds ?? [])
            var next = state
            next.token = nil
            next.tokenChecking = false
            next.tokenError = nil
            next.tokenValue = value
            next.tokenGrant = grant
            next.packsToBuy = state.packsToBuy.filter { !granted.contains($0) }
            return applied(advance(next, from: .token, issuer: issuer))

        case .tokenRejected(let token, let message):
            if state.step != .token || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            var next = state
            next.token = nil
            next.tokenChecking = false
            next.tokenError = message
            return applied(next)

        case .tokenSkipped:
            // A required token cannot be skipped; the server would refuse the registration anyway.
            if state.step != .token || (state.mode?.requireToken ?? false) { return ignored(state) }
            var next = state
            next.token = nil
            next.tokenChecking = false
            next.tokenError = nil
            return applied(advance(next, from: .token, issuer: issuer))

        case .planChosen(let tierId, let pricingId, let requiresPayment):
            if state.step != .plan { return ignored(state) }
            var next = state
            next.selection = SignupSelection(
                tierId: tierId,
                pricingId: pricingId,
                addOnIds: state.selection.addOnIds
            )
            next.planRequiresPayment = (requiresPayment ?? false)
            // Chosen is chosen: coming back through the form must not ask for a plan again.
            next.planPreset = true
            return applied(advance(next, from: .plan, issuer: issuer))

        case .packsChosen(let addOnIds):
            if state.step != .packs { return ignored(state) }
            let chosen: [String] = dedupe(addOnIds)
            let granted = Set(state.tokenGrant?.addOnIds ?? [])
            var next = state
            next.selection = SignupSelection(
                tierId: state.selection.tierId,
                pricingId: state.selection.pricingId,
                addOnIds: chosen
            )
            next.packsToBuy = chosen.filter { !granted.contains($0) }
            return applied(advance(next, from: .packs, issuer: issuer))

        case .paymentCompleted(let paymentTransactionId):
            if state.step != .payment { return ignored(state) }
            var paid = state
            paid.paymentTransactionId = paymentTransactionId
            // Account-first: the account is already made, so the card is the last thing before the
            // disclaimers rather than another form step on the way to creating one. A card that
            // goes through also un-pends the plan: this may be the second visit to the step, after
            // a first one the customer walked away from, and the outcome must not still call the
            // plan pending.
            if state.paymentAfterAccount {
                paid.planActivationPending = false
                return applied(afterAccountPayment(paid, issuer: issuer))
            }
            return applied(advance(paid, from: .payment, issuer: issuer))

        case .paymentAbandoned:
            // Pay-first has nothing to abandon INTO: no account exists yet, so backing out of the
            // card is a `goTo`, not this.
            if state.step != .payment || !state.paymentAfterAccount { return ignored(state) }
            var next = state
            next.planActivationPending = true
            return applied(afterAccountPayment(next, issuer: issuer))

        case .accountCreated(let token, let userId, let requiresDisclaimers):
            if state.step != .creating || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            // Default true: the plan's order puts disclaimers after account creation, and a host
            // that knows there are none passes false rather than rendering an empty step.
            let needsDisclaimers: Bool = (requiresDisclaimers ?? true)
            var next = state
            next.token = nil
            next.userId = userId
            // Remembered, because an account-first card step runs between here and there.
            next.pendingDisclaimers = needsDisclaimers
            let alreadyPaid: Bool = !(state.paymentTransactionId ?? "").isEmpty
            if state.options.paymentOrder == .afterAccount && !alreadyPaid && planNeedsPayment(state) {
                next.paymentAfterAccount = true
                return applied(enter(next, .payment, issuer: issuer))
            }
            if needsDisclaimers { return applied(enter(next, .disclaimers, issuer: issuer)) }
            return applied(afterDisclaimers(next, issuer: issuer))

        case .accountFailed(let token, let message):
            if state.step != .creating || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            return applied(fail(state, message: message, retryFrom: .creating))

        case .disclaimersAccepted:
            if state.step != .disclaimers { return ignored(state) }
            return applied(afterDisclaimers(state, issuer: issuer))

        case .packCheckoutFinished(let token, let packs):
            if state.step != .packCheckout || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            var next = state
            next.token = nil
            return applied(finish(next, bought: packs))

        case .packCheckoutFailed(let token, let message):
            if state.step != .packCheckout || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            return applied(fail(state, message: message, retryFrom: .packCheckout))

        case .goTo(let target):
            if state.step == .loading || state.step == .closed || state.step == .done { return ignored(state) }
            if target == .payment && state.options.paymentOrder == .afterAccount {
                // There is no pre-account card step in that order, so the card can only be
                // re-opened where the machine itself put it: at the step, or at the disclaimers an
                // abandoned card dropped the flow into. Past the disclaimers the signup is buying
                // packs — re-opening the plan's card there would come back through disclaimers
                // already accepted and restart a checkout that may already be charging. `done` is
                // refused by the guard above: the outcome is out.
                if state.step != .payment && state.step != .disclaimers { return ignored(state) }
                // Only while the card is genuinely still outstanding: an account to attach it to, a
                // plan that has to be paid for, and nothing taken for it yet.
                if state.userId.isEmpty { return ignored(state) }
                if !(state.paymentTransactionId ?? "").isEmpty { return ignored(state) }
                if !planNeedsPayment(state) { return ignored(state) }
                var reopened = state
                reopened.tokenError = nil
                reopened.paymentAfterAccount = true
                return applied(enter(reopened, .payment, issuer: issuer))
            }
            var next = state
            next.tokenError = nil
            return applied(enter(next, target.step, issuer: issuer))

        case .retry:
            guard state.step == .failed, let retryFrom = state.retryFrom else { return ignored(state) }
            if retryFrom == .loading {
                var next = state
                next.step = .loading
                next.token = nil
                next.error = nil
                next.retryFrom = nil
                return applied(next)
            }
            // `retryFrom` is only ever an async step (loading, creating, packCheckout), so
            // re-entering it never lands on a payment step and the account-first latch is left
            // exactly as it was.
            return applied(enter(state, retryFrom, issuer: issuer))

        case .reset:
            var fresh = initialState(
                SignupMachineOptions(
                    tokenMode: state.options.tokenMode,
                    planSelection: state.options.planSelection,
                    packSelection: state.options.packSelection,
                    paymentOrder: state.options.paymentOrder
                )
            )
            // The latch belongs to the visit, not the attempt: starting over must not suddenly
            // claim they were already signed in.
            fresh.initialized = state.initialized
            fresh.alreadySignedInLatched = state.alreadySignedInLatched
            return applied(fresh)
        }
    }

    // MARK: Results

    private static func ignored(_ state: SignupState) -> SignupTransitionResult {
        SignupTransitionResult(state: state, applied: false)
    }

    private static func applied(_ state: SignupState) -> SignupTransitionResult {
        SignupTransitionResult(state: state, applied: true)
    }

    // MARK: Flow helpers

    /// Move into a step, issuing a token when that step starts async work.
    private static func enter(_ state: SignupState, _ step: SignupStep, issuer: StepTokenIssuer) -> SignupState {
        let startsWork: Bool = step == .creating || step == .packCheckout
        var next = state
        next.step = step
        next.token = startsWork ? issuer.issue() : nil
        next.tokenChecking = false
        next.error = nil
        next.retryFrom = nil
        return next
    }

    private static func fail(_ state: SignupState, message: String, retryFrom: SignupStep) -> SignupState {
        var next = state
        next.step = .failed
        next.token = nil
        next.tokenChecking = false
        next.error = message
        next.retryFrom = retryFrom
        return next
    }

    /// Whether a step is passed over for this flow.
    private static func isSkipped(_ state: SignupState, _ step: SignupFormStep) -> Bool {
        switch step {
        case .register:
            return false
        case .token:
            // No token path at all: neither required nor offered as an option.
            let requires: Bool = state.mode?.requireToken ?? false
            let offered: Bool = state.mode?.showOptionalTokenEntry ?? false
            return !(requires || offered)
        case .plan:
            // A grant already names the plan, a resolved link already chose it, and invite
            // redemption is "take what the invite gives" — in none of those is there anything to
            // choose.
            return state.options.planSelection == .skip
                || state.options.tokenMode == .required
                || state.planPreset
                || state.tokenGrant != nil
        case .packs:
            // Invite redemption is "take what the invite gives", not a shopping trip.
            return state.options.packSelection == SignupPackSelection.none
                || state.options.tokenMode == .required
        case .payment:
            // Account-first: the card is taken after `creating`, not inside the form's order, so
            // the form never walks a payment step at all.
            if state.options.paymentOrder == .afterAccount { return true }
            return !planNeedsPayment(state)
        case .creating:
            return false
        }
    }

    /// The next step after `from`, skipping whatever this flow does not need.
    private static func advance(_ state: SignupState, from: SignupFormStep, issuer: StepTokenIssuer) -> SignupState {
        // The form comes first, always. A visitor who followed "change plan" out of the form and
        // chose there is sent back to it with their new choice, rather than on towards a card form
        // or an account creation that has no details to work with.
        if !state.formSubmitted { return enter(state, .register, issuer: issuer) }

        let order: [SignupFormStep] = SignupFormStep.allCases
        var index: Int = from.rawValue + 1
        while index < order.count {
            let candidate: SignupFormStep = order[index]
            if !isSkipped(state, candidate) { return enter(state, candidate.step, issuer: issuer) }
            index += 1
        }
        return enter(state, .creating, issuer: issuer)
    }

    private static func resolveTier(_ state: SignupState) -> SignupOutcomeTier? {
        let tierId: String
        if let grant = state.tokenGrant {
            tierId = grant.tierId
        } else {
            tierId = state.selection.tierId ?? ""
        }
        if tierId.isEmpty { return nil }

        let name: String = state.names.tiers[tierId] ?? tierId
        let pricingId: String?
        if let grantPricing = state.tokenGrant?.pricingId {
            pricingId = grantPricing
        } else {
            pricingId = state.selection.pricingId
        }
        return SignupOutcomeTier(tierId: tierId, name: name, pricingId: pricingId)
    }

    /// Everything is done: build the outcome, granted packs first.
    private static func finish(_ state: SignupState, bought: [SignupPackOutcome]) -> SignupState {
        let grantedIds: [String] = state.tokenGrant?.addOnIds ?? []
        var packs: [SignupPackOutcome] = grantedIds.map { addOnId in
            SignupPackOutcome(
                addOnId: addOnId,
                name: state.names.addOns[addOnId] ?? addOnId,
                status: SignupPackStatuses.granted
            )
        }
        packs.append(contentsOf: bought)

        var next = state
        next.step = .done
        next.token = nil
        next.error = nil
        next.retryFrom = nil
        next.outcome = SignupOutcome(
            userId: state.userId,
            tier: resolveTier(state),
            packs: packs,
            tokenGrant: state.tokenGrant,
            // Left off entirely when it did not happen, so the ordinary outcome carries no dead
            // flag.
            planActivationPending: state.planActivationPending ? true : nil
        )
        return next
    }

    /// After the account exists and the disclaimers are out of the way.
    private static func afterDisclaimers(_ state: SignupState, issuer: StepTokenIssuer) -> SignupState {
        if !state.packsToBuy.isEmpty { return enter(state, .packCheckout, issuer: issuer) }
        return finish(state, bought: [])
    }

    /// Leaving the ACCOUNT-FIRST payment step, whether the card was given or walked away from: on
    /// to the disclaimers the account event asked for, or straight past them — exactly where that
    /// event would have gone had there been no card to take.
    private static func afterAccountPayment(_ state: SignupState, issuer: StepTokenIssuer) -> SignupState {
        var next = state
        next.paymentAfterAccount = false
        if next.pendingDisclaimers { return enter(next, .disclaimers, issuer: issuer) }
        return afterDisclaimers(next, issuer: issuer)
    }

    /// Both the mode and the catalog are in: open the form, or say sign-up is closed.
    private static func startForm(_ state: SignupState, issuer: StepTokenIssuer) -> SignupState {
        if !state.modeReady || !state.catalogReady { return state }
        if state.mode?.closed == true {
            var next = state
            next.step = .closed
            next.token = nil
            return next
        }
        return enter(state, .register, issuer: issuer)
    }

    /// TS `[...new Set(ids ?? [])]`: first occurrence wins, order preserved.
    private static func dedupe(_ ids: [String]?) -> [String] {
        guard let ids else { return [] }
        var seen = Set<String>()
        var out: [String] = []
        for id in ids where seen.insert(id).inserted {
            out.append(id)
        }
        return out
    }
}

/// TS `signupPlanNeedsPayment(state)`.
public func signupPlanNeedsPayment(_ state: SignupState) -> Bool {
    SignupMachine.planNeedsPayment(state)
}
