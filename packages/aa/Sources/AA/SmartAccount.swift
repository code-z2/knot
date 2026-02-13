import BigInt
import Foundation
import Passkey
import RPC
import Transactions
import web3swift

public enum SmartAccountError: Error {
  case invalidAddress(String)
  case invalidHex(String)
  case invalidBytes32Length(Int)
  case invalidUIntValue(String)
  case malformedRPCResponse(String)
  case missingConfiguration(key: String, chainId: UInt64)
  case emptyCalls
}

public struct OnchainCrossChainOrder: Sendable, Equatable {
  public let orderDataType: Data
  public let fillDeadline: UInt32
  public let orderData: Data

  public init(orderDataType: Data, fillDeadline: UInt32, orderData: Data) {
    self.orderDataType = orderDataType
    self.fillDeadline = fillDeadline
    self.orderData = orderData
  }
}

public struct InitializationConfig: Sendable, Equatable {
  public let accumulatorFactory: String
  public let wrappedNativeToken: String
  public let spokePool: String

  public init(accumulatorFactory: String, wrappedNativeToken: String, spokePool: String) {
    self.accumulatorFactory = accumulatorFactory
    self.wrappedNativeToken = wrappedNativeToken
    self.spokePool = spokePool
  }
}

public enum SmartAccount {
  /// Explicit-signature account execution helpers.
  public enum ExecuteAuthorized {
    public static func hashSingle(
      account: String,
      chainId: UInt64,
      call: Call,
      nonce: UInt64,
      deadline: UInt64
    ) throws -> Data {
      let targetWord = try ABIWord.address(call.to)
      let valueWord = try ABIWord.uint(call.valueWei)
      let data = try AAUtils.hexToData(call.dataHex)
      let dataHashWord = try ABIWord.bytes32(Data(data.sha3(.keccak256)))
      let nonceWord = ABIWord.uint(BigUInt(nonce))
      let deadlineWord = ABIWord.uint(BigUInt(deadline))

      let structHash = Data(
        (AAUtils.executeTypeHash + targetWord + valueWord + dataHashWord + nonceWord + deadlineWord).sha3(
          .keccak256))
      let domain = try AAUtils.accountDomainSeparator(chainId: chainId, account: account)
      return AAUtils.hashTypedDataV4(domainSeparator: domain, structHash: structHash)
    }

    public static func hashBatch(
      account: String,
      chainId: UInt64,
      calls: [Call],
      nonce: UInt64,
      deadline: UInt64
    ) throws -> Data {
      let callsEncoded = try ABIEncoder.encodeCallTupleArray(calls)
      let callsHashWord = try ABIWord.bytes32(Data(callsEncoded.sha3(.keccak256)))
      let nonceWord = ABIWord.uint(BigUInt(nonce))
      let deadlineWord = ABIWord.uint(BigUInt(deadline))

      let structHash = Data(
        (AAUtils.executeBatchTypeHash + callsHashWord + nonceWord + deadlineWord).sha3(.keccak256))
      let domain = try AAUtils.accountDomainSeparator(chainId: chainId, account: account)
      return AAUtils.hashTypedDataV4(domainSeparator: domain, structHash: structHash)
    }

    public static func encodeSingle(
      call: Call,
      nonce: UInt64,
      deadline: UInt64,
      signature: Data
    ) throws -> Data {
      let callTuple = try ABIEncoder.encodeCallTuple(call)
      let nonceWord = ABIWord.uint(BigUInt(nonce))
      let deadlineWord = ABIWord.uint(BigUInt(deadline))
      let signatureBytes = ABIEncoder.encodeBytes(signature)

      return ABIEncoder.functionCallOrdered(
        signature: "execute((address,uint256,bytes),uint256,uint256,bytes)",
        arguments: [
          .dynamic(callTuple),
          .word(nonceWord),
          .word(deadlineWord),
          .dynamic(signatureBytes),
        ]
      )
    }

