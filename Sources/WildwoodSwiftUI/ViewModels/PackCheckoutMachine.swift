// Buying any number of packs against one card, as a pure reducer.
//
//   idle -> quoting -> quoted -> [collectingCard] -> checkingOut
//        -> authenticating -> completing -> (next item) -> done
//
// The server prices the basket (`quoteAddOnCheckout`), the customer's card is collected once when
// there is none on file, the basket is bought in one call, and then any pack the bank wants
// authenticated is walked ONE AT A TIME, in order: confirm its `clientSecret`, complete it on the
// server, move to the next. One pack failing never stops the others — a basket is a basket, not a
// transaction — so read `results` per pack rather than a single success flag.
//
// Async steps carry a ``StepToken``: a doubled task or a payment callback that fires twice cannot
// buy anything twice or skip a pack.
//
// Ported from packages/wildwood-react-shared/src/registrationSubscription/packCheckoutMachine.ts
// and mirroring WildwoodComponents.Shared/RegistrationSubscription/PackCheckoutMachine.cs.

import Foundation
import WildwoodCore

// MARK: - Steps

public enum PackCheckoutStep: String, Sendable, Equatable, CaseIterable {
    case idle
    case quoting
    case quoted
    case collectingCard
    case checkingOut
    case authenticating
    case completing
    case done
    case failed
}

// MARK: - State

public struct PackCheckoutState: Sendable, Equatable {
    public var step: PackCheckoutStep
    /// The async step in flight, or nil. Results carrying another token are ignored.
    public var token: StepToken?

    public var appId: String
    public var items: [AddOnCheckoutItemInput]
    public var quote: AddOnCheckoutQuoteModel?

    /// The SetupIntent secret the card form confirms, while a card is being collected.
    public var cardClientSecret: String?
    /// The card, once collected — handed to the purchase so it reads the saved card off it.
    public var paymentTransactionId: String?
    /// Whether the purchase should charge the card already on file.
    public var useSavedCard: Bool

    /// One entry per requested pack, updated in place as each one is authenticated and completed.
    public var results: [AddOnCheckoutItemResultModel]
    /// The indexes into ``results`` still needing 3-D Secure, in the order they are walked.
    public var pendingIndexes: [Int]
    /// How far along ``pendingIndexes`` the walk is.
    public var pendingPosition: Int

    public var error: String?
    public var errorCode: String?
    /// Which step a ``PackCheckoutEvent/retry`` goes back to.
    public var retryFrom: PackCheckoutStep?

    public init(
        step: PackCheckoutStep = .idle,
        token: StepToken? = nil,
        appId: String = "",
        items: [AddOnCheckoutItemInput] = [],
        quote: AddOnCheckoutQuoteModel? = nil,
        cardClientSecret: String? = nil,
        paymentTransactionId: String? = nil,
        useSavedCard: Bool = false,
        results: [AddOnCheckoutItemResultModel] = [],
        pendingIndexes: [Int] = [],
        pendingPosition: Int = 0,
        error: String? = nil,
        errorCode: String? = nil,
        retryFrom: PackCheckoutStep? = nil
    ) {
        self.step = step
        self.token = token
        self.appId = appId
        self.items = items
        self.quote = quote
        self.cardClientSecret = cardClientSecret
        self.paymentTransactionId = paymentTransactionId
        self.useSavedCard = useSavedCard
        self.results = results
        self.pendingIndexes = pendingIndexes
        self.pendingPosition = pendingPosition
        self.error = error
        self.errorCode = errorCode
        self.retryFrom = retryFrom
    }

    public static func == (lhs: PackCheckoutState, rhs: PackCheckoutState) -> Bool {
        lhs.step == rhs.step
            && lhs.token == rhs.token
            && lhs.appId == rhs.appId
            && lhs.items == rhs.items
            && lhs.quote == rhs.quote
            && lhs.cardClientSecret == rhs.cardClientSecret
            && lhs.paymentTransactionId == rhs.paymentTransactionId
            && lhs.useSavedCard == rhs.useSavedCard
            && lhs.results == rhs.results
            && lhs.pendingIndexes == rhs.pendingIndexes
            && lhs.pendingPosition == rhs.pendingPosition
            && lhs.error == rhs.error
            && lhs.errorCode == rhs.errorCode
            && lhs.retryFrom == rhs.retryFrom
    }
}

/// What a pack-checkout reducer call answers.
public typealias PackCheckoutTransitionResult = MachineTransition<PackCheckoutState>

