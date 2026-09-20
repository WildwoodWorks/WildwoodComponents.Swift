// The copy the signup view and the pack checkout say.
//
// Values are the JS defaults byte for byte
// (packages/wildwood-react-shared/src/registrationSubscription/labels.ts, Appendix A C.2), so the
// stacks say the same words. Only the SIGNUP and PACK-CHECKOUT keys are here: the full overridable
// set — `RegistrationSubscriptionLabels`, covering pricing and manage as well — arrives with the
// manage view, and this struct is the signup slice of it, exactly as
// ``RegistrationSubscriptionPricingLabels`` is the pricing slice. Every view reads members BY NAME
// and never writes a sentence of its own, so the full type can take this one's place without
// touching a call site.
//
// Two keys sit here that the label file files elsewhere, and both are deliberate:
//
//  · `changePlan` is a manage-view key in JS, but the signup's plan summary card is the other place
//    that says it. It is the same sentence in both, so it is carried once and the merge drops the
//    duplicate.
//  · `finishOnWeb` is a shared key. It is the one thing this stack says that the web never has to:
//    a card challenge needs a payment SDK the package does not ship.
//
// What is NOT here, on purpose: the register form's submit text when the form is the last thing
// before an account exists. The web hard-codes "Create Account" there — capital A, unlike the
// `createAccount` label — and the live sites' locators depend on it, so
// ``SignupViewRules/createAccountSubmitText`` carries it verbatim instead of pretending it is
// overridable.

import Foundation

/// The signup view's overridable copy. Every member defaults to the JS default string, so a host
/// overrides one by naming one: `RegistrationSubscriptionSignupLabels(tryAgain: "Retry")`.
public struct RegistrationSubscriptionSignupLabels: Sendable, Equatable {
    // MARK: Frame

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

    // MARK: The plan being carried

    /// Shown on a free plan in the plan summary card, where a price would otherwise be.
    public var planFree: String
    /// Returns to the plan grid from the summary card. Shared with the manage view.
    public var changePlan: String
    /// Heading over the plan and packs a registration token sets up.
    public var tokenPlanIncludes: String
    /// Sub-heading over the token's packs.
    public var tokenPlanPacks: String
    /// Sub-heading over the token's extra features.
    public var tokenPlanFeatures: String
    /// Said while the registration token is being checked.
    public var checkingToken: String

    // MARK: Money

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

    // MARK: Pack outcomes

    /// The pack's trial has started.
    public var packStatusTrialing: String
    /// The pack is running and paid for.
    public var packStatusActive: String
    /// The pack could not be bought.
    public var packStatusFailed: String
    /// The registration token included the pack.
    public var packStatusGranted: String

    // MARK: Disclaimers

    /// Heading over the disclaimers step.
    public var disclaimersTitle: String
    /// Sentence under that heading.
    public var disclaimersIntro: String

    // MARK: Creating the account

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

    // MARK: Success

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

    // MARK: Shared

    /// Said when a purchase needs a card challenge nothing on this device can answer.
    public var finishOnWeb: String

    public init(
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
        changePlan: String = "Change plan",
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
        finishOnWeb: String = "This purchase has to be finished on the web."
    ) {
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
        self.changePlan = changePlan
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
        self.finishOnWeb = finishOnWeb
    }

    /// The JS defaults, unchanged.
    public static let defaults = RegistrationSubscriptionSignupLabels()
}

extension RegistrationSubscriptionSignupLabels {
    /// The subset a DRIVER stores in its state or puts in an `onError` message.
    ///
    /// The drivers were written before any view existed, so they carry their own small copy type;
    /// this hands the host's overrides down to it, member for member, so a host that renamed
    /// "Your packs could not be bought." sees its own words in a driver-produced message too. Only
    /// the six members the signup and pack-checkout drivers actually say are mapped — the plan
    /// change's five belong to the manage view's slice.
    var driverLabels: RegistrationSubscriptionDriverLabels {
        var resolved: RegistrationSubscriptionDriverLabels = .defaults
        resolved.finishOnWeb = finishOnWeb
        resolved.packsUnavailable = packsUnavailable
        resolved.signupCompletePending = signupCompletePending
        resolved.statusCreatingAccount = statusCreatingAccount
        resolved.statusSigningIn = statusSigningIn
        resolved.statusActivatingPlan = statusActivatingPlan
        return resolved
    }
}
