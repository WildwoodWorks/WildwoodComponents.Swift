// The signup flow, driven.
//
// The order and every skip live in the shared ``SignupMachine``; this is the half that touches the
// world — it reads the app's registration mode and catalog, runs the server calls a step asks for,
// and applies the result back. The view below it renders ``step``.
//
// Ported from packages/wildwood-react-shared/src/registrationSubscription/useSignupFlow.ts and
// mirroring WildwoodComponents.Blazor's SignupFlowDriver.
//
// Three rules keep it honest:
//
//  · Every async step is CLAIMED by the machine's step token before it starts, so a re-entered
//    `.task`, a double tap and a payment callback that fires twice cannot register, charge or buy
//    twice.
//
//  · The account is created by ONE implementation, ``SignupAccountCreator`` — the same one the
//    older `SignupWithSubscriptionComponent` wizard uses — and its progress lives on a
//    ``SignupAccountAttempt`` this model keeps, so "Try Again" RESUMES instead of registering the
//    same person again or charging a card twice.
//
//  · The order is ACCOUNT-FIRST by default (``SignupPaymentOrder/afterAccount``), unlike the web.
//    A store or card purchase that succeeds before a registration that then fails strands a paid
//    subscription with no account to attach it to, which is worse than an account with no plan. A
//    customer who walks away from the card still finishes the signup, with the plan's activation
//    pending and the outcome saying so. A host that wants the web's pay-first order asks for
//    ``SignupPaymentOrder/beforeAccount``.

import Foundation
import Observation
import WildwoodCore

/// The plan the signup is buying, resolved against the live catalog. TS `ResolvedPlan`.
public struct ResolvedSignupPlan: Sendable, Equatable {
    public var tier: AppTierModel
    public var pricing: AppTierPricingModel?

    public init(tier: AppTierModel, pricing: AppTierPricingModel?) {
        self.tier = tier
        self.pricing = pricing
    }

    public static func == (lhs: ResolvedSignupPlan, rhs: ResolvedSignupPlan) -> Bool {
        lhs.tier == rhs.tier && lhs.pricing == rhs.pricing
    }
}

/// Everything the signup driver needs that carries no UI.
public struct WildwoodSignupFlowOptions: Sendable, Equatable {
    /// The app to read the catalog and settings of. Nil takes the client's configured app.
    public var appId: String?
    /// Overrides the currency the catalog is quoted in. Rarely needed.
    public var currency: String?
    /// The plan a pricing page already chose. Ignored when the app does not sell it.
    public var preSelectedTierId: String?
    /// The pricing option within that plan (the annual one, typically).
    public var preSelectedPricingId: String?
    /// Packs a pricing page already chose. Checked against the catalog and capped at 25.
    public var preSelectedAddOnIds: [String]
    /// An invitation token from the signup link.
    public var registrationToken: String?
    /// Pre-fills the username and email fields, e.g. from an invitation.
    public var prefillEmail: String?
    /// `.skip` leaves the plan to the host: a single-plan product, or one chosen elsewhere.
    public var planSelection: SignupPlanSelection
    /// Whether the visitor may pick packs on the way in.
    public var packSelection: SignupPackSelection
    /// `.required` is invite redemption: a token is the only way in.
    public var tokenMode: SignupTokenMode
    /// When the plan's card is taken. Defaults to ``SignupPaymentOrder/afterAccount`` here, which
    /// is the whole point of the native default — see this file's header.
    public var paymentOrder: SignupPaymentOrder
    /// What the registration is told it was made from.
    public var platform: String
    /// The device the registration is told about. Nil asks ``PlatformDetection``.
    public var deviceInfo: String?

    public init(
        appId: String? = nil,
        currency: String? = nil,
        preSelectedTierId: String? = nil,
        preSelectedPricingId: String? = nil,
        preSelectedAddOnIds: [String] = [],
        registrationToken: String? = nil,
        prefillEmail: String? = nil,
        planSelection: SignupPlanSelection = .choose,
        packSelection: SignupPackSelection = SignupPackSelection.none,
        tokenMode: SignupTokenMode = .auto,
        paymentOrder: SignupPaymentOrder = .afterAccount,
        platform: String = "ios",
        deviceInfo: String? = nil
    ) {
        self.appId = appId
        self.currency = currency
        self.preSelectedTierId = preSelectedTierId
        self.preSelectedPricingId = preSelectedPricingId
        self.preSelectedAddOnIds = preSelectedAddOnIds
        self.registrationToken = registrationToken
        self.prefillEmail = prefillEmail
        self.planSelection = planSelection
        self.packSelection = packSelection
        self.tokenMode = tokenMode
        self.paymentOrder = paymentOrder
        self.platform = platform
        self.deviceInfo = deviceInfo
    }

