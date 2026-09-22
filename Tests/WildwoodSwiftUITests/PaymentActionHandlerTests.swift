// The payment-action seam itself: the outcome type, the publishable-key lookups, the precedence
// of the three places a handler can come from, and the one flag only a capable handler may send.

import Foundation
import Testing
import WildwoodCore
@testable import WildwoodSwiftUI

@MainActor
struct PaymentActionHandlerTests {
    private func configuration(_ json: String) throws -> AppPaymentConfigurationDto {
        try WildwoodJSON.decoder().decode(AppPaymentConfigurationDto.self, from: Data(json.utf8))
    }

    @Test func anOutcomeSaysWhatThereIsToShow() {
        #expect(PaymentActionOutcome.succeeded.isSucceeded == true)
        #expect(PaymentActionOutcome.succeeded.failureMessage == nil)
        // A deliberate cancel carries nothing to show the customer.
        #expect(PaymentActionOutcome.cancelled.failureMessage == nil)
        #expect(PaymentActionOutcome.cancelled.isSucceeded == false)
        #expect(PaymentActionOutcome.failed(message: "declined").failureMessage == "declined")
        // An empty failure message is "nothing to say", so the caller's own copy wins.
        #expect(PaymentActionOutcome.failed(message: "").failureMessage == nil)
        #expect(PaymentActionOutcome.failed(message: "a") == PaymentActionOutcome.failed(message: "a"))
        #expect(PaymentActionOutcome.failed(message: "a") != PaymentActionOutcome.cancelled)
    }

    @Test func theDefaultStripeKeyFollowsTheJsRule() throws {
        let config = try configuration(
            """
            {"appId":"app-1","defaultProviderId":"prov-2","providers":[
              {"id":"prov-1","providerType":1,"isEnabled":true,"isDefault":true,"publishableKey":"pk_1"},
              {"id":"prov-2","providerType":1,"isEnabled":true,"isDefault":false,"publishableKey":"pk_2"}]}
            """
        )
        #expect(WildwoodPublishableKey.defaultStripe(config) == "pk_2")

        let noNamedDefault = try configuration(
            """
            {"appId":"app-1","providers":[
              {"id":"prov-1","providerType":1,"isEnabled":true,"isDefault":false,"publishableKey":"pk_1"},
              {"id":"prov-2","providerType":1,"isEnabled":true,"isDefault":true,"publishableKey":"pk_2"}]}
            """
        )
        #expect(WildwoodPublishableKey.defaultStripe(noNamedDefault) == "pk_2")

        // Disabled providers, non-Stripe providers and providers with no key are not candidates.
        let unusable = try configuration(
            """
            {"appId":"app-1","providers":[
              {"id":"prov-1","providerType":1,"isEnabled":false,"publishableKey":"pk_1"},
              {"id":"prov-2","providerType":2,"isEnabled":true,"publishableKey":"pk_2"},
              {"id":"prov-3","providerType":1,"isEnabled":true}]}
            """
        )
        #expect(WildwoodPublishableKey.defaultStripe(unusable) == nil)
        #expect(WildwoodPublishableKey.defaultStripe(nil) == nil)
    }

    @Test func aQuotesOwnProviderWinsForAPackCheckout() throws {
        let config = try configuration(
            """
            {"appId":"app-1","defaultProviderId":"prov-1","providers":[
              {"id":"prov-1","providerType":1,"isEnabled":true,"isDefault":true,"publishableKey":"pk_1"},
              {"id":"prov-2","providerType":1,"isEnabled":true,"publishableKey":"pk_2"}]}
            """
        )
        #expect(WildwoodPublishableKey.forProvider(config, providerId: "prov-2") == "pk_2")
        // No provider named: the first enabled one carrying a key.
        #expect(WildwoodPublishableKey.forProvider(config, providerId: nil) == "pk_1")
        #expect(WildwoodPublishableKey.forProvider(nil, providerId: "prov-2") == nil)
    }

