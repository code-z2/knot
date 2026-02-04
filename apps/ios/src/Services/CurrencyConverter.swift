import Foundation

enum CurrencyConverterError: Error {
  case missingRate(String)
  case invalidResponse
}

protocol CurrencyRateProviding {
  func latestRates(base: String) async throws -> [String: Decimal]
}

struct FrankfurterRateProvider: CurrencyRateProviding {
  func latestRates(base: String) async throws -> [String: Decimal] {
    var components = URLComponents(string: "https://api.frankfurter.app/latest")
    components?.queryItems = [URLQueryItem(name: "from", value: base.uppercased())]
    guard let url = components?.url else { throw CurrencyConverterError.invalidResponse }

    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw CurrencyConverterError.invalidResponse
    }

    let decoded = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
    var normalized: [String: Decimal] = [:]
    normalized[base.uppercased()] = 1
    for (k, v) in decoded.rates {
      normalized[k.uppercased()] = Decimal(v)
    }
    return normalized
  }
}

struct StaticRateProvider: CurrencyRateProviding {
  let table: [String: [String: Decimal]]

  init(table: [String: [String: Decimal]] = [:]) {
    self.table = table
  }

  func latestRates(base: String) async throws -> [String: Decimal] {
    if let row = table[base.uppercased()] { return row }
    return [base.uppercased(): 1]
  }
}

struct CurrencyConverter {
  let provider: CurrencyRateProviding

  init(provider: CurrencyRateProviding = FrankfurterRateProvider()) {
    self.provider = provider
  }

  func convert(amount: Decimal, from: String, to: String) async throws -> Decimal {
    let source = from.uppercased()
    let target = to.uppercased()
    if source == target { return amount }

    let rates = try await provider.latestRates(base: source)
    guard let rate = rates[target] else { throw CurrencyConverterError.missingRate(target) }
    return amount * rate
  }
}

private struct FrankfurterResponse: Decodable {
  let rates: [String: Double]
}