    /// Fold a signup link's parameters in (DD-5): the plan, the packs, the token and the email a
    /// universal link or deep link carried. An `invite` makes the token step the only way in, as
    /// the web's invite links do — the server validates the token, so a closed configuration does
    /// not block a genuine invitation.
    public func applying(_ params: SignupParams) -> WildwoodSignupFlowOptions {
        var merged: WildwoodSignupFlowOptions = self
        if let tierId = params.tierId { merged.preSelectedTierId = tierId }
        if let pricingId = params.pricingId { merged.preSelectedPricingId = pricingId }
        if !params.addOnIds.isEmpty { merged.preSelectedAddOnIds = params.addOnIds }
        let linkToken: String? = params.token ?? params.invite
        if let linkToken { merged.registrationToken = linkToken }
        if let email = params.email { merged.prefillEmail = email }
        if params.invite != nil { merged.tokenMode = .required }
        return merged
    }

    public static func == (lhs: WildwoodSignupFlowOptions, rhs: WildwoodSignupFlowOptions) -> Bool {
        lhs.appId == rhs.appId
            && lhs.currency == rhs.currency
            && lhs.preSelectedTierId == rhs.preSelectedTierId
            && lhs.preSelectedPricingId == rhs.preSelectedPricingId
            && lhs.preSelectedAddOnIds == rhs.preSelectedAddOnIds
            && lhs.registrationToken == rhs.registrationToken
            && lhs.prefillEmail == rhs.prefillEmail
            && lhs.planSelection == rhs.planSelection
            && lhs.packSelection == rhs.packSelection
            && lhs.tokenMode == rhs.tokenMode
            && lhs.paymentOrder == rhs.paymentOrder
            && lhs.platform == rhs.platform
            && lhs.deviceInfo == rhs.deviceInfo
    }
}

@MainActor
@Observable
public final class WildwoodSignupFlowModel {
    private static let maxPumpIterations: Int = 64

    @ObservationIgnored private let client: WildwoodClient
    @ObservationIgnored private let handler: (any WildwoodPaymentActionHandler)?
    @ObservationIgnored private let issuer: StepTokenIssuer
    @ObservationIgnored public let appId: String
    @ObservationIgnored public let options: WildwoodSignupFlowOptions

    /// Copy for the messages this driver produces.
    @ObservationIgnored var labels: RegistrationSubscriptionDriverLabels = .defaults

    // MARK: Host wiring

    /// Called instead of rendering the form when the visitor already had a session. Once only.
    @ObservationIgnored public var onAlreadySignedIn: (() -> Void)?
    /// Called once the account exists and everything asked for has been granted or reported.
    @ObservationIgnored public var onSignupComplete: ((SignupOutcome) -> Void)?
    /// Called after the new user's entitlements change, so the host can refresh its own gates.
    @ObservationIgnored public var onEntitlementsChanged: ((EntitlementsChangedReason) -> Void)?
    /// Called whenever the flow gives up on something.
    @ObservationIgnored public var onError: ((RegistrationSubscriptionError) -> Void)?
    /// Raised whenever the state changed — for a UIKit host. Cleared by ``detach()``.
    @ObservationIgnored public var onStateChanged: (() -> Void)?

    // MARK: State

    public private(set) var state: SignupState
    /// How the app lets people register, read LIVE (never cached) every time the flow starts.
    public private(set) var mode: SignupRegistrationMode
    public private(set) var catalog: PublicCatalog?
    /// The registration token's grant for THIS app, with the server's display names.
    public private(set) var tokenGrant: RegistrationTokenAppGrant?
    /// A rejected token, shown above the form.
    public private(set) var tokenMessage: String?
    /// What the flow is doing while the account is being created.
    public private(set) var processingStatus: String = ""
    /// The account was created but the plan could not be activated.
    public private(set) var subscriptionFailed: Bool = false
    /// The registration form as last submitted, so a step back re-fills it.
    public private(set) var formData: RegistrationFormData?
    /// Packs ticked on the pack step.
    public private(set) var selectedPackIds: [String] = []
    /// Monthly or annual, for the plan grid's toggle. The catalog's own frequency strings.
    public var billing: String = "monthly"
    /// The pack checkout, while one is running. Owned here so the view can render its progress.
    public private(set) var packCheckout: WildwoodPackCheckoutModel?