// MARK: - Events

public enum PackCheckoutEvent: Sendable {
    /// TS `QUOTE_REQUESTED`.
    case quoteRequested(appId: String, items: [AddOnCheckoutItemInput])
    /// TS `QUOTE_RECEIVED`.
    case quoteReceived(token: StepToken, quote: AddOnCheckoutQuoteModel)
    /// TS `QUOTE_FAILED`.
    case quoteFailed(token: StepToken, message: String, errorCode: String?)
    /// TS `CARD_REQUESTED`. The quote needs a card: start collecting one.
    case cardRequested
    /// TS `CARD_INTENT_RECEIVED`.
    case cardIntentReceived(token: StepToken, clientSecret: String, paymentTransactionId: String)
    /// TS `CARD_INTENT_FAILED`.
    case cardIntentFailed(token: StepToken, message: String, errorCode: String?)
    /// TS `CARD_CONFIRMED`. The customer confirmed the SetupIntent in the card form.
    case cardConfirmed(token: StepToken, paymentTransactionId: String?)
    /// TS `CARD_FAILED`.
    case cardFailed(token: StepToken, message: String)
    /// TS `CHECKOUT_REQUESTED`. Buy the basket with whatever card the flow has.
    case checkoutRequested
    /// TS `CHECKOUT_RECEIVED`.
    case checkoutReceived(token: StepToken, result: AddOnCheckoutResultModel)
    /// TS `CHECKOUT_FAILED`.
    case checkoutFailed(token: StepToken, message: String, errorCode: String?)
    /// TS `ITEM_AUTHENTICATED`. The current pack's 3-D Secure was confirmed.
    case itemAuthenticated(token: StepToken)
    /// TS `ITEM_AUTH_FAILED`.
    case itemAuthFailed(token: StepToken, message: String)
    /// TS `ITEM_COMPLETED`.
    case itemCompleted(token: StepToken, result: AddOnCheckoutItemResultModel)
    /// TS `RETRY`.
    case retry
    /// TS `RESET`.
    case reset
}

public struct PackCheckoutMachineOptions: Sendable, Equatable {
    public var appId: String
    public var items: [AddOnCheckoutItemInput]

    public init(appId: String = "", items: [AddOnCheckoutItemInput] = []) {
        self.appId = appId
        self.items = items
    }

    public static func == (lhs: PackCheckoutMachineOptions, rhs: PackCheckoutMachineOptions) -> Bool {
        lhs.appId == rhs.appId && lhs.items == rhs.items
    }
}

// MARK: - Machine

/// The pack-checkout reducer. Pure apart from issuing step tokens.
public enum PackCheckoutMachine {
    public static func initialState(
        _ options: PackCheckoutMachineOptions = PackCheckoutMachineOptions()
    ) -> PackCheckoutState {
        PackCheckoutState(
            step: .idle,
            token: nil,
            appId: options.appId,
            items: options.items,
            quote: nil,
            cardClientSecret: nil,
            paymentTransactionId: nil,
            useSavedCard: false,
            results: [],
            pendingIndexes: [],
            pendingPosition: 0,
            error: nil,
            errorCode: nil,
            retryFrom: nil
        )
    }

    /// The pack currently being authenticated/completed, or nil when the walk is over.
    ///
    /// TS `currentPackCheckoutItem`.
    public static func currentItem(_ state: PackCheckoutState) -> AddOnCheckoutItemResultModel? {
        guard let index = currentIndex(state) else { return nil }
        return state.results[index]
    }

