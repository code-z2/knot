import Foundation

// MARK: - GoldRush Address Activity API Response

struct GoldRushActivityEnvelope: Decodable {
  let data: GoldRushActivityData?
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

struct GoldRushActivityData: Decodable {
  let address: String?
  let items: [GoldRushActivityItem]?
}

struct GoldRushActivityItem: Decodable {
  let chainId: String?
  let chainName: String?
  let firstSeenAt: String?
  let lastSeenAt: String?

  enum CodingKeys: String, CodingKey {
    case chainId = "chain_id"
    case chainName = "chain_name"
    case firstSeenAt = "first_seen_at"
    case lastSeenAt = "last_seen_at"
  }
}
