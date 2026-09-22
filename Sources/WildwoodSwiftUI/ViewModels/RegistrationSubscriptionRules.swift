// The rules the payment-action seam and an App-Store-exclusive app add, as pure functions.
//
// They live outside the drivers because the views ask them too — and because a rule inside a view
// is a rule that cannot be tested on a machine with no simulator.
//
// Ported from packages/wildwood-react-native/src/components/registrationSubscription/views/
// manageViewModel.ts (`maySendSupportsPaymentAction`, `packSelfServiceOffered`, `showsProration`).

import Foundation
import WildwoodCore

public enum RegistrationSubscriptionRules {
    /// Whether a change may tell the server this device can answer a 3-D Secure challenge.
    ///
    /// With a handler the change is posted in the OPTIONS form carrying `SupportsPaymentAction`
    /// and the server may PARK a change on a challenge; without one the plain change goes up and
    /// the server refuses rather than parking. Asking for a park nothing can answer strands the
    /// customer's money in an intent nobody confirms, so this is the only gate on that flag.
    public static func maySendSupportsPaymentAction(_ handler: (any WildwoodPaymentActionHandler)?) -> Bool {
        handler != nil
    }

    /// Whether a card may be collected in-app for a pack basket.
    ///
    /// Collecting one means asking the server for a SetupIntent
    /// (`createCheckoutPaymentMethod`) and confirming it, so it needs a handler that can confirm a
    /// card setup — not merely a handler.
    public static func mayCollectCardInApp(_ handler: (any WildwoodPaymentActionHandler)?) -> Bool {
        guard let handler else { return false }
        return handler.supportsCardSetup
    }

    /// Whether the packs panel offers a PURCHASE.
    ///
    /// A store-billed app is the interesting case: pack checkout is a card purchase and there is
    /// no in-app-purchase product behind an add-on (`IapProductMapping` is tier-only), so buying
    /// one is hidden. Packs the account already has — bought, bundled or granted — still render
    /// and can still be cancelled: hiding those would hide what the customer is paying for.
    public static func packPurchaseOffered(
        allowPackSelfService: Bool,
        showAddOns: Bool,
        requiresAppStorePayment: Bool
    ) -> Bool {
        allowPackSelfService && showAddOns && !requiresAppStorePayment
    }

    /// Whether a plan-change confirmation shows the server's proration figures.
    ///
    /// The preview prices a CARD change: a credit for unused days, a prorated charge today, a next
    /// billing date. None of that describes a store subscription, which the store prices and bills
    /// on its own terms, so a store-billed app gets the `storeManagesBilling` notice instead of
    /// numbers nobody here can honour.
    public static func showsProration(requiresAppStorePayment: Bool) -> Bool {
        !requiresAppStorePayment
    }
}

/// Which payment-action handler is in force.
public enum WildwoodPaymentAction {
    /// Nearest wins: a component's own parameter, then the `.wildwoodPaymentActionHandler(_:)`
    /// environment value, then the client's app-wide one. Nil all the way down is the supported
    /// no-handler state.
    @MainActor
    public static func resolve(
        parameter: (any WildwoodPaymentActionHandler)?,
        environment: (any WildwoodPaymentActionHandler)?,
        client: WildwoodClient?
    ) -> (any WildwoodPaymentActionHandler)? {
        if let parameter { return parameter }
        if let environment { return environment }
        return client?.paymentActionHandler
    }
}
