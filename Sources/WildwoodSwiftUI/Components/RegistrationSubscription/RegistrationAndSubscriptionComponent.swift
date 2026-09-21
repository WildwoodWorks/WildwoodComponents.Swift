#if os(iOS)
// One entry point for everything a customer does with money in this app: see the price list, sign
// up and buy, and manage what they bought.
//
// It is a switch and nothing more. The three views are separate types with no shared state, so a
// screen that wants one imports it directly; this component exists for a host that would rather
// pass a value than pick a type — a navigation destination, say, whose shape comes out of a route.
// It adds no behaviour, owns no state and provides nothing of its own: like every other component
// here it reads the client out of `.wildwoodClient(_:)`.
//
// The web's discriminated union (`view: 'pricing' | 'signup' | 'manage'` plus that view's props)
// maps onto an enum with an associated CONFIGURATION per case. The configurations are plain
// structs of the view's own parameters, every one of them defaulted, so:
//
//  · nothing here is generic — a `View`-typed slot or a generic parameter on this type would be
//    paid for by all three views and by every host that stores one in a property;
//  · a parameter added to a view is added to its configuration and to nothing else; and
//  · each view keeps its own initializer as the primary way in. The `init(configuration:)`
//    convenience below just forwards, so the two cannot disagree.
//
// The enum is `RegistrationSubscriptionScreen` rather than the `…ViewKind` the port notes
// suggested: that name already belongs to the test-hook enum whose raw values are the web's
// `data-ww-view` strings, and one of the two had to keep it.

import SwiftUI
import WildwoodCore

// MARK: - Configurations

/// Everything ``RegistrationSubscriptionPricingView`` takes. See that view for what each one does.
public struct RegistrationSubscriptionPricingConfiguration {
    public var appId: String?
    public var currency: String?
    public var contactUrl: String?
    public var showPlans: Bool
    public var showAddOns: Bool
    public var offerFreeTierChoice: Bool
    public var packSelection: PricingPackSelection
    public var packPurchaseAvailable: Bool
    public var addOnGroups: [WildwoodAddOnGroup]?
    public var describeAddOn: ((AppTierAddOnModel) -> WildwoodAddOnPresentation?)?
    public var showBillingToggle: Bool
    public var defaultBilling: PricingBilling
    public var showFeatureComparison: Bool
    public var showLimits: Bool
    public var highlightTierId: String?
    public var labels: RegistrationSubscriptionLabels
    public var onError: ((RegistrationSubscriptionError) -> Void)?
    /// The plan or packs the visitor chose. The one parameter with no sensible default: a pricing
    /// screen nobody listens to sells nothing.
    public var onSelect: (PricingSelection) -> Void

    public init(
        appId: String? = nil,
        currency: String? = nil,
        contactUrl: String? = nil,
        showPlans: Bool = true,
        showAddOns: Bool = false,
        offerFreeTierChoice: Bool = true,
        packSelection: PricingPackSelection = PricingPackSelection.none,
        packPurchaseAvailable: Bool = true,
        addOnGroups: [WildwoodAddOnGroup]? = nil,
        describeAddOn: ((AppTierAddOnModel) -> WildwoodAddOnPresentation?)? = nil,
        showBillingToggle: Bool = true,
        defaultBilling: PricingBilling = .monthly,
        showFeatureComparison: Bool = true,
        showLimits: Bool = true,
        highlightTierId: String? = nil,
        labels: RegistrationSubscriptionLabels = .defaults,
        onError: ((RegistrationSubscriptionError) -> Void)? = nil,
        onSelect: @escaping (PricingSelection) -> Void
    ) {
        self.appId = appId
        self.currency = currency
        self.contactUrl = contactUrl
        self.showPlans = showPlans
        self.showAddOns = showAddOns
        self.offerFreeTierChoice = offerFreeTierChoice
        self.packSelection = packSelection
        self.packPurchaseAvailable = packPurchaseAvailable
        self.addOnGroups = addOnGroups
        self.describeAddOn = describeAddOn
        self.showBillingToggle = showBillingToggle
        self.defaultBilling = defaultBilling
        self.showFeatureComparison = showFeatureComparison
        self.showLimits = showLimits
        self.highlightTierId = highlightTierId
        self.labels = labels
        self.onError = onError
        self.onSelect = onSelect
    }
}

