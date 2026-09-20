// Changing an existing subscriber's plan, as a pure reducer.
//
//   idle -> previewing -> confirm -> [collectingPayment] -> changing
//        -> [authenticating -> completing] -> done
//
// Every layout confirms: the preview says what the change costs today and what it gains or loses,
// and nobody is billed without seeing it. From there the change either applies straight away, or
// the processor wants the prorated charge authenticated (3-D Secure) — which is a "not yet", not a
// refusal: confirm the `clientSecret`, then complete the parked change by its `pendingChangeId`.
// `processing` means the money is in and the server is still applying the change, so completion is
// retried rather than reported as a failure.
//
// `collectingPayment` is the pre-3-D-Secure path: a host that supplies its own payment-action
// handler, or the built-in card sheet, produces a `paymentTransactionId` before the change is
// posted at all.
//
// The delay between a `processing` answer and the next completion attempt belongs to the driver
// (a cancellable `Task.sleep`), not here: this reducer reads no clock.
//
// Ported from packages/wildwood-react-shared/src/registrationSubscription/planChangeMachine.ts and
// mirroring WildwoodComponents.Shared/RegistrationSubscription/PlanChangeMachine.cs.

import Foundation
import WildwoodCore

// MARK: - Steps

public enum PlanChangeStep: String, Sendable, Equatable, CaseIterable {
    case idle
    case previewing
    case confirm
    case collectingPayment
    case changing
    case authenticating
    case completing
    case done
    case failed
}

// MARK: - State

public struct PlanChangeState: Sendable, Equatable {
    public var step: PlanChangeStep
    /// The async step in flight, or nil. Results carrying another token are ignored.
    public var token: StepToken?

    public var appId: String
    public var tierId: String
    public var pricingId: String?
    public var immediate: Bool

    public var preview: TierChangePreviewModel?
    /// A payment made before the change was posted (the legacy/sheet path).
    public var paymentTransactionId: String?

    /// 3-D Secure, set when the server parks the change. Secret — never log ``clientSecret``.
    public var clientSecret: String?
    public var pendingChangeId: String?

    public var result: AppTierChangeResultModel?
    /// How many completion attempts the server has answered `processing`.
    public var completeAttempts: Int

    public var error: String?
    /// The server's machine-readable refusal reason, when it sent one.
    public var errorCode: String?
    /// Which step a ``PlanChangeEvent/retry`` goes back to.
    public var retryFrom: PlanChangeStep?

    public init(
        step: PlanChangeStep = .idle,
        token: StepToken? = nil,
        appId: String = "",
        tierId: String = "",
        pricingId: String? = nil,
        immediate: Bool = true,
        preview: TierChangePreviewModel? = nil,
        paymentTransactionId: String? = nil,
        clientSecret: String? = nil,
        pendingChangeId: String? = nil,
        result: AppTierChangeResultModel? = nil,
        completeAttempts: Int = 0,
        error: String? = nil,
        errorCode: String? = nil,
        retryFrom: PlanChangeStep? = nil
    ) {
        self.step = step
        self.token = token
        self.appId = appId
        self.tierId = tierId
        self.pricingId = pricingId
        self.immediate = immediate
        self.preview = preview
        self.paymentTransactionId = paymentTransactionId
        self.clientSecret = clientSecret
        self.pendingChangeId = pendingChangeId
        self.result = result
        self.completeAttempts = completeAttempts
        self.error = error
        self.errorCode = errorCode
        self.retryFrom = retryFrom
    }

    public static func == (lhs: PlanChangeState, rhs: PlanChangeState) -> Bool {
        lhs.step == rhs.step
            && lhs.token == rhs.token
            && lhs.appId == rhs.appId
            && lhs.tierId == rhs.tierId
            && lhs.pricingId == rhs.pricingId
            && lhs.immediate == rhs.immediate
            && lhs.preview == rhs.preview
            && lhs.paymentTransactionId == rhs.paymentTransactionId
            && lhs.clientSecret == rhs.clientSecret
            && lhs.pendingChangeId == rhs.pendingChangeId
            && lhs.result == rhs.result
            && lhs.completeAttempts == rhs.completeAttempts
            && lhs.error == rhs.error
            && lhs.errorCode == rhs.errorCode
            && lhs.retryFrom == rhs.retryFrom
    }
}

/// What a plan-change reducer call answers.
public typealias PlanChangeTransitionResult = MachineTransition<PlanChangeState>

// MARK: - Events