    public static func encodeBatch(
      calls: [Call],
      nonce: UInt64,
      deadline: UInt64,
      signature: Data
    ) throws -> Data {
      let callsArray = try ABIEncoder.encodeCallTupleArray(calls)
      let nonceWord = ABIWord.uint(BigUInt(nonce))
      let deadlineWord = ABIWord.uint(BigUInt(deadline))
      let signatureBytes = ABIEncoder.encodeBytes(signature)

      return ABIEncoder.functionCallOrdered(
        signature: "executeBatch((address,uint256,bytes)[],uint256,uint256,bytes)",
        arguments: [
          .dynamic(callsArray),
          .word(nonceWord),
          .word(deadlineWord),
          .dynamic(signatureBytes),
        ]
      )
    }
  }

  public enum CrossChainOrder {
    public static func encodeCall(order: OnchainCrossChainOrder, signature: Data) throws -> Data {
      let orderTuple = try encodeOrderTuple(order)
      let signatureBytes = ABIEncoder.encodeBytes(signature)
      return ABIEncoder.functionCallOrdered(
        signature: "executeCrossChainOrder((bytes32,uint32,bytes),bytes)",
        arguments: [
          .dynamic(orderTuple),
          .dynamic(signatureBytes),
        ]
      )
    }

    private static func encodeOrderTuple(_ order: OnchainCrossChainOrder) throws -> Data {
      let orderType = try ABIWord.bytes32(order.orderDataType)
      let fillDeadline = ABIWord.uint(BigUInt(order.fillDeadline))
      let orderDataOffset = ABIWord.uint(BigUInt(96))
      let orderData = ABIEncoder.encodeBytes(order.orderData)
      return orderType + fillDeadline + orderDataOffset + orderData
    }
  }

  public enum Initialize {
    public static func initSignatureDigest(
      account: String,
      chainId: UInt64,
      passkeyPublicKey: PasskeyPublicKey,
      config: InitializationConfig
    ) throws -> Data {
      let chainWord = ABIWord.uint(BigUInt(chainId))
      let accountWord = try ABIWord.address(account)
      let qx = try ABIWord.bytes32(passkeyPublicKey.x)
      let qy = try ABIWord.bytes32(passkeyPublicKey.y)
      let accumulatorFactory = try ABIWord.address(config.accumulatorFactory)
      let wrappedNativeToken = try ABIWord.address(config.wrappedNativeToken)
      let spokePool = try ABIWord.address(config.spokePool)
      return Data((chainWord + accountWord + qx + qy + accumulatorFactory + wrappedNativeToken + spokePool).sha3(.keccak256))
    }

    public static func encodeCall(
      passkeyPublicKey: PasskeyPublicKey,
      config: InitializationConfig,
      initSignature: Data
    ) throws -> Data {
      let qx = try ABIWord.bytes32(passkeyPublicKey.x)
      let qy = try ABIWord.bytes32(passkeyPublicKey.y)
      let accumulatorFactory = try ABIWord.address(config.accumulatorFactory)
      let wrappedNativeToken = try ABIWord.address(config.wrappedNativeToken)
      let spokePool = try ABIWord.address(config.spokePool)
      let signatureBytes = ABIEncoder.encodeBytes(initSignature)

      return ABIEncoder.functionCall(
        signature: "initialize(bytes32,bytes32,address,address,address,bytes)",
        words: [qx, qy, accumulatorFactory, wrappedNativeToken, spokePool],
        dynamic: [signatureBytes]
      )
    }

    public static func asCall(
      account: String,
      passkeyPublicKey: PasskeyPublicKey,
      config: InitializationConfig,
      initSignature: Data
    ) throws -> Call {
      Call(
        to: account,
        dataHex: "0x" + (try encodeCall(passkeyPublicKey: passkeyPublicKey, config: config, initSignature: initSignature)).toHexString(),
        valueWei: "0"
      )
    }
  }

  public enum AccumulatorFactory {
    public static func encodeComputeAddressCall(userAccount: String) throws -> Data {
      let userWord = try ABIWord.address(userAccount)
      return ABIEncoder.functionCall(
        signature: "computeAddress(address)",
        words: [userWord],
        dynamic: []
      )
    }
  }