/// Everything ``RegistrationSubscriptionSignupView`` takes. See that view for what each one does.
public struct RegistrationSubscriptionSignupConfiguration {
    public var appId: String?
    public var preSelectedTierId: String?
    public var preSelectedPricingId: String?
    public var preSelectedAddOnIds: [String]
    public var registrationToken: String?
    public var prefillEmail: String?
    public var planSelection: SignupPlanSelection
    public var planDefault: SignupPlanDefault
    public var packSelection: SignupPackSelection
    public var tokenMode: SignupTokenMode
    public var paymentOrder: SignupPaymentOrder
    public var requireBillingAddress: Bool
    public var packPurchaseAvailable: Bool
    public var paymentActionHandler: (any WildwoodPaymentActionHandler)?
    public var currency: String?
    public var contactUrl: String?
    public var closedMessage: String?
    /// One set for the signup and for the plan and pack grids inside it — they are one type.
    public var labels: RegistrationSubscriptionLabels
    public var onAlreadySignedIn: (() -> Void)?
    public var onSignupComplete: ((SignupOutcome) -> Void)?
    public var onCancel: (() -> Void)?
    public var onEntitlementsChanged: ((EntitlementsChangedReason) -> Void)?
    public var onError: ((RegistrationSubscriptionError) -> Void)?

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
        labels: RegistrationSubscriptionLabels = .defaults,
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
        self.onAlreadySignedIn = onAlreadySignedIn
        self.onSignupComplete = onSignupComplete
        self.onCancel = onCancel
        self.onEntitlementsChanged = onEntitlementsChanged
        self.onError = onError
    }
}

/// Everything ``RegistrationSubscriptionManageView`` takes. See that view for what each one does.
public struct RegistrationSubscriptionManageConfiguration {
    public var appId: String?
    public var layout: ManageLayout
    public var sections: [ManageSection]?
    public var showStatusAboveTabs: Bool
    public var isAdmin: Bool
    public var userId: String?
    public var companyId: String?
    public var allowPackSelfService: Bool
    public var allowCancel: Bool
    public var showAddOns: Bool
    public var paymentActionHandler: (any WildwoodPaymentActionHandler)?
    public var currency: String?
    public var contactUrl: String?
    public var labels: RegistrationSubscriptionLabels
    public var onMergeUsage: (@MainActor ([AppTierLimitStatusModel], UserTierSubscriptionModel?) async -> [AppTierLimitStatusModel])?
    public var onPaymentRequired: ((WildwoodPaymentRequiredArgs) async -> String?)?
    public var onSubscriptionChanged: (() -> Void)?
    public var onEntitlementsChanged: ((EntitlementsChangedReason) -> Void)?
    public var onError: ((RegistrationSubscriptionError) -> Void)?

    public init(
        appId: String? = nil,
        layout: ManageLayout = .tabs,
        sections: [ManageSection]? = nil,
        showStatusAboveTabs: Bool = false,
        isAdmin: Bool = false,
        userId: String? = nil,
        companyId: String? = nil,
        allowPackSelfService: Bool = false,
        allowCancel: Bool = true,
        showAddOns: Bool = true,
        paymentActionHandler: (any WildwoodPaymentActionHandler)? = nil,
        currency: String? = nil,
        contactUrl: String? = nil,
        labels: RegistrationSubscriptionLabels = .defaults,
        onMergeUsage: (@MainActor ([AppTierLimitStatusModel], UserTierSubscriptionModel?) async -> [AppTierLimitStatusModel])? = nil,
        onPaymentRequired: ((WildwoodPaymentRequiredArgs) async -> String?)? = nil,
        onSubscriptionChanged: (() -> Void)? = nil,
        onEntitlementsChanged: ((EntitlementsChangedReason) -> Void)? = nil,
        onError: ((RegistrationSubscriptionError) -> Void)? = nil
    ) {
        self.appId = appId
        self.layout = layout
        self.sections = sections
        self.showStatusAboveTabs = showStatusAboveTabs
        self.isAdmin = isAdmin
        self.userId = userId
        self.companyId = companyId
        self.allowPackSelfService = allowPackSelfService
        self.allowCancel = allowCancel
        self.showAddOns = showAddOns
        self.paymentActionHandler = paymentActionHandler
        self.currency = currency
        self.contactUrl = contactUrl
        self.labels = labels
        self.onMergeUsage = onMergeUsage
        self.onPaymentRequired = onPaymentRequired
        self.onSubscriptionChanged = onSubscriptionChanged
        self.onEntitlementsChanged = onEntitlementsChanged
        self.onError = onError
    }
}

// MARK: - The union

/// Which of the three views the shell renders, and what to render it with.
public enum RegistrationSubscriptionScreen {
    case pricing(RegistrationSubscriptionPricingConfiguration)
    case signup(RegistrationSubscriptionSignupConfiguration)
    case manage(RegistrationSubscriptionManageConfiguration)
}

