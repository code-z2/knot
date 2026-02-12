import Foundation
import RPC

public enum AAError: Error {
  case invalidPayloadType
  case invalidAddress(String)
  case invalidHexValue(String)
  case invalidQuantity(String)
  case invalidPackedWord(String)
  case invalidEip7702SenderCodePrefix(String)
  case missingEip7702Auth
  case relayMissingIdentifier
  case relayMissingStatus
}

extension AAError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidPayloadType: return "Unsupported AA payload type."
    case .invalidAddress(let value): return "Invalid address: \(value)"
    case .invalidHexValue(let value): return "Invalid hex value: \(value)"
    case .invalidQuantity(let value): return "Invalid numeric quantity: \(value)"
    case .invalidPackedWord(let value): return "Invalid packed word: \(value)"
    case .invalidEip7702SenderCodePrefix(let value):
      return "Invalid EIP-7702 sender code prefix: \(value)"
    case .missingEip7702Auth: return "Missing EIP-7702 authorization."
    case .relayMissingIdentifier: return "Gelato relayer response did not contain an identifier."
    case .relayMissingStatus: return "Gelato relayer status response did not contain a status field."
    }
  }
}

public enum RelayTaskState: String, Sendable {
  case pending
  case waiting
  case success
  case executed
  case failed
  case cancelled
  case reverted
  case unknown

  static func from(_ raw: String) -> RelayTaskState {
    let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized.contains("success") || normalized.contains("exec_success") || normalized.contains("executed") {
      return .executed
    }
    if normalized.contains("fail") || normalized.contains("error") {
      return .failed
    }
    if normalized.contains("revert") {
      return .reverted
    }
    if normalized.contains("cancel") {
      return .cancelled
    }
    if normalized.contains("wait") {
      return .waiting
    }
    if normalized.contains("pending") || normalized.contains("queued") {
      return .pending
    }
    return .unknown
  }
}

public struct RelayerAuthorization: Sendable, Equatable {
  public let address: String
  public let chainId: String
  public let nonce: String
  public let r: String
  public let s: String
  public let yParity: String

  public init(address: String, chainId: String, nonce: String, r: String, s: String, yParity: String) {
    self.address = address
    self.chainId = chainId
    self.nonce = nonce
    self.r = r
    self.s = s
    self.yParity = yParity
  }

  var rpcObject: [String: Any] {
    [
      "address": AAUtils.normalizeAddressOrEmpty(address),
      "chainId": AAUtils.normalizeHexQuantity(chainId),
      "nonce": AAUtils.normalizeHexQuantity(nonce),
      "r": AAUtils.normalizeHexBytes(r),
      "s": AAUtils.normalizeHexBytes(s),
      "yParity": AAUtils.normalizeHexQuantity(yParity),
    ]
  }
}

public struct RelayerTransactionRequest: Sendable, Equatable {
  public let from: String
  public let to: String
  public let data: String
  public let value: String
  public let gasLimit: String?
  public let isSponsored: Bool
  public let authorization: RelayerAuthorization?
  public let paymentToken: String?

  public init(
    from: String,
    to: String,
    data: String,
    value: String = "0x0",
    gasLimit: String? = nil,
    isSponsored: Bool = true,
    authorization: RelayerAuthorization? = nil,
    paymentToken: String? = nil
  ) {
    self.from = from
    self.to = to
    self.data = data
    self.value = value
    self.gasLimit = gasLimit
    self.isSponsored = isSponsored
    self.authorization = authorization
    self.paymentToken = paymentToken
  }

  var rpcObject: [String: Any] {
    var object: [String: Any] = [
      "from": AAUtils.normalizeAddressOrEmpty(from),
      "to": AAUtils.normalizeAddressOrEmpty(to),
      "data": AAUtils.normalizeHexBytes(data),
      "value": AAUtils.normalizeHexQuantity(value),
      "isSponsored": isSponsored,
    ]
    if let gasLimit {
      object["gasLimit"] = AAUtils.normalizeHexQuantity(gasLimit)
    }
    if let paymentToken, !paymentToken.isEmpty {
      object["paymentToken"] = AAUtils.normalizeAddressOrEmpty(paymentToken)
    }
    if let authorization {
      object["authorizationList"] = [authorization.rpcObject]
      object["eip7702Auth"] = authorization.rpcObject
    }
    return object
  }
}

public struct RelayerSubmission: Sendable, Equatable {
  public let id: String
  public let transactionHash: String?

  public init(id: String, transactionHash: String?) {
    self.id = id
    self.transactionHash = transactionHash
  }
}

public struct RelayerStatus: Sendable, Equatable {
  public let id: String
  public let state: RelayTaskState
  public let rawStatus: String
  public let transactionHash: String?
  public let blockNumber: String?
  public let failureReason: String?

  public init(
    id: String,
    state: RelayTaskState,
    rawStatus: String,
    transactionHash: String?,
    blockNumber: String?,
    failureReason: String?
  ) {
    self.id = id
    self.state = state
    self.rawStatus = rawStatus
    self.transactionHash = transactionHash
    self.blockNumber = blockNumber
    self.failureReason = failureReason
  }
}

public struct RelayerFeeQuote: Sendable, Equatable {
  public let token: String?
  public let amount: String?

  public init(token: String?, amount: String?) {
    self.token = token
    self.amount = amount
  }
}

