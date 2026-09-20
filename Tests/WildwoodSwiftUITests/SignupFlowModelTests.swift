// WildwoodSignupFlowModel: the driver half of the signup.
//
// What these pin is the native ORDER and the rules that make it safe: the account is created
// BEFORE the card is taken (so a purchase can never strand a paid plan with no account), a
// registration token's plan is never subscribed over, an abandoned card still finishes the signup
// with the plan's activation pending, and "Try Again" resumes rather than registering the same
// person twice.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct SignupFlowModelTests {
    private static let appId = "app-1"

    private var authConfigPath: String { "/api/AppComponentConfigurations/\(Self.appId)/auth-configuration" }
    private var publicTiersPath: String { "/api/app-tiers/\(Self.appId)/public" }
    private var publicAddOnsPath: String { "/api/app-tier-addons/\(Self.appId)/public" }
    private var registerPath: String { "/api/userregistration/register" }
    private var loginPath: String { "/api/auth/login" }
    private var subscribePath: String { "/api/app-tiers/\(Self.appId)/my-subscription" }
    private var tokenDetailsPath: String { "/api/registrationtokens/validate-detailed/tok-1" }

    private func stubCatalog(_ backend: TestBackend, paid: Bool = true) {
        let price: String = paid ? "20" : "0"
        backend.stub(
            "GET",
            publicTiersPath,
            TestStubResponse(
                json: """
                [{"id":"tier-pro","appId":"\(Self.appId)","name":"Pro","status":"Active","displayOrder":1,
                  "isFreeTier":\(paid ? "false" : "true"),"currency":"USD",
                  "pricingOptions":[{"id":"p-1","appTierId":"tier-pro","price":\(price),
                    "billingFrequency":"Monthly","pricingModelId":"pm-1","isDefault":true}]}]
                """
            )
        )
        backend.stub("GET", publicAddOnsPath, TestStubResponse(json: "[]"))
    }

    private func stubOpenRegistration(_ backend: TestBackend) {
        backend.stub(
            "GET",
            authConfigPath,
            TestStubResponse(json: #"{"allowOpenRegistration":true,"allowTokenRegistration":true}"#)
        )
    }

    private func stubRegisterAndLogin(_ backend: TestBackend) {
        backend.stub(
            "POST",
            registerPath,
            TestStubResponse(json: #"{"success":true,"message":"ok","userId":"user-1"}"#)
        )
        backend.stub(
            "POST",
            loginPath,
            TestStubResponse(
                json: """
                {"id":"user-1","userId":"user-1","email":"a@b.test","jwtToken":"jwt-1",
                 "requiresDisclaimerAcceptance":false}
                """
            )
        )
    }

    private func form(useToken: Bool = false, token: String? = nil) -> RegistrationFormData {
        RegistrationFormData(
            firstName: "Ada",
            lastName: "Lovelace",
            username: "ada",
            email: "a@b.test",
            password: "Sekrit!1",
            registrationToken: token,
            useToken: useToken
        )
    }

    private func makeModel(
        _ backend: TestBackend,
        options: WildwoodSignupFlowOptions = WildwoodSignupFlowOptions(preSelectedTierId: "tier-pro")
    ) -> WildwoodSignupFlowModel {
        WildwoodSignupFlowModel(
            client: makeTestClient(backend, appId: Self.appId),
            options: options,
            paymentActionHandler: nil,
            issuer: StepTokenIssuer()
        )
    }

    // MARK: - Ordering

    @Test func theAccountIsCreatedBeforeTheCardIsTaken() async {
        let backend = TestBackend()
        stubOpenRegistration(backend)
        stubCatalog(backend)
        stubRegisterAndLogin(backend)

        let model = makeModel(backend)
        #expect(model.state.options.paymentOrder == .afterAccount)

        model.start()
        await waitUntil { model.step == .register }
        model.submitForm(form())
        await waitUntil { model.step == .payment || model.step == .failed || model.step == .done }

        // The card step comes AFTER the account: the registration is already on the wire.
        #expect(model.step == .payment)
        #expect(model.paymentAfterAccount == true)
        #expect(requestCount(backend, path: registerPath) == 1)
        #expect(requestCount(backend, path: loginPath) == 1)
        // Nothing is subscribed until there is a transaction to subscribe with.
        #expect(requestCount(backend, path: subscribePath) == 0)
    }

    @Test func abandoningTheCardStillFinishesTheSignupWithThePlanPending() async {
        let backend = TestBackend()
        stubOpenRegistration(backend)
        stubCatalog(backend)
        stubRegisterAndLogin(backend)

        let model = makeModel(backend)
        model.start()
        await waitUntil { model.step == .register }
        model.submitForm(form())
        await waitUntil { model.step == .payment }

        model.paymentAbandoned()
        await waitUntil { model.step == .done }

        #expect(model.outcome?.planActivationPending == true)
        #expect(requestCount(backend, path: subscribePath) == 0)

        // The completion callback fires exactly once, from the success panel's button.
        let completed = Recorder<SignupOutcome>()
        model.onSignupComplete = { completed.record($0) }
        model.complete()
        model.complete()
        #expect(completed.count == 1)
    }

    @Test func aFreePlanNeedsNoCardAndFinishesStraightAway() async {
        let backend = TestBackend()
        stubOpenRegistration(backend)
        stubCatalog(backend, paid: false)
        stubRegisterAndLogin(backend)
        backend.stub("POST", subscribePath, TestStubResponse(json: #"{"success":true,"errorMessage":""}"#))

        let model = makeModel(backend)
        model.start()
        await waitUntil { model.step == .register }
        model.submitForm(form())
        await waitUntil { model.step == .done || model.step == .failed }

        #expect(model.step == .done)
        #expect(requestCount(backend, path: subscribePath) == 1)
        #expect(model.outcome?.planActivationPending == nil)
    }

    // MARK: - Registration tokens

    @Test func aTokensPlanIsNeverSubscribedOver() async {
        let backend = TestBackend()
        stubOpenRegistration(backend)
        stubCatalog(backend)
        stubRegisterAndLogin(backend)
        backend.stub(
            "GET",
            tokenDetailsPath,
            TestStubResponse(
                json: """
                {"isValid":true,"appGrants":[
                  {"appId":"APP-1","appTierId":"tier-pro","appTierName":"Pro","addOnIds":[],"featureCodes":[]}]}
                """
            )
        )
        backend.stub(
            "POST",
            "/api/userregistration/register-with-token",
            TestStubResponse(
                json: """
                {"id":"user-1","userId":"user-1","email":"a@b.test","jwtToken":"jwt-1",
                 "requiresDisclaimerAcceptance":false}
                """
            )
        )

        let model = makeModel(backend)
        model.start()
        await waitUntil { model.step == .register }
        model.submitForm(form(useToken: true, token: "tok-1"))
        await waitUntil { model.step == .done || model.step == .failed }

        #expect(model.step == .done)
        // The app id was matched case-insensitively, so the grant was honoured...
        #expect(model.tokenGrant?.appTierId == "tier-pro")
        // ...and nothing self-subscribed over the plan the token already set up.
        #expect(requestCount(backend, path: subscribePath) == 0)
        #expect(model.outcome?.tokenGrant?.tierId == "tier-pro")
    }

    @Test func anUnreadableTokenIsNotAnInvalidOne() async {
        let backend = TestBackend()
        stubOpenRegistration(backend)
        stubCatalog(backend, paid: false)
        stubRegisterAndLogin(backend)
        backend.stub("POST", subscribePath, TestStubResponse(json: #"{"success":true,"errorMessage":""}"#))
        // No stub for the details route: a 404 is "could not be read", not "invalid".
        backend.stub(
            "POST",
            "/api/userregistration/register-with-token",
            TestStubResponse(
                json: """
                {"id":"user-1","userId":"user-1","email":"a@b.test","jwtToken":"jwt-1",
                 "requiresDisclaimerAcceptance":false}
                """
            )
        )

        let model = makeModel(backend)
        model.start()
        await waitUntil { model.step == .register }
        model.submitForm(form(useToken: true, token: "tok-1"))
        await waitUntil { model.step == .done || model.step == .failed }

        #expect(model.step == .done)
        #expect(model.tokenGrant == nil)
        #expect(model.tokenMessage == nil)
    }

    @Test func aRejectedTokenGoesBackToTheFormWithTheServersWords() async {
        let backend = TestBackend()
        stubOpenRegistration(backend)
        stubCatalog(backend)
        backend.stub(
            "GET",
            tokenDetailsPath,
            TestStubResponse(json: #"{"isValid":false,"errorMessage":"That token has expired.","appGrants":[]}"#)
        )

        let model = makeModel(backend)
        let reported = Recorder<RegistrationSubscriptionError>()
        model.onError = { reported.record($0) }
        model.start()
        await waitUntil { model.step == .register }
        model.submitForm(form(useToken: true, token: "tok-1"))
        await waitUntil { model.tokenMessage != nil }

        #expect(model.tokenMessage == "That token has expired.")
        #expect(model.step == .register)
        #expect(reported.first?.code == RegistrationSubscriptionErrorCodes.registrationTokenRejected)
        #expect(requestCount(backend, path: registerPath) == 0)
    }

    // MARK: - Retries

    @Test func retryResumesInsteadOfRegisteringTheSamePersonAgain() async {
        let backend = TestBackend()
        stubOpenRegistration(backend)
        stubCatalog(backend, paid: false)
        backend.stub(
            "POST",
            registerPath,
            TestStubResponse(json: #"{"success":true,"message":"ok","userId":"user-1"}"#)
        )
        // The sign-in fails first, which is a failed signup with the account already created.
        backend.stub("POST", loginPath, TestStubResponse(statusCode: 500, json: #"{"message":"boom"}"#))
        backend.stub("POST", subscribePath, TestStubResponse(json: #"{"success":true,"errorMessage":""}"#))

        let model = makeModel(backend)
        model.start()
        await waitUntil { model.step == .register }
        model.submitForm(form())
        await waitUntil { model.step == .failed }

        #expect(requestCount(backend, path: registerPath) == 1)

        backend.stub(
            "POST",
            loginPath,
            TestStubResponse(
                json: """
                {"id":"user-1","userId":"user-1","email":"a@b.test","jwtToken":"jwt-1",
                 "requiresDisclaimerAcceptance":false}
                """
            )
        )
        model.retry()
        await waitUntil { model.step == .done || model.step == .register }

        #expect(model.step == .done)
        // The account was created once and only once.
        #expect(requestCount(backend, path: registerPath) == 1)
        #expect(requestCount(backend, path: loginPath) == 2)
    }

    // MARK: - Already signed in

    @Test func theAlreadySignedInNoticeIsLatchedOnceAtTheFirstStart() async {
        let backend = TestBackend()
        stubOpenRegistration(backend)
        stubCatalog(backend)

        let client = makeTestClient(backend, appId: Self.appId)
        client.session.login(
            AuthenticationResponse(id: "u-1", userId: "u-1", email: "a@b.test", jwtToken: "jwt-1")
        )
        let model = WildwoodSignupFlowModel(
            client: client,
            options: WildwoodSignupFlowOptions(preSelectedTierId: "tier-pro"),
            issuer: StepTokenIssuer()
        )
        let notices = CallCounter()
        model.onAlreadySignedIn = { notices.bump() }

        model.start()
        model.start()
        await waitUntil { model.alreadySignedIn }

        #expect(model.alreadySignedIn == true)
        #expect(notices.count == 1)
    }

    // MARK: - Signup links (DD-5)

    @Test func aSignupLinksParametersBecomeThePreselection() {
        let params = SignupParams(
            tierId: "tier-pro",
            pricingId: "p-1",
            addOnIds: ["pack-a"],
            token: nil,
            invite: "inv-9",
            email: "invited@b.test"
        )
        let merged = WildwoodSignupFlowOptions().applying(params)

        #expect(merged.preSelectedTierId == "tier-pro")
        #expect(merged.preSelectedPricingId == "p-1")
        #expect(merged.preSelectedAddOnIds == ["pack-a"])
        #expect(merged.registrationToken == "inv-9")
        #expect(merged.prefillEmail == "invited@b.test")
        // An invite makes the token step the only way in, whatever the app's configuration says.
        #expect(merged.tokenMode == .required)
        // And the native default order is untouched.
        #expect(merged.paymentOrder == .afterAccount)
    }

    @Test func anInvitationsEmailPrefillsBothFields() {
        let backend = TestBackend()
        let model = makeModel(
            backend,
            options: WildwoodSignupFlowOptions(
                registrationToken: "tok-1",
                prefillEmail: "invited@b.test",
                tokenMode: .required
            )
        )
        let initial = model.initialFormData

        #expect(initial?.email == "invited@b.test")
        #expect(initial?.username == "invited@b.test")
        #expect(initial?.useToken == true)
        #expect(initial?.registrationToken == "tok-1")
    }

    // MARK: - Teardown

    @Test func detachStartsNothingNewAndSaysNothingToTheView() async {
        let backend = TestBackend()
        stubOpenRegistration(backend)
        stubCatalog(backend)

        let model = makeModel(backend)
        let changes = CallCounter()
        model.onStateChanged = { changes.bump() }
        model.detach()
        model.start()
        await waitUntil(timeout: 0.2) { requestCount(backend, path: publicTiersPath) > 0 }

        #expect(requestCount(backend, path: publicTiersPath) == 0)
        #expect(changes.count == 0)
        model.detach()
    }
}