// MARK: - The shell

public struct RegistrationAndSubscriptionComponent: View {
    private let screen: RegistrationSubscriptionScreen

    public init(_ screen: RegistrationSubscriptionScreen) {
        self.screen = screen
    }

    /// The labelled form, for a call site that reads better with it:
    /// `RegistrationAndSubscriptionComponent(view: .manage(configuration))`.
    public init(view: RegistrationSubscriptionScreen) {
        self.init(view)
    }

    public var body: some View {
        switch screen {
        case .pricing(let configuration):
            RegistrationSubscriptionPricingView(configuration: configuration)
        case .signup(let configuration):
            RegistrationSubscriptionSignupView(configuration: configuration)
        case .manage(let configuration):
            RegistrationSubscriptionManageView(configuration: configuration)
        }
    }
}

// MARK: - Forwarding initializers

public extension RegistrationSubscriptionPricingView {
    /// The view's own parameters, carried in one value. Forwards to the designated initializer, so
    /// the two cannot drift.
    init(configuration: RegistrationSubscriptionPricingConfiguration) {
        self.init(
            appId: configuration.appId,
            currency: configuration.currency,
            contactUrl: configuration.contactUrl,
            showPlans: configuration.showPlans,
            showAddOns: configuration.showAddOns,
            offerFreeTierChoice: configuration.offerFreeTierChoice,
            packSelection: configuration.packSelection,
            packPurchaseAvailable: configuration.packPurchaseAvailable,
            addOnGroups: configuration.addOnGroups,
            describeAddOn: configuration.describeAddOn,
            showBillingToggle: configuration.showBillingToggle,
            defaultBilling: configuration.defaultBilling,
            showFeatureComparison: configuration.showFeatureComparison,
            showLimits: configuration.showLimits,
            highlightTierId: configuration.highlightTierId,
            labels: configuration.labels,
            onError: configuration.onError,
            onSelect: configuration.onSelect
        )
    }
}

public extension RegistrationSubscriptionSignupView {
    /// The view's own parameters, carried in one value. The single `labels` set feeds the signup
    /// and the grids inside it — since the merge they are one type.
    init(configuration: RegistrationSubscriptionSignupConfiguration) {
        self.init(
            appId: configuration.appId,
            preSelectedTierId: configuration.preSelectedTierId,
            preSelectedPricingId: configuration.preSelectedPricingId,
            preSelectedAddOnIds: configuration.preSelectedAddOnIds,
            registrationToken: configuration.registrationToken,
            prefillEmail: configuration.prefillEmail,
            planSelection: configuration.planSelection,
            planDefault: configuration.planDefault,
            packSelection: configuration.packSelection,
            tokenMode: configuration.tokenMode,
            paymentOrder: configuration.paymentOrder,
            requireBillingAddress: configuration.requireBillingAddress,
            packPurchaseAvailable: configuration.packPurchaseAvailable,
            paymentActionHandler: configuration.paymentActionHandler,
            currency: configuration.currency,
            contactUrl: configuration.contactUrl,
            closedMessage: configuration.closedMessage,
            labels: configuration.labels,
            pricingLabels: configuration.labels,
            onAlreadySignedIn: configuration.onAlreadySignedIn,
            onSignupComplete: configuration.onSignupComplete,
            onCancel: configuration.onCancel,
            onEntitlementsChanged: configuration.onEntitlementsChanged,
            onError: configuration.onError
        )
    }
}

public extension RegistrationSubscriptionManageView {
    /// The view's own parameters, carried in one value. Forwards to the designated initializer, so
    /// the two cannot drift.
    init(configuration: RegistrationSubscriptionManageConfiguration) {
        self.init(
            appId: configuration.appId,
            layout: configuration.layout,
            sections: configuration.sections,
            showStatusAboveTabs: configuration.showStatusAboveTabs,
            isAdmin: configuration.isAdmin,
            userId: configuration.userId,
            companyId: configuration.companyId,
            allowPackSelfService: configuration.allowPackSelfService,
            allowCancel: configuration.allowCancel,
            showAddOns: configuration.showAddOns,
            paymentActionHandler: configuration.paymentActionHandler,
            currency: configuration.currency,
            contactUrl: configuration.contactUrl,
            labels: configuration.labels,
            onMergeUsage: configuration.onMergeUsage,
            onPaymentRequired: configuration.onPaymentRequired,
            onSubscriptionChanged: configuration.onSubscriptionChanged,
            onEntitlementsChanged: configuration.onEntitlementsChanged,
            onError: configuration.onError
        )
    }
}
#endif
