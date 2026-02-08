import Foundation

// MARK: - GoldRush Multichain Balance API Response

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
  let items: [GoldRushChainData]?
}

struct GoldRushChainData: Decodable {
  let chainId: Int?
  let chainName: String?
  let items: [GoldRushBalanceItem]?

  enum CodingKeys: String, CodingKey {
    case chainId = "chain_id"
    case chainName = "chain_name"
    case items
  }
}

struct GoldRushBalanceItem: Decodable {
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
