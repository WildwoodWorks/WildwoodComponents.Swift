// The cross-stack copy contract, pinned key by key.
//
// Every default in ``RegistrationSubscriptionLabels`` is asserted against a literal transcribed
// from packages/wildwood-react-shared/src/registrationSubscription/labels.ts (Appendix A C.2).
// This is the one test in the suite that is deliberately a table of strings: the labels ARE the
// contract, three stacks ship them, and a word changed in one of them has to fail here rather
// than in somebody's screenshot.
//
// A key added to the JS set and not here is caught by the count assertion at the end.

import Foundation
import Testing
@testable import WildwoodSwiftUI

@MainActor
struct RegistrationSubscriptionLabelsTests {
    /// Key to default string, transcribed from `DEFAULT_LABELS` in labels.ts.
    private static let table: [(String, String)] = [
        // Pricing
        ("billingMonthly", "Monthly"),
        ("billingAnnual", "Annual"),
        ("billingToggleAriaLabel", "Toggle annual billing"),
        ("annualSavings", "Save up to {percent}%"),
        ("loadingPlans", "Loading plans..."),
        ("pricingUnavailable", "Pricing is unavailable right now"),
        ("retry", "Retry"),
        ("contactUs", "Contact us"),
        ("morePacks", "More packs"),
        ("packUnavailable", "Not yet available"),
        ("packSelect", "Select"),
        ("packSelectNamed", "Select {name}"),
        ("continueWithPacks", "Continue with {count} packs"),
        ("continueWithOnePack", "Continue with 1 pack"),
        // Signup
        ("loadingSignup", "Getting things ready..."),
        ("registrationClosed", "Registration is closed"),
        ("createAccount", "Create account"),
        ("continueLabel", "Continue"),
        ("back", "Back"),
        ("cancel", "Cancel"),
        ("skipForNow", "Skip for now"),
        ("haveToken", "Have a registration token?"),
        ("tokenLabel", "Registration token"),
        ("emailLabel", "Email"),
        ("choosePlan", "Choose a plan"),
        ("choosePacks", "Choose your packs"),
        ("reviewSelection", "Review your selection"),
        ("signupComplete", "You are all set"),
        ("alreadySignedIn", "You are already signed in"),
        ("planFree", "Free"),
        ("tokenPlanIncludes", "Your registration token includes"),
        ("tokenPlanPacks", "Packs"),
        ("tokenPlanFeatures", "Features"),
        ("checkingToken", "Checking your registration token..."),
        ("orderSummary", "Order Summary"),
        ("dueToday", "Due today"),
        ("savedCardOnFile", "{brand} ending in {last4}"),
        ("cardDetails", "Card Details"),
        ("saveCard", "Save card and continue"),
        ("buyingPacks", "Setting up your packs..."),
        ("authenticatingPack", "Confirming {name} with your bank..."),
        ("packsUnavailable", "Your packs could not be bought."),
        ("packStatusTrialing", "Trial started"),
        ("packStatusActive", "Active"),
        ("packStatusFailed", "Could not be added"),
        ("packStatusGranted", "Included"),
        ("disclaimersTitle", "One more step"),
        ("disclaimersIntro", "Please review and accept the following before continuing."),
        ("statusCreatingAccount", "Creating your account..."),
        ("statusSigningIn", "Signing you in..."),
        ("statusActivatingPlan", "Activating your plan..."),
        ("processingWait", "Please wait while we set up your account."),
        ("signupFailed", "Something Went Wrong"),
        ("tryAgain", "Try Again"),
        ("startOver", "Start Over"),
        ("signupCompleteTitle", "You're All Set!"),
        (
            "signupCompleteToken",
            "Your account has been created with the {tier} from your registration token."
        ),
        (
            "signupCompleteTrial",
            "Your account has been created and your {days}-day free trial has started."
        ),
        ("signupCompletePlain", "Your account has been created successfully."),
        ("signupCompleteActive", "Your account has been created and your plan is active."),
        (
            "signupCompletePending",
            "Your account is ready! Plan activation is pending - you can select a plan from your dashboard."
        ),
        ("getStarted", "Get Started"),
        // Manage
        ("currentPlan", "Current plan"),
        ("changePlan", "Change plan"),
        ("cancelPlan", "Cancel plan"),
        ("keepPlan", "Keep plan"),
        ("sectionStatus", "Subscription"),
        ("sectionPlans", "Plans"),
        ("sectionPacks", "Packs"),
        ("sectionUsage", "Usage"),
        ("sectionFeatures", "Features"),
        ("sectionOverrides", "Overrides"),
        ("upgradeToPlan", "Upgrade to {tier}"),
        ("closePayment", "Cancel payment"),
        ("authenticatingChange", "Confirming the charge with your bank..."),
        ("applyingChange", "Applying your new plan..."),
        ("planChangeFailed", "The plan change could not be completed"),
        ("planChangeExpired", "The payment window closed - please start the change again"),
        (
            "planChangePaymentFailed",
            "That payment was not completed, so your plan has not changed. Please try again."
        ),
        ("planChangeSuperseded", "This plan was changed somewhere else. Refresh and try again."),
        ("planChangeNotFound", "That plan change is no longer available. Please start it again."),
        (
            "planChangeInProgress",
            "A change to this plan is already under way. Give it a moment and refresh."
        ),
        (
            "paymentUnconfirmed",
            "Your payment went through but the plan change could not be confirmed automatically. Please contact support with your receipt."
        ),
        ("addPacks", "Add packs"),
        ("addPacksTitle", "Add packs to your plan"),
        ("packIncluded", "Included with your registration"),
        (
            "packCancelIncluded",
            "This pack was included with your registration. Cancelling removes it from your account."
        ),
        ("packCancelBilled", "You keep access until the end of the current billing period."),
        ("packCancelConfirm", "Cancel pack"),
        ("packCancelKeep", "Keep pack"),
        ("packReactivate", "Reactivate"),
        ("featureIncluded", "Included"),
        ("storeManagesBilling", "Your app store manages billing for this change."),
        // Shared
        ("finishOnWeb", "This purchase has to be finished on the web."),
        ("viewNotAvailable", "This view is not available yet"),
    ]

