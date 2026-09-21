// Every decision the signup view makes, as pure functions with no SwiftUI in them.
//
// The ORDER of the signup — what is skipped, what a registration token's grant takes out of it,
// when the card is taken — is the shared ``SignupMachine``, and the server calls around it are
// ``WildwoodSignupFlowModel``. Neither is re-implemented here. What is here is the half a view
// owns: which body renders for the state the flow is in, what the success panel says, what the
// payment step is handed, and the rules a store-billed device adds.
//
// It exists as its own file for the reason every rule in this folder does: a rule that lives
// inside a `body` cannot be tested on a machine with no simulator, and this package is authored on
// one.
//
// Two rules bind the file:
//
//  · No price is stated here. Amounts come off the plan the catalog quoted, or off the server's
//    own quote, and are formatted by ``WildwoodMoney/format(_:currency:)``.
//  · Nothing fails silently. A pack that cannot be bought on this device is REPORTED as a pack
//    that was not bought, with the reason, rather than dropped from the basket.
//
// Ported function for function from
// packages/wildwood-react-native/src/components/registrationSubscription/views/signupViewModel.ts,
// minus the two bodies that only React Native needs: its plan purchase mounts a separate store
// sheet, while this package's ``PaymentComponent`` already drives StoreKit itself when the app's
// platform-filtered providers say the store owns the money. There is therefore one `payment` body
// here where RN has three.

import Foundation
import WildwoodCore

/// Which body the signup view renders. Every value but the last is also the `ww-step` identifier
/// the web puts in `data-ww-step` — the machine's `done` is spelled `success` there, and so it is
/// here.
public enum SignupBody: String, Sendable, Equatable, CaseIterable {
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
    case failed
    case success
    /// A signed-in visitor: the notice, and no second account on offer. The web renders no
    /// `data-ww-step` for it, so neither does this.
    case signedIn
}

/// What ``SignupViewRules/body(_:)`` reads.
public struct SignupBodyInput: Sendable, Equatable {
    /// The machine's step.
    public var step: SignupStep
    /// The visitor already had a session when the flow started.
    public var alreadySignedIn: Bool
    /// A plan is being carried, resolved against the live catalog.
    public var hasPlan: Bool
    /// The registration form has been submitted.
    public var formSubmitted: Bool

    public init(
        step: SignupStep,
        alreadySignedIn: Bool = false,
        hasPlan: Bool = false,
        formSubmitted: Bool = false
    ) {
        self.step = step
        self.alreadySignedIn = alreadySignedIn
        self.hasPlan = hasPlan
        self.formSubmitted = formSubmitted
    }
}

/// What the success panel decides from.
public struct SignupSuccessInput: Sendable, Equatable {
    public var labels: RegistrationSubscriptionSignupLabels
    /// The plan name a registration token granted, when the signup ran on one.
    public var tokenPlanName: String?
    /// Whether a registration token granted a plan at all.
    public var hasTokenGrant: Bool
    /// Whether the signup chose a plan of its own.
    public var hasPlan: Bool
    /// The server refused the subscription after the account was made.
    public var subscriptionFailed: Bool
    /// The account exists but its card was walked away from (account-first order only).
    public var planActivationPending: Bool
    /// Free-trial days on the plan that was paid for.
    public var trialDays: Int

    public init(
        labels: RegistrationSubscriptionSignupLabels = .defaults,
        tokenPlanName: String? = nil,
        hasTokenGrant: Bool = false,
        hasPlan: Bool = false,
        subscriptionFailed: Bool = false,
        planActivationPending: Bool = false,
        trialDays: Int = 0
    ) {
        self.labels = labels
        self.tokenPlanName = tokenPlanName
        self.hasTokenGrant = hasTokenGrant
        self.hasPlan = hasPlan
        self.subscriptionFailed = subscriptionFailed
        self.planActivationPending = planActivationPending
        self.trialDays = trialDays
    }
}

/// What the payment step charges for, taken off the plan the catalog quoted.
public struct SignupPaymentProps: Sendable, Equatable {
    /// The pricing option's OWN price — never a prorated figure and never a remembered one,
    /// because this is a first subscription and the option is what the server will bill.
    public var amount: Double
    public var currency: String
    /// What the charge is called: the plan's name.
    public var description: String
    /// The pricing MODEL behind the option, so the server starts a subscription and not a charge.
    public var pricingModelId: String?
    /// Always true here: a signup buys a plan, and a plan recurs.
    public var isSubscription: Bool
    /// Nil rather than zero, so ``PaymentComponent`` offers a trial only when there is one.
    public var trialDays: Int?
    /// The period the server named, passed through so the button can say it.
    public var billingFrequency: String?