    /// Whether packs may be BOUGHT on this run.
    ///
    /// False on an App-Store-exclusive app (Decision 5 / Appendix C DD-4): pack checkout is a card
    /// purchase and Apple's in-app-purchase product mapping is tier-only, so there is no way to buy
    /// an add-on here. The pack STEP is then skipped and the basket is REPORTED as not bought, with
    /// the reason — never quoted, never charged, and never quietly forgotten.
    ///
    /// The driver does not ask the question itself: the answer comes from the app's
    /// platform-filtered payment providers, which the view already reads for its own reasons, and
    /// an unanswerable lookup must not stop a card-billed app selling. Set it through
    /// ``setPackPurchaseAvailable(_:)``.
    @ObservationIgnored public private(set) var packPurchaseAvailable: Bool = true

    @ObservationIgnored private let attempt: SignupAccountAttempt
    @ObservationIgnored private var chosenPlan: ResolvedSignupPlan?
    @ObservationIgnored private var paymentTransactionId: String?
    @ObservationIgnored private var paymentExternalId: String?
    @ObservationIgnored private var runs: [String: StepToken] = [:]
    @ObservationIgnored private var packCheckoutToken: StepToken?
    @ObservationIgnored private var started: Bool = false
    @ObservationIgnored private var signedInNotified: Bool = false
    @ObservationIgnored private var entitlementsNotified: Bool = false
    @ObservationIgnored private var completionNotified: Bool = false
    @ObservationIgnored private var pumping: Bool = false
    @ObservationIgnored private var pumpTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// The account-first tail, owned here so a cancelled `.task` cannot take it with it.
    @ObservationIgnored private var paymentTask: Task<Void, Never>?
    @ObservationIgnored private var detached: Bool = false
    @ObservationIgnored private var detachFinished: Bool = false

    public init(
        client: WildwoodClient,
        options: WildwoodSignupFlowOptions = WildwoodSignupFlowOptions(),
        paymentActionHandler: (any WildwoodPaymentActionHandler)? = nil,
        issuer: StepTokenIssuer = StepTokenIssuer.shared
    ) {
        self.client = client
        self.options = options
        self.handler = paymentActionHandler
        self.issuer = issuer
        self.attempt = SignupAccountAttempt()
        self.appId = options.appId ?? client.config.appId ?? ""
        self.mode = SignupRegistrationMode.resolve(nil, tokenMode: options.tokenMode)
        self.state = SignupMachine.initialState(
            SignupMachineOptions(
                tokenMode: options.tokenMode,
                planSelection: options.planSelection,
                packSelection: options.packSelection,
                paymentOrder: options.paymentOrder,
                selection: SignupSelection(
                    tierId: options.preSelectedTierId,
                    pricingId: options.preSelectedPricingId,
                    addOnIds: options.preSelectedAddOnIds
                )
            )
        )
    }

    // MARK: - What the view renders from

    public var step: SignupStep { state.step }

    /// The `ww-step` identifier a test hook reads; `done` is spelled `success`, as JS spells it.
    public var stepName: String {
        state.step == .done ? "success" : state.step.rawValue
    }

    /// Whether the visitor already had a session when the flow started.
    public var alreadySignedIn: Bool { state.initialized && state.alreadySignedInLatched }

    /// The currency every price on screen is quoted in.
    public var currency: String { options.currency ?? catalog?.currency ?? "" }

    /// The plan the signup is carrying: a link's, the app's default in a `skip` flow, or whatever
    /// the visitor last chose in the grid. Nil until there is one.
    public var plan: ResolvedSignupPlan? {
        if let chosen = chosenPlan { return chosen }
        guard let loaded = catalog, let tierId = state.selection.tierId, !tierId.isEmpty else { return nil }
        for tier in loaded.tiers where tier.id == tierId {
            return ResolvedSignupPlan(
                tier: tier,
                pricing: Catalog.resolvePriceOption(tier, pricingId: state.selection.pricingId)
            )
        }
        return nil
    }

    /// Whether a plan is still to be chosen, which is what the form's submit button says.
    public var planStepAhead: Bool {
        options.planSelection == .choose && options.tokenMode != .required && !state.planPreset
    }

