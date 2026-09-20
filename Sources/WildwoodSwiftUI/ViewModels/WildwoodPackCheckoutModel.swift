// Buying the packs an account asked for: ONE quote, ONE card at most, ONE purchase, then any pack
// the bank wants authenticated, one at a time.
//
// It runs AS THE SIGNED-IN USER, because the checkout controller is `[Authorize]` — the quote finds
// the customer the plan's payment already created, so a card taken minutes ago on the payment step
// is the saved card here and nothing is asked for twice.
//
// The ORDER lives in the shared ``PackCheckoutMachine``; this is the half that touches the world.
// Ported from packages/wildwood-react-shared/src/registrationSubscription/usePackCheckoutFlow.ts
// and mirroring WildwoodComponents.Blazor's PackCheckoutDriver.
//
// The card and the bank challenge are the two things this driver cannot do itself: it takes no
// payment SDK. WITHOUT a ``WildwoodPaymentActionHandler`` that can confirm a card setup, no
// SetupIntent is ever asked for (`createCheckoutPaymentMethod` is not called) and an in-app
// purchase is offered only when the server's quote says a card is already on file
// (`requiresPaymentMethod == false`, bought with `UseSavedCard: true`). A pack that comes back
// `requires_action` without a handler is reported as NOT COMPLETED with the "finish this purchase
// on the web" copy — never a silent failure, and never a throw.

import Foundation
import Observation
import WildwoodCore

@MainActor
@Observable
public final class WildwoodPackCheckoutModel {
    /// A ceiling on one pump: every iteration either advances the machine or stops.
    private static let maxPumpIterations: Int = 64

    @ObservationIgnored private let client: WildwoodClient
    @ObservationIgnored private let appId: String
    @ObservationIgnored private let handler: (any WildwoodPaymentActionHandler)?
    @ObservationIgnored private let issuer: StepTokenIssuer

    /// Copy for the messages this driver produces.
    @ObservationIgnored var labels: RegistrationSubscriptionDriverLabels = .defaults

    /// The packs still to buy — the chosen ones, minus anything a registration token granted.
    @ObservationIgnored public private(set) var items: [AddOnCheckoutItemInput]
    /// Pack names from the catalog, so an outcome can name a pack the quote never priced.
    @ObservationIgnored public var names: [String: String]

    // MARK: Host wiring

    /// Every requested pack's outcome, including the ones that failed or were skipped. Raised once.
    @ObservationIgnored public var onFinished: (([SignupPackOutcome]) -> Void)?
    /// Told about every failure, with a stable code.
    @ObservationIgnored public var onError: ((RegistrationSubscriptionError) -> Void)?
    /// Raised whenever the state changed — for a UIKit host. Cleared by ``detach()``.
    @ObservationIgnored public var onStateChanged: (() -> Void)?

    // MARK: State

    public private(set) var state: PackCheckoutState
    /// The Stripe account the quote's provider belongs to, once it has been looked up.
    public private(set) var publishableKey: String?

    @ObservationIgnored private var runs: [String: StepToken] = [:]
    @ObservationIgnored private var keyLookupDone: Bool = false
    @ObservationIgnored private var started: Bool = false
    @ObservationIgnored private var finished: Bool = false
    @ObservationIgnored private var pumping: Bool = false
    @ObservationIgnored private var pumpTask: Task<Void, Never>?
    @ObservationIgnored private var detached: Bool = false

    public init(
        client: WildwoodClient,
        appId: String,
        items: [AddOnCheckoutItemInput],
        names: [String: String] = [:],
        paymentActionHandler: (any WildwoodPaymentActionHandler)? = nil,
        issuer: StepTokenIssuer = StepTokenIssuer.shared
    ) {
        self.client = client
        self.appId = appId
        self.items = items
        self.names = names
        self.handler = paymentActionHandler
        self.issuer = issuer
        self.state = PackCheckoutMachine.initialState(
            PackCheckoutMachineOptions(appId: appId, items: items)
        )
    }

    // MARK: - What the view renders from

    public var step: PackCheckoutStep { state.step }

    /// The `ww-step` identifier a test hook reads.
    public var stepName: String { state.step.rawValue }

    /// Whether a server call is in flight.
    public var busy: Bool {
        switch state.step {
        case .checkingOut, .authenticating, .completing:
            return true
        case .idle, .quoting, .quoted, .collectingCard, .done, .failed:
            return false
        }
    }

    /// The pack whose card is being authenticated, named, for the status line.
    public var authenticatingName: String {
        guard let item = PackCheckoutMachine.currentItem(state) else { return "" }
        if let name = names[item.addOnId] { return name }
        let lines: [AddOnCheckoutQuoteLineModel] = state.quote?.lines ?? []
        for line in lines where line.addOnId == item.addOnId {
            return line.name
        }
        return ""
    }