    public init(
        amount: Double = 0,
        currency: String = "",
        description: String = "",
        pricingModelId: String? = nil,
        isSubscription: Bool = true,
        trialDays: Int? = nil,
        billingFrequency: String? = nil
    ) {
        self.amount = amount
        self.currency = currency
        self.description = description
        self.pricingModelId = pricingModelId
        self.isSubscription = isSubscription
        self.trialDays = trialDays
        self.billingFrequency = billingFrequency
    }
}

/// One line of what a registration token granted: a pack or an extra feature, named.
///
/// The identity carries the POSITION as well as the id, because a malformed grant that repeats an
/// id would otherwise hand a list two rows with one identity — a runtime fault in SwiftUI rather
/// than a cosmetic one.
public struct SignupGrantEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// The plan the grid opens on when nothing has chosen one.
///
/// Deliberately NOT one of ``SignupMachineOptions``'s settings, and deliberately not in
/// `SignupMachine.swift`: the machine never sees this. It MARKS a card in the grid and the visitor
/// still taps it, so a default that reached the reducer would be a choice nobody made.
public enum SignupPlanDefault: String, Sendable, Equatable, CaseIterable {
    /// Nothing is marked; the grid opens exactly as it always did.
    case none
    /// The app's free plan is marked — a suggestion the visitor still confirms, not a choice
    /// already made. Ignored once a link or a grant has chosen.
    case free
}

/// How a pack basket's card is dealt with on this device.
public enum PackCheckoutCardBranch: String, Sendable, Equatable, CaseIterable {
    /// The quote found a card already on file: the basket is bought against it.
    case savedCard
    /// A card is needed and the host's handler can confirm a SetupIntent: collected once, here.
    case handlerCard
    /// A card is needed and nothing on this device can take one.
    case finishOnWeb
}

public enum SignupViewRules {
    /// The register form's submit text when the form is the last thing between the visitor and an
    /// account.
    ///
    /// Hard-coded, and deliberately NOT ``RegistrationSubscriptionSignupLabels/createAccount``
    /// ("Create account"): the web writes this one with a capital A and the live sites' end-to-end
    /// locators read it, so it is carried verbatim rather than quietly title-cased.
    public static let createAccountSubmitText: String = "Create Account"

    // MARK: - Which body renders

    /// Which body applies.
    ///
    /// Every step but `payment` is its own body. `payment` is the one that can arrive with nothing
    /// to charge for — no plan left in the catalog, or a form that was never submitted — and a card
    /// form shown there would take money with nothing to attach it to. The flow has already
    /// dispatched the way out of that state, so what shows meanwhile is the loading panel, not a
    /// card.
    public static func body(_ input: SignupBodyInput) -> SignupBody {
        // A visitor who already had a session is the host's problem, not this view's: it says so
        // through `onAlreadySignedIn` and offers no second account, whatever the flow is doing
        // underneath.
        if input.alreadySignedIn { return .signedIn }

        switch input.step {
        case .loading: return .loading
        case .closed: return .closed
        case .register: return .register
        case .token: return .token
        case .plan: return .plan
        case .packs: return .packs
        case .creating: return .creating
        case .disclaimers: return .disclaimers
        case .packCheckout: return .packCheckout
        case .failed: return .failed
        case .done: return .success
        case .payment:
            if !input.hasPlan || !input.formSubmitted { return .loading }
            return .payment
        }
    }

    /// The `ww-step` identifier for a body, or nil for the one the web hangs no step off.
    public static func stepIdentifier(_ body: SignupBody) -> String? {
        body == .signedIn ? nil : body.rawValue
    }

    /// Whether what a registration token granted is shown beside a body — asked in ONE place.
    ///
    /// The web renders its token summary in the outer frame, above whichever step is on screen, so
    /// a visitor arriving on an invitation can always see what it already paid for. Asking it here
    /// rather than inside each body is the point: a rule kept in a `body` is a rule the next body
    /// can quietly drop, and the disclaimers step is exactly where the sibling stacks dropped it.
    ///
    /// `signedIn` is the one body the web leaves it out of — that early return offers a notice and
    /// no second account — and there is no grant behind it in any case, since the flow never ran.
    public static func showsTokenPlanSummary(
        body: SignupBody,
        grant: RegistrationTokenAppGrant?
    ) -> Bool {
        grant != nil && body != .signedIn
    }

