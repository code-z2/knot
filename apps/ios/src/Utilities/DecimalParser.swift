import Foundation

enum DecimalParser {
    /// Parses a machine-formatted decimal string (e.g. API responses).
    static func parse(_ value: String) -> Decimal? {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Parses user-typed input, handling commas as grouping or decimal separators.
    static func parseUserInput(_ input: String) -> Decimal? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        var normalized =
            trimmed
                .replacingOccurrences(of: "\u{00A0}", with: "")
                .replacingOccurrences(of: " ", with: "")

        if normalized.contains(","), normalized.contains(".") {
            normalized = normalized.replacingOccurrences(of: ",", with: "")
        } else if normalized.contains(",") {
            normalized = normalized.replacingOccurrences(of: ",", with: ".")
        }

        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
}