  public enum IsValidSignature {
    public static func encodeCall(hash: Data, signature: Data) throws -> Data {
      let hashWord = try ABIWord.bytes32(hash)
      let signatureBytes = ABIEncoder.encodeBytes(signature)
      return ABIEncoder.functionCall(
        signature: "isValidSignature(bytes32,bytes)",
        words: [hashWord],
        dynamic: [signatureBytes]
      )
    }
  }
}

public actor SmartAccountClient {
  private let rpcClient: RPCClient
  private static let validSignatureSelector = "0x1626ba7e"

  public init(rpcClient: RPCClient = RPCClient()) {
    self.rpcClient = rpcClient
  }

  public func isDeployed(account: String, chainId: UInt64) async throws -> Bool {
    let code = try await rpcClient.getCode(chainId: chainId, address: account)
    let normalized = code.lowercased()
    return normalized != "0x" && normalized != "0x0"
  }

  public func getTransactionCount(account: String, chainId: UInt64, blockTag: String = "pending") async throws -> UInt64 {
    let nonceHex: String = try await rpcClient.makeRpcCall(
      chainId: chainId,
      method: "eth_getTransactionCount",
      params: [AnyCodable(account), AnyCodable(blockTag)],
      responseType: String.self
    )
    let clean = nonceHex.replacingOccurrences(of: "0x", with: "")
    return UInt64(clean, radix: 16) ?? 0
  }

  public func isValidSignature(
    account: String,
    chainId: UInt64,
    hash: Data,
    passkeySignature: PasskeySignature
  ) async throws -> Bool {
    let authBytes = try passkeySignature.webAuthnAuthBytes(payload: hash)
    let calldata = try SmartAccount.IsValidSignature.encodeCall(hash: hash, signature: authBytes)
    let response = try await ethCallHex(account: account, chainId: chainId, data: calldata)
    return response.lowercased().hasPrefix(Self.validSignatureSelector)
  }

  public func computeAccumulatorAddress(
    account: String,
    chainId: UInt64
  ) async throws -> String {
    let accumulatorFactory = AAConstants.accumulatorFactoryAddress
    let data = try SmartAccount.AccumulatorFactory.encodeComputeAddressCall(
      userAccount: account
    )
    let response = try await ethCallHex(account: accumulatorFactory, chainId: chainId, data: data)
    return try ABIUtils.decodeAddressFromABIWord(response)
  }

  public func simulateCall(
    account: String,
    chainId: UInt64,
    from: String,
    data: Data,
    valueHex: String = "0x0"
  ) async throws {
    let txObject: [String: Any] = [
      "to": account,
      "from": from,
      "data": "0x" + data.toHexString(),
      "value": AAUtils.normalizeHexQuantity(valueHex),
    ]
    let _: String = try await rpcClient.makeRpcCall(
      chainId: chainId,
      method: "eth_call",
      params: [AnyCodable(txObject), AnyCodable("latest")],
      responseType: String.self
    )
  }

  public func estimateGas(
    account: String,
    chainId: UInt64,
    from: String,
    data: Data,
    valueHex: String = "0x0"
  ) async throws -> UInt64 {
    let txObject: [String: Any] = [
      "to": account,
      "from": from,
      "data": "0x" + data.toHexString(),
      "value": AAUtils.normalizeHexQuantity(valueHex),
    ]
    let gasHex: String = try await rpcClient.makeRpcCall(
      chainId: chainId,
      method: "eth_estimateGas",
      params: [AnyCodable(txObject)],
      responseType: String.self
    )
    let clean = gasHex.replacingOccurrences(of: "0x", with: "")
    return UInt64(clean, radix: 16) ?? 0
  }

  private func ethCallHex(account: String, chainId: UInt64, data: Data) async throws -> String {
    let txObject: [String: Any] = [
      "to": account,
      "data": "0x" + data.toHexString(),
    ]
    let response: String = try await rpcClient.makeRpcCall(
      chainId: chainId,
      method: "eth_call",
      params: [AnyCodable(txObject), AnyCodable("latest")],
      responseType: String.self
    )
    return response
  }
}
