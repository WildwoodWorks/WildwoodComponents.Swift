#if os(iOS)
// The signup view: an account, a plan, packs and a card, in the order that keeps them consistent.
//
// The order, every skip and every server call are ``WildwoodSignupFlowModel`` over the shared
// ``SignupMachine`` — the same table the web and React Native walk — so the stacks cannot drift on
// what a registration token grants, when a plan is skipped or what the outcome says. This file
// renders whichever step the flow is on, and every decision it makes of its own is a function in
// ``SignupViewRules``, because a rule inside a `body` cannot be tested on a machine with no
// simulator.
//
// One deliberate difference from the web, and it is the reason `paymentOrder` exists: this view
// defaults to ACCOUNT-FIRST. The web takes the card before the account, because a card that fails
// then leaves nothing behind. A phone may be billed through the App Store, and a store purchase
// that succeeds before a registration that then fails strands a paid subscription with nobody to
// attach it to — a support ticket, not a void. An account with no plan is the cheaper and the
// recoverable failure, so it is the one this stack risks. A customer who walks away from the card
// is not thrown away with it: the signup finishes, and the success panel says activation is
// pending.
//
// Three more native rules, all from the platform rather than from taste:
//
//  · The plan's card is ``PaymentComponent``, which already asks the server which processor this
//    device must use and runs StoreKit itself when the answer is the App Store. There is therefore
//    no separate store branch here, where React Native needs two.
//  · A store-billed app does not offer pack PURCHASE at all (Decision 5 / Appendix C DD-4): there
//    is no in-app-purchase product behind an add-on. The driver is told, and it reports the packs
//    as not bought rather than quoting a basket nothing can pay for. Packs a registration token
//    granted are unaffected; nothing is being charged for them.
//  · A card challenge needs a payment SDK this package does not ship. With no
//    ``WildwoodPaymentActionHandler`` wired, packs are bought against a card already on file or
//    reported as not bought — never silently dropped.
//
// What the web's props list has and this does not: `returnUrl`, which JS carries and never
// navigates to (Appendix C DD-5), and `renderClosed`, a node slot. A `View`-typed slot means a
// generic parameter on this type AND on the shell that will host it, which is the price the
// pricing view already declined to pay; `closedMessage` overrides the sentence instead, and a host
// that wants a whole panel of its own composes around the view.

import SwiftUI
import WildwoodCore
import WildwoodTestIDs

public struct RegistrationSubscriptionSignupView: View {
    @Environment(\.wildwoodClient) private var client
    @Environment(\.wildwoodTheme) private var theme
    @Environment(\.wildwoodPaymentActionHandler) private var environmentPaymentActionHandler

    private let appId: String?
    private let preSelectedTierId: String?
    private let preSelectedPricingId: String?
    private let preSelectedAddOnIds: [String]
    private let registrationToken: String?
    private let prefillEmail: String?
    private let planSelection: SignupPlanSelection
    private let planDefault: SignupPlanDefault
    private let packSelection: SignupPackSelection
    private let tokenMode: SignupTokenMode
    private let paymentOrder: SignupPaymentOrder
    private let requireBillingAddress: Bool
    private let packPurchaseAvailable: Bool
    private let paymentActionHandler: (any WildwoodPaymentActionHandler)?
    private let currency: String?
    private let contactUrl: String?
    private let closedMessage: String?
    private let labels: RegistrationSubscriptionSignupLabels
    private let pricingLabels: RegistrationSubscriptionPricingLabels
    private let onAlreadySignedIn: (() -> Void)?
    private let onSignupComplete: ((SignupOutcome) -> Void)?
    private let onCancel: (() -> Void)?
    private let onEntitlementsChanged: ((EntitlementsChangedReason) -> Void)?
    private let onError: ((RegistrationSubscriptionError) -> Void)?

    @State private var model: WildwoodSignupFlowModel?
    /// The app's platform-filtered providers said this device must pay through its store.
    @State private var storeOnly: Bool = false
    /// What a signup link carried in, folded into the flow's options before the form is submitted.
    @State private var linkParams: SignupParams?
    /// Bumped when a signup link arrives, which is what re-runs the task that builds the flow.
    @State private var generation: Int = 0

