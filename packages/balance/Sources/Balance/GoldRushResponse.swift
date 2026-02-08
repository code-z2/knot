import Foundation

// MARK: - GoldRush Allchains Balance API Response
//
// The allchains endpoint returns a flat list of balance items, each annotated
// with chain_id and chain_name directly on the item (no chain-level grouping).

struct GoldRushEnvelope: Decodable {
  let data: GoldRushDataWrapper?
  let error: Bool?
  let errorMessage: String?
  let errorCode: Int?

  enum CodingKeys: String, CodingKey {
    case data
    case error
    case errorMessage = "error_message"
    case errorCode = "error_code"
  }
}

struct GoldRushDataWrapper: Decodable {
  let items: [GoldRushBalanceItem]?
}

struct GoldRushBalanceItem: Decodable {
  let chainId: Int?
  let chainName: String?
  let contractDecimals: Int?
  let contractName: String?
  let contractTickerSymbol: String?
  let contractAddress: String?
  let contractDisplayName: String?
  let logoUrls: LogoUrls?
  let isNativeToken: Bool?
  let type: String?
  let isSpam: Bool?
  let balance: String?
  let balance24h: String?
  let quoteRate: Double?
  let quoteRate24h: Double?
  let quote: Double?
  let quote24h: Double?

  enum CodingKeys: String, CodingKey {
    case chainId = "chain_id"
    case chainName = "chain_name"
    case contractDecimals = "contract_decimals"
    case contractName = "contract_name"
    case contractTickerSymbol = "contract_ticker_symbol"
    case contractAddress = "contract_address"
    case contractDisplayName = "contract_display_name"
    case logoUrls = "logo_urls"
    case isNativeToken = "is_native_token"
    case type
    case isSpam = "is_spam"
    case balance
    case balance24h = "balance_24h"
    case quoteRate = "quote_rate"
    case quoteRate24h = "quote_rate_24h"
    case quote
    case quote24h = "quote_24h"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    chainName = try container.decodeIfPresent(String.self, forKey: .chainName)
    contractDecimals = try container.decodeIfPresent(Int.self, forKey: .contractDecimals)
    contractName = try container.decodeIfPresent(String.self, forKey: .contractName)
    contractTickerSymbol = try container.decodeIfPresent(String.self, forKey: .contractTickerSymbol)
    contractAddress = try container.decodeIfPresent(String.self, forKey: .contractAddress)
    contractDisplayName = try container.decodeIfPresent(String.self, forKey: .contractDisplayName)
    logoUrls = try container.decodeIfPresent(LogoUrls.self, forKey: .logoUrls)
    isNativeToken = try container.decodeIfPresent(Bool.self, forKey: .isNativeToken)
    type = try container.decodeIfPresent(String.self, forKey: .type)
    isSpam = try container.decodeIfPresent(Bool.self, forKey: .isSpam)
    balance = try container.decodeIfPresent(String.self, forKey: .balance)
    balance24h = try container.decodeIfPresent(String.self, forKey: .balance24h)
    quoteRate = try container.decodeIfPresent(Double.self, forKey: .quoteRate)
    quoteRate24h = try container.decodeIfPresent(Double.self, forKey: .quoteRate24h)
    quote = try container.decodeIfPresent(Double.self, forKey: .quote)
    quote24h = try container.decodeIfPresent(Double.self, forKey: .quote24h)

    // chain_id can be either Int or String in the API response
    if let intVal = try? container.decodeIfPresent(Int.self, forKey: .chainId) {
      chainId = intVal
    } else if let strVal = try? container.decodeIfPresent(String.self, forKey: .chainId) {
      chainId = Int(strVal)
    } else {
      chainId = nil
    }
  }
}

struct LogoUrls: Decodable, Hashable {
  let tokenLogoUrl: String?
  let protocolLogoUrl: String?
  let chainLogoUrl: String?

  enum CodingKeys: String, CodingKey {
    case tokenLogoUrl = "token_logo_url"
    case protocolLogoUrl = "protocol_logo_url"
    case chainLogoUrl = "chain_logo_url"
  }
}
