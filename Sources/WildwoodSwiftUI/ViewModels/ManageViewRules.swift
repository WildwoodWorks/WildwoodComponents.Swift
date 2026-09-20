// Every decision the manage view makes, as functions with no SwiftUI in them.
//
// The ORDER of a plan change — preview, confirm, card, change, challenge, complete — is
// ``PlanChangeMachine`` driving ``WildwoodPlanChangeModel``, and the panels are this package's
// existing subscription-admin panels. What is here is the half a VIEW owns: which sections render
// and in what arrangement, where the card for a change comes from, which packs are still on offer,
// and the two rules a store-billed device adds.
//
// Ported from packages/wildwood-react-native/src/components/registrationSubscription/views/
// manageViewModel.ts and the notice rule in parts/PlanChangeNotice.tsx, because nothing under
// `Components/` can be tested on a machine with no simulator.
//
// Two rules bind the file:
//
//  · No price is ever stated here. Amounts come off the catalog or the server's preview and are
//    formatted by ``WildwoodMoney``.
//  · A store-billed device is told the truth about who bills it, rather than being quoted a
//    proration the store will not honour (Decision 5 / Appendix C DD-4).

import Foundation
import WildwoodCore

// MARK: - Sections and layout

/// One panel of the manage view. Raw values are the web's `data-ww-section` values.
public enum ManageSection: String, Sendable, Equatable, CaseIterable {
    case subscription
    case plans
    case features
    case addOns
    case usage
    case overrides
}

/// How the sections are arranged.
public enum ManageLayout: String, Sendable, Equatable, CaseIterable {
    /// One section at a time behind a tab bar.
    case tabs
    /// Every section down one page.
    case stacked
}

/// Where the subscription card goes, and what is left for the tabs or the stacked page.
public struct ManageBodyLayout: Sendable, Equatable {
    /// The subscription card is lifted out of the section list and rendered above it.
    public var statusAbove: Bool
    /// The sections the tab bar or the stacked page carries.
    public var body: [ManageSection]

    public init(statusAbove: Bool, body: [ManageSection]) {
        self.statusAbove = statusAbove
        self.body = body
    }

    public static func == (lhs: ManageBodyLayout, rhs: ManageBodyLayout) -> Bool {
        lhs.statusAbove == rhs.statusAbove && lhs.body == rhs.body
    }
}

// MARK: - The card a plan change needs

/// Where the card for a plan change comes from, at this moment.
public enum PlanChangeCardSource: String, Sendable, Equatable, CaseIterable {
    /// Nothing is being collected: the change is elsewhere in the flow, or needs no card.
    case none
    /// The host's own `onPaymentRequired` owns the step; its answer is final.
    case host
    /// The surface's own payment sheet is mounted for it.
    case builtIn
    /// Nothing on this surface can take a card, so the customer is told where to finish.
    case finishOnWeb
}

/// Which of the notice's four shapes applies.
public enum PlanChangeNoticeKind: String, Sendable, Equatable, CaseIterable {
    case none
    case progress
    case payment
    case failed
}

/// What a plan change says about itself while it is neither waiting on the customer nor finished.
public struct PlanChangeNoticeContent: Sendable, Equatable {
    public var kind: PlanChangeNoticeKind
    /// Heading, on a failure.
    public var title: String?
    /// The sentence to show. Empty when nothing is shown.
    public var message: String
    /// Whether the failed step can be run again.
    public var canRetry: Bool
    /// Whether the notice offers a way to abandon the change.
    public var canDismiss: Bool

    public init(
        kind: PlanChangeNoticeKind,
        title: String? = nil,
        message: String = "",
        canRetry: Bool = false,
        canDismiss: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.canRetry = canRetry
        self.canDismiss = canDismiss
    }

    public static func == (lhs: PlanChangeNoticeContent, rhs: PlanChangeNoticeContent) -> Bool {
        lhs.kind == rhs.kind
            && lhs.title == rhs.title
            && lhs.message == rhs.message
            && lhs.canRetry == rhs.canRetry
            && lhs.canDismiss == rhs.canDismiss
    }
}

public enum ManageViewRules {
    /// What the manage view says when neither the host nor the client named an app. Not a label:
    /// the web hard-codes this sentence and the live suites locate it.
    public static let appIdRequiredMessage: String = "An appId is required."

    /// The sections a viewer may see, in the order they render when the host names none.
    public static let allSections: [ManageSection] = [
        .subscription, .plans, .features, .addOns, .usage, .overrides
    ]