    /// - Parameters:
    ///   - appId: overrides the client's configured app.
    ///   - preSelectedTierId: the plan a pricing page already chose. A plan the app does not sell
    ///     is ignored rather than honoured — the link is stale or hand-edited.
    ///   - preSelectedPricingId: the pricing option within that plan.
    ///   - preSelectedAddOnIds: packs a pricing page already chose. Deduped and capped at
    ///     ``Catalog/maxAddOnSelection`` here, then vetted against the live catalog by the flow.
    ///   - registrationToken: an invitation token from the signup link.
    ///   - prefillEmail: pre-fills the username and email fields.
    ///   - planSelection: `.skip` leaves the plan to the app — a single-plan product, or one
    ///     chosen elsewhere. The plan summary card then offers no way back to the grid.
    ///   - planDefault: `.free` opens the plan step MARKED on the app's free plan — a suggestion
    ///     the visitor still taps, not a choice already made. Ignored once a link or a token's
    ///     grant has chosen, and ignored in invite mode. The flow never sees it: it is a highlight
    ///     and nothing else.
    ///   - packSelection: `.none` removes the pack STEP. It does NOT un-choose the packs a signup
    ///     link already chose; those are still bought after login, exactly as on the web.
    ///   - tokenMode: `.required` is invite redemption — a token is the only way in, there is no
    ///     plan or pack step, and it overrides a CLOSED configuration, because the server
    ///     validates the invitation itself.
    ///   - paymentOrder: when the plan's card is taken. Defaults to
    ///     ``SignupPaymentOrder/afterAccount`` on this stack: see this file's header.
    ///   - requireBillingAddress: accepted for cross-stack parity and NOT collected on iOS. The
    ///     web's card form asks for an address; this stack has no card form of its own, and
    ///     WildwoodAPI's `InitiatePaymentRequest` carries no billing-address property in any case
    ///     (Decision 10). Passing true changes nothing today.
    ///   - packPurchaseAvailable: false LISTS no pack purchase. The App-Store-exclusive case is
    ///     detected on its own from the app's platform-filtered providers; this is the host's own
    ///     say on top of that, for a host that knows more than the lookup does.
    ///   - paymentActionHandler: this screen's own handler, which beats the subtree's
    ///     (`.wildwoodPaymentActionHandler(_:)`) and the client's. No handler anywhere is
    ///     supported and is the default.
    ///   - currency: display override. Wins over the currency the catalog names.
    ///   - contactUrl: where a visitor who still wants in is sent from the closed notice.
    ///   - closedMessage: replaces the closed notice's sentence.
    ///   - labels: overridable copy for the signup.
    ///   - pricingLabels: overridable copy for the plan and pack grids inside it. One `labels`
    ///     parameter once the full label set lands with the manage view.
    ///   - onAlreadySignedIn: raised once when the visitor already had a session. The view then
    ///     offers a notice and no second account.
    ///   - onSignupComplete: raised exactly once, from the finished panel's call to action.
    ///   - onCancel: offered beside the form and the plan grid. Omitted, neither shows one.
    ///   - onEntitlementsChanged: raised once the new account's entitlements are in.
    ///   - onError: told about every failure, with a stable code.
    public init(
        appId: String? = nil,
        preSelectedTierId: String? = nil,
        preSelectedPricingId: String? = nil,
        preSelectedAddOnIds: [String] = [],
        registrationToken: String? = nil,
        prefillEmail: String? = nil,
        planSelection: SignupPlanSelection = .choose,
        planDefault: SignupPlanDefault = SignupPlanDefault.none,
        packSelection: SignupPackSelection = SignupPackSelection.none,
        tokenMode: SignupTokenMode = .auto,
        paymentOrder: SignupPaymentOrder = .afterAccount,
        requireBillingAddress: Bool = false,
        packPurchaseAvailable: Bool = true,
        paymentActionHandler: (any WildwoodPaymentActionHandler)? = nil,
        currency: String? = nil,
        contactUrl: String? = nil,
        closedMessage: String? = nil,
        labels: RegistrationSubscriptionSignupLabels = .defaults,
        pricingLabels: RegistrationSubscriptionPricingLabels = .defaults,
        onAlreadySignedIn: (() -> Void)? = nil,
        onSignupComplete: ((SignupOutcome) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onEntitlementsChanged: ((EntitlementsChangedReason) -> Void)? = nil,
        onError: ((RegistrationSubscriptionError) -> Void)? = nil
    ) {
        self.appId = appId
        self.preSelectedTierId = preSelectedTierId
        self.preSelectedPricingId = preSelectedPricingId
        self.preSelectedAddOnIds = preSelectedAddOnIds
        self.registrationToken = registrationToken
        self.prefillEmail = prefillEmail
        self.planSelection = planSelection
        self.planDefault = planDefault
        self.packSelection = packSelection
        self.tokenMode = tokenMode
        self.paymentOrder = paymentOrder
        self.requireBillingAddress = requireBillingAddress
        self.packPurchaseAvailable = packPurchaseAvailable
        self.paymentActionHandler = paymentActionHandler
        self.currency = currency
        self.contactUrl = contactUrl
        self.closedMessage = closedMessage
        self.labels = labels
        self.pricingLabels = pricingLabels
        self.onAlreadySignedIn = onAlreadySignedIn
        self.onSignupComplete = onSignupComplete
        self.onCancel = onCancel
        self.onEntitlementsChanged = onEntitlementsChanged
        self.onError = onError
    }

    public var body: some View {
        // ONE frame, so what a registration token granted is rendered once, above whichever step
        // is on screen. The sibling stacks return a second frame for the disclaimers step and had
        // to repeat the summary in it; nothing here returns early, so nothing can drop it.
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                tokenSummary
                stepContent
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // `.contain` before the identifier, as on the order summary below: a `ScrollView` is not
        // itself an accessibility element, and an identifier on one is free to propagate to its
        // descendants instead of naming a queryable element of its own. `.contain` asks for the
        // element, and children stay individually accessible.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            RegistrationSubscriptionTestID.view(.signup, step: SignupViewRules.stepIdentifier(currentBody))
        )
        .task(id: generation) { await startFlow() }
        // DD-5. A signup or invite link may land while the visitor is still looking at the form;
        // its plan, packs, token and email are folded in and the flow restarted on them. The same
        // URL reaches Campaign Attribution through `.wildwoodClient(_:)`, which already captures
        // every opened URL, so it is deliberately not captured a second time here.
        .onOpenURL { url in applySignupLink(url) }
        // Never cancels money already in flight: `detach()` lets account creation and a pack
        // completion run to their end and only silences the callbacks.
        .onDisappear { model?.detach() }
    }

