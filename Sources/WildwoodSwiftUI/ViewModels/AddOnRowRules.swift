// What a pack row says about itself, in one place.
//
// Ported from packages/wildwood-react/src/components/subscription/admin/AddOnsPanel.tsx and its
// react-native twin (JS d7eae5a, 27daa30); the twin of
// WildwoodComponents.Shared/Utilities/AddOnRowRules.cs.
//
// A pack row says how it is paid for, because that decides what cancelling it does. A row with no
// payment behind it was GRANTED — a registration token's pack, or an admin's — so nothing bills
// it, there is no renewal to show and there is nothing to reactivate at a provider; cancelling one
// simply removes it. A billed row keeps access to the end of the period it is paid up to, and a
// cancellation scheduled that way can be taken back.
//
// Everything here is pure, so the rules are tested as functions on macOS rather than through a
// rendered row.

import Foundation
import WildwoodCore

/// Copy the add-ons panel lets a host replace. Anything left alone keeps the shipped words, which
/// are the strings `@wildwood/react`'s `DEFAULT_ADDON_LABELS` ships.
public struct AddOnsPanelLabels: Sendable, Equatable {
    /// Badge on a pack nothing bills.
    public var included: String
    /// Confirmation copy before cancelling a pack nothing bills.
    public var cancelIncluded: String
    /// Confirmation copy before cancelling a billed pack.
    public var cancelBilled: String
    /// Confirms the cancellation.
    public var cancelConfirm: String
    /// Backs out of it.
    public var cancelKeep: String
    /// Takes back a scheduled cancellation.
    public var reactivate: String
    /// Opens the host's pack picker.
    public var addPacks: String

    public init(
        included: String = "Included with your registration",
        cancelIncluded: String = "This pack was included with your registration. Cancelling removes it from your account.",
        cancelBilled: String = "You keep access until the end of the current billing period.",
        cancelConfirm: String = "Cancel pack",
        cancelKeep: String = "Keep pack",
        reactivate: String = "Reactivate",
        addPacks: String = "Add packs"
    ) {
        self.included = included
        self.cancelIncluded = cancelIncluded
        self.cancelBilled = cancelBilled
        self.cancelConfirm = cancelConfirm
        self.cancelKeep = cancelKeep
        self.reactivate = reactivate
        self.addPacks = addPacks
    }

    // Written out rather than synthesised: every conformance in this package is explicit so a
    // change to the stored properties cannot silently change equality.
    public static func == (lhs: AddOnsPanelLabels, rhs: AddOnsPanelLabels) -> Bool {
        lhs.included == rhs.included
            && lhs.cancelIncluded == rhs.cancelIncluded
            && lhs.cancelBilled == rhs.cancelBilled
            && lhs.cancelConfirm == rhs.cancelConfirm
            && lhs.cancelKeep == rhs.cancelKeep
            && lhs.reactivate == rhs.reactivate
            && lhs.addPacks == rhs.addPacks
    }
}

/// Which date line an owned pack's row shows, if any.
public enum AddOnDateLine: String, Sendable, Equatable, CaseIterable {
    /// Nothing is promised: a granted pack has no renewal and no scheduled end.
    case none
    /// "Renews: {date}" — a billed pack that keeps going.
    case renews
    /// "Cancels on: {date}" — a scheduled cancellation the server dated.
    case cancels
    /// "Cancels at the end of the billing period" — scheduled, but the server sent no date.
    case cancelsAtPeriodEnd
}

/// The three things a row can ask the server to do, for the failure wording.
public enum AddOnAction: String, Sendable, Equatable, CaseIterable {
    case subscribe
    case cancel
    case reactivate
}

/// Everything an owned pack's row decides about itself.
public struct AddOnRowDecision: Sendable, Equatable {
    /// The row is scheduled to cancel at the end of the period.
    public var cancelling: Bool
    /// Nothing bills this row — it was granted, not sold.
    public var complimentary: Bool
    /// The badge next to the pack name.
    public var statusLabel: String
    /// Which of the two date lines to show, or none.
    public var dateLine: AddOnDateLine
    /// The date ``dateLine`` prints, when it prints one.
    public var endDate: Date?
    /// A scheduled cancellation on a BILLED pack can be taken back.
    public var offersReactivate: Bool
    /// Cancel is offered on a row that is neither bundled nor already cancelling.
    public var offersCancel: Bool
    /// What the confirmation asks before the cancel is sent.
    public var cancelMessage: String