    // MARK: - What a signup link carried in

    /// The packs a signup link may carry in, deduped and capped at ``Catalog/maxAddOnSelection``.
    ///
    /// The cap is applied before the ids ever reach the flow, so a link carrying hundreds of them
    /// cannot make the signup quote a basket the server would refuse. WHICH of them the app
    /// actually sells is the catalog's answer and is settled inside the flow — this only bounds the
    /// request.
    public static func cappedPreSelectedPackIds(_ ids: [String]?) -> [String] {
        guard let ids else { return [] }
        var seen = Set<String>()
        var capped: [String] = []
        for id in ids where !id.isEmpty {
            if !seen.insert(id).inserted { continue }
            capped.append(id)
            if capped.count >= Catalog.maxAddOnSelection { return capped }
        }
        return capped
    }

    /// Whether a signup or invite link that arrives NOW may still change what is being bought.
    ///
    /// Only while the form is still ahead. Past it the visitor has committed to a plan and
    /// possibly to a card, and rewriting the selection underneath them would change what they are
    /// buying after they agreed to it. A link that arrives later is left to Campaign Attribution,
    /// which has already had the URL.
    public static func acceptsSignupLink(formSubmitted: Bool) -> Bool {
        !formSubmitted
    }

    /// Whether a parsed link carried anything this screen acts on.
    public static func signupLinkCarriesSelection(_ params: SignupParams) -> Bool {
        params != SignupParams()
    }

    // MARK: - The plan the grid opens on

    /// The plan ``SignupPlanDefault/free`` suggests: the FIRST plan the catalog marks free, or
    /// nothing at all.
    ///
    /// Nil in invite mode — an invite's plan comes from its token, so there is nothing to suggest —
    /// and nil when the app sells no free plan, which is not a failure: the grid is then the one it
    /// would have been anyway.
    ///
    /// A highlight only. The value goes to ``highlightTierId(selectionTierId:defaultTierId:preSelectedTierId:)``
    /// and nowhere near ``SignupMachine``, so nothing here selects a plan, prices one or skips a
    /// step.
    public static func defaultTierId(
        planDefault: SignupPlanDefault,
        isInvite: Bool,
        catalog: PublicCatalog?
    ) -> String? {
        guard planDefault == SignupPlanDefault.free, !isInvite, let catalog else { return nil }
        for tier in catalog.tiers where tier.isFreeTier { return tier.id }
        return nil
    }

    /// Which plan the grid opens MARKED, in the order the web resolves it.
    ///
    /// The visitor's own choice first; then the default above, which ``SignupPlanDefault/free``
    /// puts there. A link's `preSelectedTierId` sits LAST on purpose: a stale or hand-edited one is
    /// an id the flow already refused, so the grid opens on the host's default rather than on
    /// nothing at all.
    ///
    /// None of the three is a choice — the grid marks one and the visitor still taps it.
    public static func highlightTierId(
        selectionTierId: String?,
        defaultTierId: String?,
        preSelectedTierId: String?
    ) -> String? {
        selectionTierId ?? defaultTierId ?? preSelectedTierId
    }

    // MARK: - What the panels say

    /// What the success panel says, by what actually happened — in the same order the web resolves
    /// it, with one addition this stack needs: an account-first signup whose card was abandoned has
    /// an account and no plan, which is exactly what "activation is pending" already says.
    public static func successMessage(_ input: SignupSuccessInput) -> String {
        let labels: RegistrationSubscriptionSignupLabels = input.labels
        if input.hasTokenGrant {
            // A token that named no plan still granted one; "plan" is what the web calls it then.
            let tier: String = SignupPlanRules.nonBlank(input.tokenPlanName) ?? "plan"
            return RegistrationSubscriptionLabelFormat.format(
                labels.signupCompleteToken,
                values: ["tier": tier]
            )
        }
        if !input.hasPlan { return labels.signupCompletePlain }
        if input.subscriptionFailed || input.planActivationPending { return labels.signupCompletePending }
        if input.trialDays > 0 {
            return RegistrationSubscriptionLabelFormat.format(
                labels.signupCompleteTrial,
                values: ["days": String(input.trialDays)]
            )
        }
        return labels.signupCompleteActive
    }