    /// Free-trial days on the chosen plan, or 0.
    public var trialDays: Int {
        guard let chosen = plan, Self.requiresPayment(chosen) else { return 0 }
        return chosen.pricing?.trialDays ?? 0
    }

    /// Whether the card on screen is the ACCOUNT-FIRST one, so backing out of it finishes the
    /// signup rather than stepping back.
    public var paymentAfterAccount: Bool { state.paymentAfterAccount }

    /// The packs still to buy after login.
    public var checkoutItems: [AddOnCheckoutItemInput] {
        state.packsToBuy.map { AddOnCheckoutItemInput(addOnId: $0) }
    }

    /// Pack names from the catalog, for outcomes the quote never priced.
    public var packNames: [String: String] { state.names.addOns }

    /// The packs worth offering at the pack step: everything the app sells that a token did not
    /// already grant.
    public var availablePacks: [AppTierAddOnModel] {
        let granted = Set(state.tokenGrant?.addOnIds ?? [])
        let all: [AppTierAddOnModel] = catalog?.addOns ?? []
        var offered: [AppTierAddOnModel] = []
        for addOn in all where !granted.contains(addOn.id) {
            offered.append(addOn)
        }
        return offered
    }

    /// The registration form's initial values: the previous attempt's, or the invitation's email.
    public var initialFormData: RegistrationFormData? {
        if let submitted = formData { return submitted }
        guard let prefillEmail = options.prefillEmail, !prefillEmail.isEmpty else { return nil }
        let token: String? = options.registrationToken
        // An invitation's email is the username too, so the visitor types neither.
        return RegistrationFormData(
            firstName: "",
            lastName: "",
            username: prefillEmail,
            email: prefillEmail,
            password: "",
            registrationToken: token,
            useToken: !(token ?? "").isEmpty
        )
    }

    /// The outcome, once the signup is done.
    public var outcome: SignupOutcome? { state.outcome }

    /// Why the signup stopped, in words. Nil unless it failed.
    public var error: String? { state.step == .failed ? state.error : nil }

    // MARK: - What the view calls

    /// Start the flow: latch whether the visitor was already signed in, then read the app's
    /// registration mode and catalog. Idempotent, so a re-entered `.task` loads nothing twice.
    public func start() {
        if started || detached { return }
        started = true
        dispatch(.initialize(signedIn: client.session.isAuthenticated))
        notifyAlreadySignedIn()
        loadTask = Task { await self.load() }
    }

    public func submitForm(_ data: RegistrationFormData) {
        formData = data
        tokenMessage = nil
        dispatch(.registerSubmitted(email: data.email))
    }

    public func choosePlan(_ tier: AppTierModel) {
        let pricing: AppTierPricingModel? = Catalog.resolvePriceOption(tier, billing: billing)
        let resolved = ResolvedSignupPlan(tier: tier, pricing: pricing)
        chosenPlan = resolved
        dispatch(
            .planChosen(
                tierId: tier.id,
                pricingId: pricing?.id,
                requiresPayment: Self.requiresPayment(resolved)
            )
        )
    }

    public func togglePack(_ addOnId: String) {
        if let index = selectedPackIds.firstIndex(of: addOnId) {
            selectedPackIds.remove(at: index)
        } else {
            selectedPackIds.append(addOnId)
        }
    }

    public func choosePacks() {
        dispatch(.packsChosen(addOnIds: selectedPackIds))
    }

    /// Say whether packs may be bought on this device — see ``packPurchaseAvailable``.
    ///
    /// The answer usually arrives while the flow is still loading, but it is allowed to arrive
    /// late, so the pump is nudged: a flow already sitting on the pack step must apply the new
    /// answer where it actually is rather than waiting for the next thing the visitor does.
    public func setPackPurchaseAvailable(_ available: Bool) {
        if packPurchaseAvailable == available || detached { return }
        packPurchaseAvailable = available
        schedulePump()
    }

    public func skipPacks() {
        selectedPackIds = []
        dispatch(.packsChosen(addOnIds: []))
    }

    public func changePlan() {
        dispatch(.goTo(step: .plan))
    }

    public func back(to step: SignupGoToStep) {
        dispatch(.goTo(step: step))
    }

    /// The plan's card went through.
    public func paymentSucceeded(_ result: PaymentCompletionResult) {
        paymentSucceeded(transactionId: result.transactionId, paymentIntentId: result.paymentIntentId)
    }

