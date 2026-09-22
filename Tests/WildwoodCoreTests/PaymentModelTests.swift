// Wire-shape tests for the payment model additions: the PascalCase BillingAddress key on the
// initiate request, and the SetupIntent/trial fields on its response.

import Foundation
import Testing
@testable import WildwoodCore

struct PaymentRequestEncodingTests {
    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try WildwoodJSON.encoder().encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func initiatePaymentSendsTheBillingAddressPascalCase() throws {
        let request = InitiatePaymentRequest(
            providerId: "prov-1",
            appId: "app-1",
            amount: 9.99,
            currency: "USD",
            billingAddress: BillingAddress(
                firstName: "Ada",
                lastName: "Lovelace",
                street: "1 Analytical Way",
                city: "London",
                state: "LDN",
                zipCode: "E1 6AN",
                country: "GB"
            ),
            supportsSetupIntent: true
        )

        let body = try jsonObject(request)

        // The rest of the body has always gone up camelCase and stays that way.
        #expect(body["providerId"] as? String == "prov-1")
        #expect(body["appId"] as? String == "app-1")
        #expect(body["amount"] as? Double == 9.99)
        #expect(body["supportsSetupIntent"] as? Bool == true)
        #expect(body.keys.contains("billingAddress") == false)

        let address = try #require(body["BillingAddress"] as? [String: Any])
        #expect(address["firstName"] as? String == "Ada")
        #expect(address["lastName"] as? String == "Lovelace")
        #expect(address["street"] as? String == "1 Analytical Way")
        #expect(address["city"] as? String == "London")
        #expect(address["state"] as? String == "LDN")
        #expect(address["zipCode"] as? String == "E1 6AN")
        #expect(address["country"] as? String == "GB")
    }

    @Test func initiatePaymentOmitsTheBillingAddressWhenThereIsNone() throws {
        let body = try jsonObject(InitiatePaymentRequest(providerId: "prov-1", appId: "app-1", amount: 5))

        #expect(body.keys.contains("BillingAddress") == false)
        #expect(body.keys.contains("supportsSetupIntent") == false)
        #expect(body.keys.contains("currency") == false)
        #expect(body["providerId"] as? String == "prov-1")
    }
}

struct PaymentResponseDecodingTests {
    @Test func initiateResponseDecodesTheTrialAndSecretType() throws {
        let json = """
        {"success":true,"paymentIntentId":"pi_1","clientSecret":"seti_1_secret",
         "clientSecretType":"setup_intent","trialDays":14,"trialEnd":"2026-10-15T00:00:00Z",
         "providerType":1}
        """
        let response = try WildwoodJSON.decoder().decode(InitiatePaymentResponse.self, from: Data(json.utf8))

        #expect(response.success)
        #expect(response.clientSecretType == PaymentClientSecretTypes.setupIntent)
        #expect(response.trialDays == 14)
        #expect(response.trialEnd != nil)
        #expect(response.providerType == 1)
    }

    @Test func initiateResponseLeavesTheTrialFieldsNilOnAnOlderServer() throws {
        let json = #"{"success":true,"clientSecret":"pi_1_secret","providerType":1}"#
        let response = try WildwoodJSON.decoder().decode(InitiatePaymentResponse.self, from: Data(json.utf8))

        #expect(response.clientSecretType == nil)
        #expect(response.trialDays == nil)
        #expect(response.trialEnd == nil)
        #expect(PaymentClientSecretTypes.paymentIntent == "payment_intent")
    }

    @Test func billingAddressDecodesLeniently() throws {
        let address = try WildwoodJSON.decoder().decode(BillingAddress.self, from: Data(#"{"city":"London"}"#.utf8))

        #expect(address.city == "London")
        #expect(address.country.isEmpty)
    }
}
