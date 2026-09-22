// Signup link parameters — a port of packages/wildwood-core/src/features/signupParams.ts and the
// twin of WildwoodComponents.Shared/Utilities/SignupParams.cs.
//
// Pure: the caller supplies the URL or query, so nothing here reads a location of its own. On iOS
// the source is `.onOpenURL` — an invite/signup universal link (`https://app.example/signup?…`)
// or a custom-scheme deep link (`myapp://signup?…`) carries exactly these keys. Hand the same URL
// to `client.attribution.capture(url:)` so the campaign that produced the signup is recorded too.

import Foundation

/// Everything a signup link can carry. Every value is trimmed; an empty one becomes nil.
public struct SignupParams: Sendable, Equatable {
    /// The tier the visitor arrived wanting (`?tier=`).
    public var tierId: String?
    /// The pricing option within that tier (`?pricing=`).
    public var pricingId: String?
    /// Packs to pre-select (`?addons=`), de-duplicated and capped. Always an array.
    public var addOnIds: [String]
    /// A registration token (`?token=`).
    public var token: String?
    /// An invitation id (`?invite=`).
    public var invite: String?
    /// An email to prefill (`?email=`).
    public var email: String?

    public init(
        tierId: String? = nil,
        pricingId: String? = nil,
        addOnIds: [String] = [],
        token: String? = nil,
        invite: String? = nil,
        email: String? = nil
    ) {
        self.tierId = tierId
        self.pricingId = pricingId
        self.addOnIds = addOnIds
        self.token = token
        self.invite = invite
        self.email = email
    }

    /// Parse a signup URL's query into the selection and identity hints a registration screen
    /// needs. Accepts a full URL, a query string with or without its leading `?`, or nil.
    ///
    /// Pass the catalog once it has loaded to drop add-on ids the app does not sell — without it
    /// the ids are returned as given, which is what a screen that parses before fetching wants.
    public static func parse(_ searchOrUrl: String?, catalog: PublicCatalog? = nil) -> SignupParams {
        parse(query: CatalogQuery.parse(searchOrUrl), catalog: catalog)
    }

    /// The `.onOpenURL` form: a universal link or a custom-scheme deep link.
    public static func parse(url: URL, catalog: PublicCatalog? = nil) -> SignupParams {
        parse(query: CatalogQuery.parse(url: url), catalog: catalog)
    }

    /// Parse already-parsed parameters, for a caller that holds a query collection rather than a
    /// string (JS `parseSignupParams` takes a `URLSearchParams` the same way).
    public static func parse(query: CatalogQuery, catalog: PublicCatalog? = nil) -> SignupParams {
        let selection: DecodedCatalogSelection = Catalog.decodeSelection(query, catalog: catalog)

        return SignupParams(
            tierId: selection.tierId,
            pricingId: selection.pricingId,
            addOnIds: selection.addOnIds,
            token: Catalog.trimmedOrNil(query.first("token")),
            invite: Catalog.trimmedOrNil(query.first("invite")),
            email: Catalog.trimmedOrNil(query.first("email"))
        )
    }
}
