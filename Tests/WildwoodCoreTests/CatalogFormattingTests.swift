// WildwoodMoney / WildwoodTrial — the two catalog formatters every priced surface shares.
//
// The expected strings are the output of
// `new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(amount)`, which is what
// the JS SDK renders and what WildwoodComponents.Shared's FormatHelpers.FormatMoney reproduces.
// The separator between an alphabetic symbol (CHF) and the digits is CLDR's currency spacing:
// U+00A0, written here as an escape so it survives a copy-paste.

import Foundation
import Testing
@testable import WildwoodCore

struct CatalogFormattingTests {
    @Test func formatsTheCurrenciesWithTheirOwnSymbolAndFractionDigits() {
        #expect(WildwoodMoney.format(1234.5, currency: "USD") == "$1,234.50")
        #expect(WildwoodMoney.format(79, currency: "EUR") == "\u{20AC}79.00")
        #expect(WildwoodMoney.format(79, currency: "GBP") == "\u{00A3}79.00")
        // Zero-decimal currency: ICU gives JPY no fraction digits.
        #expect(WildwoodMoney.format(79, currency: "JPY") == "\u{00A5}79")
        // An alphabetic symbol is separated from the digits by a NO-BREAK space.
        #expect(WildwoodMoney.format(79, currency: "CHF") == "CHF\u{00A0}79.00")
    }

    @Test func groupsThousandsAndKeepsTheSignInFront() {
        #expect(WildwoodMoney.format(1234567.89, currency: "USD") == "$1,234,567.89")
        #expect(WildwoodMoney.format(-1234.5, currency: "USD") == "-$1,234.50")
    }

    @Test func blankCurrencyMeansUSD() {
        #expect(WildwoodMoney.format(79, currency: nil) == "$79.00")
        #expect(WildwoodMoney.format(79, currency: "") == "$79.00")
        #expect(WildwoodMoney.format(79, currency: "   ") == "$79.00")
    }

    @Test func codeIsNormalisedToUppercase() {
        #expect(WildwoodMoney.format(79, currency: "eur") == "\u{20AC}79.00")
        #expect(WildwoodMoney.format(79, currency: " usd ") == "$79.00")
    }

    @Test func aCodeIntlCannotRenderFallsBackToCodePlusAmount() {
        // Intl throws on anything that is not three letters; JS says the amount and the code
        // rather than nothing, ungrouped and with a plain space.
        #expect(WildwoodMoney.format(79, currency: "BITCOIN") == "BITCOIN 79.00")
        #expect(WildwoodMoney.format(1234.5, currency: "US") == "US 1234.50")
        #expect(WildwoodMoney.format(-79, currency: "US1") == "US1 -79.00")
    }

    @Test func wellFormedCodeIsThreeAsciiLetters() {
        #expect(WildwoodMoney.isWellFormedCurrencyCode("USD"))
        #expect(WildwoodMoney.isWellFormedCurrencyCode("US") == false)
        #expect(WildwoodMoney.isWellFormedCurrencyCode("USDD") == false)
        #expect(WildwoodMoney.isWellFormedCurrencyCode("US1") == false)
    }

    @Test func trialLabelMatchesTheJsWording() {
        #expect(WildwoodTrial.label(days: 14) == "14-day free trial")
        #expect(WildwoodTrial.label(days: 1) == "1-day free trial")
        // A pack or plan with no trial never renders a bare "0".
        #expect(WildwoodTrial.label(days: 0) == "")
        #expect(WildwoodTrial.label(days: nil) == "")
        #expect(WildwoodTrial.label(days: -3) == "")
    }
}
