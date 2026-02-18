import Foundation

enum CurrencyDisplayFormatter {
    private static let symbolOverrides: [String: String] = [
        "NGN": "₦",
        "ETH": "Ξ",
    ]
    private static let maxSupportedFractionDigits = 4

    static func format(
        amount: Decimal,
        currencyCode: String,
        locale: Locale,
        minimumFractionDigits: Int = 2,
        maximumFractionDigits: Int = 2,
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        let normalizedCode = currencyCode.uppercased()
        formatter.currencyCode = normalizedCode
        if let symbol = symbolOverrides[normalizedCode] {
            formatter.currencySymbol = symbol
        }
        let cappedMaxFractionDigits = max(0, min(maximumFractionDigits, maxSupportedFractionDigits))
        let cappedMinFractionDigits = min(max(0, minimumFractionDigits), cappedMaxFractionDigits)
        formatter.minimumFractionDigits = cappedMinFractionDigits
        formatter.maximumFractionDigits = cappedMaxFractionDigits

        let truncatedAmount = DecimalTruncation.truncate(amount, fractionDigits: cappedMaxFractionDigits)
        return formatter.string(from: truncatedAmount as NSDecimalNumber) ?? "\(truncatedAmount)"
    }

    static func symbol(currencyCode: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        let normalizedCode = currencyCode.uppercased()
        formatter.currencyCode = normalizedCode
        if let symbol = symbolOverrides[normalizedCode] {
            formatter.currencySymbol = symbol
        }
        return formatter.currencySymbol ?? currencyCode.uppercased()
    }
}