    /// Which sections render, in the order they were asked for.
    ///
    /// The two filters apply whether the section was NAMED or defaulted: naming `overrides` does
    /// not let a non-admin see per-user grants, and naming `addOns` does not put the packs panel
    /// back on a surface the host turned packs off for.
    public static func visibleSections(
        sections: [ManageSection]?,
        isAdmin: Bool,
        showAddOns: Bool
    ) -> [ManageSection] {
        let requested: [ManageSection] = sections ?? allSections
        return requested.filter { section in
            switch section {
            case .overrides: return isAdmin
            case .addOns: return showAddOns
            case .subscription, .plans, .features, .usage: return true
            }
        }
    }

    /// The status card lifted above the tabs is not ALSO one of the sections below them — it would
    /// otherwise render twice, which is what the web's `showStatusAboveTabs` has always avoided.
    public static func bodyLayout(_ visible: [ManageSection], showStatusAboveTabs: Bool) -> ManageBodyLayout {
        let statusAbove: Bool = showStatusAboveTabs && visible.contains(.subscription)
        let body: [ManageSection] = visible.filter { !(statusAbove && $0 == .subscription) }
        return ManageBodyLayout(statusAbove: statusAbove, body: body)
    }

    /// Both filters and the lift, in one call — what a view actually asks for.
    public static func layout(
        sections: [ManageSection]?,
        isAdmin: Bool,
        showAddOns: Bool,
        showStatusAboveTabs: Bool
    ) -> ManageBodyLayout {
        bodyLayout(
            visibleSections(sections: sections, isAdmin: isAdmin, showAddOns: showAddOns),
            showStatusAboveTabs: showStatusAboveTabs
        )
    }

    /// Which tab is open: the one the user chose while it is still on offer, else the first.
    ///
    /// A tab can stop being on offer without anybody pressing anything — `isAdmin` flipping takes
    /// `overrides` away — and a layout that keeps pointing at it renders nothing at all.
    public static func currentTab(_ active: ManageSection?, body: [ManageSection]) -> ManageSection? {
        if let active, body.contains(active) { return active }
        return body.first
    }

    /// Whether this layout puts one section on screen at a time.
    public static func isTabbed(_ layout: ManageLayout) -> Bool {
        layout != .stacked
    }

    /// The heading a section carries, in both layouts. Every one of them is a label.
    public static func sectionTitle(_ section: ManageSection, labels: RegistrationSubscriptionLabels) -> String {
        switch section {
        case .subscription: return labels.sectionStatus
        case .plans: return labels.sectionPlans
        case .features: return labels.sectionFeatures
        case .addOns: return labels.sectionPacks
        case .usage: return labels.sectionUsage
        case .overrides: return labels.sectionOverrides
        }
    }

