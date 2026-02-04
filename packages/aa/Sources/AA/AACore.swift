import Foundation
import RPC

public struct AnySendable: @unchecked Sendable {
  public let value: Any
  public init(_ value: Any) { self.value = value }
}

public struct ChainUserOperation: Sendable {
  public let chainId: UInt64
  public let userOperation: AnySendable
  public init(chainId: UInt64, userOperation: AnySendable) {
    self.chainId = chainId
    self.userOperation = userOperation
  }
}

public enum AAError: Error {
  case invalidPayloadType
  case invalidAddress(String)
  case invalidHexValue(String)
  case invalidQuantity(String)
  case invalidPackedWord(String)
  case invalidEip7702SenderCodePrefix(String)
  case missingEip7702Auth
}

extension AAError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidPayloadType: return "Unsupported AA payload type."
    case .invalidAddress(let value): return "Invalid address: \(value)"
    case .invalidHexValue(let value): return "Invalid hex value: \(value)"
    case .invalidQuantity(let value): return "Invalid numeric quantity: \(value)"
    case .invalidPackedWord(let value): return "Invalid packed word: \(value)"
    case .invalidEip7702SenderCodePrefix(let value): return "Invalid EIP-7702 sender code prefix: \(value)"
    case .missingEip7702Auth: return "Missing EIP-7702 authorization."
    }
  }
}

public actor AACore {
  private let rpcClient: RPCClient

  public init(rpcClient: RPCClient = RPCClient()) {
    self.rpcClient = rpcClient
  }

  public func getUserOperationGasPrice(chainId: UInt64) async throws -> UserOperationGasPrice {
    struct GelatoGasPriceEnvelope: Decodable {
      struct SlowPrice: Decodable { let maxFeePerGas: String; let maxPriorityFeePerGas: String }
      let slow: SlowPrice?
      let standard: SlowPrice?
      let fast: SlowPrice?
    }
    let result: GelatoGasPriceEnvelope = try await rpcClient.makeBundlerRpcCall(
      chainId: chainId,
      method: "gelato_getUserOperationGasPrice",
      params: [],
      responseType: GelatoGasPriceEnvelope.self
    )
    let selected = result.standard ?? result.fast ?? result.slow
    guard let selected else { throw RPCError.missingResult }
    return UserOperationGasPrice(
      maxFeePerGas: AAUtils.normalizeHexQuantity(selected.maxFeePerGas),
      maxPriorityFeePerGas: AAUtils.normalizeHexQuantity(selected.maxPriorityFeePerGas)
    )
  }

  public func estimateUserOperationGas(_ userOperation: UserOperation) async throws -> UserOperation {
    let estimate: UserOperationGasEstimate = try await rpcClient.makeBundlerRpcCall(
      chainId: userOperation.chainId,
      method: "eth_estimateUserOperationGas",
      params: [AnyCodable(userOperation.rpcObject), AnyCodable(userOperation.entryPoint)],
      responseType: UserOperationGasEstimate.self
    )
    var op = userOperation
    op.applyGasEstimate(estimate)
    return op
  }

  public func getPaymasterStubData(_ userOperation: UserOperation) async throws -> PaymasterStubData {
    try await rpcClient.makePaymasterRpcCall(
      chainId: userOperation.chainId,
      method: "pm_getPaymasterStubData",
      params: [
        AnyCodable(userOperation.rpcObject),
        AnyCodable(userOperation.entryPoint),
        AnyCodable(AAUtils.normalizeHexQuantity(String(userOperation.chainId)))
      ],
      responseType: PaymasterStubData.self
    )
  }

  public func sponsorUserOperation(_ userOperation: UserOperation) async throws -> UserOperation {
    let _: PaymasterStubData = try await getPaymasterStubData(userOperation)
    let sponsored: SponsoredPaymasterData = try await rpcClient.makePaymasterRpcCall(
      chainId: userOperation.chainId,
      method: "pm_sponsorUserOperation",
      params: [
        AnyCodable(userOperation.rpcObject),
        AnyCodable(userOperation.entryPoint),
        AnyCodable(AAUtils.normalizeHexQuantity(String(userOperation.chainId)))
      ],
      responseType: SponsoredPaymasterData.self
    )
    var op = userOperation
    op.applyPaymaster(sponsored)
    return op
  }

  public func sendUserOperation(_ userOperation: UserOperation) async throws -> String {
    try await rpcClient.makeBundlerRpcCall(
      chainId: userOperation.chainId,
      method: "eth_sendUserOperation",
      params: [AnyCodable(userOperation.rpcObject), AnyCodable(userOperation.entryPoint)],
      responseType: String.self
    )
  }
}