    /// The basket as the server priced it, or nil until it has.
    public var quote: AddOnCheckoutQuoteModel? { state.quote }

    /// Why the checkout stopped, in words. Nil unless it failed.
    public var error: String? { state.step == .failed ? state.error : nil }

    /// Whether this device can collect a card for a basket the server says needs one.
    public var canCollectCard: Bool {
        RegistrationSubscriptionRules.mayCollectCardInApp(handler)
    }

    // MARK: - What the view calls

    /// Start the checkout. Idempotent: a re-entered `.task` cannot quote twice.
    public func start() {
        if started || detached { return }
        started = true
        dispatch(.quoteRequested(appId: appId, items: items))
    }

    /// Run the failed step again. A card is always collected afresh.
    public func retry() {
        dispatch(.retry)
    }

    /// Give up on the packs and let the signup finish: they are reported as failed, not forgotten.
    public func skip() {
        if finished { return }
        finished = true
        onFinished?(outcomes(fallbackMessage: state.error))
    }

    /// DETACH from the view: no more state or host callbacks, and no new work that needs a person.
    ///
    /// A pack whose card the customer HAS answered is a different matter: that money moved, and
    /// only ``AppTierService/completeAddOnCheckout(appId:paymentTransactionId:)`` turns it into a
    /// subscription. So `completing` — and the `done` that follows it — still run, server-side and
    /// silently. Packs still waiting on a challenge are left as the server has them: not
    /// authenticated, not completed, and reconciled by the platform's own 24-hour cleanup.
    ///
    /// Never waits on anything, and idempotent. The drain runs on a `Task` this model owns, so a
    /// SwiftUI `.task` cancelled on disappear cannot take it with it.
    public func detach() {
        if detached { return }
        detached = true
        onFinished = nil
        onError = nil
        onStateChanged = nil
    }

    // MARK: - The pump

    private func dispatch(_ event: PackCheckoutEvent) {
        if detached { return }
        apply(event)
        schedulePump()
    }

    @discardableResult
    private func apply(_ event: PackCheckoutEvent) -> Bool {
        let transition: PackCheckoutTransitionResult = PackCheckoutMachine.transition(
            state, event, issuer: issuer
        )
        guard transition.applied else { return false }
        state = transition.state
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
            if !mayRunNextStep() { break }
            let carriedOn: Bool = await runStepWork()
            if !carriedOn { break }
        }

