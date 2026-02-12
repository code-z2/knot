import Foundation

struct ZerionPositionsEnvelope: Decodable {
  let data: [ZerionPositionItem]
  let links: ZerionPaginationLinks?
}

struct ZerionPaginationLinks: Decodable {
  let next: String?
}

struct ZerionPositionItem: Decodable {
  let id: String
  let attributes: ZerionPositionAttributes
  let relationships: ZerionPositionRelationships?
}

struct ZerionPositionAttributes: Decodable {
  let quantity: ZerionQuantity?
  let value: ZerionFlexibleDecimal?
  let price: ZerionFlexibleDecimal?
  let changes: ZerionPriceChanges?
  let fungibleInfo: ZerionFungibleInfo?
  let name: String?

  enum CodingKeys: String, CodingKey {
    case quantity
    case value
    case price
    case changes
    case fungibleInfo = "fungible_info"
    case name
  }
}

struct ZerionPriceChanges: Decodable {
  let absolute1d: ZerionFlexibleDecimal?
  let percent1d: ZerionFlexibleDecimal?

  enum CodingKeys: String, CodingKey {
    case absolute1d = "absolute_1d"
    case percent1d = "percent_1d"
  }
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
  let implementations: [ZerionFungibleImplementation]?
}

struct ZerionFungibleIcon: Decodable {
  let url: String?
}

struct ZerionFungibleImplementation: Decodable {
  let chainID: String?
  let address: String?

  enum CodingKeys: String, CodingKey {
    case chainID = "chain_id"
    case address
  }
}

struct ZerionPositionRelationships: Decodable {
  let chain: ZerionRelationshipObject?
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
