// Every user-facing string the registration-and-subscription views say, in ONE overridable type.
//
// Values are the JS defaults byte for byte
// (packages/wildwood-react-shared/src/registrationSubscription/labels.ts, Appendix A C.2) and the
// members are declared in that file's order, so the three stacks say the same words and a host
// that overrides a subset names only what it is replacing:
//
//     RegistrationSubscriptionLabels(retry: "Try again", addPacks: "Add more")
//
// `RegistrationSubscriptionPricingLabels`, `RegistrationSubscriptionSignupLabels` and the drivers'
// `RegistrationSubscriptionDriverLabels` are TYPEALIASES of this type. They were the per-view
// slices this file merges: each view and driver reads its members BY NAME, so collapsing them onto
// one struct changed no call site and left one source of truth for every string. A test pins every
// default against a table transcribed from `labels.ts`, so a stack that drifts fails a test rather
// than a review.
//
// What is NOT here, on purpose:
//
//  · The plan card's own call-to-action texts ("Current Plan", "Select <Tier>", "Contact Us",
//    "Free", "Save N%"). Those live on the shared ``TierCard`` in every stack — React says so in as
//    many words ("Plan-card CTAs are NOT labels") — because one card serves the pricing view, the
//    admin panels and the standalone pricing grid.
//  · The register form's submit text when the form is the last thing before an account exists. The
//    web hard-codes "Create Account" there — capital A, unlike the `createAccount` label — and the
//    live sites' locators depend on it, so ``SignupViewRules/createAccountSubmitText`` carries it
//    verbatim instead of pretending it is overridable.

import Foundation

/// The overridable copy for the pricing, signup and manage views. Every member defaults to the JS
/// default string.
public struct RegistrationSubscriptionLabels: Sendable, Equatable {
    // MARK: - Pricing view

    /// The monthly side of the billing switch.
    public var billingMonthly: String
    /// The annual side of the billing switch.
    public var billingAnnual: String
    /// What a screen reader calls the billing switch.
    public var billingToggleAriaLabel: String
    /// The best annual saving on offer. Carries a `{percent}` slot.
    public var annualSavings: String
    /// What a screen reader hears while the prices load.
    public var loadingPlans: String
    /// Said when the catalog could not be read. No price is shown with it.
    public var pricingUnavailable: String
    /// Loads the catalog again, bypassing the cache.
    public var retry: String
    /// A contact link's text, where a view rather than the plan card renders one.
    public var contactUs: String
    /// The trailing group that holds packs no host group claimed.
    public var morePacks: String
    /// Said in place of a price for a pack the operator has not priced.
    public var packUnavailable: String
    /// The single-select pack call to action.
    public var packSelect: String
    /// The same call to action for a screen reader. Carries a `{name}` slot.
    public var packSelectNamed: String
    /// The multi-select Continue, for any count but one. Carries a `{count}` slot.
    public var continueWithPacks: String
    /// The multi-select Continue when exactly one pack is ticked.
    public var continueWithOnePack: String

    // MARK: - Signup view

    /// Said while the app's registration settings and catalog are still being read.
    public var loadingSignup: String
    /// Said when the app is not accepting registrations at all.
    public var registrationClosed: String
    /// Submits the registration form.
    public var createAccount: String
    /// Advances a step.
    public var continueLabel: String
    /// Returns to the previous step.
    public var back: String
    /// Abandons the flow.
    public var cancel: String
    /// Skips an optional step (the pack step, typically).
    public var skipForNow: String
    /// Opens the optional registration-token entry.
    public var haveToken: String
    /// Field label for the registration token.
    public var tokenLabel: String
    /// Field label for the email address.
    public var emailLabel: String
    /// Step heading: pick a plan.
    public var choosePlan: String
    /// Step heading: pick packs.
    public var choosePacks: String
    /// Step heading: confirm what is about to be bought.
    public var reviewSelection: String
    /// Said once the account exists and everything asked for has been granted.
    public var signupComplete: String
    /// Said when a signed-in visitor lands on the signup view.
    public var alreadySignedIn: String

