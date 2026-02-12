import Foundation

struct ZerionTransactionsEnvelope: Decodable {
  let data: [ZerionTransactionItem]
  let links: ZerionTransactionLinks?
}

struct ZerionTransactionLinks: Decodable {
  let next: String?
}

struct ZerionTransactionItem: Decodable {
  let id: String
  let attributes: ZerionTransactionAttributes
  let relationships: ZerionTransactionRelationships?
}

struct ZerionTransactionAttributes: Decodable {
  let operationType: String?
  let hash: String?
  let minedAtBlock: Int?
  let minedAt: String?
  let sentFrom: String?
  let sentTo: String?
  let status: String?
  let nonce: Int?
  let fee: ZerionTransactionFee?
  let transfers: [ZerionTransactionTransfer]?

  enum CodingKeys: String, CodingKey {
    case operationType = "operation_type"
    case hash
    case minedAtBlock = "mined_at_block"
    case minedAt = "mined_at"
    case sentFrom = "sent_from"
    case sentTo = "sent_to"
    case status
    case nonce
    case fee
    case transfers
  }
}

struct ZerionTransactionFee: Decodable {
  let value: ZerionFlexibleDecimal?
  let price: ZerionFlexibleDecimal?
  let quantity: ZerionQuantity?
  let fungibleInfo: ZerionFungibleInfo?

  enum CodingKeys: String, CodingKey {
    case value
    case price
    case quantity
    case fungibleInfo = "fungible_info"
  }
}

struct ZerionTransactionTransfer: Decodable {
  let direction: String?
  let quantity: ZerionQuantity?
  let value: ZerionFlexibleDecimal?
  let fungibleInfo: ZerionFungibleInfo?

  enum CodingKeys: String, CodingKey {
    case direction
    case quantity
    case value
    case fungibleInfo = "fungible_info"
  }
}

struct ZerionTransactionRelationships: Decodable {
  let chain: ZerionRelationshipObject?
}

struct ZerionQuantity: Decodable {
  let int: String?
  let decimals: Int?
  let float: Double?
  let numeric: String?

  var decimalValue: Decimal {
    if let numeric, let value = Decimal(string: numeric) {
      return value
    }

    if let float {
      return Decimal(float)
    }

    if let int, let intValue = Decimal(string: int), let decimals {
      let divisor = pow10(decimals)
      guard divisor > 0 else { return intValue }
      return intValue / divisor
    }

    return 0
  }

  private func pow10(_ exponent: Int) -> Decimal {
    guard exponent > 0 else { return 1 }
    var value: Decimal = 1
    for _ in 0..<exponent {
      value *= 10
    }
    return value
  }
}

struct ZerionFungibleInfo: Decodable {
  let name: String?
  let symbol: String?
  let icon: ZerionFungibleIcon?
}

struct ZerionFungibleIcon: Decodable {
  let url: String?
}

struct ZerionRelationshipObject: Decodable {
  let data: ZerionRelationshipData?
}

struct ZerionRelationshipData: Decodable {
  let type: String?
  let id: String?
}

struct ZerionFlexibleDecimal: Decodable {
  let value: Decimal

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if let decimal = try? container.decode(Decimal.self) {
      self.value = decimal
      return
    }

    if let int = try? container.decode(Int.self) {
      self.value = Decimal(int)
      return
    }

    if let double = try? container.decode(Double.self) {
      self.value = Decimal(double)
      return
    }

    if let string = try? container.decode(String.self), let decimal = Decimal(string: string) {
      self.value = decimal
      return
    }

    self.value = 0
  }
}