    /// The defaults, read by the same key names the table uses. A mismatch names the key.
    private static func value(_ key: String, _ labels: RegistrationSubscriptionLabels) -> String? {
        switch key {
        case "billingMonthly": return labels.billingMonthly
        case "billingAnnual": return labels.billingAnnual
        case "billingToggleAriaLabel": return labels.billingToggleAriaLabel
        case "annualSavings": return labels.annualSavings
        case "loadingPlans": return labels.loadingPlans
        case "pricingUnavailable": return labels.pricingUnavailable
        case "retry": return labels.retry
        case "contactUs": return labels.contactUs
        case "morePacks": return labels.morePacks
        case "packUnavailable": return labels.packUnavailable
        case "packSelect": return labels.packSelect
        case "packSelectNamed": return labels.packSelectNamed
        case "continueWithPacks": return labels.continueWithPacks
        case "continueWithOnePack": return labels.continueWithOnePack
        case "loadingSignup": return labels.loadingSignup
        case "registrationClosed": return labels.registrationClosed
        case "createAccount": return labels.createAccount
        case "continueLabel": return labels.continueLabel
        case "back": return labels.back
        case "cancel": return labels.cancel
        case "skipForNow": return labels.skipForNow
        case "haveToken": return labels.haveToken
        case "tokenLabel": return labels.tokenLabel
        case "emailLabel": return labels.emailLabel
        case "choosePlan": return labels.choosePlan
        case "choosePacks": return labels.choosePacks
        case "reviewSelection": return labels.reviewSelection
        case "signupComplete": return labels.signupComplete
        case "alreadySignedIn": return labels.alreadySignedIn
        case "planFree": return labels.planFree
        case "tokenPlanIncludes": return labels.tokenPlanIncludes
        case "tokenPlanPacks": return labels.tokenPlanPacks
        case "tokenPlanFeatures": return labels.tokenPlanFeatures
        case "checkingToken": return labels.checkingToken
        case "orderSummary": return labels.orderSummary
        case "dueToday": return labels.dueToday
        case "savedCardOnFile": return labels.savedCardOnFile
        case "cardDetails": return labels.cardDetails
        case "saveCard": return labels.saveCard
        case "buyingPacks": return labels.buyingPacks
        case "authenticatingPack": return labels.authenticatingPack
        case "packsUnavailable": return labels.packsUnavailable
        case "packStatusTrialing": return labels.packStatusTrialing
        case "packStatusActive": return labels.packStatusActive
        case "packStatusFailed": return labels.packStatusFailed
        case "packStatusGranted": return labels.packStatusGranted
        case "disclaimersTitle": return labels.disclaimersTitle
        case "disclaimersIntro": return labels.disclaimersIntro
        case "statusCreatingAccount": return labels.statusCreatingAccount
        case "statusSigningIn": return labels.statusSigningIn
        case "statusActivatingPlan": return labels.statusActivatingPlan
        case "processingWait": return labels.processingWait
        case "signupFailed": return labels.signupFailed
        case "tryAgain": return labels.tryAgain
        case "startOver": return labels.startOver
        case "signupCompleteTitle": return labels.signupCompleteTitle
        case "signupCompleteToken": return labels.signupCompleteToken
        case "signupCompleteTrial": return labels.signupCompleteTrial
        case "signupCompletePlain": return labels.signupCompletePlain
        case "signupCompleteActive": return labels.signupCompleteActive
        case "signupCompletePending": return labels.signupCompletePending
        case "getStarted": return labels.getStarted
        case "currentPlan": return labels.currentPlan
        case "changePlan": return labels.changePlan
        case "cancelPlan": return labels.cancelPlan
        case "keepPlan": return labels.keepPlan
        case "sectionStatus": return labels.sectionStatus
        case "sectionPlans": return labels.sectionPlans
        case "sectionPacks": return labels.sectionPacks
        case "sectionUsage": return labels.sectionUsage
        case "sectionFeatures": return labels.sectionFeatures
        case "sectionOverrides": return labels.sectionOverrides
        case "upgradeToPlan": return labels.upgradeToPlan
        case "closePayment": return labels.closePayment
        case "authenticatingChange": return labels.authenticatingChange
        case "applyingChange": return labels.applyingChange
        case "planChangeFailed": return labels.planChangeFailed
        case "planChangeExpired": return labels.planChangeExpired
        case "planChangePaymentFailed": return labels.planChangePaymentFailed
        case "planChangeSuperseded": return labels.planChangeSuperseded
        case "planChangeNotFound": return labels.planChangeNotFound
        case "planChangeInProgress": return labels.planChangeInProgress
        case "paymentUnconfirmed": return labels.paymentUnconfirmed
        case "addPacks": return labels.addPacks
        case "addPacksTitle": return labels.addPacksTitle
        case "packIncluded": return labels.packIncluded
        case "packCancelIncluded": return labels.packCancelIncluded
        case "packCancelBilled": return labels.packCancelBilled
        case "packCancelConfirm": return labels.packCancelConfirm
        case "packCancelKeep": return labels.packCancelKeep
        case "packReactivate": return labels.packReactivate
        case "featureIncluded": return labels.featureIncluded
        case "storeManagesBilling": return labels.storeManagesBilling
        case "finishOnWeb": return labels.finishOnWeb
        case "viewNotAvailable": return labels.viewNotAvailable
        default: return nil
        }
    }