public actor AACore {
  private let rpcClient: RPCClient

  public init(rpcClient: RPCClient = RPCClient()) {
    self.rpcClient = rpcClient
  }

  public func estimateGas(
    chainId: UInt64,
    from: String,
    to: String,
    data: String,
    value: String = "0x0"
  ) async throws -> String {
    let txObject: [String: Any] = [
      "from": AAUtils.normalizeAddressOrEmpty(from),
      "to": AAUtils.normalizeAddressOrEmpty(to),
      "data": AAUtils.normalizeHexBytes(data),
      "value": AAUtils.normalizeHexQuantity(value),
    ]
    let gasHex: String = try await rpcClient.makeRpcCall(
      chainId: chainId,
      method: "eth_estimateGas",
      params: [AnyCodable(txObject)],
      responseType: String.self
    )
    return AAUtils.normalizeHexQuantity(gasHex)
  }

  public func relayerSendTransaction(
    chainId: UInt64,
    request: RelayerTransactionRequest
  ) async throws -> RelayerSubmission {
    try await send(chainId: chainId, method: "relayer_sendTransaction", request: request)
  }

  public func relayerSendTransactionSync(
    chainId: UInt64,
    request: RelayerTransactionRequest
  ) async throws -> RelayerSubmission {
    try await send(chainId: chainId, method: "relayer_sendTransactionSync", request: request)
  }

  public func relayerGetStatus(chainId: UInt64, id: String) async throws -> RelayerStatus {
    let result: AnyCodable = try await rpcClient.makeBundlerRpcCall(
      chainId: chainId,
      method: "relayer_getStatus",
      params: [AnyCodable(id)],
      responseType: AnyCodable.self
    )
    return try parseStatus(result.value, fallbackID: id)
  }

  public func relayerGetFeeQuote(
    chainId: UInt64,
    request: RelayerTransactionRequest
  ) async throws -> RelayerFeeQuote {
    let result: AnyCodable = try await rpcClient.makeBundlerRpcCall(
      chainId: chainId,
      method: "relayer_getFeeQuote",
      params: [AnyCodable(request.rpcObject)],
      responseType: AnyCodable.self
    )
    return parseFeeQuote(result.value)
  }

  private func send(
    chainId: UInt64,
    method: String,
    request: RelayerTransactionRequest
  ) async throws -> RelayerSubmission {
    let result: AnyCodable = try await rpcClient.makeBundlerRpcCall(
      chainId: chainId,
      method: method,
      params: [AnyCodable(request.rpcObject)],
      responseType: AnyCodable.self
    )
    return try parseSubmission(result.value)
  }

  private func parseSubmission(_ value: Any) throws -> RelayerSubmission {
    if let id = value as? String {
      return RelayerSubmission(id: id, transactionHash: nil)
    }

    guard let dict = value as? [String: Any] else {
      throw AAError.relayMissingIdentifier
    }

    let identifier = pickString(dict, keys: ["taskId", "taskID", "id", "relayTaskId", "submissionId"])
      ?? pickString(dict, keys: ["hash", "transactionHash", "txHash"])

    guard let identifier else {
      throw AAError.relayMissingIdentifier
    }

    let txHash = pickString(dict, keys: ["transactionHash", "txHash", "hash"])
    return RelayerSubmission(id: identifier, transactionHash: txHash)
  }

  private func parseStatus(_ value: Any, fallbackID: String) throws -> RelayerStatus {
    guard let dict = value as? [String: Any] else {
      throw AAError.relayMissingStatus
    }

    let nestedTask = dict["task"] as? [String: Any]
    let scope = nestedTask ?? dict

    let rawStatus =
      pickString(scope, keys: ["status", "taskState", "taskStatus", "state"])
      ?? pickString(dict, keys: ["status", "taskState", "taskStatus", "state"])

    guard let rawStatus else {
      throw AAError.relayMissingStatus
    }

    let id =
      pickString(scope, keys: ["taskId", "taskID", "id", "relayTaskId", "submissionId"]) ?? fallbackID
    let txHash = pickString(scope, keys: ["transactionHash", "txHash", "hash"])
      ?? pickString(dict, keys: ["transactionHash", "txHash", "hash"])
    let blockNumber = pickString(scope, keys: ["blockNumber"])
      ?? pickString(dict, keys: ["blockNumber"])
    let failureReason = pickString(scope, keys: ["reason", "error", "failureReason", "message"])
      ?? pickString(dict, keys: ["reason", "error", "failureReason", "message"])

    return RelayerStatus(
      id: id,
      state: RelayTaskState.from(rawStatus),
      rawStatus: rawStatus,
      transactionHash: txHash,
      blockNumber: blockNumber,
      failureReason: failureReason
    )
  }

  private func parseFeeQuote(_ value: Any) -> RelayerFeeQuote {
    if let dict = value as? [String: Any] {
      let token = pickString(dict, keys: ["token", "paymentToken", "feeToken", "feeTokenAddress"])
      let amount = pickString(dict, keys: ["amount", "fee", "feeAmount", "estimatedFee"])
      return RelayerFeeQuote(token: token, amount: amount)
    }
    if let amount = value as? String {
      return RelayerFeeQuote(token: nil, amount: amount)
    }
    return RelayerFeeQuote(token: nil, amount: nil)
  }

  private func pickString(_ dict: [String: Any], keys: [String]) -> String? {
    for key in keys {
      guard let value = dict[key] else { continue }
      if let string = value as? String, !string.isEmpty { return string }
      if let int = value as? Int { return String(int) }
      if let int64 = value as? Int64 { return String(int64) }
      if let double = value as? Double { return String(double) }
      if let nested = value as? [String: Any] {
        if let candidate = pickString(nested, keys: keys), !candidate.isEmpty {
          return candidate
        }
      }
    }
    return nil
  }
}
