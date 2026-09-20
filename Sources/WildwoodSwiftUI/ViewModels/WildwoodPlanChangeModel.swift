// Changing an existing subscriber's plan: price it, confirm it, take a card if one is needed,
// post the change, answer the bank if it asks, and finish the parked change.
//
// The ORDER lives in the shared ``PlanChangeMachine``; this is the half that touches the world.
// Ported from packages/wildwood-react-shared/src/registrationSubscription/usePlanChangeFlow.ts and
// mirroring WildwoodComponents.Blazor's PlanChangeDriver.
//
// Two rules keep it honest:
//
//  · Every async step is CLAIMED by the machine's step token before it starts. A double tap, a
//    re-entered `.task`, and a payment callback that fires twice all land on a token the machine
//    has moved past, so nothing is previewed, charged or changed twice.
//
//  · A `processing` completion is a "not yet", not a failure: the money is in and the server is
//    still applying the change, so it is asked again on the machine's bounded budget
//    (``PlanChangeMachine/maxCompleteAttempts``). A manual "Try Again" starts that budget over.
//
// The card, when one is needed BEFORE the change is posted, comes from the host's own
// ``onPaymentRequired`` when it supplied one — that seam predates this driver and keeps winning —
// and otherwise from the view's built-in payment sheet, which is what ``paymentRequest`` is for.
// The two answer differently on purpose: a host's sheet is outside this flow, so dismissing it
// abandons the change; the built-in one is inside it, so dismissing it returns to the confirmation
// with the priced change intact.
//
// The 3-D Secure challenge itself is the one thing this driver cannot do: it takes no payment SDK.
// WITHOUT a ``WildwoodPaymentActionHandler`` the change is posted in the PLAIN form — the server is
// never told this device can answer a challenge, so it refuses instead of parking one — and a
// challenge that arrives anyway stops the change with the `finishOnWeb` copy rather than failing
// silently.

import Foundation
import Observation
import WildwoodCore

/// The plan a change is moving to, and whether the account is already on one.
public struct PlanChangeSelection: Sendable, Equatable {
    public var tier: AppTierModel
    public var pricing: AppTierPricingModel?
    /// False when the account has no subscription yet, which is a subscribe rather than a change.
    public var isChange: Bool

    public init(tier: AppTierModel, pricing: AppTierPricingModel? = nil, isChange: Bool) {
        self.tier = tier
        self.pricing = pricing
        self.isChange = isChange
    }

    public static func == (lhs: PlanChangeSelection, rhs: PlanChangeSelection) -> Bool {
        lhs.tier == rhs.tier && lhs.pricing == rhs.pricing && lhs.isChange == rhs.isChange
    }
}

@MainActor
@Observable
public final class WildwoodPlanChangeModel {
    /// A ceiling on one pump: every iteration either advances the machine or stops, so this is
    /// only reached by a bug. Breaking beats spinning forever.
    private static let maxPumpIterations: Int = 64

    @ObservationIgnored private let client: WildwoodClient
    @ObservationIgnored private let admin: WildwoodSubscriptionAdminModel
    @ObservationIgnored private let handler: (any WildwoodPaymentActionHandler)?
    @ObservationIgnored private let issuer: StepTokenIssuer

    /// Copy for the messages this driver produces. Swapped for the full label set when the views
    /// land; the driver only ever reads members by name.
    @ObservationIgnored var labels: RegistrationSubscriptionDriverLabels = .defaults

    /// How long a `processing` answer is left alone before the completion is asked again (JS
    /// `COMPLETE_RETRY_DELAY_MS`). Settable so a test does not wait out the real one.
    @ObservationIgnored public var completeRetryDelay: Duration = .milliseconds(500)

    // MARK: Host wiring

    /// The host's own card sheet. Given one, it is used INSTEAD of the built-in sheet and its
    /// answer is final: a transaction id completes the change, nil abandons it.
    @ObservationIgnored public var onPaymentRequired: ((WildwoodPaymentRequiredArgs) async -> String?)?
    /// Reload whatever ELSE shows the subscription, once a change has landed. The admin model this
    /// driver was built on has already been reloaded by then (see ``settleChange()``), so a host
    /// that reloads it again here fetches everything twice.
    @ObservationIgnored public var onChanged: (() async -> Void)?
    /// Told after a change lands, so the host can refresh its own gates.
    @ObservationIgnored public var onEntitlementsChanged: ((EntitlementsChangedReason) -> Void)?
    /// Told about every failure, with a stable code. Raised once per failure.
    @ObservationIgnored public var onError: ((RegistrationSubscriptionError) -> Void)?
    /// Raised whenever the state changed — for a UIKit host. SwiftUI reads ``state`` through
    /// Observation and needs none of it. Cleared by ``detach()``.
    @ObservationIgnored public var onStateChanged: (() -> Void)?