    @Test func theNearestHandlerWins() {
        let backend = TestBackend()
        let client = makeTestClient(backend)
        let fromClient = RecordingPaymentActionHandler(id: "client")
        let fromEnvironment = RecordingPaymentActionHandler(id: "environment")
        let fromParameter = RecordingPaymentActionHandler(id: "parameter")
        client.paymentActionHandler = fromClient

        let resolvedParameter = WildwoodPaymentAction.resolve(
            parameter: fromParameter, environment: fromEnvironment, client: client
        )
        #expect((resolvedParameter as? RecordingPaymentActionHandler)?.id == "parameter")

        let resolvedEnvironment = WildwoodPaymentAction.resolve(
            parameter: nil, environment: fromEnvironment, client: client
        )
        #expect((resolvedEnvironment as? RecordingPaymentActionHandler)?.id == "environment")

        let resolvedClient = WildwoodPaymentAction.resolve(parameter: nil, environment: nil, client: client)
        #expect((resolvedClient as? RecordingPaymentActionHandler)?.id == "client")

        client.paymentActionHandler = nil
        let resolvedNone = WildwoodPaymentAction.resolve(parameter: nil, environment: nil, client: client)
        #expect(resolvedNone == nil)
        let resolvedNoClient = WildwoodPaymentAction.resolve(parameter: nil, environment: nil, client: nil)
        #expect(resolvedNoClient == nil)
    }

    @Test func onlyAHandlerThatCanSaveACardAsksForASetupIntent() {
        let backend = TestBackend()
        let client = makeTestClient(backend)
        let attempt = WildwoodPaymentAttempt(
            providerId: "prov-1",
            appId: "app-1",
            amount: 20,
            pricingModelId: "pm-1",
            isSubscription: true,
            trialDays: 14
        )

        let none = WildwoodPaymentModel(payment: client.payment)
        #expect(none.supportsSetupIntent == false)
        #expect(none.supportsPaymentAction == false)
        #expect(none.makeRequest(attempt).supportsSetupIntent == nil)

        let paymentOnly = WildwoodPaymentModel(
            payment: client.payment,
            paymentActionHandler: RecordingPaymentActionHandler(supportsCardSetup: false)
        )
        // It can answer a bank challenge, so it may say so — but it must not ask for a card it
        // cannot save.
        #expect(paymentOnly.supportsPaymentAction == true)
        #expect(paymentOnly.supportsSetupIntent == false)
        #expect(paymentOnly.makeRequest(attempt).supportsSetupIntent == nil)

        let capable = WildwoodPaymentModel(
            payment: client.payment,
            paymentActionHandler: RecordingPaymentActionHandler()
        )
        #expect(capable.supportsSetupIntent == true)
        #expect(capable.makeRequest(attempt).supportsSetupIntent == true)
    }

    @Test func aClientSecretIsRoutedByItsType() async throws {
        let backend = TestBackend()
        let client = makeTestClient(backend)
        let handler = RecordingPaymentActionHandler()
        let model = WildwoodPaymentModel(payment: client.payment, paymentActionHandler: handler)

        let setup = try WildwoodJSON.decoder().decode(
            InitiatePaymentResponse.self,
            from: Data(#"{"success":true,"clientSecret":"seti_1","clientSecretType":"setup_intent"}"#.utf8)
        )
        let setupOutcome = await model.confirmIntent(setup, publishableKey: "pk_1")
        #expect(setupOutcome == PaymentActionOutcome.succeeded)
        #expect(handler.recorded().last?.kind == .cardSetup)

        let charge = try WildwoodJSON.decoder().decode(
            InitiatePaymentResponse.self,
            from: Data(#"{"success":true,"clientSecret":"pi_1","clientSecretType":"payment_intent"}"#.utf8)
        )
        let chargeOutcome = await model.confirmIntent(charge, publishableKey: "pk_1")
        #expect(chargeOutcome == PaymentActionOutcome.succeeded)
        #expect(handler.recorded().last?.kind == .payment)
        #expect(handler.recorded().count == 2)

        // No handler: nothing to confirm with, and the caller carries on as it always did.
        let bare = WildwoodPaymentModel(payment: client.payment)
        let bareOutcome = await bare.confirmIntent(charge, publishableKey: "pk_1")
        #expect(bareOutcome == nil)
    }
}
