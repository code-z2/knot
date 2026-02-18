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
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
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

struct OpenERAPIRateProvider: CurrencyRateProviding {
    func latestRates(base: String) async throws -> [String: Decimal] {
        guard let url = URL(string: "https://open.er-api.com/v6/latest/\(base.uppercased())") else {
            throw CurrencyConverterError.invalidResponse
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw CurrencyConverterError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(OpenERAPIResponse.self, from: data)
        guard decoded.result.lowercased() == "success" else {
            throw CurrencyConverterError.invalidResponse
        }

        var normalized: [String: Decimal] = [:]
        normalized[base.uppercased()] = 1
        for (k, v) in decoded.rates {
            normalized[k.uppercased()] = Decimal(v)
        }
        return normalized
    }
}

struct FallbackRateProvider: CurrencyRateProviding {
    let primary: CurrencyRateProviding
    let secondary: CurrencyRateProviding
    let crypto: CurrencyRateProviding?

    init(
        primary: CurrencyRateProviding = FrankfurterRateProvider(),
        secondary: CurrencyRateProviding = OpenERAPIRateProvider(),
        crypto: CurrencyRateProviding? = CoinbaseCryptoRateProvider(),
    ) {
        self.primary = primary
        self.secondary = secondary
        self.crypto = crypto
    }

    func latestRates(base: String) async throws -> [String: Decimal] {
        async let primaryRatesTask: [String: Decimal]? = try? await primary.latestRates(base: base)
        async let secondaryRatesTask: [String: Decimal]? = try? await secondary.latestRates(base: base)
        async let cryptoRatesTask: [String: Decimal]? = try? await crypto?.latestRates(base: base)

        let primaryRates = await primaryRatesTask
        let secondaryRates = await secondaryRatesTask
        let cryptoRates = await cryptoRatesTask

        if primaryRates == nil, secondaryRates == nil, cryptoRates == nil {
            throw CurrencyConverterError.invalidResponse
        }

        var merged = secondaryRates ?? [:]
        if let primaryRates {
            for (key, value) in primaryRates {
                merged[key] = value
            }
        }
        if let cryptoRates {
            for (key, value) in cryptoRates {
                merged[key] = value
            }
        }
        merged[base.uppercased()] = 1
        return merged
    }
}

struct CoinbaseCryptoRateProvider: CurrencyRateProviding {
    func latestRates(base: String) async throws -> [String: Decimal] {
        let normalizedBase = base.uppercased()
        guard normalizedBase == "USD" else {
            return [normalizedBase: 1]
        }

        guard let url = URL(string: "https://api.coinbase.com/v2/prices/ETH-USD/spot") else {
            throw CurrencyConverterError.invalidResponse
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw CurrencyConverterError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(CoinbaseSpotResponse.self, from: data)
        guard let usdPerEth = Decimal(string: decoded.data.amount), usdPerEth > 0 else {
            throw CurrencyConverterError.invalidResponse
        }

        return [
            "USD": 1,
            "ETH": Decimal(1) / usdPerEth,
        ]
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

    init(provider: CurrencyRateProviding = FallbackRateProvider()) {
        self.provider = provider
    }

    func latestRates(base: String) async throws -> [String: Decimal] {
        try await provider.latestRates(base: base)
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

private struct OpenERAPIResponse: Decodable {
    let result: String
    let rates: [String: Double]
}

private struct CoinbaseSpotResponse: Decodable {
    struct Payload: Decodable {
        let amount: String
    }

    let data: Payload
}