    // MARK: State

    public private(set) var state: PlanChangeState

    @ObservationIgnored private var selection: PlanChangeSelection?
    @ObservationIgnored private var runs: [String: StepToken] = [:]
    @ObservationIgnored private var publishableKey: String?
    @ObservationIgnored private var keyLookupDone: Bool = false
    @ObservationIgnored private var pumping: Bool = false
    @ObservationIgnored private var pumpTask: Task<Void, Never>?
    /// The steps the machine does not tokenise, each claimed once per entry.
    @ObservationIgnored private var paymentAsked: Bool = false
    @ObservationIgnored private var doneHandled: Bool = false
    @ObservationIgnored private var failureReported: Bool = false
    /// The change that landed has been settled — see ``settleChange()``. Armed again by the next
    /// ``selectTier(_:)``, so a second change settles on its own account.
    @ObservationIgnored private var changeSettled: Bool = false
    /// The view has gone. See ``detach()``: detach is not stop.
    @ObservationIgnored private var detached: Bool = false
    @ObservationIgnored private var detachFinished: Bool = false

    public init(
        client: WildwoodClient,
        admin: WildwoodSubscriptionAdminModel,
        paymentActionHandler: (any WildwoodPaymentActionHandler)? = nil,
        issuer: StepTokenIssuer = StepTokenIssuer.shared
    ) {
        self.client = client
        self.admin = admin
        self.handler = paymentActionHandler
        self.issuer = issuer
        self.state = PlanChangeMachine.initialState(PlanChangeMachineOptions(appId: admin.appId))
    }

    // MARK: - What the view renders from

    public var step: PlanChangeStep { state.step }

    /// The `ww-step` identifier a test hook reads.
    public var stepName: String { state.step.rawValue }

    /// The preview to confirm, or nil when nothing is waiting on the customer.
    public var preview: TierChangePreviewModel? {
        state.step == .confirm ? state.preview : nil
    }

    /// The plan the change is moving to, while one is in flight. The confirmation and the card
    /// sheet name it, and the preview's own `newTierName` is not always filled in.
    public var selectedTier: AppTierModel? { selection?.tier }

    /// What the BUILT-IN card sheet should collect, or nil — either because no card is needed right
    /// now, or because the host brought its own sheet.
    public var paymentRequest: WildwoodPaymentRequiredArgs? {
        if onPaymentRequired != nil { return nil }
        return buildPaymentRequest()
    }

    /// Whether a server call is in flight: the confirmation's button reads "Processing...".
    public var busy: Bool {
        switch state.step {
        case .previewing, .changing, .authenticating, .completing:
            return true
        case .idle, .confirm, .collectingPayment, .done, .failed:
            return false
        }
    }

    /// Why the change stopped, in words. Nil unless the flow failed.
    public var error: String? {
        guard state.step == .failed else { return nil }
        return Self.messageForCode(labels, errorCode: state.errorCode, fallback: state.error)
    }

    /// The server's machine-readable refusal reason, when it sent one.
    public var errorCode: String? { state.errorCode }

    /// Whether a failure can be retried from where it stopped.
    public var canRetry: Bool { state.step == .failed && state.retryFrom != nil }

    /// Whether the confirmation may show the server's proration figures. False on an
    /// App-Store-exclusive app, where ``storeBillingNotice`` is shown instead.
    public var showsProration: Bool {
        RegistrationSubscriptionRules.showsProration(requiresAppStorePayment: admin.requiresAppStorePayment)
    }

    /// What to say in place of those figures, or nil when the figures stand.
    public var storeBillingNotice: String? {
        showsProration ? nil : labels.storeManagesBilling
    }

    /// Whether this device may tell the server it can answer a bank challenge.
    public var supportsPaymentAction: Bool {
        RegistrationSubscriptionRules.maySendSupportsPaymentAction(handler)
    }

