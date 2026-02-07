import Foundation

enum CurrencyDisplayFormatter {
  private static let symbolOverrides: [String: String] = [
    "NGN": "₦",
    "ETH": "Ξ",
  ]

  static func format(
    amount: Decimal,
    currencyCode: String,
    locale: Locale,
    minimumFractionDigits: Int = 2,
    maximumFractionDigits: Int = 2
  ) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .currency
    let normalizedCode = currencyCode.uppercased()
    formatter.currencyCode = normalizedCode
    if let symbol = symbolOverrides[normalizedCode] {
      formatter.currencySymbol = symbol
    }
    formatter.minimumFractionDigits = minimumFractionDigits
    formatter.maximumFractionDigits = maximumFractionDigits
    return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
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
