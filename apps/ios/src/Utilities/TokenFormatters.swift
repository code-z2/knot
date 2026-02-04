import Foundation

enum TokenFormatters {
  static func weiToEthString(_ wei: String, maximumFractionDigits: Int = 4) -> String {
    let clean = wei.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Decimal(string: clean) else { return "0" }
    let divisor = Decimal(string: "1000000000000000000") ?? 1
    let eth = value / divisor
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = maximumFractionDigits
    formatter.minimumFractionDigits = 0
    return formatter.string(from: eth as NSDecimalNumber) ?? "\(eth)"
  }
}