    // MARK: - What the view calls

    /// Price the chosen plan and open the confirmation.
    public func selectTier(_ selection: PlanChangeSelection) {
        self.selection = selection
        changeSettled = false
        admin.clearMessages()
        dispatch(
            .previewRequested(
                appId: admin.appId,
                tierId: selection.tier.id,
                pricingId: selection.pricing?.id,
                immediate: nil
            )
        )
    }

    /// The customer confirmed the preview.
    public func confirm(immediate: Bool, bypassPayment: Bool = false) {
        admin.clearMessages()
        // An admin-scoped change is authorised server-side and bypasses payment there, so a card
        // is only ever asked for on the customer's own subscription.
        let adminScoped: Bool = admin.scope.isAdmin
        let paymentRequired: Bool = state.preview?.paymentRequired ?? false
        let alreadyPaid: Bool = !(state.paymentTransactionId ?? "").isEmpty
        let collect: Bool = !adminScoped && paymentRequired && !bypassPayment && !alreadyPaid
        dispatch(.confirmed(collectPayment: collect, immediate: immediate))
    }

    /// The customer backed out of the confirmation.
    public func cancel() {
        dispatch(.reset)
    }

    /// The built-in sheet's answer: a transaction id, or nil when the customer closed it. Closing
    /// returns to the confirmation, so the priced change is not thrown away.
    public func providePayment(_ paymentTransactionId: String?) {
        if let paymentTransactionId, !paymentTransactionId.isEmpty {
            dispatch(.paymentCompleted(paymentTransactionId: paymentTransactionId))
        } else {
            dispatch(.paymentCancelled)
        }
    }

    /// Run the failed step again, with the completion budget started over.
    public func retry() {
        dispatch(.retry)
    }

    /// Forget the whole attempt.
    public func reset() {
        dispatch(.reset)
    }

    /// DETACH the flow from the view, and let whatever the bank has already been asked drain to
    /// its end in the background.
    ///
    /// Clearing the host callbacks is the easy half: an answer still in flight must not report
    /// into a screen that has gone, and no NEW work that needs a person — a fresh preview, a card,
    /// a change not yet posted, a challenge not yet put to anyone — may start for a customer who
    /// left.
    ///
    /// The hard half is what has ALREADY moved money. A 3-D Secure confirmation runs in the host's
    /// payment SDK: teardown neither cancels it nor waits for it, and the bank answers it anyway.
    /// Abandoning that answer would charge the card and then never complete the parked change, so
    /// the proration is paid and the plan never moves, with no message either way. An authenticated
    /// change is therefore DRAINED — server-side only, no state callback, no host callback —
    /// through its completion, and SETTLED afterwards (``settleChange()``) because the plan really
    /// did change: once, the same once an attached change gets. See ``mayRunNextStep()``.
    ///
    /// Never waits on anything, and idempotent. The drain runs on a `Task` this model owns, so a
    /// SwiftUI `.task` being cancelled on disappear cannot take it with it.
    public func detach() {
        if detached { return }
        detached = true

        onPaymentRequired = nil
        onChanged = nil
        onEntitlementsChanged = nil
        onError = nil
        onStateChanged = nil

        // Nothing in flight: settle up now. Otherwise the pump does it when the call that is
        // running finishes.
        if !pumping { finishDetached() }
    }

    // MARK: - The pump

    private func dispatch(_ event: PlanChangeEvent) {
        // Every dispatch comes from the VIEW. Detached, there is no view, so there is nothing left
        // that could raise one. A step's own result does not come through here — it is applied
        // straight onto the state.
        if detached { return }
        apply(event)
        schedulePump()
    }

    @discardableResult
    private func apply(_ event: PlanChangeEvent) -> Bool {
        let transition: PlanChangeTransitionResult = PlanChangeMachine.transition(state, event, issuer: issuer)
        guard transition.applied else { return false }

        state = transition.state

        // The steps the machine does not tokenise are claimed once PER ENTRY, so leaving one arms
        // it again: a second upgrade asks for a card again, a second failure is reported again.
        if state.step != .collectingPayment { paymentAsked = false }
        if state.step != .done { doneHandled = false }
        if state.step != .failed { failureReported = false }

        notify()
        return true
    }

    private func schedulePump() {
        if pumping { return }
        pumpTask = Task { await self.pump() }
    }