    /// Shown on a free plan in the plan summary card, where a price would otherwise be.
    public var planFree: String
    /// Heading over the plan and packs a registration token sets up.
    public var tokenPlanIncludes: String
    /// Sub-heading over the token's packs.
    public var tokenPlanPacks: String
    /// Sub-heading over the token's extra features.
    public var tokenPlanFeatures: String
    /// Said while the registration token is being checked.
    public var checkingToken: String

    /// Heading over what is about to be charged.
    public var orderSummary: String
    /// Labels the amount charged today (zero while a trial runs).
    public var dueToday: String
    /// The card already on file. Carries `{brand}` and `{last4}` slots the server's quote fills.
    public var savedCardOnFile: String
    /// Field label over the card entry.
    public var cardDetails: String
    /// Saves the card and continues the purchase.
    public var saveCard: String
    /// Said while the packs are being bought.
    public var buyingPacks: String
    /// Said while one pack's card is being authenticated with the bank. Carries a `{name}` slot.
    public var authenticatingPack: String
    /// Said when a pack purchase was refused and no message came back.
    public var packsUnavailable: String

    /// Pack outcome: the pack's trial has started.
    public var packStatusTrialing: String
    /// Pack outcome: the pack is running and paid for.
    public var packStatusActive: String
    /// Pack outcome: the pack could not be bought.
    public var packStatusFailed: String
    /// Pack outcome: the registration token included the pack.
    public var packStatusGranted: String

    /// Heading over the disclaimers step.
    public var disclaimersTitle: String
    /// Sentence under that heading.
    public var disclaimersIntro: String

    /// Status while the account is being registered.
    public var statusCreatingAccount: String
    /// Status while the new account is being signed in.
    public var statusSigningIn: String
    /// Status while the plan is being activated.
    public var statusActivatingPlan: String
    /// Reassurance under the processing status.
    public var processingWait: String
    /// Heading of the failed-signup panel.
    public var signupFailed: String
    /// Resumes a failed signup where it stopped.
    public var tryAgain: String
    /// Throws the attempt away and returns to the form.
    public var startOver: String

    /// Heading of the success panel.
    public var signupCompleteTitle: String
    /// Success copy when a registration token set the account up. Carries a `{tier}` slot.
    public var signupCompleteToken: String
    /// Success copy when the plan started a trial. Carries a `{days}` slot.
    public var signupCompleteTrial: String
    /// Success copy when no plan was chosen.
    public var signupCompletePlain: String
    /// Success copy when the plan is running.
    public var signupCompleteActive: String
    /// Success copy when the account exists but the plan could not be activated.
    public var signupCompletePending: String
    /// Leaves the finished signup.
    public var getStarted: String

    // MARK: - Manage view

    /// Names the plan the user is on.
    public var currentPlan: String
    /// Starts a plan change. Also the signup plan card's way back to the grid.
    public var changePlan: String
    /// Starts a cancellation.
    public var cancelPlan: String
    /// Backs out of a cancellation.
    public var keepPlan: String
    /// Section/tab: the subscription itself.
    public var sectionStatus: String
    /// Section/tab: the plans on offer.
    public var sectionPlans: String
    /// Section/tab: the packs on offer.
    public var sectionPacks: String
    /// Section/tab: usage against the plan's limits.
    public var sectionUsage: String
    /// Section/tab: the features the plan grants.
    public var sectionFeatures: String
    /// Section/tab: per-user feature overrides (admins only).
    public var sectionOverrides: String

