import Foundation
import Observation

@MainActor
@Observable
final class CurrencyRateStore {
  private enum CacheKey {
    static let payload = "currency.rates.usd.cache.v1"
  }

  private struct RatesCachePayload: Codable {
    let updatedAt: Date
    let rates: [String: String]
  }

  @ObservationIgnored
  private let converter: CurrencyConverter
  @ObservationIgnored
  private let defaults: UserDefaults

  private(set) var usdRates: [String: Decimal]
  private(set) var updatedAt: Date?
  private(set) var isRefreshing: Bool = false

  init(
    converter: CurrencyConverter = CurrencyConverter(),
    defaults: UserDefaults = .standard
  ) {
    self.converter = converter
    self.defaults = defaults

    if
      let data = defaults.data(forKey: CacheKey.payload),
      let payload = try? JSONDecoder().decode(RatesCachePayload.self, from: data)
    {
      self.updatedAt = payload.updatedAt
      self.usdRates = payload.rates.reduce(into: ["USD": 1]) { partial, entry in
        if let value = Decimal(string: entry.value) {
          partial[entry.key.uppercased()] = value
        }
      }
    } else {
      self.updatedAt = nil
      self.usdRates = ["USD": 1]
    }
  }

  func refreshIfNeeded(maxCacheAge: TimeInterval = 60 * 30) async {
    guard shouldRefresh(maxCacheAge: maxCacheAge) else { return }
    await refresh()
  }

  func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }

    do {
      let latest = try await converter.latestRates(base: "USD")
      var normalized: [String: Decimal] = ["USD": 1]
      for (key, value) in latest {
        normalized[key.uppercased()] = value
      }
      usdRates = normalized
      updatedAt = Date()
      persistCache()
    } catch {
      // Keep stale cache as fallback.
    }
  }

  func ensureRate(for currencyCode: String) async {
    let normalized = normalizeCode(currencyCode)
    if usdRates[normalized] == nil {
      await refresh()
    }
  }

  func rateFromUSD(to currencyCode: String) -> Decimal {
    let normalized = normalizeCode(currencyCode)
    return usdRates[normalized] ?? 1
  }

  func convertUSDToSelected(_ amountUSD: Decimal, currencyCode: String) -> Decimal {
    amountUSD * rateFromUSD(to: currencyCode)
  }

  func convertSelectedToUSD(_ amount: Decimal, currencyCode: String) -> Decimal {
    let rate = rateFromUSD(to: currencyCode)
    guard rate > 0 else { return amount }
    return amount / rate
  }

  func formatUSD(
    _ amountUSD: Decimal,
    currencyCode: String,
    locale: Locale,
    minimumFractionDigits: Int = 2,
    maximumFractionDigits: Int = 2
  ) -> String {
    let converted = convertUSDToSelected(amountUSD, currencyCode: currencyCode)
    return CurrencyDisplayFormatter.format(
      amount: converted,
      currencyCode: normalizeCode(currencyCode),
      locale: locale,
      minimumFractionDigits: minimumFractionDigits,
      maximumFractionDigits: maximumFractionDigits
    )
  }

  func symbol(for currencyCode: String, locale: Locale) -> String {
    CurrencyDisplayFormatter.symbol(
      currencyCode: normalizeCode(currencyCode),
      locale: locale
    )
  }

  private func shouldRefresh(maxCacheAge: TimeInterval) -> Bool {
    guard let updatedAt else { return true }
    return Date().timeIntervalSince(updatedAt) >= maxCacheAge
  }

  private func normalizeCode(_ code: String) -> String {
    let normalized = code.uppercased()
    switch normalized {
    case "YEN":
      return "JPY"
    case "SUR":
      return "RUB"
    default:
      return normalized
    }
  }

  private func persistCache() {
    let payload = RatesCachePayload(
      updatedAt: updatedAt ?? Date(),
      rates: usdRates.mapValues { NSDecimalNumber(decimal: $0).stringValue }
    )
    if let encoded = try? JSONEncoder().encode(payload) {
      defaults.set(encoded, forKey: CacheKey.payload)
    }
  }
}
