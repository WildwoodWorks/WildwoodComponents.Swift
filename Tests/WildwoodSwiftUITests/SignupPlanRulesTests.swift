// SignupPlanRules — the signup wizard's plan decisions.
//
// The load-bearing test here is `aTokenGrantIsNeverSubscribedOver`: registering with a token that
// carries a plan ALREADY subscribed the account to it, and a self-subscribe on top REPLACES that
// subscription, cancelling the plan the token just set up. The assertion is made against the
// stubbed backend's recorded requests, so it pins the absence of the HTTP call itself rather than
// the absence of a flag.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct SignupPlanRulesTests {
    private static let subscribePath = "/api/app-tiers/app-1/my-subscription"

    private func makeClient(_ backend: TestBackend) -> WildwoodClient {
        WildwoodClient(
            config: WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false, storage: .memory),
            urlSession: backend.makeSession()
        )
    }

    private func subscribeCalls(_ backend: TestBackend) -> Int {
        backend.requests().filter { $0.method == "POST" && $0.path == Self.subscribePath }.count
    }

    /// Runs the activation against a real (stubbed) client, the way the component does.
    private func activate(
        client: WildwoodClient,
        tierId: String?,
        tokenGrant: RegistrationTokenAppGrant?
    ) async -> SignupPlanActivation {
        await SignupPlanRules.activatePlan(
            tierId: tierId,
            pricingId: "pricing-1",
            tokenGrant: tokenGrant,
            paymentTransactionId: nil,
            selfSubscribe: { tier, pricing, transaction in
                try await client.appTier.selfSubscribe(
                    appId: "app-1",
                    appTierId: tier,
                    appTierPricingId: pricing,
                    paymentTransactionId: transaction
                )
            }
        )
    }

    // MARK: - The grant skip

    @Test func aTokenGrantIsNeverSubscribedOver() async {
        let backend = TestBackend()
        backend.stub("POST", Self.subscribePath, .init(json: #"{"success":true}"#))
        let client = makeClient(backend)
        let grant = RegistrationTokenAppGrant(appId: "app-1", appTierName: "Pro")

        let activation = await activate(client: client, tierId: "tier-1", tokenGrant: grant)

        #expect(activation.attempted == false)
        #expect(activation.failed == false)
        #expect(subscribeCalls(backend) == 0)
    }

    @Test func withoutAGrantThePlanIsActivated() async {
        let backend = TestBackend()
        backend.stub("POST", Self.subscribePath, .init(json: #"{"success":true}"#))
        let client = makeClient(backend)

        let activation = await activate(client: client, tierId: "tier-1", tokenGrant: nil)

        #expect(activation.attempted)
        #expect(activation.failed == false)
        #expect(activation.result?.success == true)
        #expect(subscribeCalls(backend) == 1)
    }

    @Test func noTierMeansNothingToActivate() async {
        let backend = TestBackend()
        backend.stub("POST", Self.subscribePath, .init(json: #"{"success":true}"#))
        let client = makeClient(backend)

        let activation = await activate(client: client, tierId: nil, tokenGrant: nil)

        #expect(activation.attempted == false)
        #expect(subscribeCalls(backend) == 0)
    }

    // MARK: - Non-fatal refusals

    @Test func aRefusedSubscribeIsNonFatalAndKeepsTheServersReason() async {
        let backend = TestBackend()
        backend.stub(
            "POST",
            Self.subscribePath,
            .init(statusCode: 400, json: #"{"errorMessage":"That plan is closed to new signups."}"#)
        )
        let client = makeClient(backend)

        let activation = await activate(client: client, tierId: "tier-1", tokenGrant: nil)

        #expect(activation.attempted)
        #expect(activation.failed)
        #expect(activation.errorMessage == "That plan is closed to new signups.")
        #expect(SignupPlanRules.activationWarning(activation).contains("That plan is closed to new signups."))
    }

    @Test func aSuccessFalseBodyIsAlsoARefusal() async {
        let backend = TestBackend()
        backend.stub(
            "POST",
            Self.subscribePath,
            .init(json: #"{"success":false,"errorMessage":"No payment on file."}"#)
        )
        let client = makeClient(backend)

        let activation = await activate(client: client, tierId: "tier-1", tokenGrant: nil)

        #expect(activation.failed)
        #expect(activation.errorMessage == "No payment on file.")
    }

    @Test func theWarningIsNeverEmptyEvenWithoutAReason() {
        let warning = SignupPlanRules.activationWarning(SignupPlanActivation(attempted: true, failed: true))
        #expect(warning == "Your account is ready! Plan activation is pending \u{2014} you can select a plan from your dashboard.")
    }

    // MARK: - Finding the grant

    @Test func theGrantIsMatchedCaseInsensitivelyOnAppId() {
        let details = RegistrationTokenDetails(
            isValid: true,
            appGrants: [RegistrationTokenAppGrant(appId: "APP-1", appTierName: "Pro")]
        )
        #expect(SignupPlanRules.findTokenPlanGrant(details, appId: "app-1")?.appTierName == "Pro")
        #expect(SignupPlanRules.findTokenPlanGrant(details, appId: "app-2") == nil)
        #expect(SignupPlanRules.findTokenPlanGrant(details, appId: "") == nil)
    }

    @Test func unreadableDetailsAreNotAGrant() {
        // nil = the details could not be READ, which is not an invalid token: the wizard falls
        // back to its normal flow rather than honouring a grant it never saw.
        #expect(SignupPlanRules.findTokenPlanGrant(nil, appId: "app-1") == nil)
        #expect(SignupPlanRules.findTokenPlanGrant(RegistrationTokenDetails(isValid: true), appId: "app-1") == nil)
    }

    @Test func aGrantForAnotherAppIsIgnored() {
        let details = RegistrationTokenDetails(
            isValid: true,
            appGrants: [RegistrationTokenAppGrant(appId: "other-app", appTierName: "Pro")]
        )
        #expect(SignupPlanRules.findTokenPlanGrant(details, appId: "app-1") == nil)
    }

    // MARK: - Success copy

    @Test func successCopyNamesTheGrantedPlan() {
        let grant = RegistrationTokenAppGrant(appId: "app-1", appTierName: "Pro")
        #expect(
            SignupPlanRules.successMessage(tokenGrant: grant, accountOnly: false, subscriptionFailed: false)
                == "Your account has been created with the Pro from your registration token."
        )
        let unnamed = RegistrationTokenAppGrant(appId: "app-1")
        #expect(
            SignupPlanRules.successMessage(tokenGrant: unnamed, accountOnly: false, subscriptionFailed: false)
                == "Your account has been created with the plan from your registration token."
        )
    }

    @Test func successCopyCoversTheOtherThreeOutcomes() {
        #expect(
            SignupPlanRules.successMessage(tokenGrant: nil, accountOnly: true, subscriptionFailed: false)
                == "Your account has been created successfully."
        )
        #expect(
            SignupPlanRules.successMessage(tokenGrant: nil, accountOnly: false, subscriptionFailed: true)
                == "Your account is ready! Plan activation is pending \u{2014} you can select a plan from your dashboard."
        )
        #expect(
            SignupPlanRules.successMessage(tokenGrant: nil, accountOnly: false, subscriptionFailed: false, trialDays: 14)
                == "Your account has been created and your 14-day free trial has started."
        )
        #expect(
            SignupPlanRules.successMessage(tokenGrant: nil, accountOnly: false, subscriptionFailed: false)
                == "Your account has been created and your plan is active."
        )
    }
}