    // MARK: - Frame

    @ViewBuilder private var tokenSummary: some View {
        if let model,
           let grant = model.tokenGrant,
           SignupViewRules.showsTokenPlanSummary(body: currentBody, grant: grant) {
            TokenPlanSummaryView(grant: grant, labels: labels)
        }
    }

    @ViewBuilder private var stepContent: some View {
        if let model {
            content(model, body: currentBody)
        } else {
            // No model yet: the client is still being resolved, which is the loading state by any
            // other name.
            workingPanel(heading: labels.loadingSignup, detail: nil)
        }
    }

    @ViewBuilder private func content(_ model: WildwoodSignupFlowModel, body: SignupBody) -> some View {
        switch body {
        case .loading:
            workingPanel(heading: labels.loadingSignup, detail: nil)
        case .closed:
            closedPanel()
        case .register:
            registerStep(model)
        case .token:
            workingPanel(heading: labels.checkingToken, detail: nil)
        case .plan:
            planStep(model)
        case .packs:
            packsStep(model)
        case .payment:
            paymentStep(model)
        case .creating:
            workingPanel(heading: creatingHeading(model), detail: labels.processingWait)
        case .disclaimers:
            disclaimersStep(model)
        case .packCheckout:
            packCheckoutStep(model)
        case .failed:
            failedPanel(model)
        case .success:
            successPanel(model)
        case .signedIn:
            signedInNotice()
        }
    }

    // MARK: - Bodies

    private func closedPanel() -> some View {
        ClosedNoticeView(
            message: closedMessage ?? labels.registrationClosed,
            contactUrl: contactUrl,
            contactLabel: pricingLabels.contactUs
        )
    }