    /// Title of the built-in card sheet. Carries a `{tier}` slot.
    public var upgradeToPlan: String
    /// What closing that sheet is called.
    public var closePayment: String
    /// Said while the prorated charge is being confirmed with the bank.
    public var authenticatingChange: String
    /// Said while the server finishes applying a paid-for change.
    public var applyingChange: String
    /// Heading over a failed plan change.
    public var planChangeFailed: String
    /// The parked change's payment window closed before it was finished.
    public var planChangeExpired: String
    /// The prorated charge was refused.
    public var planChangePaymentFailed: String
    /// Another change replaced the one being finished.
    public var planChangeSuperseded: String
    /// The parked change is no longer on the server.
    public var planChangeNotFound: String
    /// A change is already under way on this subscription.
    public var planChangeInProgress: String
    /// Said when a payment went through but carried no id to complete the change with.
    public var paymentUnconfirmed: String
    /// Opens the pack picker from the packs panel.
    public var addPacks: String
    /// Heading of the pack picker.
    public var addPacksTitle: String
    /// Badge on a pack nothing bills: a registration token's, or an admin grant.
    public var packIncluded: String
    /// Confirmation copy before cancelling a pack nothing bills.
    public var packCancelIncluded: String
    /// Confirmation copy before cancelling a pack that is billed.
    public var packCancelBilled: String
    /// Confirms a pack cancellation.
    public var packCancelConfirm: String
    /// Backs out of a pack cancellation.
    public var packCancelKeep: String
    /// Takes back a scheduled pack cancellation.
    public var packReactivate: String
    /// Marks a feature an override grants outside the plan.
    public var featureIncluded: String
    /// Said in place of the preview's proration figures when a device store owns the billing.
    ///
    /// A store subscription is not prorated the way the server's own preview describes: the store
    /// decides what is charged and when. Quoting a net charge today at somebody the App Store will
    /// bill on its own terms states a number nobody here can honour, so the store is named instead.
    public var storeManagesBilling: String

    // MARK: - Shared

    /// Said when a purchase needs a card challenge nothing on this device can answer — this
    /// package ships no payment SDK, so a 3-D Secure prompt has nowhere to run. Never a silent
    /// failure: the customer is told where to finish it instead.
    public var finishOnWeb: String
    /// Said by a view that has not shipped yet.
    public var viewNotAvailable: String

