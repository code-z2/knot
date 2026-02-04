import Foundation

enum AddressShortener {
  static func shortened(
    _ address: String,
    prefixCount: Int = 6,
    suffixCount: Int = 4,
    separator: String = "..."
  ) -> String {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return trimmed }

    let minimumLength = prefixCount + suffixCount + separator.count
    guard trimmed.count > minimumLength else { return trimmed }

    return "\(trimmed.prefix(prefixCount))\(separator)\(trimmed.suffix(suffixCount))"
  }
}