    /// The included badge shows on exactly the rows nothing bills.
    public var showsIncludedBadge: Bool { complimentary }

    public init(
        cancelling: Bool,
        complimentary: Bool,
        statusLabel: String,
        dateLine: AddOnDateLine,
        endDate: Date?,
        offersReactivate: Bool,
        offersCancel: Bool,
        cancelMessage: String
    ) {
        self.cancelling = cancelling
        self.complimentary = complimentary
        self.statusLabel = statusLabel
        self.dateLine = dateLine
        self.endDate = endDate
        self.offersReactivate = offersReactivate
        self.offersCancel = offersCancel
        self.cancelMessage = cancelMessage
    }

    public static func == (lhs: AddOnRowDecision, rhs: AddOnRowDecision) -> Bool {
        lhs.cancelling == rhs.cancelling
            && lhs.complimentary == rhs.complimentary
            && lhs.statusLabel == rhs.statusLabel
            && lhs.dateLine == rhs.dateLine
            && lhs.endDate == rhs.endDate
            && lhs.offersReactivate == rhs.offersReactivate
            && lhs.offersCancel == rhs.offersCancel
            && lhs.cancelMessage == rhs.cancelMessage
    }
}

public enum AddOnRowRules {
    /// Granted, not sold: no payment behind the row and no plan bundling it in. Exactly the web's
    /// predicate (`!sub.isBundled && !sub.paymentTransactionId`), because the same row has to read
    /// the same way on every stack. An empty transaction id is no payment, the way JS treats `""`
    /// as falsy.
    public static func isComplimentary(_ subscription: UserAddOnSubscriptionModel) -> Bool {
        if subscription.isBundled { return false }
        guard let transactionId = subscription.paymentTransactionId else { return true }
        return transactionId.isEmpty
    }

    /// Whether the account already owns this pack. One access-granting rule for both lists: a row
    /// that is Cancelled or Expired is on offer again, and one scheduled to cancel is still owned,
    /// so it is not sold twice.
    public static func ownsAddOn(_ subscriptions: [UserAddOnSubscriptionModel], addOnId: String) -> Bool {
        guard !addOnId.isEmpty else { return false }
        let wanted = addOnId.lowercased()
        for subscription in subscriptions {
            guard subscription.appTierAddOnId.lowercased() == wanted else { continue }
            if SubscriptionAccess.grantsAccess(subscription.status) { return true }
        }
        return false
    }

    /// The rows that still grant what they pay for — the "Active Add-Ons" list. The server returns
    /// every row it has, cancelled ones included; listing those under "Active" with a Cancel
    /// button was the live bug.
    public static func ownedRows(_ subscriptions: [UserAddOnSubscriptionModel]) -> [UserAddOnSubscriptionModel] {
        subscriptions.filter { SubscriptionAccess.grantsAccess($0.status) }
    }

    /// The packs still on offer: everything the account does not currently own.
    public static func availableRows(
        _ addOns: [AppTierAddOnModel],
        subscriptions: [UserAddOnSubscriptionModel]
    ) -> [AppTierAddOnModel] {
        addOns.filter { !ownsAddOn(subscriptions, addOnId: $0.id) }
    }

    /// Whether the account's current plan already bundles this pack, so it is shown as included
    /// rather than sold.
    public static func isBundledInTier(_ addOn: AppTierAddOnModel, currentTierId: String?) -> Bool {
        guard let currentTierId, !currentTierId.isEmpty else { return false }
        let wanted = currentTierId.lowercased()
        for tierId in addOn.bundledInTierIds where tierId.lowercased() == wanted {
            return true
        }
        return false
    }

    /// The date a row's line prints. JS carries one `endDate`; the Swift model splits it into
    /// ``UserAddOnSubscriptionModel/endDate`` (set when a cancellation is scheduled) and
    /// ``UserAddOnSubscriptionModel/currentPeriodEnd`` (the renewal a live row is paid up to), so
    /// both feed the one line the web shows.
    public static func rowEndDate(_ subscription: UserAddOnSubscriptionModel) -> Date? {
        subscription.endDate ?? subscription.currentPeriodEnd
    }

