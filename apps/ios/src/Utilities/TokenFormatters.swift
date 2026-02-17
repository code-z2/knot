import Foundation

enum TokenFormatters {
  static func weiToEthString(_ wei: String, maximumFractionDigits: Int = 4) -> String {
    let clean = wei.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Decimal(string: clean) else { return "0" }
    let divisor = Decimal(string: "1000000000000000000") ?? 1
    let eth = value / divisor
    let cappedFractionDigits = max(0, min(maximumFractionDigits, 4))
    let truncatedEth = DecimalTruncation.truncate(eth, fractionDigits: cappedFractionDigits)
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = cappedFractionDigits
    formatter.minimumFractionDigits = 0
    return formatter.string(from: truncatedEth as NSDecimalNumber) ?? "\(truncatedEth)"
  }
}
