// Decoding tests for the detailed registration-token models
// (GET api/registrationtokens/validate-detailed/{token}).

import Foundation
import Testing
@testable import WildwoodCore

struct RegistrationTokenDetailsTests {
    @Test func detailsDecodeEveryGrantField() throws {
        let json = """
        {"isValid":true,"appGrants":[
          {"appId":"app-1","appName":"Demo","appTierId":"t1","appTierName":"Pro",
           "appTierPricingId":"p1","pricingName":"Monthly","addOnIds":["a1","a2"],
           "addOnNames":["Pack A","Pack B"],"featureCodes":["DOCUMENTS"],"featureNames":["Documents"]}]}
        """
        let details = try WildwoodJSON.decoder().decode(RegistrationTokenDetails.self, from: Data(json.utf8))

        #expect(details.isValid)
        #expect(details.errorMessage == nil)
        #expect(details.appGrants.count == 1)

        let grant = try #require(details.appGrants.first)
        #expect(grant.id == "app-1")
        #expect(grant.appName == "Demo")
        #expect(grant.appTierId == "t1")
        #expect(grant.appTierName == "Pro")
        #expect(grant.appTierPricingId == "p1")
        #expect(grant.pricingName == "Monthly")
        #expect(grant.addOnIds == ["a1", "a2"])
        #expect(grant.addOnNames == ["Pack A", "Pack B"])
        #expect(grant.featureCodes == ["DOCUMENTS"])
        #expect(grant.featureNames == ["Documents"])
    }

    @Test func aTokenThatOnlyGrantsAppAccessHasNoGrants() throws {
        let details = try WildwoodJSON.decoder().decode(RegistrationTokenDetails.self, from: Data(#"{"isValid":true}"#.utf8))

        #expect(details.isValid)
        #expect(details.appGrants.isEmpty)
    }

    @Test func anInvalidTokenCarriesItsReason() throws {
        let json = #"{"isValid":false,"errorMessage":"Token expired","appGrants":[]}"#
        let details = try WildwoodJSON.decoder().decode(RegistrationTokenDetails.self, from: Data(json.utf8))

        #expect(details.isValid == false)
        #expect(details.errorMessage == "Token expired")
    }

    @Test func aGrantSurvivesAServerThatSentOnlyIds() throws {
        let json = #"{"isValid":true,"appGrants":[{"appId":"app-1","appTierId":"t1"}]}"#
        let details = try WildwoodJSON.decoder().decode(RegistrationTokenDetails.self, from: Data(json.utf8))

        let grant = try #require(details.appGrants.first)
        #expect(grant.appName == nil)
        #expect(grant.addOnIds.isEmpty)
        #expect(grant.featureCodes.isEmpty)
        #expect(grant.addOnNames == nil)
    }
}
