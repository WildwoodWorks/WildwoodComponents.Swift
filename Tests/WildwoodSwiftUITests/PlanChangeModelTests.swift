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

    /// The four reads one settlement runs: the subscription, the feature definitions and the
    /// entitlement map, and the usage limits.
    private var statusPath: String { "/api/app-tiers/\(Self.appId)/my-subscription" }
    private var definitionsPath: String { "/api/app-feature-definitions/\(Self.appId)/active" }
    private var featuresPath: String { "/api/app-tiers/\(Self.appId)/user-features" }
    private var limitsPath: String { "/api/app-tiers/\(Self.appId)/limit-statuses" }

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
        makeDriver(backend, handler: handler).model
    }

    /// The driver AND the client it settles through — what the counting tests below need, because
    /// "settled once" is a fact about the shared ``FeatureStore`` and the shared event bus.
    private func makeDriver(
        _ backend: TestBackend,
        handler: (any WildwoodPaymentActionHandler)?
    ) -> (model: WildwoodPlanChangeModel, client: WildwoodClient) {
        let client = makeTestClient(backend, appId: Self.appId)
        let admin = WildwoodSubscriptionAdminModel(client: client, appId: Self.appId, scope: .currentUser)
        let model = WildwoodPlanChangeModel(
            client: client,
            admin: admin,
            paymentActionHandler: handler,
            issuer: StepTokenIssuer()
        )
        model.completeRetryDelay = .zero
        return (model, client)
    }

    /// Everything the shared bus carried, as `appId|reason`. The subscription is deliberately
    /// dropped: it unsubscribes only when cancelled, and this one listens for the whole test.
    private func entitlementEvents(_ client: WildwoodClient) -> Recorder<String> {
        let seen = Recorder<String>()
        client.events.on { event in
            if case .entitlementsChanged(let appId, let reason) = event {
                seen.record("\(appId)|\(reason.rawValue)")
            }
        }
        return seen
    }

    /// The reads a settlement makes. Stubbed so a settlement that ran twice is counted twice
    /// rather than failing differently the second time.
    private func stubReloads(_ backend: TestBackend) {
        backend.stub(
            "GET",
            statusPath,
            TestStubResponse(
                json: """
                {"id":"sub-1","appId":"\(Self.appId)","appTierId":"tier-pro","status":"Active"}
                """
            )
        )
        backend.stub("GET", definitionsPath, TestStubResponse(json: "[]"))
        backend.stub("GET", featuresPath, TestStubResponse(json: #"{"PRO":true}"#))
        backend.stub("GET", limitsPath, TestStubResponse(json: "[]"))
    }

    /// How many settlements the backend has actually seen. The limits read is the LAST of the
    /// three a settlement runs, so counting it counts settlements that ran to the end.
    private func settlements(_ backend: TestBackend) -> Int {
        requestCount(backend, path: limitsPath)
    }

    /// Give a settlement beyond `count` every chance to land before it is ruled out — the bug
    /// these tests pin is a second settlement arriving a moment after the first.
    private func waitForSettlements(beyond count: Int, _ backend: TestBackend) async {
        await waitUntil(timeout: 0.3) { settlements(backend) > count }
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

    // MARK: - One change, one settlement

    // A plan change moves the plan ONCE, so everything downstream of it must happen once: the
    // shared FeatureStore's epoch bumps by one (mounted FeatureGates re-read exactly once),
    // `entitlementsChanged` reaches the host's other subscribers once, and the three things a plan
    // move changes are re-read once. The driver owns that settlement end to end — which is why it
    // posts the change with `settles: false` — and the surfaces hosting it add no reload of their
    // own.

    @Test func aSuccessfulChangeSettlesExactlyOnce() async throws {
        let backend = TestBackend()
        stubPreview(backend)
        stubReloads(backend)
        backend.stub("POST", changePath, TestStubResponse(json: #"{"success":true,"errorMessage":""}"#))

        let (model, client) = makeDriver(backend, handler: nil)
        let events = entitlementEvents(client)
        let epochBefore: Int = client.features.epoch

        model.selectTier(try selection())
        await waitUntil { model.step == .confirm }
        model.confirm(immediate: true, bypassPayment: true)
        await waitUntil { model.step == .done || model.step == .failed }
        await waitUntil { settlements(backend) > 0 }
        await waitForSettlements(beyond: 1, backend)

        #expect(model.step == .done)
        #expect(client.features.epoch == epochBefore + 1)
        #expect(events.values == ["\(Self.appId)|tierChange"])
        #expect(requestCount(backend, path: statusPath) == 1)
        #expect(requestCount(backend, path: definitionsPath) == 1)
        #expect(requestCount(backend, path: featuresPath) == 1)
        #expect(requestCount(backend, path: limitsPath) == 1)
    }

    @Test func aChangeCompletedAfterTheBankSettlesExactlyOnce() async throws {
        let backend = TestBackend()
        stubPreview(backend)
        stubPaymentConfig(backend)
        stubReloads(backend)
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

        let (model, client) = makeDriver(backend, handler: RecordingPaymentActionHandler())
        let events = entitlementEvents(client)
        let epochBefore: Int = client.features.epoch

        model.selectTier(try selection())
        await waitUntil { model.step == .confirm }
        model.confirm(immediate: true, bypassPayment: true)
        await waitUntil { model.step == .done || model.step == .failed }
        await waitUntil { settlements(backend) > 0 }
        await waitForSettlements(beyond: 1, backend)

        #expect(model.step == .done)
        // The change was posted AND completed — two calls the admin model would each have settled.
        #expect(requestCount(backend, path: completePath) == 1)
        #expect(client.features.epoch == epochBefore + 1)
        #expect(events.values == ["\(Self.appId)|tierChange"])
        #expect(requestCount(backend, path: statusPath) == 1)
        #expect(requestCount(backend, path: featuresPath) == 1)
        #expect(requestCount(backend, path: limitsPath) == 1)
    }

    @Test func aParkedChangeSettlesNothingBecauseThePlanHasNotMovedYet() async throws {
        let backend = TestBackend()
        stubPreview(backend)
        stubReloads(backend)
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

        // No handler: the change parks and nothing here can answer the bank, so it stops.
        let (model, client) = makeDriver(backend, handler: nil)
        let events = entitlementEvents(client)
        let epochBefore: Int = client.features.epoch

        model.selectTier(try selection())
        await waitUntil { model.step == .confirm }
        model.confirm(immediate: true, bypassPayment: true)
        await waitUntil { model.step == .failed }
        await waitForSettlements(beyond: 0, backend)

        // Nothing changed, so nothing is announced and nothing is re-read.
        #expect(client.features.epoch == epochBefore)
        #expect(events.isEmpty)
        #expect(requestCount(backend, path: statusPath) == 0)
        #expect(requestCount(backend, path: featuresPath) == 0)
        #expect(requestCount(backend, path: limitsPath) == 0)
    }

    @Test func aDrainedChangeStillSettlesExactlyOnceWithNoViewLeft() async throws {
        let backend = TestBackend()
        stubPreview(backend)
        stubPaymentConfig(backend)
        stubReloads(backend)
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
        let (model, client) = makeDriver(backend, handler: gate)
        let events = entitlementEvents(client)
        let epochBefore: Int = client.features.epoch

        model.selectTier(try selection())
        await waitUntil { model.step == .confirm }
        model.confirm(immediate: true, bypassPayment: true)
        await waitUntil { gate.wasAsked }

        model.detach()
        gate.open()

        await waitUntil { settlements(backend) > 0 }
        await waitForSettlements(beyond: 1, backend)

        // The host callbacks are gone, so the driver is the ONLY thing left that can settle — and
        // it settles once, not once per server call.
        #expect(requestCount(backend, path: completePath) == 1)
        #expect(client.features.epoch == epochBefore + 1)
        #expect(events.values == ["\(Self.appId)|tierChange"])
        #expect(requestCount(backend, path: statusPath) == 1)
        #expect(settlements(backend) == 1)
        // A second detach neither settles again nor undoes anything.
        model.detach()
        await waitForSettlements(beyond: 1, backend)
        #expect(client.features.epoch == epochBefore + 1)
        #expect(events.count == 1)
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
