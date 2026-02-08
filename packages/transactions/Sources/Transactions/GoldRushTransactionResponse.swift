import Foundation

// MARK: - GoldRush Allchains Transactions API Response

struct GoldRushTxEnvelope: Decodable {
  let data: GoldRushTxDataWrapper?
  let error: Bool?
  let errorMessage: String?

  enum CodingKeys: String, CodingKey {
    case data
    case error
    case errorMessage = "error_message"
  }
}

struct GoldRushTxDataWrapper: Decodable {
  let items: [GoldRushTxItem]?
  let currentPageSize: Int?
  let cursorBefore: String?
  let cursorAfter: String?
  let hasMore: Bool?

  enum CodingKeys: String, CodingKey {
    case items
    case currentPageSize = "current_page_size"
    case cursorBefore = "cursor_before"
    case cursorAfter = "cursor_after"
    case hasMore = "has_more"
  }
}

struct GoldRushTxItem: Decodable {
  let chainId: String?
  let chainName: String?
  let txHash: String?
  let fromAddress: String?
  let toAddress: String?
  let value: String?
  let valueQuote: Double?
  let prettyValueQuote: String?
  let successful: Bool?
  let blockSignedAt: String?
  let blockHeight: Int?
  let gasSpent: Int?
  let gasPrice: Int?
  let gasQuote: Double?
  let prettyGasQuote: String?
  let feesPaid: String?
  let logEvents: [GoldRushLogEvent]?
  let explorers: [GoldRushExplorer]?

  enum CodingKeys: String, CodingKey {
    case chainId = "chain_id"
    case chainName = "chain_name"
    case txHash = "tx_hash"
    case fromAddress = "from_address"
    case toAddress = "to_address"
    case value
    case valueQuote = "value_quote"
    case prettyValueQuote = "pretty_value_quote"
    case successful
    case blockSignedAt = "block_signed_at"
    case blockHeight = "block_height"
    case gasSpent = "gas_spent"
    case gasPrice = "gas_price"
    case gasQuote = "gas_quote"
    case prettyGasQuote = "pretty_gas_quote"
    case feesPaid = "fees_paid"
    case logEvents = "log_events"
    case explorers
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    chainId = try container.decodeIfPresent(String.self, forKey: .chainId)
    chainName = try container.decodeIfPresent(String.self, forKey: .chainName)
    txHash = try container.decodeIfPresent(String.self, forKey: .txHash)
    fromAddress = try container.decodeIfPresent(String.self, forKey: .fromAddress)
    toAddress = try container.decodeIfPresent(String.self, forKey: .toAddress)
    value = try container.decodeIfPresent(String.self, forKey: .value)
    valueQuote = try container.decodeIfPresent(Double.self, forKey: .valueQuote)
    prettyValueQuote = try container.decodeIfPresent(String.self, forKey: .prettyValueQuote)
    successful = try container.decodeIfPresent(Bool.self, forKey: .successful)
    blockSignedAt = try container.decodeIfPresent(String.self, forKey: .blockSignedAt)
    blockHeight = try container.decodeIfPresent(Int.self, forKey: .blockHeight)
    gasSpent = try container.decodeIfPresent(Int.self, forKey: .gasSpent)
    gasPrice = try container.decodeIfPresent(Int.self, forKey: .gasPrice)
    gasQuote = try container.decodeIfPresent(Double.self, forKey: .gasQuote)
    prettyGasQuote = try container.decodeIfPresent(String.self, forKey: .prettyGasQuote)
    logEvents = try container.decodeIfPresent([GoldRushLogEvent].self, forKey: .logEvents)
    explorers = try container.decodeIfPresent([GoldRushExplorer].self, forKey: .explorers)

    // fees_paid can be either String or number in the API response
    if let strVal = try? container.decodeIfPresent(String.self, forKey: .feesPaid) {
      feesPaid = strVal
    } else if let intVal = try? container.decodeIfPresent(Int64.self, forKey: .feesPaid) {
      feesPaid = String(intVal)
    } else if let doubleVal = try? container.decodeIfPresent(Double.self, forKey: .feesPaid) {
      feesPaid = String(format: "%.0f", doubleVal)
    } else {
      feesPaid = nil
    }
  }
}

struct GoldRushLogEvent: Decodable {
  let senderContractDecimals: Int?
  let senderName: String?
  let senderContractTickerSymbol: String?
  let senderAddress: String?
  let senderLogoUrl: String?
  let rawLogTopics: [String]?
  let rawLogData: String?
  let decoded: GoldRushDecodedEvent?

  enum CodingKeys: String, CodingKey {
    case senderContractDecimals = "sender_contract_decimals"
    case senderName = "sender_name"
    case senderContractTickerSymbol = "sender_contract_ticker_symbol"
    case senderAddress = "sender_address"
    case senderLogoUrl = "sender_logo_url"
    case rawLogTopics = "raw_log_topics"
    case rawLogData = "raw_log_data"
    case decoded
  }
}

struct GoldRushDecodedEvent: Decodable {
  let name: String?
  let signature: String?
  let params: [GoldRushEventParam]?
}

struct GoldRushEventParam: Decodable {
  let name: String?
  let type: String?
  let indexed: Bool?
  let decoded: Bool?
  let value: AnyCodableValue?
}

/// Minimal type-erased value wrapper for GoldRush event param values,
/// which can be strings, numbers, arrays, or booleans.
enum AnyCodableValue: Decodable, Hashable {
  case string(String)
  case int(Int)
  case double(Double)
  case bool(Bool)
  case array([String])
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
      return
    }
    if let boolVal = try? container.decode(Bool.self) {
      self = .bool(boolVal)
      return
    }
    if let intVal = try? container.decode(Int.self) {
      self = .int(intVal)
      return
    }
    if let doubleVal = try? container.decode(Double.self) {
      self = .double(doubleVal)
      return
    }
    if let stringVal = try? container.decode(String.self) {
      self = .string(stringVal)
      return
    }
    if let arrayVal = try? container.decode([String].self) {
      self = .array(arrayVal)
      return
    }
    self = .null
  }

  var stringValue: String? {
    switch self {
    case .string(let s): return s
    case .int(let i): return String(i)
    case .double(let d): return String(d)
    case .bool(let b): return String(b)
    default: return nil
    }
  }

  var arrayValue: [String]? {
    if case .array(let arr) = self { return arr }
    return nil
  }
}

struct GoldRushExplorer: Decodable {
  let label: String?
  let url: String?
}