    /// The pack-checkout reducer.
    ///
    /// - Parameter issuer: the step-token source. Tests pass their own so the tokens are literal
    ///   and deterministic under parallel execution.
    public static func transition(
        _ state: PackCheckoutState,
        _ event: PackCheckoutEvent,
        issuer: StepTokenIssuer = StepTokenIssuer.shared
    ) -> PackCheckoutTransitionResult {
        switch event {
        case .quoteRequested(let appId, let items):
            // Re-quoting while a quote is in flight is allowed and supersedes it — that is exactly
            // what a doubled task does, and the older answer is then dropped as stale.
            if state.step != .idle && state.step != .failed && state.step != .quoted && state.step != .quoting {
                return ignored(state)
            }
            var next = state
            next.appId = appId
            next.items = items
            next.quote = nil
            return applied(enter(next, .quoting, issuer: issuer))

        case .quoteReceived(let token, let quote):
            if state.step != .quoting || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            if !quote.success {
                var refused = state
                refused.quote = quote
                let message: String = quote.errorMessage ?? "The packs could not be priced."
                return applied(fail(refused, message: message, retryFrom: .quoting, errorCode: quote.errorCode))
            }
            var priced = state
            priced.quote = quote
            var next = enter(priced, .quoted, issuer: issuer)
            // A quote that needs no new card is bought against the one already on file.
            next.useSavedCard = !quote.requiresPaymentMethod
            return applied(next)

        case .quoteFailed(let token, let message, let errorCode):
            if state.step != .quoting || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            return applied(fail(state, message: message, retryFrom: .quoting, errorCode: errorCode))

        case .cardRequested:
            if state.step != .quoted { return ignored(state) }
            var next = state
            next.cardClientSecret = nil
            return applied(enter(next, .collectingCard, issuer: issuer))

        case .cardIntentReceived(let token, let clientSecret, let paymentTransactionId):
            if state.step != .collectingCard || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            var next = state
            next.cardClientSecret = clientSecret
            next.paymentTransactionId = paymentTransactionId
            return applied(next)

        case .cardIntentFailed(let token, let message, let errorCode):
            if state.step != .collectingCard || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            return applied(fail(state, message: message, retryFrom: .collectingCard, errorCode: errorCode))

        case .cardConfirmed(let token, let paymentTransactionId):
            if state.step != .collectingCard || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            var withCard = state
            withCard.paymentTransactionId = paymentTransactionId ?? state.paymentTransactionId
            withCard.useSavedCard = false
            return applied(enter(withCard, .checkingOut, issuer: issuer))

        case .cardFailed(let token, let message):
            if state.step != .collectingCard || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            return applied(fail(state, message: message, retryFrom: .collectingCard, errorCode: nil))

        case .checkoutRequested:
            if state.step != .quoted { return ignored(state) }
            return applied(enter(state, .checkingOut, issuer: issuer))

        case .checkoutReceived(let token, let result):
            if state.step != .checkingOut || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            let results: [AddOnCheckoutItemResultModel] = result.results
            if results.isEmpty {
                let message: String = result.errorMessage ?? "The packs could not be bought."
                return applied(fail(state, message: message, retryFrom: .checkingOut, errorCode: result.errorCode))
            }
            var pendingIndexes: [Int] = []
            for index in results.indices where results[index].status == AddOnCheckoutItemStatuses.requiresAction {
                pendingIndexes.append(index)
            }
            var withResults = state
            withResults.results = results
            withResults.pendingIndexes = pendingIndexes
            withResults.pendingPosition = 0
            if pendingIndexes.isEmpty { return applied(done(withResults)) }
            return applied(enter(withResults, .authenticating, issuer: issuer))

        case .checkoutFailed(let token, let message, let errorCode):
            if state.step != .checkingOut || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            return applied(fail(state, message: message, retryFrom: .checkingOut, errorCode: errorCode))

        case .itemAuthenticated(let token):
            if state.step != .authenticating || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            return applied(enter(state, .completing, issuer: issuer))

        case .itemAuthFailed(let token, let message):
            if state.step != .authenticating || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            // This pack is lost; the rest of the basket is not.
            let results: [AddOnCheckoutItemResultModel] = replaceCurrent(state) { current in
                var patched = current
                patched.status = AddOnCheckoutItemStatuses.failed
                patched.errorMessage = message
                return patched
            }
            var next = state
            next.results = results
            return applied(nextPending(next, issuer: issuer))

        case .itemCompleted(let token, let result):
            if state.step != .completing || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            let results: [AddOnCheckoutItemResultModel] = replaceCurrent(state) { current in
                mergeItem(current, result)
            }
            var next = state
            next.results = results
            return applied(nextPending(next, issuer: issuer))

        case .retry:
            guard state.step == .failed, let retryFrom = state.retryFrom else { return ignored(state) }
            // Back to the card form means collecting a NEW SetupIntent: the secret this state is
            // holding belongs to the attempt that just failed, and confirming it again confirms
            // the wrong intent.
            if retryFrom == .collectingCard {
                var fresh = state
                fresh.cardClientSecret = nil
                fresh.paymentTransactionId = nil
                return applied(enter(fresh, .collectingCard, issuer: issuer))
            }
            return applied(enter(state, retryFrom, issuer: issuer))

        case .reset:
            return applied(initialState(PackCheckoutMachineOptions(appId: state.appId, items: state.items)))
        }
    }

