import XCTest
import ArcaCore

final class LocalizedNumericInputTests: XCTestCase {
    func testTurkishDecimalAndGroupingAreParsedWithoutLosingInput() {
        let locale = Locale(identifier: "tr")
        XCTAssertEqual(LocalizedNumericInput.number("12,5", locale: locale), 12.5)
        XCTAssertEqual(LocalizedNumericInput.number("1.234,56", locale: locale), 1234.56)
        XCTAssertEqual(LocalizedNumericInput.money("1.234,56", currencyCode: "TRY", locale: locale)?.minorUnits, 123456)
        XCTAssertNil(LocalizedNumericInput.number("12.5", locale: locale), "Malformed Turkish grouping must not be partially parsed")
        XCTAssertNil(LocalizedNumericInput.number("12,5oops", locale: locale))
        XCTAssertNil(LocalizedNumericInput.money("12,345", currencyCode: "TRY", locale: locale), "Extra precision must not be silently discarded")
    }

    func testArabicDigitsAndSeparatorsAndDirectionMarksAreAccepted() {
        let locale = Locale(identifier: "ar")
        XCTAssertEqual(LocalizedNumericInput.number("١٢٫٥", locale: locale), 12.5)
        XCTAssertEqual(LocalizedNumericInput.number("١٬٢٣٤٫٥٦", locale: locale), 1234.56)
        XCTAssertEqual(LocalizedNumericInput.money("١٬٢٣٤٫٥٦", currencyCode: "USD", locale: locale)?.minorUnits, 123456)
        XCTAssertEqual(LocalizedNumericInput.number("\u{061C}-١٢٫٥", locale: locale), -12.5)
        XCTAssertNil(LocalizedNumericInput.number("١٢٫٥abc", locale: locale))
    }

    func testEditingTextRoundTripsForTurkishAndArabic() throws {
        let money = MoneyValue(minorUnits: 123456, currencyCode: "TRY")
        for code in ["tr", "ar", "en"] {
            let locale = Locale(identifier: code)
            let numberText = LocalizedNumericInput.editingText(for: 1234.56, locale: locale)
            XCTAssertEqual(try XCTUnwrap(LocalizedNumericInput.number(numberText, locale: locale)), 1234.56, accuracy: 0.000001)
            let moneyText = LocalizedNumericInput.editingText(for: money, locale: locale)
            XCTAssertEqual(LocalizedNumericInput.money(moneyText, currencyCode: "TRY", locale: locale), money)
        }
    }

    func testInvalidOrOverflowingInputNeverProducesAPartialValue() {
        let locale = Locale(identifier: "en")
        for text in ["", "-", "+", ".", "12invalid", "1,2", "12.3.4", "NaN", "infinity"] {
            XCTAssertNil(LocalizedNumericInput.number(text, locale: locale), text)
            XCTAssertNil(LocalizedNumericInput.money(text, currencyCode: "USD", locale: locale), text)
        }
        XCTAssertNil(LocalizedNumericInput.money("999999999999999999", currencyCode: "USD", locale: locale))
    }
}