        pumping = false
    }

    /// Attached, every step. Detached, only the two that are consequences of money already moved.
    private func mayRunNextStep() -> Bool {
        if !detached { return true }
        switch state.step {
        case .completing, .done:
            return true
        case .idle, .quoting, .quoted, .collectingCard, .checkingOut, .authenticating, .failed:
            return false
        }
    }

    private func runStepWork() async -> Bool {
        switch state.step {
        case .idle:
            return false

        case .quoting:
            guard let token = claim("quote", state.token) else { return false }
            await runQuote(token)
            return true

        case .quoted:
            // A quote that needs a card only asks for one when something here can take it;
            // otherwise the basket is bought against the card already on file, or not at all.
            if state.quote?.requiresPaymentMethod == true {
                apply(.cardRequested)
            } else {
                apply(.checkoutRequested)
            }
            return true

        case .collectingCard:
            guard let token = claim("card", state.token) else { return false }
            await runCardIntent(token, providerId: state.quote?.providerId)
            return true

        case .checkingOut:
            guard let quote = state.quote, let token = claim("checkout", state.token) else { return false }
            await runCheckout(
                token,
                quote: quote,
                paymentTransactionId: state.paymentTransactionId,
                useSavedCard: state.useSavedCard
            )
            return true

        case .authenticating:
            guard let item = PackCheckoutMachine.currentItem(state) else { return false }
            guard let token = claim("auth:\(state.pendingPosition)", state.token) else { return false }
            await runAuthenticate(token, item: item, providerId: state.quote?.providerId)
            return true

        case .completing:
            guard let item = PackCheckoutMachine.currentItem(state) else { return false }
            guard let token = claim("complete:\(state.pendingPosition)", state.token) else { return false }
            await runComplete(token, item: item)
            return true

        case .done:
            if finished { return false }
            finished = true
            let settled: [SignupPackOutcome] = outcomes(fallbackMessage: nil)
            onFinished?(settled)
            return false

        case .failed:
            return false
        }
    }

    // MARK: - The work a step asks for

    private func runQuote(_ token: StepToken) async {
        do {
            let quote: AddOnCheckoutQuoteModel = try await client.appTier.quoteAddOnCheckout(
                appId: appId,
                items: items
            )
            if !quote.success {
                report(
                    RegistrationSubscriptionErrorCodes.packQuoteFailed,
                    quote.errorMessage ?? labels.packsUnavailable
                )
            }
            apply(.quoteReceived(token: token, quote: quote))
        } catch {
            let message: String = Self.message(error, fallback: labels.packsUnavailable)
            report(RegistrationSubscriptionErrorCodes.packQuoteFailed, message)
            apply(.quoteFailed(token: token, message: message, errorCode: nil))
        }
    }

    /// Collect the one-off card. Never reached without a handler that can confirm a card setup —
    /// the `quoted` step refuses to ask for one — but the guard states the rule where it is read.
    private func runCardIntent(_ token: StepToken, providerId: String?) async {
        guard let handler = self.handler, handler.supportsCardSetup else {
            // Nothing here can take a card, so none is asked for: no SetupIntent is created, and
            // the customer is told where the basket can be paid for instead.
            report(RegistrationSubscriptionErrorCodes.packCardFailed, labels.finishOnWeb)
            apply(.cardIntentFailed(token: token, message: labels.finishOnWeb, errorCode: nil))
            return
        }

        do {
            let intent: AddOnCheckoutPaymentMethodModel = try await client.appTier.createCheckoutPaymentMethod(
                appId: appId,
                providerId: providerId ?? ""
            )
            let key: String? = await resolvePublishableKey(providerId: providerId)
            let clientSecret: String = intent.clientSecret ?? ""
            let cardTransactionId: String = intent.paymentTransactionId ?? ""

            guard intent.success,
                  !clientSecret.isEmpty,
                  !cardTransactionId.isEmpty,
                  let key,
                  !key.isEmpty
            else {
                let message: String = intent.errorMessage ?? RegistrationSubscriptionDriverMessages.cardUnavailable
                report(RegistrationSubscriptionErrorCodes.packCardFailed, message)
                apply(.cardIntentFailed(token: token, message: message, errorCode: intent.errorCode))
                return
            }

            apply(
                .cardIntentReceived(
                    token: token,
                    clientSecret: clientSecret,
                    paymentTransactionId: cardTransactionId
                )
            )

            // ONE card for a basket of any size.
            let outcome: PaymentActionOutcome = await handler.confirmCardSetup(
                clientSecret: clientSecret,
                publishableKey: key
            )
            switch outcome {
            case .succeeded:
                apply(.cardConfirmed(token: token, paymentTransactionId: cardTransactionId))
            case .failed(let text):
                let message: String = text.isEmpty
                    ? RegistrationSubscriptionDriverMessages.cardUnconfirmed
                    : text
                report(RegistrationSubscriptionErrorCodes.packCardFailed, message)
                apply(.cardFailed(token: token, message: message))
            case .cancelled:
                // The customer's own choice, not a fault worth reporting to the host.
                apply(
                    .cardFailed(
                        token: token,
                        message: RegistrationSubscriptionDriverMessages.cardUnconfirmed
                    )
                )
            }
        } catch {
            let message: String = Self.message(
                error,
                fallback: RegistrationSubscriptionDriverMessages.cardUnavailable
            )
            report(RegistrationSubscriptionErrorCodes.packCardFailed, message)
            apply(.cardIntentFailed(token: token, message: message, errorCode: nil))
        }
    }

    private func runCheckout(
        _ token: StepToken,
        quote: AddOnCheckoutQuoteModel,
        paymentTransactionId: String?,
        useSavedCard: Bool
    ) async {
        do {
            // The quote's `checkoutId` is what makes the purchase idempotent: a doubled buy cannot
            // buy the same pack twice.
            let request = AddOnCheckoutRequestModel(
                checkoutId: quote.checkoutId,
                providerId: quote.providerId ?? "",
                paymentTransactionId: useSavedCard ? nil : paymentTransactionId,
                useSavedCard: useSavedCard,
                items: items
            )
            let result: AddOnCheckoutResultModel = try await client.appTier.checkoutAddOns(
                appId: appId,
                request: request
            )
            if !result.success && result.results.isEmpty {
                report(
                    RegistrationSubscriptionErrorCodes.packCheckoutFailed,
                    result.errorMessage ?? labels.packsUnavailable
                )
            }
            apply(.checkoutReceived(token: token, result: result))
        } catch {
            let message: String = Self.message(error, fallback: labels.packsUnavailable)
            report(RegistrationSubscriptionErrorCodes.packCheckoutFailed, message)
            apply(.checkoutFailed(token: token, message: message, errorCode: nil))
        }
    }

    /// One pack's 3-D Secure, put to the customer. Only THIS pack is marked when it fails; the
    /// basket carries on, as it does for any other refusal.
    private func runAuthenticate(
        _ token: StepToken,
        item: AddOnCheckoutItemResultModel,
        providerId: String?
    ) async {
        guard let handler = self.handler else {
            apply(.itemAuthFailed(token: token, message: labels.finishOnWeb))
            return
        }

        let key: String? = await resolvePublishableKey(providerId: providerId)
        let clientSecret: String = item.clientSecret ?? ""
        guard let key, !key.isEmpty, !clientSecret.isEmpty else {
            apply(
                .itemAuthFailed(token: token, message: RegistrationSubscriptionDriverMessages.packUnconfirmed)
            )
            return
        }

        let outcome: PaymentActionOutcome = await handler.confirmPayment(
            clientSecret: clientSecret,
            publishableKey: key
        )
        if outcome.isSucceeded {
            apply(.itemAuthenticated(token: token))
            return
        }
        let message: String = outcome.failureMessage ?? RegistrationSubscriptionDriverMessages.cardUnconfirmed
        apply(.itemAuthFailed(token: token, message: message))
    }

    private func runComplete(_ token: StepToken, item: AddOnCheckoutItemResultModel) async {
        var result: AddOnCheckoutItemResultModel
        do {
            result = try await client.appTier.completeAddOnCheckout(
                appId: appId,
                paymentTransactionId: item.paymentTransactionId ?? ""
            )
        } catch {
            result = AddOnCheckoutItemResultModel(
                addOnId: item.addOnId,
                pricingId: item.pricingId,
                status: AddOnCheckoutItemStatuses.failed,
                errorMessage: Self.message(
                    error,
                    fallback: RegistrationSubscriptionDriverMessages.packUnconfirmed
                )
            )
        }
        // The server answers a refusal with the item itself, so its pack id is kept whatever
        // happened.
        if result.addOnId.isEmpty { result.addOnId = item.addOnId }
        apply(.itemCompleted(token: token, result: result))
    }

    // MARK: - Helpers

    /// ONE outcome per requested pack, so nothing the visitor asked for goes unmentioned.
    /// TS `toPackOutcomes`.
    func outcomes(fallbackMessage: String?) -> [SignupPackOutcome] {
        var settled: [SignupPackOutcome] = []
        for item in items {
            var result: AddOnCheckoutItemResultModel?
            for candidate in state.results where candidate.addOnId == item.addOnId {
                result = candidate
                break
            }

            var lineName: String?
            let lines: [AddOnCheckoutQuoteLineModel] = state.quote?.lines ?? []
            for line in lines where line.addOnId == item.addOnId {
                lineName = line.name
                break
            }
            let name: String = names[item.addOnId] ?? lineName ?? item.addOnId

            let status: String = result?.status ?? ""
            if status == AddOnCheckoutItemStatuses.trialing || status == AddOnCheckoutItemStatuses.active {
                settled.append(
                    SignupPackOutcome(
                        addOnId: item.addOnId,
                        name: name,
                        status: status,
                        trialEnd: result?.trialEnd,
                        errorMessage: nil
                    )
                )
                continue
            }

            settled.append(
                SignupPackOutcome(
                    addOnId: item.addOnId,
                    name: name,
                    status: SignupPackStatuses.failed,
                    trialEnd: nil,
                    errorMessage: result?.errorMessage ?? fallbackMessage
                )
            )
        }
        return settled
    }

    /// The Stripe account the quote's provider belongs to. Looked up once, then reused.
    private func resolvePublishableKey(providerId: String?) async -> String? {
        if keyLookupDone { return publishableKey }
        keyLookupDone = true
        let configuration: AppPaymentConfigurationDto? = await client.payment.getAppPaymentConfiguration(
            appId: appId
        )
        publishableKey = WildwoodPublishableKey.forProvider(configuration, providerId: providerId)
        return publishableKey
    }

    private func report(_ code: String, _ message: String) {
        onError?(RegistrationSubscriptionError(code: code, message: message))
    }

    private func notify() {
        if detached { return }
        onStateChanged?()
    }

    private func claim(_ key: String, _ token: StepToken?) -> StepToken? {
        guard let token, !token.isEmpty else { return nil }
        if runs[key] == token { return nil }
        runs[key] = token
        return token
    }

    private static func message(_ error: any Error, fallback: String) -> String {
        if let wildwood = error as? WildwoodError, !wildwood.message.isEmpty { return wildwood.message }
        let described: String = error.localizedDescription
        return described.isEmpty ? fallback : described
    }
}
