import Foundation

enum CurrencyDisplayFormatter {
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
    formatter.currencyCode = currencyCode.uppercased()
    formatter.minimumFractionDigits = minimumFractionDigits
    formatter.maximumFractionDigits = maximumFractionDigits
    return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
  }

  static func symbol(currencyCode: String, locale: Locale) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .currency
    formatter.currencyCode = currencyCode.uppercased()
    return formatter.currencySymbol ?? currencyCode.uppercased()
  }
}