    /// The plan's card went through, for a host that holds the ids rather than the result model.
    public func paymentSucceeded(transactionId: String?, paymentIntentId: String?) {
        // The server looks a transaction up by the PROVIDER's own id when it is linked to a user,
        // and subscribes with the Wildwood one.
        paymentTransactionId = transactionId ?? paymentIntentId
        paymentExternalId = paymentIntentId
        let settled: String = transactionId ?? paymentIntentId ?? ""

        // Account-first: the account is already there, so this is the moment the transaction can
        // be attached to it and the plan started — the same work `creating` does in the pay-first
        // order, which is why it is the same call.
        if state.paymentAfterAccount {
            paymentTask = Task { await self.activateAfterPayment(settled) }
            return
        }
        dispatch(.paymentCompleted(paymentTransactionId: settled))
    }

    /// The customer walked away from the ACCOUNT-FIRST card step. The signup finishes without the
    /// plan, and the outcome says `planActivationPending`. A no-op in the pay-first order.
    public func paymentAbandoned() {
        dispatch(.paymentAbandoned)
    }

    public func disclaimersDone() {
        dispatch(.disclaimersAccepted)
    }

    /// The pack checkout answered. Carries the token its step was entered on, so a second answer
    /// cannot finish the signup twice.
    public func packsBought(_ packs: [SignupPackOutcome]) {
        guard let token = packCheckoutToken else { return }
        dispatch(.packCheckoutFinished(token: token, packs: packs))
    }

    /// Resume a failed signup where it stopped. Never re-registers: the attempt remembers.
    public func retry() {
        if state.retryFrom == .loading {
            loadTask = Task { await self.load(forceRefresh: true) }
        }
        dispatch(.retry)
    }

    /// Throw the attempt away and return to the form.
    public func startOver() {
        attempt.reset()
        runs = [:]
        packCheckoutToken = nil
        packCheckout?.detach()
        packCheckout = nil
        paymentTransactionId = nil
        paymentExternalId = nil
        subscriptionFailed = false
        tokenGrant = nil
        tokenMessage = nil
        chosenPlan = nil
        processingStatus = ""
        completionNotified = false
        dispatch(.reset)
    }

    /// The "Get Started" button on the success panel. Raises ``onSignupComplete`` once.
    public func complete() {
        guard let outcome = state.outcome, !completionNotified else { return }
        completionNotified = true
        onSignupComplete?(outcome)
    }

    /// DETACH from the view: no more state or host callbacks, and no new work that needs a person.
    ///
    /// What it deliberately does NOT do is cut account creation short. That is one awaited call
    /// that registers, signs in, links the plan's payment and subscribes; abandoning it between
    /// the charge and the link would strand a paid transaction attached to nobody. Nothing here
    /// cancels it and nothing waits on it — it runs to its end on the `Task` this model owns,
    /// writing its progress onto the retry-safe attempt as usual, while every callback stays
    /// silent. The pump then stops at the next step, because every one of those needs a person.
    ///
    /// The one thing still owed afterwards is the entitlement cache: an account that got created
    /// is entitled to what it paid for, so the shared store is told directly.
    public func detach() {
        if detached { return }
        detached = true

        onAlreadySignedIn = nil
        onSignupComplete = nil
        onEntitlementsChanged = nil
        onError = nil
        onStateChanged = nil
        packCheckout?.detach()

        if !pumping { finishDetached() }
    }

    // MARK: - Loading

    private func load(forceRefresh: Bool = false) async {
        // The registration mode is read live every time: an operator who closes sign-up must not
        // be served a cached "open" from a minute ago.
        let configuration: AuthenticationConfiguration? = await client.auth.getAuthenticationConfiguration(
            appId: appId
        )
        let resolved: SignupRegistrationMode = SignupRegistrationMode.resolve(
            configuration: configuration,
            tokenMode: options.tokenMode
        )
        mode = resolved
        dispatch(.modeLoaded(mode: resolved))

        do {
            let loaded: PublicCatalog = try await client.catalog.catalog(
                appId: appId,
                currencyOverride: options.currency,
                forceRefresh: forceRefresh
            )
            catalog = loaded
            resolveSelection(loaded)
        } catch {
            let message: String = Self.message(
                error,
                fallback: RegistrationSubscriptionDriverMessages.catalogUnavailable
            )
            report(RegistrationSubscriptionErrorCodes.catalogUnavailable, message)
            dispatch(.loadFailed(message: message))
        }
    }