    private func pump() async {
        if pumping { return }
        pumping = true

        var iteration: Int = 0
        while iteration < Self.maxPumpIterations {
            iteration += 1
            // A detach that landed while the last step was awaiting decides here what still runs:
            // the drain, and nothing else.
            if !mayRunNextStep() { break }
            let carriedOn: Bool = await runStepWork()
            if !carriedOn { break }
        }

        pumping = false
        if detached { finishDetached() }
    }

    /// Whether the step the machine has landed on may run now.
    ///
    /// Attached, always. Detached, only the two steps that are pure consequences of money that has
    /// ALREADY moved: `completing` (the bank said yes, and completing is what turns that into the
    /// new plan) and `done` (the change still has to be settled). Everything else needs a person
    /// who has left.
    private func mayRunNextStep() -> Bool {
        if !detached { return true }
        switch state.step {
        case .completing, .done:
            return true
        case .idle, .previewing, .confirm, .collectingPayment, .changing, .authenticating, .failed:
            return false
        }
    }

    private func runStepWork() async -> Bool {
        switch state.step {
        case .previewing:
            guard let token = claim("preview", state.token) else { return false }
            await runPreview(token)
            return true

        case .collectingPayment:
            // Only the host's handler is driven from here; the built-in sheet answers through
            // `providePayment(_:)` when the view renders it.
            guard let host = onPaymentRequired, !paymentAsked else { return false }
            guard let request = buildPaymentRequest() else { return false }
            paymentAsked = true
            await runHostPayment(host, request)
            return true

        case .changing:
            guard let token = claim("change", state.token) else { return false }
            await runChange(token, immediate: state.immediate, paymentTransactionId: state.paymentTransactionId)
            return true

        case .authenticating:
            guard let token = claim("authenticate", state.token) else { return false }
            await runAuthenticate(token, clientSecret: state.clientSecret)
            return true

        case .completing:
            guard let token = claim("complete", state.token) else { return false }
            await runComplete(token, pendingChangeId: state.pendingChangeId, attempt: state.completeAttempts)
            return true

        case .done:
            if doneHandled { return false }
            doneHandled = true
            await runDone()
            return false

        case .failed:
            if failureReported { return false }
            failureReported = true
            report(Self.codeForFailure(state), Self.messageForCode(labels, errorCode: state.errorCode, fallback: state.error) ?? "")
            return false

        case .idle, .confirm:
            return false
        }
    }

    // MARK: - The work a step asks for

    private func runPreview(_ token: StepToken) async {
        guard let chosen = selection else { return }
        let result: TierChangePreviewModel? = await admin.previewTierChange(
            tierId: chosen.tier.id,
            pricingId: chosen.pricing?.id
        )
        guard let result else {
            // The data layer already kept the server's own reason; only fall back when it said
            // nothing at all.
            let reason: String = admin.errorMessage.isEmpty
                ? RegistrationSubscriptionDriverMessages.previewRefused
                : admin.errorMessage
            apply(.previewFailed(token: token, message: reason))
            return
        }
        apply(.previewReceived(token: token, preview: result))
    }

    /// Put the card to the customer through the HOST's own sheet. Its answer is final: the host
    /// owns that sheet, so dismissing it is the customer walking away from the whole change, not a
    /// step back to a confirmation they already dismissed.
    private func runHostPayment(
        _ host: (WildwoodPaymentRequiredArgs) async -> String?,
        _ request: WildwoodPaymentRequiredArgs
    ) async {
        let answer: String? = await host(request)
        guard let answer, !answer.isEmpty else {
            apply(.reset)
            return
        }
        apply(.paymentCompleted(paymentTransactionId: answer))
    }

    /// Post the change. `SupportsPaymentAction` goes up ONLY when a handler exists: without one
    /// nothing here can answer a challenge, so the server must refuse rather than park.
    ///
    /// `settles: false`: this driver owns the settlement for the whole change (``settleChange()``).
    /// A success here is not necessarily the end of it — a parked change still has a challenge and
    /// a completion to run — and a change settled twice drops the entitlement cache twice.
    private func runChange(_ token: StepToken, immediate: Bool, paymentTransactionId: String?) async {
        guard let chosen = selection else { return }
        let result: AppTierChangeResultModel = await admin.postTierChange(
            tierId: chosen.tier.id,
            pricingId: chosen.pricing?.id,
            tierName: chosen.tier.name,
            isChange: chosen.isChange,
            immediate: immediate,
            paymentTransactionId: paymentTransactionId,
            supportsPaymentAction: supportsPaymentAction,
            settles: false
        )
        apply(.changeResult(token: token, result: result))
    }