    // MARK: Results

    private static func ignored(_ state: PackCheckoutState) -> PackCheckoutTransitionResult {
        PackCheckoutTransitionResult(state: state, applied: false)
    }

    private static func applied(_ state: PackCheckoutState) -> PackCheckoutTransitionResult {
        PackCheckoutTransitionResult(state: state, applied: true)
    }

    // MARK: Flow helpers

    private static func enter(
        _ state: PackCheckoutState,
        _ step: PackCheckoutStep,
        issuer: StepTokenIssuer
    ) -> PackCheckoutState {
        let startsWork: Bool = step == .quoting
            || step == .collectingCard
            || step == .checkingOut
            || step == .authenticating
            || step == .completing
        var next = state
        next.step = step
        next.token = startsWork ? issuer.issue() : nil
        next.error = nil
        next.errorCode = nil
        next.retryFrom = nil
        return next
    }

    private static func fail(
        _ state: PackCheckoutState,
        message: String,
        retryFrom: PackCheckoutStep,
        errorCode: String?
    ) -> PackCheckoutState {
        var next = state
        next.step = .failed
        next.token = nil
        next.error = message
        next.errorCode = errorCode
        next.retryFrom = retryFrom
        return next
    }

    private static func done(_ state: PackCheckoutState) -> PackCheckoutState {
        var next = state
        next.step = .done
        next.token = nil
        next.error = nil
        next.errorCode = nil
        next.retryFrom = nil
        return next
    }

    /// Move to the next pack needing 3-D Secure, or finish.
    private static func nextPending(_ state: PackCheckoutState, issuer: StepTokenIssuer) -> PackCheckoutState {
        var advanced = state
        advanced.pendingPosition = state.pendingPosition + 1
        if advanced.pendingPosition >= advanced.pendingIndexes.count { return done(advanced) }
        return enter(advanced, .authenticating, issuer: issuer)
    }

    private static func currentIndex(_ state: PackCheckoutState) -> Int? {
        guard state.pendingPosition >= 0, state.pendingPosition < state.pendingIndexes.count else { return nil }
        let index: Int = state.pendingIndexes[state.pendingPosition]
        guard index >= 0, index < state.results.count else { return nil }
        return index
    }

    /// Replace the current pack's result, keeping its place in ``PackCheckoutState/results``.
    private static func replaceCurrent(
        _ state: PackCheckoutState,
        _ patch: (AddOnCheckoutItemResultModel) -> AddOnCheckoutItemResultModel
    ) -> [AddOnCheckoutItemResultModel] {
        guard let index = currentIndex(state) else { return state.results }
        var results: [AddOnCheckoutItemResultModel] = state.results
        results[index] = patch(state.results[index])
        return results
    }

    /// The Swift rendering of the TypeScript spread `{ ...current, ...result }`: JavaScript only
    /// overwrites the keys the server actually sent, so a value the completion answer left out
    /// keeps whatever the purchase put there. Swift has every property present, so "left out" is
    /// read as nil (or an empty string for the three the model declares non-optional).
    private static func mergeItem(
        _ current: AddOnCheckoutItemResultModel,
        _ patch: AddOnCheckoutItemResultModel
    ) -> AddOnCheckoutItemResultModel {
        var merged = current
        if !patch.addOnId.isEmpty { merged.addOnId = patch.addOnId }
        if !patch.pricingId.isEmpty { merged.pricingId = patch.pricingId }
        if !patch.status.isEmpty { merged.status = patch.status }
        if let value = patch.subscriptionId { merged.subscriptionId = value }
        if let value = patch.trialEnd { merged.trialEnd = value }
        if let value = patch.amountDueToday { merged.amountDueToday = value }
        if let value = patch.clientSecret { merged.clientSecret = value }
        if let value = patch.paymentIntentId { merged.paymentIntentId = value }
        if let value = patch.paymentTransactionId { merged.paymentTransactionId = value }
        if let value = patch.errorCode { merged.errorCode = value }
        if let value = patch.errorMessage { merged.errorMessage = value }
        return merged
    }
}

/// TS `currentPackCheckoutItem(state)`.
public func currentPackCheckoutItem(_ state: PackCheckoutState) -> AddOnCheckoutItemResultModel? {
    PackCheckoutMachine.currentItem(state)
}
