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
    case .invalidEip7702SenderCodePrefix(let value):
      return "Invalid EIP-7702 sender code prefix: \(value)"
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
      struct SlowPrice: Decodable {
        let maxFeePerGas: String
        let maxPriorityFeePerGas: String
      }
      let slow: SlowPrice?
      let standard: SlowPrice?
      let fast: SlowPrice?
    }

    print("[AACore] 🟢 getUserOperationGasPrice called for chain \(chainId)")

    // 1. Try Gelato Oracle
    do {
      print("[AACore] → attempting gelato_getUserOperationGasPrice")
      let result: GelatoGasPriceEnvelope = try await rpcClient.makeBundlerRpcCall(
        chainId: chainId,
        method: "gelato_getUserOperationGasPrice",
        params: [],
        responseType: GelatoGasPriceEnvelope.self
      )

      if let selected = result.standard ?? result.fast ?? result.slow {
        print("[AACore] ✅ Gelato gas price: maxFee=\(selected.maxFeePerGas)")
        return UserOperationGasPrice(
          maxFeePerGas: AAUtils.normalizeHexQuantity(selected.maxFeePerGas),
          maxPriorityFeePerGas: AAUtils.normalizeHexQuantity(selected.maxPriorityFeePerGas)
        )
      }
      print("[AACore] ⚠️ Gelato oracle returned no price tiers. Falling back...")
    } catch {
      print("[AACore] ⚠️ Gelato oracle failed: \(error). Falling back to eth_gasPrice...")
    }

    // 2. Fallback to Standard RPC
    do {
      let gasPriceHex: String = try await rpcClient.makeRpcCall(
        chainId: chainId,
        method: "eth_gasPrice",
        params: [],
        responseType: String.self
      )
      print("[AACore] ✅ Fallback gas price: \(gasPriceHex)")
      let normalized = AAUtils.normalizeHexQuantity(gasPriceHex)
      return UserOperationGasPrice(
        maxFeePerGas: normalized,
        maxPriorityFeePerGas: normalized  // Simple legacy fallback
      )
    } catch {
      print("[AACore] ❌ Gas price estimation failed completely: \(error)")
      throw error
    }
  }

  public func estimateUserOperationGas(_ userOperation: UserOperation) async throws -> UserOperation
  {
    print("[AACore] → eth_estimateUserOperationGas (chain \(userOperation.chainId))")
    let estimate: UserOperationGasEstimate = try await rpcClient.makeBundlerRpcCall(
      chainId: userOperation.chainId,
      method: "eth_estimateUserOperationGas",
      params: [AnyCodable(userOperation.rpcObject), AnyCodable(userOperation.entryPoint)],
      responseType: UserOperationGasEstimate.self
    )
    print("[AACore] ✅ gas estimated")
    var op = userOperation
    op.applyGasEstimate(estimate)
    return op
  }

  public func getPaymasterStubData(_ userOperation: UserOperation) async throws -> PaymasterStubData
  {
    print("[AACore] → pm_getPaymasterStubData (chain \(userOperation.chainId))")
    let result = try await rpcClient.makePaymasterRpcCall(
      chainId: userOperation.chainId,
      method: "pm_getPaymasterStubData",
      params: [
        AnyCodable(userOperation.rpcObject),
        AnyCodable(userOperation.entryPoint),
        AnyCodable(AAUtils.normalizeHexQuantity(String(userOperation.chainId))),
      ],
      responseType: PaymasterStubData.self
    )
    print("[AACore] ✅ paymaster stub data received")
    return result
  }

  public func sponsorUserOperation(_ userOperation: UserOperation) async throws -> UserOperation {
    let _: PaymasterStubData = try await getPaymasterStubData(userOperation)
    print("[AACore] → pm_sponsorUserOperation (chain \(userOperation.chainId))")
    let sponsored: SponsoredPaymasterData = try await rpcClient.makePaymasterRpcCall(
      chainId: userOperation.chainId,
      method: "pm_sponsorUserOperation",
      params: [
        AnyCodable(userOperation.rpcObject),
        AnyCodable(userOperation.entryPoint),
        AnyCodable(AAUtils.normalizeHexQuantity(String(userOperation.chainId))),
      ],
      responseType: SponsoredPaymasterData.self
    )
    print("[AACore] ✅ sponsored")
    var op = userOperation
    op.applyPaymaster(sponsored)
    return op
  }

  public func sendUserOperation(_ userOperation: UserOperation) async throws -> String {
    print(
      "[AACore] Sending Async UserOp. ChainID: \(userOperation.chainId). EntryPoint: \(userOperation.entryPoint)"
    )
    // print("[AACore] Payload: \(userOperation.rpcObject)") // Uncomment for full payload debug
    do {
      let hash = try await rpcClient.makeBundlerRpcCall(
        chainId: userOperation.chainId,
        method: "eth_sendUserOperation",
        params: [AnyCodable(userOperation.rpcObject), AnyCodable(userOperation.entryPoint)],
        responseType: String.self
      )
      print("[AACore] Async send success -> \(hash)")
      return hash
    } catch {
      print("[AACore] Async send failed: \(error)")
      throw error
    }
  }

  public func sendUserOperationSync(_ userOperation: UserOperation) async throws -> String {
    print(
      "[AACore] Sending Sync UserOp. ChainID: \(userOperation.chainId). EntryPoint: \(userOperation.entryPoint)"
    )
    do {
      let hash = try await rpcClient.makeBundlerRpcCall(
        chainId: userOperation.chainId,
        method: "eth_sendUserOperationSync",
        params: [AnyCodable(userOperation.rpcObject), AnyCodable(userOperation.entryPoint)],
        responseType: String.self
      )
      print("[AACore] Sync send success -> \(hash)")
      return hash
    } catch {
      print("[AACore] Sync send failed: \(error)")
      throw error
    }
  }
}