    /// What the signup starts with, once the live catalog can vet it: the plan a link preselected
    /// or the app's default in a `skip` flow, plus the packs the link asked for — deduped, checked
    /// against what the app actually sells, and capped at ``Catalog/maxAddOnSelection``.
    private func resolveSelection(_ loaded: PublicCatalog) {
        let invite: Bool = options.tokenMode == .required
        var preset: ResolvedSignupPlan?

        if !invite {
            if options.planSelection == .skip {
                // The link never picks a plan in a skip flow: the app has one, and this is it.
                var fallback: AppTierModel?
                for tier in loaded.tiers where tier.isDefault {
                    fallback = tier
                    break
                }
                if fallback == nil {
                    for tier in loaded.tiers where tier.isFreeTier {
                        fallback = tier
                        break
                    }
                }
                if let tier = fallback {
                    preset = ResolvedSignupPlan(tier: tier, pricing: Catalog.resolvePriceOption(tier))
                }
            } else if let wanted = options.preSelectedTierId, !wanted.isEmpty {
                // A plan the app does not sell is ignored rather than honoured: the link is stale
                // or hand-edited.
                let lowered: String = wanted.lowercased()
                for tier in loaded.tiers where tier.id.lowercased() == lowered {
                    preset = ResolvedSignupPlan(
                        tier: tier,
                        pricing: Catalog.resolvePriceOption(tier, pricingId: options.preSelectedPricingId)
                    )
                    break
                }
            }
        }

        let presetPackIds: [String] = invite
            ? []
            : Catalog.parseAddOnIdList(options.preSelectedAddOnIds.joined(separator: ","), catalog: loaded)
        if !presetPackIds.isEmpty { selectedPackIds = presetPackIds }

        var names = SignupCatalogNames()
        for tier in loaded.tiers { names.tiers[tier.id] = tier.name }
        for addOn in loaded.addOns { names.addOns[addOn.id] = addOn.name }

        dispatch(
            .selectionResolved(
                tierId: preset?.tier.id,
                pricingId: preset?.pricing?.id,
                addOnIds: presetPackIds,
                requiresPayment: preset.map { Self.requiresPayment($0) } ?? false
            )
        )
        dispatch(.catalogLoaded(names: names))
    }

    // MARK: - The pump

    private func dispatch(_ event: SignupEvent) {
        if detached { return }
        apply(event)
        schedulePump()
    }

    @discardableResult
    private func apply(_ event: SignupEvent) -> Bool {
        let transition: SignupTransitionResult = SignupMachine.transition(state, event, issuer: issuer)
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
            // A detach that landed while the last step was awaiting ends the pump here: everything
            // past this point needs a person who has left. The state the in-flight call wrote is
            // kept; the call itself was never cut short.
            if detached { break }
            let carriedOn: Bool = await runStepWork()
            if !carriedOn { break }
        }