    /// Put the prorated charge's 3-D Secure to the customer. The one step that can outlive the
    /// screen: a bank challenge is the host SDK's own sheet, which teardown neither cancels nor
    /// waits for — so this may well resolve into a detached driver. A success is applied and
    /// DRAINED through the completion; a refusal is applied and goes no further.
    private func runAuthenticate(_ token: StepToken, clientSecret: String?) async {
        guard let handler = self.handler else {
            // Nothing here can show the bank's challenge. Say where it can be finished rather than
            // reporting a charge that simply stopped.
            apply(.authFailed(token: token, message: labels.finishOnWeb))
            return
        }

        let key: String? = await resolvePublishableKey()
        guard let key, !key.isEmpty, let clientSecret, !clientSecret.isEmpty else {
            apply(.authFailed(token: token, message: RegistrationSubscriptionDriverMessages.chargeUnconfirmed))
            return
        }

        let outcome: PaymentActionOutcome = await handler.confirmPayment(
            clientSecret: clientSecret,
            publishableKey: key
        )
        if outcome.isSucceeded {
            apply(.authenticated(token: token))
            return
        }
        // A cancel carries no message of its own, so the plain "your plan has not changed" is the
        // truthful thing to say.
        let message: String = outcome.failureMessage ?? RegistrationSubscriptionDriverMessages.chargeUnconfirmed
        apply(.authFailed(token: token, message: message))
    }

    /// Finish the parked change. Safe to repeat — the server asks the processor whether the
    /// invoice really paid before it moves anything — so a `processing` answer is asked again
    /// rather than reported, on the machine's bounded budget.
    private func runComplete(_ token: StepToken, pendingChangeId: String?, attempt: Int) async {
        guard let pendingChangeId, !pendingChangeId.isEmpty else {
            apply(.completeFailed(token: token, message: labels.planChangeNotFound))
            return
        }

        // Only a `processing` answer waits: the first attempt asks immediately.
        if attempt > 0 && completeRetryDelay > .zero {
            try? await Task.sleep(for: completeRetryDelay)
        }

        // `settles: false` for the same reason the change itself is posted that way: a completion
        // may answer `processing` and be asked again, and only ``runDone()`` knows it is over.
        let result: AppTierChangeResultModel = await admin.completeTierChange(
            pendingChangeId: pendingChangeId,
            settles: false
        )
        apply(.completeResult(token: token, result: result))
    }

    /// The change landed. It is settled first — the entitlement cache dropped and the subscription
    /// state re-read — so anything the host refreshes next reads the new plan; then the host
    /// reloads whatever ELSE it shows, and is told why last.
    private func runDone() async {
        await settleChange()

        if let changed = onChanged {
            await changed()
        }
        onEntitlementsChanged?(.tierChange)
    }

    // MARK: - Helpers

    /// What the card sheet is asked to collect.
    ///
    /// The payment starts the NEW plan's own subscription, billed at the plan's price, so it
    /// carries the pricing MODEL id and the plan's own price and trial — never the prorated charge
    /// a preview quoted for today, which would bill the wrong amount next period. The preview's
    /// numbers are the fallback for a plan whose own price did not reach us.
    private func buildPaymentRequest() -> WildwoodPaymentRequiredArgs? {
        guard let chosen = selection, state.step == .collectingPayment else { return nil }
        let fallbackCurrency: String? = admin.catalogCurrency ?? state.preview?.currency
        let base = WildwoodPaymentRequiredArgs(
            tier: chosen.tier,
            pricing: chosen.pricing,
            fallbackCurrency: fallbackCurrency
        )
        if base.price > 0 { return base }

        let previewPrice: Double = state.preview?.newPrice ?? state.preview?.proratedChargeToday ?? 0
        if previewPrice <= 0 { return base }
        return WildwoodPaymentRequiredArgs(
            tier: chosen.tier,
            pricing: chosen.pricing,
            pricingModelId: base.pricingModelId,
            price: previewPrice,
            currency: base.currency,
            trialDays: base.trialDays,
            isSubscription: !chosen.tier.isFreeTier && previewPrice > 0
        )
    }

