// Ported case for case from packages/wildwood-core/src/__tests__/signupParams.test.ts, plus two
// iOS-only cases for `SignupParams.parse(url:)` — the `.onOpenURL` entry point (Appendix C DD-5),
// which JS has no counterpart for because a browser hands the hook a query string, not a URL.

import Foundation
import Testing
@testable import WildwoodCore

private func signupAddOn(_ id: String, _ displayOrder: Int = 0) throws -> AppTierAddOnModel {
    var value = try WildwoodJSON.decoder().decode(AppTierAddOnModel.self, from: Data("{}".utf8))
    value.id = id
    value.appId = "app-1"
    value.name = id
    value.status = "Active"
    value.displayOrder = displayOrder
    return value
}

struct SignupParamsTests {
    @Test func readsTheSelectionAndTheIdentityHintsASignupLinkCarries() {
        let params = SignupParams.parse(
            "?tier=tier-1&pricing=price-1&addons=radar,vault&token=TK-1&invite=inv-9&email=someone%40example.test"
        )

        let expected = SignupParams(
            tierId: "tier-1",
            pricingId: "price-1",
            addOnIds: ["radar", "vault"],
            token: "TK-1",
            invite: "inv-9",
            email: "someone@example.test"
        )
        #expect(params == expected)
    }

    @Test func trimsValuesAndDropsEmptyOnes() {
        let params = SignupParams.parse("tier=%20tier-1%20&pricing=&token=%20&email=%20me%40example.test%20")

        let expected = SignupParams(
            tierId: "tier-1",
            pricingId: nil,
            addOnIds: [],
            token: nil,
            invite: nil,
            email: "me@example.test"
        )
        #expect(params == expected)
    }

    @Test func returnsAnEmptySelectionForAQueryWithNothingInIt() {
        #expect(SignupParams.parse("") == SignupParams())
        #expect(SignupParams.parse(nil) == SignupParams())
    }

    @Test func acceptsAFullUrlAndAlreadyParsedParams() {
        #expect(SignupParams.parse("https://example.test/signup?tier=t1&addons=a%20b").addOnIds == ["a", "b"])
        #expect(SignupParams.parse(query: CatalogQuery.parse("token=TK-2")).token == "TK-2")
    }

    @Test func dropsAddOnIdsTheAppDoesNotSellOnceTheCatalogIsKnown() throws {
        let radar = try signupAddOn("radar")
        let vault = try signupAddOn("vault", 1)
        let catalog = PublicCatalog.build(appId: "app-1", addOns: [radar, vault])

        // Before the catalog loads the ids are returned as given…
        #expect(SignupParams.parse("?addons=radar,smuggled,vault").addOnIds == ["radar", "smuggled", "vault"])
        // …and once it has, an id the app does not sell cannot reach a checkout.
        let filtered = SignupParams.parse("?addons=radar,smuggled,vault", catalog: catalog)
        #expect(filtered.addOnIds == ["radar", "vault"])
    }

    // MARK: - iOS: the `.onOpenURL` form (DD-5)

    @Test func readsAUniversalLink() throws {
        let url = try #require(
            URL(string: "https://app.example.test/signup?tier=t1&pricing=p2&addons=radar%2Cvault&token=TK-9#top")
        )

        let params = SignupParams.parse(url: url)

        #expect(params.tierId == "t1")
        #expect(params.pricingId == "p2")
        #expect(params.addOnIds == ["radar", "vault"])
        #expect(params.token == "TK-9")
    }

    @Test func readsACustomSchemeDeepLink() throws {
        let url = try #require(URL(string: "myapp://signup?tier=t1&invite=inv-3&email=me%40example.test"))

        let params = SignupParams.parse(url: url)

        #expect(params.tierId == "t1")
        #expect(params.invite == "inv-3")
        #expect(params.email == "me@example.test")
        #expect(params.addOnIds.isEmpty)

        // A link with no query at all is an empty selection, not a parse of the URL's own text.
        let bare = try #require(URL(string: "myapp://signup"))
        #expect(SignupParams.parse(url: bare) == SignupParams())
    }
}
