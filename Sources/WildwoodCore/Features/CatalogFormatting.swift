// The two catalog formatters every priced surface shares, ported from
// packages/wildwood-core/src/features/catalog.ts (`formatMoney`, `trialLabel`) and the twin of
// WildwoodComponents.Shared/Utilities/FormatHelpers.FormatMoney / CatalogHelpers.TrialLabel.
//
// They live in WildwoodCore rather than in a view so a price reads the same in a tier card, a pack
// row and a payment button. The rest of the catalog helpers (option resolution, annual discount,
// JSON-LD offers) build on these.

import Foundation

/// Money for display, reproducing the JS SDK's
/// `new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(amount)` byte for byte.
public enum WildwoodMoney {
    /// What a blank currency means, as it does in JS.
    public static let fallbackCurrency: String = "USD"

    /// The locale is FIXED, exactly as it is in JS: a price quoted by the server has to read the
    /// same on every device, and the visitor's own locale would move the symbol and the separators
    /// around. Foundation on Apple platforms formats currency through the same ICU/CLDR data
    /// `Intl` uses, so the two stacks agree character for character.
    private static let formattingLocale: Locale = Locale(identifier: "en_US")

    /// - Parameters:
    ///   - amount: the amount, in major units.
    ///   - currency: ISO 4217 code. Blank (or nil) means ``fallbackCurrency``; a code that is not
    ///     three letters cannot be rendered by `Intl` at all, so both stacks degrade to
    ///     `"CODE 79.00"`.
    public static func format(_ amount: Double, currency: String?) -> String {
        let trimmed = (currency ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let code = (trimmed.isEmpty ? fallbackCurrency : trimmed).uppercased()

        guard isWellFormedCurrencyCode(code) else {
            // `Intl` throws on anything that is not three letters; JS says the amount and the code
            // rather than nothing. `toFixed(2)` does not group, so neither does this — and
            // `String(format:)` is unlocalised, so the separator is always a full stop.
            return code + " " + String(format: "%.2f", amount)
        }

        return amount.formatted(.currency(code: code).locale(formattingLocale))
    }

    /// Three ASCII letters — the only shape `Intl.NumberFormat` accepts as a currency.
    static func isWellFormedCurrencyCode(_ code: String) -> Bool {
        guard code.count == 3 else { return false }
        for character in code {
            guard character.isASCII, character.isLetter else { return false }
        }
        return true
    }
}

/// The free-trial line a priced surface shows under the price.
public enum WildwoodTrial {
    /// `"14-day free trial"`, or an empty string when nothing starts a trial — a plan or pack with
    /// `trialDays == 0` never renders a bare "0".
    public static func label(days: Int?) -> String {
        guard let days, days > 0 else { return "" }
        return "\(days)-day free trial"
    }
}
