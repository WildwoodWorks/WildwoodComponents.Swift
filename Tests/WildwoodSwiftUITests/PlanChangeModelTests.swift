// WildwoodPlanChangeModel: the driver half of the plan change.
//
// What these pin is the seam's binding rules and the two hazards the flow exists to avoid:
// `SupportsPaymentAction` only ever goes up when something can answer a bank challenge, a
// `processing` answer is asked again on a BOUNDED budget rather than reported as a failure, and a
// change whose bank challenge was already answered is completed even after the view has gone.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct PlanChangeModelTests {
    private static let appId = "app-1"

    private var previewPath: String { "/api/app-tiers/\(Self.appId)/my-subscription/preview-change" }
    private var changePath: String { "/api/app-tiers/\(Self.appId)/my-subscription/change" }
    private var completePath: String { "/api/app-tiers/\(Self.appId)/my-subscription/change/pc-1/complete" }
    private var paymentConfigPath: String { "/api/payment/configuration/\(Self.appId)" }

    /// Decoded rather than constructed, so the fixture stays honest about what the server sends.
    private func tier(_ id: String = "tier-pro", free: Bool = false) throws -> AppTierModel {
        let json = """
        {"id":"\(id)","appId":"\(Self.appId)","name":"Pro","isFreeTier":\(free),
         "pricingOptions":[{"id":"p-1","appTierId":"\(id)","price":20,"billingFrequency":"Monthly",
         "pricingModelId":"pm-1","isDefault":true}]}
        """
        return try WildwoodJSON.decoder().decode(AppTierModel.self, from: Data(json.utf8))
    }

    private func selection(isChange: Bool = true) throws -> PlanChangeSelection {
        let plan = try tier()
        return PlanChangeSelection(tier: plan, pricing: plan.pricingOptions.first, isChange: isChange)
    }

    private func stubPreview(_ backend: TestBackend, paymentRequired: Bool = false) {
        backend.stub(
            "POST",
            previewPath,
            TestStubResponse(
                json: """
                {"success":true,"paymentRequired":\(paymentRequired),"paymentBypassAllowed":false,
                 "newPrice":20,"currency":"USD"}
                """
            )
        )
    }

    private func stubPaymentConfig(_ backend: TestBackend) {
        backend.stub(
            "GET",
            paymentConfigPath,
            TestStubResponse(
                json: """
                {"appId":"\(Self.appId)","providers":[
                  {"id":"prov-1","name":"Stripe","providerType":1,"isEnabled":true,"isDefault":true,
                   "publishableKey":"pk_test_1"}],
                 "defaultProviderId":"prov-1"}
                """
            )
        )
    }

    private func makeModel(
        _ backend: TestBackend,
        handler: (any WildwoodPaymentActionHandler)?
    ) -> WildwoodPlanChangeModel {
        let client = makeTestClient(backend, appId: Self.appId)
        let admin = WildwoodSubscriptionAdminModel(client: client, appId: Self.appId, scope: .currentUser)
        let model = WildwoodPlanChangeModel(
            client: client,
            admin: admin,
            paymentActionHandler: handler,
            issuer: StepTokenIssuer()
        )
        model.completeRetryDelay = .zero
        return model
    }

    // MARK: - The seam

    @Test func aHandlerLetsTheChangeAskTheServerToParkAChallenge() async throws {
        let backend = TestBackend()
        stubPreview(backend)
        stubPaymentConfig(backend)
        backend.stub(
            "POST",
            changePath,
            TestStubResponse(
                json: """
                {"success":false,"requiresAction":true,"clientSecret":"cs_1","pendingChangeId":"pc-1",
                 "errorMessage":""}
                """
            )
        )
        backend.stub("POST", completePath, TestStubResponse(json: #"{"success":true,"errorMessage":""}"#))

        let handler = RecordingPaymentActionHandler()
        let model = makeModel(backend, handler: handler)

        model.selectTier(try selection())
        await waitUntil { model.step == .confirm }
        model.confirm(immediate: true, bypassPayment: true)
        await waitUntil { model.step == .done || model.step == .failed }

        #expect(model.step == .done)
        #expect(model.supportsPaymentAction == true)
        let sent = bodies(backend, path: changePath).first ?? ""
        #expect(sent.contains("\"SupportsPaymentAction\":true"))
        #expect(handler.recorded().count == 1)
        #expect(handler.recorded().first?.kind == .payment)
        #expect(handler.recorded().first?.clientSecret == "cs_1")
        #expect(handler.recorded().first?.publishableKey == "pk_test_1")
        #expect(requestCount(backend, path: completePath) == 1)
    }

    @Test func withoutAHandlerTheFlagIsNeverSentAndAChallengeSaysFinishOnTheWeb() async throws {
        let backend = TestBackend()
        stubPreview(backend)
        stubPaymentConfig(backend)
        backend.stub(
            "POST",
            changePath,
            TestStubResponse(
                json: """
                {"success":false,"requiresAction":true,"clientSecret":"cs_1","pendingChangeId":"pc-1",
                 "errorMessage":""}
                """
            )
        )

        let model = makeModel(backend, handler: nil)
        model.selectTier(try selection())
        await waitUntil { model.step == .confirm }
        model.confirm(immediate: true, bypassPayment: true)
        await waitUntil { model.step == .failed }

        #expect(model.supportsPaymentAction == false)
        let sent = bodies(backend, path: changePath).first ?? ""
        #expect(!sent.contains("SupportsPaymentAction"))
        #expect(model.error == RegistrationSubscriptionDriverLabels.defaults.finishOnWeb)
        // Nothing was completed: no money moved, so there is nothing to finish.
        #expect(requestCount(backend, path: completePath) == 0)
    }

    @Test func aRefusedChallengeStopsTheChangeWithTheHandlersReason() async throws {
        let backend = TestBackend()
        stubPreview(backend)
        stubPaymentConfig(backend)
        backend.stub(
            "POST",
            changePath,
            TestStubResponse(
                json: """
                {"success":false,"requiresAction":true,"clientSecret":"cs_1","pendingChangeId":"pc-1",
                 "errorMessage":""}
                """
            )
        )

        let handler = RecordingPaymentActionHandler(payment: .failed(message: "Your bank said no."))
        let model = makeModel(backend, handler: handler)
        model.selectTier(try selection())
        await waitUntil { model.step == .confirm }
        model.confirm(immediate: true, bypassPayment: true)
        await waitUntil { model.step == .failed }

        #expect(model.error == "Your bank said no.")
        #expect(requestCount(backend, path: completePath) == 0)
    }

    // MARK: - The bounded completion retry

    @Test func aProcessingCompletionIsAskedAgainAndGivesUpAtTheMachinesBudget() async throws {
        let backend = TestBackend()
        stubPreview(backend)
        stubPaymentConfig(backend)
        backend.stub(
            "POST",
            changePath,
            TestStubResponse(
                json: """
                {"success":false,"requiresAction":true,"clientSecret":"cs_1","pendingChangeId":"pc-1",
                 "errorMessage":""}
                """
            )
        )
        backend.stub(
            "POST",
            completePath,
            TestStubResponse(json: #"{"success":false,"processing":true,"errorMessage":""}"#)
        )

        let model = makeModel(backend, handler: RecordingPaymentActionHandler())
        model.selectTier(try selection())
        await waitUntil { model.step == .confirm }
        model.confirm(immediate: true, bypassPayment: true)
        await waitUntil { model.step == .failed }

        #expect(requestCount(backend, path: completePath) == PlanChangeMachine.maxCompleteAttempts)
        #expect(maxPlanChangeCompleteAttempts == 5)
    }

    // MARK: - The host's own card sheet

    @Test func aHostHandlerThatAnswersNothingResetsTheWholeChange() async throws {
        let backend = TestBackend()
        stubPreview(backend, paymentRequired: true)
        stubPaymentConfig(backend)

        let model = makeModel(backend, handler: nil)
        let asked = CallCounter()
        model.onPaymentRequired = { _ in
            asked.bump()
            return nil
        }

        model.selectTier(try selection())
        await waitUntil { model.step == .confirm }
        model.confirm(immediate: true)
        await waitUntil { model.step == .idle }

        #expect(asked.count == 1)
        #expect(model.step == .idle)
        // The host owns that sheet, so the built-in request is never offered alongside it.
        #expect(model.paymentRequest == nil)
        #expect(requestCount(backend, path: changePath) == 0)
    }

    @Test func anAdminScopedChangeNeverCollectsACard() async throws {
        let backend = TestBackend()
        // An admin acting on one user previews against THAT user's own endpoint.
        backend.stub(
            "POST",
            "/api/app-tiers/\(Self.appId)/admin/preview-change/u-9",
            TestStubResponse(
                json: """
                {"success":true,"paymentRequired":true,"paymentBypassAllowed":false,
                 "newPrice":20,"currency":"USD"}
                """
            )
        )
        backend.stub("POST", "/api/app-tiers/change-tier", TestStubResponse(json: #"{"success":true,"errorMessage":""}"#))

        let client = makeTestClient(backend, appId: Self.appId)
        let admin = WildwoodSubscriptionAdminModel(client: client, appId: Self.appId, scope: .user(id: "u-9"))
        let model = WildwoodPlanChangeModel(
            client: client,
            admin: admin,
            paymentActionHandler: RecordingPaymentActionHandler(),
            issuer: StepTokenIssuer()
        )
        model.completeRetryDelay = .zero

        model.selectTier(try selection())
        await waitUntil { model.step == .confirm }
        model.confirm(immediate: true)
        await waitUntil { model.step == .done || model.step == .failed }

        // Straight to `changing`: an admin change is authorised server-side.
        #expect(model.step == .done)
        #expect(requestCount(backend, path: changePath) == 0)
    }

    // MARK: - App-Store-exclusive apps (Decision 5 / DD-4)

    @Test func aStoreBilledAppShowsTheStoreNoticeInsteadOfProration() async {
        let backend = TestBackend()
        backend.stub(
            "GET",
            "/api/payment/providers/\(Self.appId)",
            TestStubResponse(
                json: """
                {"appId":"\(Self.appId)","platform":"ios","requiresAppStorePayment":true,
                 "availableProviders":[]}
                """
            )
        )

        let client = makeTestClient(backend, appId: Self.appId)
        let admin = WildwoodSubscriptionAdminModel(client: client, appId: Self.appId, scope: .currentUser)
        let model = WildwoodPlanChangeModel(client: client, admin: admin, issuer: StepTokenIssuer())

        #expect(model.showsProration == true)
        #expect(model.storeBillingNotice == nil)

        await admin.loadPaymentPlatform()

        #expect(admin.requiresAppStorePayment == true)
        #expect(model.showsProration == false)
        #expect(model.storeBillingNotice == RegistrationSubscriptionDriverLabels.defaults.storeManagesBilling)
        // And the pack PURCHASE is hidden, while owned rows keep rendering.
        #expect(
            RegistrationSubscriptionRules.packPurchaseOffered(
                allowPackSelfService: true, showAddOns: true, requiresAppStorePayment: true
            ) == false
        )
        #expect(
            RegistrationSubscriptionRules.packPurchaseOffered(
                allowPackSelfService: true, showAddOns: true, requiresAppStorePayment: false
            ) == true
        )
    }

    // MARK: - Teardown

    @Test func detachDrainsAnAuthenticatedChangeAndSaysNothingToTheView() async throws {
        let backend = TestBackend()
        stubPreview(backend)
        stubPaymentConfig(backend)
        backend.stub(
            "POST",
            changePath,
            TestStubResponse(
                json: """
                {"success":false,"requiresAction":true,"clientSecret":"cs_1","pendingChangeId":"pc-1",
                 "errorMessage":""}
                """
            )
        )
        backend.stub("POST", completePath, TestStubResponse(json: #"{"success":true,"errorMessage":""}"#))

        let gate = GatedPaymentActionHandler()
        let model = makeModel(backend, handler: gate)
        let changes = CallCounter()

        model.selectTier(try selection())
        await waitUntil { model.step == .confirm }
        model.confirm(immediate: true, bypassPayment: true)
        // The bank has been asked and has not answered yet.
        await waitUntil { gate.wasAsked }

        model.onStateChanged = { changes.bump() }
        model.detach()
        gate.open()

        // The charge went through, so the parked change is still finished — server-side only.
        await waitUntil { requestCount(backend, path: completePath) == 1 }
        #expect(requestCount(backend, path: completePath) == 1)
        #expect(changes.count == 0)
        // A second detach is a no-op.
        model.detach()
    }

    @Test func detachStartsNoNewWorkThatNeedsAPerson() async throws {
        let backend = TestBackend()
        stubPreview(backend)
        let model = makeModel(backend, handler: nil)

        model.detach()
        model.selectTier(try selection())
        await waitUntil(timeout: 0.2) { requestCount(backend, path: previewPath) > 0 }

        #expect(requestCount(backend, path: previewPath) == 0)
        #expect(model.step == .idle)
    }

    // MARK: - Messages

    @Test func aServerCodeChoosesTheMessageAndTheErrorCode() {
        let labels = RegistrationSubscriptionDriverLabels.defaults
        #expect(
            WildwoodPlanChangeModel.messageForCode(
                labels, errorCode: TierChangeErrorCodes.pendingChangeExpired, fallback: "raw"
            ) == labels.planChangeExpired
        )
        #expect(
            WildwoodPlanChangeModel.messageForCode(labels, errorCode: nil, fallback: "raw") == "raw"
        )

        let failedPreview = PlanChangeState(step: .failed, retryFrom: .previewing)
        #expect(
            WildwoodPlanChangeModel.codeForFailure(failedPreview)
                == RegistrationSubscriptionErrorCodes.tierPreviewFailed
        )
        let failedAuth = PlanChangeState(step: .failed, retryFrom: .authenticating)
        #expect(
            WildwoodPlanChangeModel.codeForFailure(failedAuth)
                == RegistrationSubscriptionErrorCodes.tierChangeAuthenticationFailed
        )
        let serverNamed = PlanChangeState(step: .failed, errorCode: "custom_code", retryFrom: .completing)
        #expect(WildwoodPlanChangeModel.codeForFailure(serverNamed) == "custom_code")
    }
}