        pumping = false
        if detached { finishDetached() }
    }

    private func runStepWork() async -> Bool {
        switch state.step {
        case .token:
            return await runTokenStep()

        case .payment:
            // A payment step with nothing to charge for cannot be paid, and a card taken there
            // would be stranded. Back to the form — unless the account already exists, in which
            // case there is no form to go back to and the signup finishes with the plan pending.
            if state.formSubmitted && plan != nil { return false }
            if state.paymentAfterAccount { return apply(.paymentAbandoned) }
            return apply(.goTo(step: .register))

        case .creating:
            guard formData != nil else { return apply(.goTo(step: .register)) }
            guard let token = claim("creating", state.token) else { return false }
            await runSignup(token)
            return true

        case .packs:
            // Nothing on this device can buy a pack, so the step has nothing to offer. Skipping it
            // is exactly what the visitor would have pressed, and it empties the basket a signup
            // link filled rather than carrying it to a checkout that cannot run.
            if packPurchaseAvailable { return false }
            selectedPackIds = []
            return apply(.packsChosen(addOnIds: []))

        case .packCheckout:
            guard let token = claim("packCheckout", state.token) else { return false }
            if !packPurchaseAvailable {
                // Reported, not forgotten: the visitor asked for these packs, and a signup that
                // drops them silently leaves them believing they have something they do not.
                let unbought: [SignupPackOutcome] = SignupViewRules.unbuyablePackOutcomes(
                    addOnIds: state.packsToBuy,
                    names: state.names.addOns,
                    message: labels.finishOnWeb
                )
                return apply(.packCheckoutFinished(token: token, packs: unbought))
            }
            startPackCheckout(token)
            return false

        case .done:
            if entitlementsNotified { return false }
            entitlementsNotified = true
            // The gates in the rest of the app are holding the anonymous answer; drop it, say why.
            client.features.invalidateEntitlements(appId: appId, reason: .signup)
            onEntitlementsChanged?(.signup)
            return false

        case .loading, .closed, .register, .plan, .disclaimers, .failed:
            return false
        }
    }

    // MARK: - The work a step asks for

    /// Check the registration token, or step past it. A nil answer from the server is "the details
    /// could not be READ", not "invalid": the token may still grant app access, so the signup
    /// carries on as an ordinary one and the registration endpoint has the last word.
    private func runTokenStep() async -> Bool {
        // A rejected token is a FORM error, not a failed flow: back to the form with the server's
        // words above it.
        if state.tokenError != nil {
            return apply(.goTo(step: .register))
        }

        if !state.tokenChecking {
            let typed: String = formData?.registrationToken ?? ""
            if formData?.useToken == true && !typed.isEmpty {
                return apply(.tokenCheckStarted)
            }
            return apply(.tokenSkipped)
        }

        guard let token = claim("token", state.token) else { return false }
        let value: String = formData?.registrationToken ?? ""
        let details: RegistrationTokenDetails? = await client.auth.getRegistrationTokenDetails(
            token: value,
            appId: appId
        )

        if let details, !details.isValid {
            let message: String = SignupPlanRules.nonBlank(details.errorMessage)
                ?? RegistrationSubscriptionDriverMessages.tokenRejected
            report(RegistrationSubscriptionErrorCodes.registrationTokenRejected, message)
            tokenMessage = message
            return apply(.tokenRejected(token: token, message: message))
        }

        // App ids are compared case-insensitively: the server returns them in whichever casing it
        // stored.
        let grant: RegistrationTokenAppGrant? = SignupPlanRules.findTokenPlanGrant(details, appId: appId)
        tokenGrant = grant
        // A granted pack is neither charged for nor shown as chosen.
        if let grant, !grant.addOnIds.isEmpty {
            let granted = Set(grant.addOnIds)
            selectedPackIds = selectedPackIds.filter { !granted.contains($0) }
        }

        let machineGrant: SignupTokenGrant? = grant.map { appGrant in
            SignupTokenGrant(
                tierId: appGrant.appTierId,
                pricingId: appGrant.appTierPricingId,
                addOnIds: appGrant.addOnIds,
                featureCodes: appGrant.featureCodes
            )
        }
        return apply(.tokenAccepted(token: token, value: value, grant: machineGrant))
    }

    private func runSignup(_ token: StepToken) async {
        guard let form = formData else {
            apply(.goTo(step: .register))
            return
        }

        let request: SignupAccountRequest = makeAccountRequest(form: form)
        do {
            let refusal: SignupAccountResult? = try await SignupAccountCreator.establishSession(
                client: client,
                request: request,
                attempt: attempt,
                onStep: { [weak self] step in
                    guard let self else { return }
                    self.setStatus(step)
                }
            )
            if let refusal {
                let message: String = refusal.errorMessage ?? RegistrationSubscriptionDriverMessages.signupFailed
                let code: String = refusal.errorCode ?? RegistrationSubscriptionErrorCodes.signupFailed
                report(code, message)
                apply(.accountFailed(token: token, message: message))
                return
            }

            // Account-first with a card still to take: the plan is activated by
            // `paymentSucceeded`, once there is a transaction to subscribe with. The MACHINE
            // decides whether there is still a card outstanding, so it is asked.
            let alreadyPaid: Bool = !(state.paymentTransactionId ?? "").isEmpty
            let deferPlan: Bool = state.options.paymentOrder == .afterAccount
                && !alreadyPaid
                && SignupMachine.planNeedsPayment(state)
            if !deferPlan {
                await SignupAccountCreator.activatePlan(
                    client: client,
                    request: request,
                    attempt: attempt,
                    onStep: { [weak self] step in
                        guard let self else { return }
                        self.setStatus(step)
                    }
                )
                subscriptionFailed = attempt.subscriptionFailed
            }

            let settled: SignupAccountResult = SignupAccountCreator.settled(attempt)
            apply(
                .accountCreated(
                    token: token,
                    userId: settled.userId,
                    requiresDisclaimers: settled.requiresDisclaimers
                )
            )
        } catch {
            let failure: RegistrationSubscriptionError = Self.toFailure(error)
            report(failure.code, failure.message)
            apply(.accountFailed(token: token, message: failure.message))
        }
    }

    /// The account-first tail: attach the card that has just been taken and start the plan, then
    /// tell the machine. Runs even after ``detach()`` — the money moved, so the subscription it
    /// paid for must still be created; only the dispatch afterwards is silenced.
    private func activateAfterPayment(_ settled: String) async {
        guard let form = formData else { return }
        await SignupAccountCreator.activatePlan(
            client: client,
            request: makeAccountRequest(form: form),
            attempt: attempt,
            onStep: { [weak self] step in
                guard let self else { return }
                self.setStatus(step)
            }
        )
        subscriptionFailed = attempt.subscriptionFailed
        dispatch(.paymentCompleted(paymentTransactionId: settled))
    }

    private func startPackCheckout(_ token: StepToken) {
        packCheckoutToken = token
        let model = WildwoodPackCheckoutModel(
            client: client,
            appId: appId,
            items: checkoutItems,
            names: packNames,
            paymentActionHandler: handler,
            issuer: issuer
        )
        model.labels = labels
        model.onFinished = { [weak self] packs in
            guard let self else { return }
            self.packsBought(packs)
        }
        model.onError = { [weak self] failure in
            guard let self, let forward = self.onError else { return }
            forward(failure)
        }
        packCheckout = model
        model.start()
    }

    // MARK: - Helpers

    private func makeAccountRequest(form: RegistrationFormData) -> SignupAccountRequest {
        let chosen: ResolvedSignupPlan? = plan
        return SignupAccountRequest(
            appId: appId,
            form: form,
            tierId: chosen?.tier.id,
            pricingId: chosen?.pricing?.id,
            paymentTransactionId: paymentTransactionId,
            paymentExternalId: paymentExternalId,
            tokenGrant: tokenGrant,
            platform: options.platform,
            deviceInfo: options.deviceInfo ?? PlatformDetection.deviceInfo()
        )
    }

    private func setStatus(_ step: SignupAccountStep) {
        switch step {
        case .registering:
            processingStatus = labels.statusCreatingAccount
        case .signingIn:
            processingStatus = labels.statusSigningIn
        case .activatingPlan:
            processingStatus = labels.statusActivatingPlan
        }
    }

    private func notifyAlreadySignedIn() {
        guard alreadySignedIn, !signedInNotified else { return }
        signedInNotified = true
        onAlreadySignedIn?()
    }

    /// The end of a detached run. An account that got created before the view left is entitled to
    /// whatever it signed up for, wherever the flow then stopped — so the shared entitlement store
    /// is told directly, the host callback having been cleared.
    private func finishDetached() {
        if detachFinished { return }
        detachFinished = true
        guard attempt.authResponse != nil, !entitlementsNotified else { return }
        entitlementsNotified = true
        client.features.invalidateEntitlements(appId: appId, reason: .signup)
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

    /// Whether a plan has to be paid for. TS `requiresPayment`.
    static func requiresPayment(_ plan: ResolvedSignupPlan) -> Bool {
        guard !plan.tier.isFreeTier, let pricing = plan.pricing else { return false }
        return pricing.price > 0
    }

    /// A failure, as a code a host can branch on and a message it can show. The server's own error
    /// code wins: a refused registration is a different problem from a transport failure.
    static func toFailure(_ error: any Error) -> RegistrationSubscriptionError {
        if let wildwood = error as? WildwoodError {
            let message: String = wildwood.message.isEmpty
                ? RegistrationSubscriptionDriverMessages.signupFailed
                : wildwood.message
            return RegistrationSubscriptionError(code: wildwood.code.rawValue, message: message)
        }
        return RegistrationSubscriptionError(
            code: RegistrationSubscriptionErrorCodes.signupFailed,
            message: message(error, fallback: RegistrationSubscriptionDriverMessages.signupFailed)
        )
    }

    private static func message(_ error: any Error, fallback: String) -> String {
        if let wildwood = error as? WildwoodError, !wildwood.message.isEmpty { return wildwood.message }
        let described: String = error.localizedDescription
        return described.isEmpty ? fallback : described
    }
}
