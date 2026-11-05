import Foundation

/// Strict user-input parsing. Rejects partial numbers rather than silently retaining an old value.
public enum LocalizedNumericInput {
    public static func number(_ input: String, locale: Locale) -> Double? {
        guard let normalized = normalizedDecimal(input, locale: locale),
              let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    public static func decimal(_ input: String, locale: Locale) -> Decimal? {
        guard let normalized = normalizedDecimal(input, locale: locale),
              let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN else { return nil }
        return value
    }

    public static func money(_ input: String, currencyCode: String, locale: Locale, fractionDigits: Int = 2) -> MoneyValue? {
        guard (0...8).contains(fractionDigits) else { return nil }
        guard let normalized = normalizedDecimal(input, locale: locale),
              (normalized.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0) <= fractionDigits,
              let amount = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), !amount.isNaN else { return nil }
        var multiplier = Decimal(1)
        for _ in 0..<fractionDigits { multiplier *= 10 }
        let units = amount * multiplier
        guard units <= Decimal(Int64.max), units >= -Decimal(Int64.max) else { return nil }
        return MoneyValue(decimalString: normalized, currencyCode: currencyCode, fractionDigits: fractionDigits)
    }

    public static func editingText(for value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 17
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    public static func editingText(for value: MoneyValue, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = value.fractionDigits
        formatter.maximumFractionDigits = value.fractionDigits
        return formatter.string(from: value.decimalValue as NSDecimalNumber) ?? String(describing: value.decimalValue)
    }

    private static func normalizedDecimal(_ input: String, locale: Locale) -> String? {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let decimal = formatter.decimalSeparator ?? "."
        let grouping = formatter.groupingSeparator ?? ","
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // The language-only Arabic locale can default to Latin separators on Apple OS versions.
        // Accept the unambiguous separators produced by Arabic keyboards as well.
        if locale.language.languageCode?.identifier == "ar" {
            text = text.replacingOccurrences(of: "\u{066B}", with: decimal)
                .replacingOccurrences(of: "\u{066C}", with: grouping)
        }
        // Arabic keyboards may include a direction mark alongside the minus sign.
        for mark in ["\u{061C}", "\u{200E}", "\u{200F}"] { text = text.replacingOccurrences(of: mark, with: "") }
        guard !text.isEmpty else { return nil }
        var sign = ""
        if text.hasPrefix("-") || text.hasPrefix("+") {
            sign = text.hasPrefix("-") ? "-" : ""
            text.removeFirst()
        }
        guard !text.isEmpty else { return nil }
        // A dot remains useful with Arabic keyboards, where it is not a grouping separator.
        if decimal != ".", grouping != "." { text = text.replacingOccurrences(of: ".", with: decimal) }
        let parts = text.components(separatedBy: decimal)
        guard parts.count <= 2 else { return nil }
        var whole = parts[0]
        if !grouping.isEmpty, whole.contains(grouping) {
            let groups = whole.components(separatedBy: grouping)
            let primary = max(1, formatter.groupingSize)
            let secondary = formatter.secondaryGroupingSize > 0 ? formatter.secondaryGroupingSize : primary
            guard let first = groups.first, !first.isEmpty, first.count <= secondary,
                  groups.last?.count == primary,
                  groups.dropFirst().dropLast().allSatisfy({ $0.count == secondary }) else { return nil }
            whole = groups.joined()
        }
        func digits(_ text: String) -> String? {
            var result = ""
            for character in text {
                guard character.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }),
                      let digit = character.wholeNumberValue, (0...9).contains(digit) else { return nil }
                result.append(String(digit))
            }
            return result
        }
        guard let wholeDigits = digits(whole) else { return nil }
        let fraction = parts.count == 2 ? parts[1] : ""
        guard let fractionDigits = digits(fraction), !wholeDigits.isEmpty || !fractionDigits.isEmpty else { return nil }
        return sign + (wholeDigits.isEmpty ? "0" : wholeDigits) + (parts.count == 2 ? "." + fractionDigits : "")
    }
}