    public init(
        billingMonthly: String = "Monthly",
        billingAnnual: String = "Annual",
        billingToggleAriaLabel: String = "Toggle annual billing",
        annualSavings: String = "Save up to {percent}%",
        loadingPlans: String = "Loading plans...",
        pricingUnavailable: String = "Pricing is unavailable right now",
        retry: String = "Retry",
        contactUs: String = "Contact us",
        morePacks: String = "More packs",
        packUnavailable: String = "Not yet available",
        packSelect: String = "Select",
        packSelectNamed: String = "Select {name}",
        continueWithPacks: String = "Continue with {count} packs",
        continueWithOnePack: String = "Continue with 1 pack",
        loadingSignup: String = "Getting things ready...",
        registrationClosed: String = "Registration is closed",
        createAccount: String = "Create account",
        continueLabel: String = "Continue",
        back: String = "Back",
        cancel: String = "Cancel",
        skipForNow: String = "Skip for now",
        haveToken: String = "Have a registration token?",
        tokenLabel: String = "Registration token",
        emailLabel: String = "Email",
        choosePlan: String = "Choose a plan",
        choosePacks: String = "Choose your packs",
        reviewSelection: String = "Review your selection",
        signupComplete: String = "You are all set",
        alreadySignedIn: String = "You are already signed in",
        planFree: String = "Free",
        tokenPlanIncludes: String = "Your registration token includes",
        tokenPlanPacks: String = "Packs",
        tokenPlanFeatures: String = "Features",
        checkingToken: String = "Checking your registration token...",
        orderSummary: String = "Order Summary",
        dueToday: String = "Due today",
        savedCardOnFile: String = "{brand} ending in {last4}",
        cardDetails: String = "Card Details",
        saveCard: String = "Save card and continue",
        buyingPacks: String = "Setting up your packs...",
        authenticatingPack: String = "Confirming {name} with your bank...",
        packsUnavailable: String = "Your packs could not be bought.",
        packStatusTrialing: String = "Trial started",
        packStatusActive: String = "Active",
        packStatusFailed: String = "Could not be added",
        packStatusGranted: String = "Included",
        disclaimersTitle: String = "One more step",
        disclaimersIntro: String = "Please review and accept the following before continuing.",
        statusCreatingAccount: String = "Creating your account...",
        statusSigningIn: String = "Signing you in...",
        statusActivatingPlan: String = "Activating your plan...",
        processingWait: String = "Please wait while we set up your account.",
        signupFailed: String = "Something Went Wrong",
        tryAgain: String = "Try Again",
        startOver: String = "Start Over",
        signupCompleteTitle: String = "You're All Set!",
        signupCompleteToken: String =
            "Your account has been created with the {tier} from your registration token.",
        signupCompleteTrial: String =
            "Your account has been created and your {days}-day free trial has started.",
        signupCompletePlain: String = "Your account has been created successfully.",
        signupCompleteActive: String = "Your account has been created and your plan is active.",
        signupCompletePending: String =
            "Your account is ready! Plan activation is pending - you can select a plan from your dashboard.",
        getStarted: String = "Get Started",
        currentPlan: String = "Current plan",
        changePlan: String = "Change plan",
        cancelPlan: String = "Cancel plan",
        keepPlan: String = "Keep plan",
        sectionStatus: String = "Subscription",
        sectionPlans: String = "Plans",
        sectionPacks: String = "Packs",
        sectionUsage: String = "Usage",
        sectionFeatures: String = "Features",
        sectionOverrides: String = "Overrides",
        upgradeToPlan: String = "Upgrade to {tier}",
        closePayment: String = "Cancel payment",
        authenticatingChange: String = "Confirming the charge with your bank...",
        applyingChange: String = "Applying your new plan...",
        planChangeFailed: String = "The plan change could not be completed",
        planChangeExpired: String = "The payment window closed - please start the change again",
        planChangePaymentFailed: String =
            "That payment was not completed, so your plan has not changed. Please try again.",
        planChangeSuperseded: String = "This plan was changed somewhere else. Refresh and try again.",
        planChangeNotFound: String = "That plan change is no longer available. Please start it again.",
        planChangeInProgress: String =
            "A change to this plan is already under way. Give it a moment and refresh.",
        paymentUnconfirmed: String =
            "Your payment went through but the plan change could not be confirmed automatically. Please contact support with your receipt.",
        addPacks: String = "Add packs",
        addPacksTitle: String = "Add packs to your plan",
        packIncluded: String = "Included with your registration",
        packCancelIncluded: String =
            "This pack was included with your registration. Cancelling removes it from your account.",
        packCancelBilled: String = "You keep access until the end of the current billing period.",
        packCancelConfirm: String = "Cancel pack",
        packCancelKeep: String = "Keep pack",
        packReactivate: String = "Reactivate",
        featureIncluded: String = "Included",
        storeManagesBilling: String = "Your app store manages billing for this change.",
        finishOnWeb: String = "This purchase has to be finished on the web.",
        viewNotAvailable: String = "This view is not available yet"
    ) {
        self.billingMonthly = billingMonthly
        self.billingAnnual = billingAnnual
        self.billingToggleAriaLabel = billingToggleAriaLabel
        self.annualSavings = annualSavings
        self.loadingPlans = loadingPlans
        self.pricingUnavailable = pricingUnavailable
        self.retry = retry
        self.contactUs = contactUs
        self.morePacks = morePacks
        self.packUnavailable = packUnavailable
        self.packSelect = packSelect
        self.packSelectNamed = packSelectNamed
        self.continueWithPacks = continueWithPacks
        self.continueWithOnePack = continueWithOnePack
        self.loadingSignup = loadingSignup
        self.registrationClosed = registrationClosed
        self.createAccount = createAccount
        self.continueLabel = continueLabel
        self.back = back
        self.cancel = cancel
        self.skipForNow = skipForNow
        self.haveToken = haveToken
        self.tokenLabel = tokenLabel
        self.emailLabel = emailLabel
        self.choosePlan = choosePlan
        self.choosePacks = choosePacks
        self.reviewSelection = reviewSelection
        self.signupComplete = signupComplete
        self.alreadySignedIn = alreadySignedIn
        self.planFree = planFree
        self.tokenPlanIncludes = tokenPlanIncludes
        self.tokenPlanPacks = tokenPlanPacks
        self.tokenPlanFeatures = tokenPlanFeatures
        self.checkingToken = checkingToken
        self.orderSummary = orderSummary
        self.dueToday = dueToday
        self.savedCardOnFile = savedCardOnFile
        self.cardDetails = cardDetails
        self.saveCard = saveCard
        self.buyingPacks = buyingPacks
        self.authenticatingPack = authenticatingPack
        self.packsUnavailable = packsUnavailable
        self.packStatusTrialing = packStatusTrialing
        self.packStatusActive = packStatusActive
        self.packStatusFailed = packStatusFailed
        self.packStatusGranted = packStatusGranted
        self.disclaimersTitle = disclaimersTitle
        self.disclaimersIntro = disclaimersIntro
        self.statusCreatingAccount = statusCreatingAccount
        self.statusSigningIn = statusSigningIn
        self.statusActivatingPlan = statusActivatingPlan
        self.processingWait = processingWait
        self.signupFailed = signupFailed
        self.tryAgain = tryAgain
        self.startOver = startOver
        self.signupCompleteTitle = signupCompleteTitle
        self.signupCompleteToken = signupCompleteToken
        self.signupCompleteTrial = signupCompleteTrial
        self.signupCompletePlain = signupCompletePlain
        self.signupCompleteActive = signupCompleteActive
        self.signupCompletePending = signupCompletePending
        self.getStarted = getStarted
        self.currentPlan = currentPlan
        self.changePlan = changePlan
        self.cancelPlan = cancelPlan
        self.keepPlan = keepPlan
        self.sectionStatus = sectionStatus
        self.sectionPlans = sectionPlans
        self.sectionPacks = sectionPacks
        self.sectionUsage = sectionUsage
        self.sectionFeatures = sectionFeatures
        self.sectionOverrides = sectionOverrides
        self.upgradeToPlan = upgradeToPlan
        self.closePayment = closePayment
        self.authenticatingChange = authenticatingChange
        self.applyingChange = applyingChange
        self.planChangeFailed = planChangeFailed
        self.planChangeExpired = planChangeExpired
        self.planChangePaymentFailed = planChangePaymentFailed
        self.planChangeSuperseded = planChangeSuperseded
        self.planChangeNotFound = planChangeNotFound
        self.planChangeInProgress = planChangeInProgress
        self.paymentUnconfirmed = paymentUnconfirmed
        self.addPacks = addPacks
        self.addPacksTitle = addPacksTitle
        self.packIncluded = packIncluded
        self.packCancelIncluded = packCancelIncluded
        self.packCancelBilled = packCancelBilled
        self.packCancelConfirm = packCancelConfirm
        self.packCancelKeep = packCancelKeep
        self.packReactivate = packReactivate
        self.featureIncluded = featureIncluded
        self.storeManagesBilling = storeManagesBilling
        self.finishOnWeb = finishOnWeb
        self.viewNotAvailable = viewNotAvailable
    }

    /// The JS defaults, unchanged.
    public static let defaults = RegistrationSubscriptionLabels()

    /// The copy the packs panel takes, mapped from this set. One place decides which label answers
    /// which row, so the panel and the pack picker beside it cannot disagree.
    public var addOnsPanelLabels: AddOnsPanelLabels {
        AddOnsPanelLabels(
            included: packIncluded,
            cancelIncluded: packCancelIncluded,
            cancelBilled: packCancelBilled,
            cancelConfirm: packCancelConfirm,
            cancelKeep: packCancelKeep,
            reactivate: packReactivate,
            addPacks: addPacks
        )
    }
}

/// The `{slot}` substitution JS calls `formatLabel`.
public enum RegistrationSubscriptionLabelFormat {
    /// Replace every `{key}` in `template` with its value. A slot with no value is left VERBATIM,
    /// exactly as the JS helper leaves it: a host that translated a label and dropped a slot sees
    /// the slot rather than a hole where a number should be.
    public static func format(_ template: String, values: [String: String]) -> String {
        var result: String = template
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{" + key + "}", with: value)
        }
        return result
    }
}