public enum PlanChangeEvent: Sendable {
    /// TS `PREVIEW_REQUESTED`.
    case previewRequested(appId: String, tierId: String, pricingId: String?, immediate: Bool?)
    /// TS `PREVIEW_RECEIVED`.
    case previewReceived(token: StepToken, preview: TierChangePreviewModel)
    /// TS `PREVIEW_FAILED`.
    case previewFailed(token: StepToken, message: String)
    /// TS `CONFIRMED`. The customer confirmed. `collectPayment` overrides what the preview implies,
    /// and `immediate` carries the timing they chose (a downgrade may be scheduled for the end of
    /// the period).
    case confirmed(collectPayment: Bool?, immediate: Bool?)
    /// TS `PAYMENT_COMPLETED`.
    case paymentCompleted(paymentTransactionId: String)
    /// TS `PAYMENT_FAILED`.
    case paymentFailed(message: String)
    /// TS `PAYMENT_CANCELLED`.
    case paymentCancelled
    /// TS `CHANGE_RESULT`.
    case changeResult(token: StepToken, result: AppTierChangeResultModel)
    /// TS `CHANGE_FAILED`.
    case changeFailed(token: StepToken, message: String)
    /// TS `AUTHENTICATED`. The prorated charge was authenticated.
    case authenticated(token: StepToken)
    /// TS `AUTH_FAILED`.
    case authFailed(token: StepToken, message: String)
    /// TS `COMPLETE_RESULT`.
    case completeResult(token: StepToken, result: AppTierChangeResultModel)
    /// TS `COMPLETE_FAILED`.
    case completeFailed(token: StepToken, message: String)
    /// TS `RETRY`.
    case retry
    /// TS `RESET`.
    case reset
}

public struct PlanChangeMachineOptions: Sendable, Equatable {
    public var appId: String
    public var tierId: String
    public var pricingId: String?
    /// Apply the change now rather than at the end of the billing period. Defaults to true.
    public var immediate: Bool

    public init(appId: String = "", tierId: String = "", pricingId: String? = nil, immediate: Bool = true) {
        self.appId = appId
        self.tierId = tierId
        self.pricingId = pricingId
        self.immediate = immediate
    }

    public static func == (lhs: PlanChangeMachineOptions, rhs: PlanChangeMachineOptions) -> Bool {
        lhs.appId == rhs.appId
            && lhs.tierId == rhs.tierId
            && lhs.pricingId == rhs.pricingId
            && lhs.immediate == rhs.immediate
    }
}

// MARK: - Machine

/// The plan-change reducer. Pure apart from issuing step tokens.
public enum PlanChangeMachine {
    /// How many times a `processing` answer is retried before the flow gives up and says so.
    public static let maxCompleteAttempts: Int = 5

    public static func initialState(
        _ options: PlanChangeMachineOptions = PlanChangeMachineOptions()
    ) -> PlanChangeState {
        PlanChangeState(
            step: .idle,
            token: nil,
            appId: options.appId,
            tierId: options.tierId,
            pricingId: options.pricingId,
            immediate: options.immediate,
            preview: nil,
            paymentTransactionId: nil,
            clientSecret: nil,
            pendingChangeId: nil,
            result: nil,
            completeAttempts: 0,
            error: nil,
            errorCode: nil,
            retryFrom: nil
        )
    }

    /// The plan-change reducer.
    ///
    /// - Parameter issuer: the step-token source. Tests pass their own so the tokens are literal
    ///   and deterministic under parallel execution.
    public static func transition(
        _ state: PlanChangeState,
        _ event: PlanChangeEvent,
        issuer: StepTokenIssuer = StepTokenIssuer.shared
    ) -> PlanChangeTransitionResult {
        switch event {
        case .previewRequested(let appId, let tierId, let pricingId, let immediate):
            // Re-previewing while one is in flight supersedes it (a doubled task, or the customer
            // flipping the billing frequency); the older answer is then dropped as stale.
            if state.step != .idle
                && state.step != .failed
                && state.step != .done
                && state.step != .confirm
                && state.step != .previewing {
                return ignored(state)
            }
            var next = state
            next.appId = appId
            next.tierId = tierId
            next.pricingId = pricingId
            next.immediate = immediate ?? state.immediate
            next.preview = nil
            next.result = nil
            next.completeAttempts = 0
            next.clientSecret = nil
            next.pendingChangeId = nil
            return applied(enter(next, .previewing, issuer: issuer))

        case .previewReceived(let token, let preview):
            if state.step != .previewing || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            if !preview.success {
                var refused = state
                refused.preview = preview
                let message: String = preview.errorMessage ?? "The plan change could not be priced."
                return applied(fail(refused, message: message, retryFrom: .previewing, errorCode: nil))
            }
            var next = state
            next.preview = preview
            return applied(enter(next, .confirm, issuer: issuer))

        case .previewFailed(let token, let message):
            if state.step != .previewing || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            return applied(fail(state, message: message, retryFrom: .previewing, errorCode: nil))

        case .confirmed(let collectPayment, let immediate):
            if state.step != .confirm { return ignored(state) }
            let collect: Bool = collectPayment ?? needsPaymentFirst(state)
            var confirmed = state
            if let immediate { confirmed.immediate = immediate }
            return applied(enter(confirmed, collect ? .collectingPayment : .changing, issuer: issuer))

        case .paymentCompleted(let paymentTransactionId):
            if state.step != .collectingPayment { return ignored(state) }
            var next = state
            next.paymentTransactionId = paymentTransactionId
            return applied(enter(next, .changing, issuer: issuer))

        case .paymentFailed(let message):
            if state.step != .collectingPayment { return ignored(state) }
            return applied(fail(state, message: message, retryFrom: .collectingPayment, errorCode: nil))

        case .paymentCancelled:
            if state.step != .collectingPayment { return ignored(state) }
            return applied(enter(state, .confirm, issuer: issuer))

        case .changeResult(let token, let result):
            if state.step != .changing || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            var cleared = state
            cleared.token = nil
            return applied(applyChangeResult(cleared, result: result, from: .changing, issuer: issuer))

        case .changeFailed(let token, let message):
            if state.step != .changing || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            return applied(fail(state, message: message, retryFrom: .changing, errorCode: nil))

        case .authenticated(let token):
            if state.step != .authenticating || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            var next = state
            next.completeAttempts = 0
            return applied(enter(next, .completing, issuer: issuer))

        case .authFailed(let token, let message):
            if state.step != .authenticating || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            return applied(fail(state, message: message, retryFrom: .authenticating, errorCode: nil))

        case .completeResult(let token, let result):
            if state.step != .completing || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            var cleared = state
            cleared.token = nil
            return applied(applyChangeResult(cleared, result: result, from: .completing, issuer: issuer))

        case .completeFailed(let token, let message):
            if state.step != .completing || !StepToken.isCurrentStep(state.token, token) { return ignored(state) }
            return applied(fail(state, message: message, retryFrom: .completing, errorCode: nil))

        case .retry:
            guard state.step == .failed, let retryFrom = state.retryFrom else { return ignored(state) }
            // The completion budget belongs to one automatic run of retries, not to the customer:
            // a manual "Try Again" that inherited an exhausted count would give up on its first
            // answer.
            var next = state
            next.completeAttempts = 0
            return applied(enter(next, retryFrom, issuer: issuer))

        case .reset:
            return applied(
                initialState(
                    PlanChangeMachineOptions(
                        appId: state.appId,
                        tierId: state.tierId,
                        pricingId: state.pricingId,
                        immediate: state.immediate
                    )
                )
            )
        }
    }