    /// The register form's submit text: "Continue" while a plan is still ahead, otherwise the
    /// account is the next thing that happens and the button says so.
    public static func submitTitle(
        planStepAhead: Bool,
        labels: RegistrationSubscriptionSignupLabels
    ) -> String {
        planStepAhead ? labels.continueLabel : createAccountSubmitText
    }

    // MARK: - What a registration token granted

    /// One entry per granted id, named the way the server named it — or by its id when it did not.
    /// Names are matched BY INDEX, which is how the server sends them.
    public static func grantEntries(ids: [String], names: [String]?) -> [SignupGrantEntry] {
        var rows: [SignupGrantEntry] = []
        for (index, id) in ids.enumerated() {
            var name: String = id
            if let names, index < names.count, !names[index].isEmpty {
                name = names[index]
            }
            rows.append(SignupGrantEntry(id: "\(index):\(id)", name: name))
        }
        return rows
    }

    /// The granted plan, and its pricing option in brackets when the server named one. Never
    /// priced: the visitor is not paying for it.
    public static func grantTierText(_ grant: RegistrationTokenAppGrant) -> String {
        let tierName: String = SignupPlanRules.nonBlank(grant.appTierName) ?? grant.appTierId
        guard let pricingName = SignupPlanRules.nonBlank(grant.pricingName) else { return tierName }
        return tierName + " (" + pricingName + ")"
    }

    // MARK: - The payment step

    /// The payment props for a plan.
    public static func paymentProps(
        tier: AppTierModel,
        pricing: AppTierPricingModel?,
        currency: String,
        trialDays: Int
    ) -> SignupPaymentProps {
        SignupPaymentProps(
            amount: pricing?.price ?? 0,
            currency: currency,
            description: tier.name,
            pricingModelId: pricing?.pricingModelId,
            isSubscription: true,
            trialDays: trialDays > 0 ? trialDays : nil,
            billingFrequency: pricing?.billingFrequency
        )
    }