    /// Everything one owned row decides about itself.
    ///
    /// - Parameters:
    ///   - subscription: the row, as the server sent it.
    ///   - canCancel: whether this surface offers cancelling at all.
    ///   - canReactivate: whether this surface offers taking a cancellation back.
    ///   - labels: host copy; the shipped words by default.
    public static func describe(
        _ subscription: UserAddOnSubscriptionModel,
        canCancel: Bool = true,
        canReactivate: Bool = true,
        labels: AddOnsPanelLabels = AddOnsPanelLabels()
    ) -> AddOnRowDecision {
        let cancelling = subscription.status == "PendingCancellation"
        let complimentary = isComplimentary(subscription)
        let endDate = rowEndDate(subscription)

        // Nothing bills a granted pack, so there is no renewal date to promise — even when the
        // server put one on the row.
        let showEndDate = endDate != nil && (cancelling || !complimentary)

        let dateLine: AddOnDateLine
        if showEndDate {
            dateLine = cancelling ? .cancels : .renews
        } else {
            dateLine = cancelling ? .cancelsAtPeriodEnd : .none
        }

        let statusLabel: String
        if subscription.isBundled {
            statusLabel = "Bundled"
        } else if cancelling {
            statusLabel = "Cancellation Scheduled"
        } else {
            statusLabel = subscription.status
        }

        return AddOnRowDecision(
            cancelling: cancelling,
            complimentary: complimentary,
            statusLabel: statusLabel,
            dateLine: dateLine,
            endDate: showEndDate ? endDate : nil,
            offersReactivate: cancelling && !subscription.isBundled && !complimentary && canReactivate,
            offersCancel: !subscription.isBundled && !cancelling && canCancel,
            cancelMessage: complimentary ? labels.cancelIncluded : labels.cancelBilled
        )
    }

    /// What the panel says when an action was refused or threw. A refusal that carried words of
    /// its own says them — "you already own that pack" has to read differently from "the card was
    /// declined"; a refusal with nothing to say gets the action's wording. Never empty.
    public static func failureMessage(_ action: AddOnAction, name: String?, serverMessage: String?) -> String {
        if let serverMessage {
            let trimmed = serverMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        let verb: String
        switch action {
        case .subscribe: verb = "subscribe to"
        case .cancel: verb = "cancel"
        case .reactivate: verb = "reactivate"
        }

        var packName = "this pack"
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { packName = trimmed }
        }
        return "Could not \(verb) \(packName). Please try again."
    }

    /// The trial the processor will actually start: the pricing option that is bought, then the
    /// pack's own value as a fallback.
    public static func trialLabel(addOn: AppTierAddOnModel?, pricing: AppTierAddOnPricingModel?) -> String {
        WildwoodTrial.label(days: pricing?.trialDays ?? addOn?.trialDays)
    }

    /// The currency a pack's prices are quoted in: the pack's own, then the catalog's, then nil —
    /// which ``WildwoodMoney/format(_:currency:)`` reads as USD.
    public static func resolveCurrency(addOn: AppTierAddOnModel?, catalogCurrency: String?) -> String? {
        if let own = addOn?.currency, !own.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return own
        }
        return catalogCurrency
    }

    /// A pricing option's price in the pack's own currency. Replaces the hard-coded "USD" that
    /// priced a CHF or SEK pack in dollars.
    public static func formatPrice(
        addOn: AppTierAddOnModel?,
        pricing: AppTierAddOnPricingModel?,
        catalogCurrency: String?
    ) -> String {
        WildwoodMoney.format(pricing?.price ?? 0, currency: resolveCurrency(addOn: addOn, catalogCurrency: catalogCurrency))
    }

    /// The pricing option a one-click subscribe buys: the pack's default, else the first it sells.
    public static func defaultPricing(_ addOn: AppTierAddOnModel) -> AppTierAddOnPricingModel? {
        addOn.pricingOptions.first(where: \.isDefault) ?? addOn.pricingOptions.first
    }

    /// The billing cycle shown after the price, lower-cased as the web renders it ("month" when
    /// the server sent nothing).
    public static func billingSuffix(_ pricing: AppTierAddOnPricingModel?) -> String {
        guard let frequency = pricing?.billingFrequency, !frequency.isEmpty else { return "month" }
        return frequency.lowercased()
    }
}