    @Test func everyDefaultIsTheStringTheOtherStacksShip() {
        let labels = RegistrationSubscriptionLabels.defaults
        for (key, expected) in Self.table {
            let actual: String? = Self.value(key, labels)
            #expect(actual != nil, "no member reads the label key \(key)")
            #expect(actual == expected, "label \(key) drifted from the JS default")
        }
    }

    /// The JS set has 95 keys. A key added there and not here would otherwise pass unnoticed,
    /// because a table only checks what it lists.
    @Test func theTableCoversEveryKeyInTheJsSet() {
        #expect(Self.table.count == 95)
    }

    // MARK: - The merge

    @Test func thePerViewSlicesAreTheSameTypeAndTheSameDefaults() {
        // The three names the views and drivers use all resolve to one struct, so a host's
        // override reaches every surface that reads that key.
        let pricing: RegistrationSubscriptionPricingLabels = .defaults
        let signup: RegistrationSubscriptionSignupLabels = .defaults
        let driver: RegistrationSubscriptionDriverLabels = .defaults

        #expect(pricing == RegistrationSubscriptionLabels.defaults)
        #expect(signup == RegistrationSubscriptionLabels.defaults)
        #expect(driver == RegistrationSubscriptionLabels.defaults)
    }

    @Test func aHostOverrideReachesTheDriversWholeSet() {
        let overridden = RegistrationSubscriptionLabels(
            packsUnavailable: "No packs for you.",
            planChangeExpired: "That window shut.",
            finishOnWeb: "Finish it on the site."
        )
        let driver: RegistrationSubscriptionDriverLabels = overridden.driverLabels

        #expect(driver.packsUnavailable == "No packs for you.")
        #expect(driver.finishOnWeb == "Finish it on the site.")
        // The merge is what makes THIS true: the plan-change sentences used to stay at their
        // defaults, because the old mapping could only carry six members across.
        #expect(driver.planChangeExpired == "That window shut.")
        #expect(driver.retry == RegistrationSubscriptionLabels.defaults.retry)
    }

    // MARK: - The formatter

    @Test func aSlotIsFilledAndAnUnmatchedOneIsLeftVerbatim() {
        let labels = RegistrationSubscriptionLabels.defaults
        #expect(
            RegistrationSubscriptionLabelFormat.format(labels.upgradeToPlan, values: ["tier": "Pro"])
                == "Upgrade to Pro"
        )
        #expect(
            RegistrationSubscriptionLabelFormat.format(labels.upgradeToPlan, values: [:])
                == "Upgrade to {tier}"
        )
        #expect(
            RegistrationSubscriptionLabelFormat.format(
                labels.savedCardOnFile,
                values: ["brand": "Visa", "last4": "4242"]
            ) == "Visa ending in 4242"
        )
    }
}