    private func signedInNotice() -> some View {
        Text(labels.alreadySignedIn)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
            .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder private func registerStep(_ model: WildwoodSignupFlowModel) -> some View {
        let mode: SignupRegistrationMode = model.mode
        let tokenMessage: String = model.tokenMessage ?? ""

        VStack(alignment: .leading, spacing: 12) {
            // Whatever plan the flow is carrying: the link's, the app's default, or the one the
            // visitor just picked through "change plan". A token's grant replaces it entirely, and
            // the summary above the frame already says so.
            if model.tokenGrant == nil, let plan = model.plan {
                PlanSummaryCardView(
                    tier: plan.tier,
                    pricing: plan.pricing,
                    currency: model.currency,
                    labels: labels,
                    onChangePlan: changePlanAction(model)
                )
            }

            if !tokenMessage.isEmpty {
                ErrorBannerView(message: tokenMessage)
            }

            SignupRegistrationFormView(
                initialFormData: model.initialFormData,
                showTokenField: mode.requireToken || mode.showOptionalTokenEntry,
                tokenRequired: mode.requireToken,
                submitTitle: SignupViewRules.submitTitle(planStepAhead: model.planStepAhead, labels: labels),
                cancelTitle: onCancel == nil ? nil : labels.cancel,
                onSubmit: { data in model.submitForm(data) },
                onCancel: onCancel
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func planStep(_ model: WildwoodSignupFlowModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(labels.choosePlan)
                .font(.title3.weight(.semibold))

            PlanGridView(
                tiers: model.catalog?.tiers ?? [],
                currency: model.currency,
                billing: planBilling(model),
                highlightTierId: highlightedTierId(model),
                contactUrl: contactUrl,
                labels: pricingLabels,
                onBillingChange: { cycle in model.billing = cycle.rawValue },
                onSelectTier: { tier in model.choosePlan(tier) }
            )

            HStack {
                Button(labels.back) { model.back(to: .register) }
                    .font(.footnote)
                Spacer()
                if let onCancel {
                    Button(labels.cancel) { onCancel() }
                        .font(.footnote)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func packsStep(_ model: WildwoodSignupFlowModel) -> some View {
        PackPickerView(
            addOns: model.availablePacks,
            currency: model.currency,
            selectedIds: model.selectedPackIds,
            labels: labels,
            pricingLabels: pricingLabels,
            onToggle: { addOnId in model.togglePack(addOnId) },
            onContinue: { model.choosePacks() },
            onSkip: { model.skipPacks() },
            onBack: { model.back(to: .register) }
        )
    }

    @ViewBuilder private func paymentStep(_ model: WildwoodSignupFlowModel) -> some View {
        if let plan = model.plan {
            paymentPanel(model, plan: plan)
        } else {
            // Unreachable: `SignupViewRules.body` gives a payment step with no plan the loading
            // body, and the driver is already on its way out of that state.
            workingPanel(heading: labels.loadingSignup, detail: nil)
        }
    }

    @ViewBuilder private func paymentPanel(
        _ model: WildwoodSignupFlowModel,
        plan: ResolvedSignupPlan
    ) -> some View {
        let payment: SignupPaymentProps = SignupViewRules.paymentProps(
            tier: plan.tier,
            pricing: plan.pricing,
            currency: model.currency,
            trialDays: model.trialDays
        )
        // Account-first: the account already exists, so backing out of the card finishes the
        // signup with the plan pending rather than stepping back to a form that is behind them.
        let leaveTitle: String = model.paymentAfterAccount ? labels.skipForNow : labels.back

        VStack(alignment: .leading, spacing: 12) {
            planOrderSummary(model, plan: plan)

            PaymentComponent(
                appId: appId,
                amount: payment.amount,
                currency: payment.currency,
                description: payment.description,
                customerEmail: model.state.email.isEmpty ? nil : model.state.email,
                isSubscription: true,
                pricingModelId: payment.pricingModelId,
                billingFrequency: payment.billingFrequency,
                trialDays: payment.trialDays,
                // The amount is already on the order summary above; saying it twice invites the
                // two to disagree.
                showAmount: false,
                paymentActionHandler: paymentActionHandler,
                onPaymentSuccess: { result in model.paymentSucceeded(result) },
                onPaymentFailure: { _ in
                    // PaymentComponent shows its own message; the step stays put so the card can
                    // be tried again on the same intent.
                }
            )

            Button(leaveTitle) { leavePayment(model) }
                .font(.footnote)
                .accessibilityIdentifier(RegistrationSubscriptionTestID.paymentLeave)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func planOrderSummary(
        _ model: WildwoodSignupFlowModel,
        plan: ResolvedSignupPlan
    ) -> some View {
        let priceText: String = SignupViewRules.planPriceText(
            tier: plan.tier,
            pricing: plan.pricing,
            currency: model.currency,
            labels: labels
        )
        let trialLine: String = SignupViewRules.planTrialLine(
            trialDays: model.trialDays,
            currency: model.currency,
            labels: labels
        )

        VStack(alignment: .leading, spacing: 8) {
            Text(labels.orderSummary)
                .font(.headline)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(plan.tier.name)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !priceText.isEmpty {
                    Text(priceText)
                        .font(.headline)
                        .foregroundStyle(theme.accent)
                }
            }

            if !trialLine.isEmpty {
                Text(trialLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.success)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(RegistrationSubscriptionTestID.orderSummary)
    }

    @ViewBuilder private func disclaimersStep(_ model: WildwoodSignupFlowModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(labels.disclaimersTitle)
                .font(.title3.weight(.semibold))
            Text(labels.disclaimersIntro)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // The session JWT is already stored, so the accepts are authenticated. Hosted exactly
            // as the older wizard hosts it, including the empty-load escape: nothing pending after
            // all must not strand the visitor on this step.
            DisclaimerComponent(
                appId: appId,
                onAllAccepted: { model.disclaimersDone() },
                onLoaded: { count in
                    if count == 0 { model.disclaimersDone() }
                }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func packCheckoutStep(_ model: WildwoodSignupFlowModel) -> some View {
        if let checkout = model.packCheckout {
            PackCheckoutView(model: checkout, labels: labels)
        } else {
            workingPanel(heading: labels.buyingPacks, detail: nil)
        }
    }

    @ViewBuilder private func failedPanel(_ model: WildwoodSignupFlowModel) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(theme.danger)
            Text(labels.signupFailed)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text(model.error ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier(RegistrationSubscriptionTestID.signupErrorMessage)

            Button(labels.tryAgain) { model.retry() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(RegistrationSubscriptionTestID.signupRetry)
            Button(labels.startOver) { model.startOver() }
                .font(.footnote)
                .accessibilityIdentifier(RegistrationSubscriptionTestID.signupStartOver)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    @ViewBuilder private func successPanel(_ model: WildwoodSignupFlowModel) -> some View {
        let message: String = SignupViewRules.successMessage(
            SignupSuccessInput(
                labels: labels,
                tokenPlanName: model.tokenGrant?.appTierName,
                hasTokenGrant: model.tokenGrant != nil,
                hasPlan: model.plan != nil,
                subscriptionFailed: model.subscriptionFailed,
                planActivationPending: model.outcome?.planActivationPending == true,
                trialDays: model.trialDays
            )
        )

        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundStyle(theme.success)
            Text(labels.signupCompleteTitle)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            PackOutcomeListView(packs: model.outcome?.packs ?? [], labels: labels)

            Button(labels.getStarted) { model.complete() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(RegistrationSubscriptionTestID.signupGetStarted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func workingPanel(heading: String, detail: String?) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(heading)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Derived state

    private var currentBody: SignupBody {
        guard let model else { return .loading }
        return SignupViewRules.body(
            SignupBodyInput(
                step: model.step,
                alreadySignedIn: model.alreadySignedIn,
                hasPlan: model.plan != nil,
                formSubmitted: model.state.formSubmitted
            )
        )
    }

    /// Whether packs may be bought here at all — the host's say and the store's, together.
    private var packsOffered: Bool {
        SignupViewRules.packPurchaseOffered(
            packPurchaseAvailable: packPurchaseAvailable,
            storeOnly: storeOnly
        )
    }

    /// The driver keeps the cycle as the catalog's own frequency string; the grid wants the enum.
    private func planBilling(_ model: WildwoodSignupFlowModel) -> PricingBilling {
        model.billing == PricingBilling.annual.rawValue ? .annual : .monthly
    }

    /// Which plan the grid opens marked: the visitor's own choice, else what `planDefault` suggests,
    /// else the link's plan. The default sits AHEAD of the link on purpose — see
    /// ``SignupViewRules/highlightTierId(selectionTierId:defaultTierId:preSelectedTierId:)``.
    ///
    /// Invite mode is read off the flow's RESOLVED options rather than this view's parameter: an
    /// invite link that landed on the form (DD-5) makes the token the only way in, and its plan
    /// comes from the token, so there is nothing to suggest then either.
    private func highlightedTierId(_ model: WildwoodSignupFlowModel) -> String? {
        SignupViewRules.highlightTierId(
            selectionTierId: model.state.selection.tierId,
            defaultTierId: SignupViewRules.defaultTierId(
                planDefault: planDefault,
                isInvite: model.options.tokenMode == .required,
                catalog: model.catalog
            ),
            preSelectedTierId: preSelectedTierId
        )
    }

    private func creatingHeading(_ model: WildwoodSignupFlowModel) -> String {
        model.processingStatus.isEmpty ? labels.statusCreatingAccount : model.processingStatus
    }

    /// "Change plan" on the summary card, or nothing at all.
    ///
    /// A `skip` flow's plan is the app's, not the visitor's — a single-plan product, or one chosen
    /// somewhere this view does not own — so there is nowhere to change it to.
    private func changePlanAction(_ model: WildwoodSignupFlowModel) -> (() -> Void)? {
        if planSelection == .skip { return nil }
        return { model.changePlan() }
    }

    // MARK: - Actions

    private func leavePayment(_ model: WildwoodSignupFlowModel) {
        if model.paymentAfterAccount {
            model.paymentAbandoned()
            return
        }
        model.back(to: planSelection == .skip ? .register : .plan)
    }

    /// DD-5: fold a signup or invite link into the flow, but only while the form is still ahead.
    ///
    /// Past the form the visitor has committed to a plan and possibly to a card, and rewriting the
    /// selection underneath them would change what they are buying after they agreed to it. A link
    /// that arrives then is left to Campaign Attribution, which has already had it.
    private func applySignupLink(_ url: URL) {
        let submitted: Bool = model?.state.formSubmitted ?? false
        if !SignupViewRules.acceptsSignupLink(formSubmitted: submitted) { return }

        let params: SignupParams = SignupParams.parse(url: url)
        // A URL that carries nothing this screen understands changes nothing.
        if !SignupViewRules.signupLinkCarriesSelection(params) { return }

        linkParams = params
        model?.detach()
        model = nil
        generation += 1
    }

    private func startFlow() async {
        guard model == nil,
              let client = requireClient(client, component: "RegistrationSubscriptionSignupView")
        else { return }

        let created = WildwoodSignupFlowModel(
            client: client,
            options: resolvedOptions(),
            paymentActionHandler: WildwoodPaymentAction.resolve(
                parameter: paymentActionHandler,
                environment: environmentPaymentActionHandler,
                client: client
            )
        )
        created.labels = labels.driverLabels
        created.onAlreadySignedIn = onAlreadySignedIn
        created.onSignupComplete = onSignupComplete
        created.onEntitlementsChanged = onEntitlementsChanged
        created.onError = onError
        created.setPackPurchaseAvailable(packsOffered)

        model = created
        created.start()

        await loadStoreOnly(client, model: created)
    }

    private func resolvedOptions() -> WildwoodSignupFlowOptions {
        let options = WildwoodSignupFlowOptions(
            appId: appId,
            currency: currency,
            preSelectedTierId: preSelectedTierId,
            preSelectedPricingId: preSelectedPricingId,
            preSelectedAddOnIds: SignupViewRules.cappedPreSelectedPackIds(preSelectedAddOnIds),
            registrationToken: registrationToken,
            prefillEmail: prefillEmail,
            planSelection: planSelection,
            packSelection: packSelection,
            tokenMode: tokenMode,
            paymentOrder: paymentOrder
        )
        guard let linkParams else { return options }
        return options.applying(linkParams)
    }

    /// Whether this device has to pay through its store. The server answers per platform, so it is
    /// asked rather than guessed, and an unanswerable question is read as "no": refusing to sell
    /// because a lookup failed would be worse than offering the card the app is configured for.
    private func loadStoreOnly(_ client: WildwoodClient, model: WildwoodSignupFlowModel) async {
        let resolvedAppId: String = appId ?? client.config.appId ?? ""
        guard !resolvedAppId.isEmpty else { return }
        guard let providers = try? await client.payment.getAvailableProviders(appId: resolvedAppId) else {
            return
        }
        // Held in a local as well as in state: the driver is told from the value just read, not
        // from a `@State` re-read, so the answer cannot depend on when SwiftUI publishes it.
        let store: Bool = providers.requiresAppStorePayment
        storeOnly = store
        model.setPackPurchaseAvailable(
            SignupViewRules.packPurchaseOffered(
                packPurchaseAvailable: packPurchaseAvailable,
                storeOnly: store
            )
        )
    }
}
#endif