    /// The per-period suffix shown beside a plan's price. Empty for a frequency the server named
    /// nothing for — never an invented "/month".
    public static func planPeriodSuffix(_ billingFrequency: String?) -> String {
        let frequency: String = (billingFrequency ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return frequency.isEmpty ? "" : "/" + frequency
    }

    /// The plan's price as the order summary and the plan card say it, or the free-plan word, or
    /// nothing at all — never a number the catalog did not quote.
    public static func planPriceText(
        tier: AppTierModel,
        pricing: AppTierPricingModel?,
        currency: String,
        labels: RegistrationSubscriptionSignupLabels
    ) -> String {
        guard let pricing else { return tier.isFreeTier ? labels.planFree : "" }
        return WildwoodMoney.format(pricing.price, currency: currency) + planPeriodSuffix(pricing.billingFrequency)
    }

    /// The trial line under the plan in the order summary: what the trial is, and that nothing is
    /// charged for it today. Empty when there is no trial.
    public static func planTrialLine(
        trialDays: Int,
        currency: String,
        labels: RegistrationSubscriptionSignupLabels
    ) -> String {
        let trial: String = WildwoodTrial.label(days: trialDays)
        if trial.isEmpty { return "" }
        // The zero is the server's arithmetic, not this file's opinion: a trial charges nothing
        // today, and it is formatted in the same currency as everything else on the panel.
        return trial + ". " + labels.dueToday + ": " + WildwoodMoney.format(0, currency: currency)
    }

    // MARK: - Packs

    /// Which of the three branches the basket is on.
    ///
    /// The important one is the last. With no handler this package has nothing that can put a card
    /// field or a bank challenge in front of the customer, so the flow does NOT ask the server for
    /// a SetupIntent it could never confirm — it says where the purchase can be finished instead.
    public static func packCheckoutCardBranch(
        requiresPaymentMethod: Bool,
        canConfirmCardSetup: Bool
    ) -> PackCheckoutCardBranch {
        if !requiresPaymentMethod { return .savedCard }
        return canConfirmCardSetup ? .handlerCard : .finishOnWeb
    }

    /// Whether a failed basket is worth offering "Try Again" for.
    ///
    /// A basket that failed because this device cannot take a card will fail again for exactly the
    /// same reason, so the only honest way on is to leave the packs unbought and finish the signup.
    public static func packCheckoutCanRetry(_ branch: PackCheckoutCardBranch) -> Bool {
        branch != .finishOnWeb
    }

    /// What the pack-checkout status line says while it is working.
    public static func packCheckoutStatusText(
        step: PackCheckoutStep,
        packName: String,
        labels: RegistrationSubscriptionSignupLabels
    ) -> String {
        if step == .authenticating || step == .completing {
            return RegistrationSubscriptionLabelFormat.format(
                labels.authenticatingPack,
                values: ["name": packName]
            )
        }
        return labels.buyingPacks
    }

    /// Whether packs may be BOUGHT on this device.
    ///
    /// An app billed through the App Store has no store product mapped to an add-on — pack checkout
    /// is a card purchase and nothing else (`IapProductMapping` is tier-only) — so on a store-billed
    /// device the purchase is not offered. What a registration token granted is unaffected: nothing
    /// is being charged for it. The host's own `packPurchaseAvailable` is the other half, for a
    /// host that knows more than the provider lookup does.
    public static func packPurchaseOffered(packPurchaseAvailable: Bool, storeOnly: Bool) -> Bool {
        packPurchaseAvailable && !storeOnly
    }

    /// The outcome for a basket that cannot be bought on this device at all.
    ///
    /// Reported rather than dropped: the visitor asked for these packs, and a signup that quietly
    /// forgets them leaves them thinking they have something they do not.
    public static func unbuyablePackOutcomes(
        items: [AddOnCheckoutItemInput],
        names: [String: String],
        message: String
    ) -> [SignupPackOutcome] {
        var settled: [SignupPackOutcome] = []
        for item in items {
            settled.append(
                SignupPackOutcome(
                    addOnId: item.addOnId,
                    name: names[item.addOnId] ?? item.addOnId,
                    status: SignupPackStatuses.failed,
                    trialEnd: nil,
                    errorMessage: message
                )
            )
        }
        return settled
    }

    /// The same, for a driver that holds pack ids rather than checkout items.
    public static func unbuyablePackOutcomes(
        addOnIds: [String],
        names: [String: String],
        message: String
    ) -> [SignupPackOutcome] {
        unbuyablePackOutcomes(
            items: addOnIds.map { AddOnCheckoutItemInput(addOnId: $0) },
            names: names,
            message: message
        )
    }

    /// What one pack's outcome row says about its status.
    public static func packStatusLabel(
        _ status: String,
        labels: RegistrationSubscriptionSignupLabels
    ) -> String {
        switch status {
        case SignupPackStatuses.trialing: return labels.packStatusTrialing
        case SignupPackStatuses.active: return labels.packStatusActive
        case SignupPackStatuses.granted: return labels.packStatusGranted
        default: return labels.packStatusFailed
        }
    }

    /// Whether an outcome row reads as a failure, for the colour it is given.
    public static func packOutcomeFailed(_ status: String) -> Bool {
        status != SignupPackStatuses.trialing
            && status != SignupPackStatuses.active
            && status != SignupPackStatuses.granted
    }

    /// A trial end date in the device's own locale, or nothing when the server sent none.
    public static func trialEndText(_ trialEnd: Date?) -> String {
        guard let trialEnd else { return "" }
        return trialEnd.formatted(date: .abbreviated, time: .omitted)
    }

    /// The card the server's quote says is already on file, named the way the label words it.
    /// Nil when the quote named none.
    public static func savedCardLine(
        _ savedCard: AddOnCheckoutSavedCardModel?,
        labels: RegistrationSubscriptionSignupLabels
    ) -> String? {
        guard let savedCard else { return nil }
        return RegistrationSubscriptionLabelFormat.format(
            labels.savedCardOnFile,
            values: ["brand": savedCard.brand ?? "", "last4": savedCard.last4 ?? ""]
        )
    }

    /// Whether the pack checkout is mid-flight, so the status line shows.
    public static func packCheckoutWorking(step: PackCheckoutStep, busy: Bool) -> Bool {
        switch step {
        case .idle, .quoting, .collectingCard:
            return true
        case .quoted, .checkingOut, .authenticating, .completing, .done, .failed:
            return busy
        }
    }
}