    // MARK: Results

    private static func ignored(_ state: PlanChangeState) -> PlanChangeTransitionResult {
        PlanChangeTransitionResult(state: state, applied: false)
    }

    private static func applied(_ state: PlanChangeState) -> PlanChangeTransitionResult {
        PlanChangeTransitionResult(state: state, applied: true)
    }

    // MARK: Flow helpers

    private static func enter(
        _ state: PlanChangeState,
        _ step: PlanChangeStep,
        issuer: StepTokenIssuer
    ) -> PlanChangeState {
        let startsWork: Bool = step == .previewing
            || step == .changing
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
        _ state: PlanChangeState,
        message: String,
        retryFrom: PlanChangeStep,
        errorCode: String?
    ) -> PlanChangeState {
        var next = state
        next.step = .failed
        next.token = nil
        next.error = message
        next.errorCode = errorCode
        next.retryFrom = retryFrom
        return next
    }

    /// Whether the change has to be paid for up front rather than through the 3-D Secure path.
    private static func needsPaymentFirst(_ state: PlanChangeState) -> Bool {
        if let transaction = state.paymentTransactionId, !transaction.isEmpty { return false }
        guard let preview = state.preview else { return false }
        return preview.paymentRequired && !preview.paymentBypassAllowed
    }

    /// Read the server's answer to a change or a completion and route on it.
    private static func applyChangeResult(
        _ state: PlanChangeState,
        result: AppTierChangeResultModel,
        from: PlanChangeStep,
        issuer: StepTokenIssuer
    ) -> PlanChangeState {
        var next = state
        next.result = result

        if result.success {
            next.step = .done
            next.token = nil
            next.error = nil
            next.errorCode = nil
            next.retryFrom = nil
            return next
        }

        // "Not yet", not "no": the processor accepted the change and is waiting on the customer.
        let requiresAction: Bool = (result.requiresAction ?? false)
        let secret: String = result.clientSecret ?? ""
        let parkedId: String = result.pendingChangeId ?? ""
        if requiresAction && !secret.isEmpty && !parkedId.isEmpty {
            next.clientSecret = secret
            next.pendingChangeId = parkedId
            next.completeAttempts = 0
            return enter(next, .authenticating, issuer: issuer)
        }

        // The money is in; the server is still applying the change. Ask again shortly.
        if result.processing == true {
            let attempts: Int = state.completeAttempts + 1
            next.completeAttempts = attempts
            if attempts >= maxCompleteAttempts {
                let message: String = result.errorMessage.isEmpty
                    ? "The payment went through but the plan change is still being applied. Refresh in a moment."
                    : result.errorMessage
                return fail(next, message: message, retryFrom: .completing, errorCode: result.errorCode)
            }
            if let parked = result.pendingChangeId { next.pendingChangeId = parked }
            return enter(next, .completing, issuer: issuer)
        }

        let message: String = result.errorMessage.isEmpty ? "The plan change was refused." : result.errorMessage
        return fail(next, message: message, retryFrom: from, errorCode: result.errorCode)
    }
}

/// TS `MAX_PLAN_CHANGE_COMPLETE_ATTEMPTS`.
public let maxPlanChangeCompleteAttempts: Int = PlanChangeMachine.maxCompleteAttempts