    /// The Stripe account the prorated charge was created on: the app's default Stripe provider,
    /// else its first enabled one with a key. Looked up once, then reused.
    private func resolvePublishableKey() async -> String? {
        if keyLookupDone { return publishableKey }
        keyLookupDone = true
        let configuration: AppPaymentConfigurationDto? = await client.payment.getAppPaymentConfiguration(
            appId: admin.appId
        )
        publishableKey = WildwoodPublishableKey.defaultStripe(configuration)
        return publishableKey
    }

    /// Settle the change that landed: drop the shared entitlement cache and re-read the
    /// subscription state the plan move changed, through
    /// ``WildwoodSubscriptionAdminModel/applyTierChangeSettlement()``.
    ///
    /// THIS DRIVER OWNS THE SETTLEMENT for every change it runs — which is why it posts and
    /// completes with `settles: false`. The admin model cannot own it: it is handed one HTTP call
    /// at a time and cannot tell a parked change from a finished one, so settling there would
    /// announce a plan that has not moved yet, and settling in both places drops the cache twice
    /// (epoch +2, `entitlementsChanged` twice) for one change.
    ///
    /// Once per change, whether the view was still there or the change drained after teardown: a
    /// plan that moved while a FeatureGate holds the old answer is a customer paying for something
    /// they cannot see.
    private func settleChange() async {
        if changeSettled { return }
        changeSettled = true
        await admin.applyTierChangeSettlement()
    }

    /// The end of a detached run. Runs exactly once, from whichever of ``detach()`` and the pump
    /// gets there last.
    ///
    /// A drained change settles in ``runDone()``, which the pump reaches for `.done` whether this
    /// driver is attached or not (see ``mayRunNextStep()``). This is the last-resort cache drop
    /// for a `.done` that was never pumped: dropping the cache is synchronous and safe during
    /// teardown, where awaiting three reloads for a screen that has gone is not.
    private func finishDetached() {
        if detachFinished { return }
        detachFinished = true
        if state.step == .done && !changeSettled {
            changeSettled = true
            admin.invalidateEntitlements(.tierChange)
        }
    }

    private func report(_ code: String, _ message: String) {
        onError?(RegistrationSubscriptionError(code: code, message: message))
    }

    private func notify() {
        if detached { return }
        onStateChanged?()
    }

    /// One run per step token: a doubled dispatch carries a token already claimed.
    private func claim(_ key: String, _ token: StepToken?) -> StepToken? {
        guard let token, !token.isEmpty else { return nil }
        if runs[key] == token { return nil }
        runs[key] = token
        return token
    }

    // MARK: - Messages

    /// The message for a refusal the server gave a code for. TS `messageForCode`.
    static func messageForCode(
        _ labels: RegistrationSubscriptionDriverLabels,
        errorCode: String?,
        fallback: String?
    ) -> String? {
        switch errorCode {
        case TierChangeErrorCodes.pendingChangeExpired:
            return labels.planChangeExpired
        case TierChangeErrorCodes.pendingChangePaymentFailed:
            return labels.planChangePaymentFailed
        case TierChangeErrorCodes.pendingChangeSuperseded:
            return labels.planChangeSuperseded
        case TierChangeErrorCodes.pendingChangeNotFound:
            return labels.planChangeNotFound
        case TierChangeErrorCodes.tierChangeAlreadyInProgress:
            return labels.planChangeInProgress
        default:
            return fallback
        }
    }

    /// The `onError` code for a failure, preferring the server's own. TS `codeForFailure`.
    static func codeForFailure(_ state: PlanChangeState) -> String {
        if let code = state.errorCode, !code.isEmpty { return code }
        guard let retryFrom = state.retryFrom else {
            return RegistrationSubscriptionErrorCodes.tierChangeFailed
        }
        switch retryFrom {
        case .previewing:
            return RegistrationSubscriptionErrorCodes.tierPreviewFailed
        case .authenticating:
            return RegistrationSubscriptionErrorCodes.tierChangeAuthenticationFailed
        case .completing:
            return RegistrationSubscriptionErrorCodes.tierChangeCompletionFailed
        case .idle, .confirm, .collectingPayment, .changing, .done, .failed:
            return RegistrationSubscriptionErrorCodes.tierChangeFailed
        }
    }
}