    /// The scope the panels load against: a named user, then a named company, else the caller.
    public static func scope(userId: String?, companyId: String?) -> SubscriptionAdminScope {
        if let userId, !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .user(id: userId)
        }
        if let companyId, !companyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .company(id: companyId)
        }
        return .currentUser
    }

    /// Whether the change is a CHANGE rather than a first subscribe. The server takes two different
    /// routes for the two, so this is the one thing a plan card's tap has to decide.
    public static func planChangeSelection(
        tier: AppTierModel,
        pricing: AppTierPricingModel?,
        hasSubscription: Bool
    ) -> PlanChangeSelection {
        PlanChangeSelection(tier: tier, pricing: pricing, isChange: hasSubscription)
    }

    /// The currency the panels quote in: the host's override, then the currency the server quoted
    /// the plans in, and only then the platform's fallback. Never a guessed one.
    public static func currency(override: String?, tiers: [AppTierModel]) -> String {
        if let override, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override
        }
        for tier in tiers {
            if let quoted = tier.currency, !quoted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return quoted
            }
        }
        return "USD"
    }

    /// The limit statuses the usage panel renders.
    ///
    /// A host merge that has not answered yet must not blank the panel, so the server's own
    /// statuses stand until it does.
    public static func effectiveLimitStatuses(
        merged: [AppTierLimitStatusModel],
        fromServer: [AppTierLimitStatusModel],
        hasMerge: Bool
    ) -> [AppTierLimitStatusModel] {
        if !hasMerge { return fromServer }
        return merged.isEmpty ? fromServer : merged
    }

    /// The `ww-step` hook the manage root carries: the plan change's step while one is running, and
    /// nothing at rest (the view's own name then names the element).
    public static func stepIdentifier(_ step: PlanChangeStep?) -> String? {
        guard let step, step != .idle else { return nil }
        return step.rawValue
    }

    // MARK: - The card

    /// Which of the four card sources applies.
    ///
    /// The host's handler wins wherever it exists — it predates the built-in sheet and a host that
    /// wired one means it. Otherwise the surface's own sheet takes the card: ``PaymentComponent``
    /// completes a payment on this stack with no payment SDK at all (StoreKit, the provider's own
    /// page, or a server-owned completion), so a missing ``WildwoodPaymentActionHandler`` does not
    /// make the card uncollectable. A surface that mounts no sheet is the only one left with
    /// nothing to offer, and it says so rather than spinning on a step that will never resolve.
    public static func planChangeCardSource(
        step: PlanChangeStep,
        hasHostHandler: Bool,
        paymentRequest: WildwoodPaymentRequiredArgs?,
        collectsPaymentInApp: Bool
    ) -> PlanChangeCardSource {
        if step != .collectingPayment { return .none }
        if hasHostHandler { return .host }
        if paymentRequest == nil { return .none }
        return collectsPaymentInApp ? .builtIn : .finishOnWeb
    }

    /// What the flow's state means for the notice above the panels.
    public static func planChangeNoticeContent(
        step: PlanChangeStep,
        paymentRequest: WildwoodPaymentRequiredArgs?,
        error: String?,
        canRetry: Bool,
        labels: RegistrationSubscriptionLabels,
        collectsPaymentInApp: Bool
    ) -> PlanChangeNoticeContent {
        if step == .authenticating {
            return PlanChangeNoticeContent(kind: .progress, message: labels.authenticatingChange)
        }
        if step == .completing {
            return PlanChangeNoticeContent(kind: .progress, message: labels.applyingChange)
        }
        // A card is wanted and nothing on this surface can take one: no host handler (the flow
        // would be driving that itself, and `paymentRequest` would be nil) and no sheet here
        // either.
        let card: PlanChangeCardSource = planChangeCardSource(
            step: step,
            hasHostHandler: false,
            paymentRequest: paymentRequest,
            collectsPaymentInApp: collectsPaymentInApp
        )
        if card == .finishOnWeb {
            return PlanChangeNoticeContent(kind: .payment, message: labels.finishOnWeb, canDismiss: true)
        }
        if step == .failed {
            return PlanChangeNoticeContent(
                kind: .failed,
                title: labels.planChangeFailed,
                message: error ?? "",
                canRetry: canRetry,
                canDismiss: true
            )
        }
        return PlanChangeNoticeContent(kind: .none)
    }

    /// The built-in card sheet's title.
    public static func paymentSheetTitle(
        labels: RegistrationSubscriptionLabels,
        tierName: String
    ) -> String {
        RegistrationSubscriptionLabelFormat.format(labels.upgradeToPlan, values: ["tier": tierName])
    }

    // MARK: - Packs

    /// The packs still on offer: everything the account does not already have access to, and
    /// nothing its current plan bundles in.
    ///
    /// A cancelled or expired row is on offer again; one scheduled to cancel is still owned, so it
    /// is not sold twice. That is the single `grantsAccess` rule the panel's own lists follow
    /// (``AddOnRowRules/availableRows(_:subscriptions:)``). A pack the plan already bundles has no
    /// subscription row of its own, so it is excluded here by the tier it is bundled in — selling
    /// somebody a pack they already have with their plan is the failure this prevents.
    public static func availablePacks(
        _ addOns: [AppTierAddOnModel],
        subscriptions: [UserAddOnSubscriptionModel],
        currentTierId: String?
    ) -> [AppTierAddOnModel] {
        AddOnRowRules.availableRows(addOns, subscriptions: subscriptions)
            .filter { !AddOnRowRules.isBundledInTier($0, currentTierId: currentTierId) }
    }

    /// What a basket of ticked pack ids is bought as: each pack's default pricing option, in the
    /// catalog's own order. A ticked id the catalog no longer sells is dropped rather than sent.
    public static func checkoutItems(
        ids: [String],
        addOns: [AppTierAddOnModel]
    ) -> [AddOnCheckoutItemInput] {
        var items: [AddOnCheckoutItemInput] = []
        for addOn in addOns where ids.contains(addOn.id) {
            items.append(
                AddOnCheckoutItemInput(addOnId: addOn.id, pricingId: AddOnRowRules.defaultPricing(addOn)?.id)
            )
        }
        return items
    }

    /// Pack names by id, so an outcome can name a pack the server's quote never priced.
    public static func packNames(_ addOns: [AppTierAddOnModel]) -> [String: String] {
        var names: [String: String] = [:]
        for addOn in addOns { names[addOn.id] = addOn.name }
        return names
    }

    /// Whether the packs panel offers "Add packs". The store-billed rule lives with the seam's
    /// other rules (``RegistrationSubscriptionRules/packPurchaseOffered(allowPackSelfService:showAddOns:requiresAppStorePayment:)``),
    /// so the manage view and the signup view cannot disagree about it.
    public static func packSelfServiceOffered(
        allowPackSelfService: Bool,
        showAddOns: Bool,
        requiresAppStorePayment: Bool
    ) -> Bool {
        RegistrationSubscriptionRules.packPurchaseOffered(
            allowPackSelfService: allowPackSelfService,
            showAddOns: showAddOns,
            requiresAppStorePayment: requiresAppStorePayment
        )
    }
}
