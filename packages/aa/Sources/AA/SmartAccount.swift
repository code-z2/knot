import BigInt
import Foundation
import Passkey
import RPC
import Transactions
import Web3Core
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

public enum SmartAccount {
  public enum ExecuteSingle {
    public static func encodeCall(_ call: Call) throws -> Data {
      let target = try ABIWord.address(call.to)
      let value = try ABIWord.uint(call.valueWei)
      let calldata = try ABIWord.bytes(call.dataHex)
      return ABIEncoder.functionCall(
        signature: "execute(address,uint256,bytes)",
        words: [target, value],
        dynamic: [calldata]
      )
    }
  }

  public enum Execute {
    public static func encodeCall(_ calls: [Call]) throws -> Data {
      guard !calls.isEmpty else { throw SmartAccountError.emptyCalls }
      if calls.count == 1, let call = calls.first {
        return try ExecuteSingle.encodeCall(call)
      }
      return try ExecuteBatch.encodeCall(calls)
    }
  }

  public enum ExecuteBatch {
    public static func encodeCall(_ calls: [Call]) throws -> Data {
      let encodedArray = try ABIEncoder.encodeCallTupleArray(calls)
      return ABIEncoder.functionCall(
        signature: "executeBatch((address,uint256,bytes)[])",
        words: [],
        dynamic: [encodedArray]
      )
    }
  }

  public enum ExecuteChainCalls {
    public static func encodeCall(chainCallsBlob: Data) -> Data {
      ABIEncoder.functionCall(
        signature: "executeChainCalls(bytes)",
        words: [],
        dynamic: [ABIEncoder.encodeBytes(chainCallsBlob)]
      )
    }

    public static func encodeCall(chainCalls: [ChainCalls]) throws -> Data {
      let blob = try ABIEncoder.encodeChainCallsArray(chainCalls)
      return encodeCall(chainCallsBlob: blob)
    }
  }

  public enum RegisterJob {
    public static func encodeCall(jobId: Data, accumulator: String) throws -> Data {
      let jobIdWord = try ABIWord.bytes32(jobId)
      let accumulatorWord = try ABIWord.address(accumulator)
      return ABIEncoder.functionCall(
        signature: "registerJob(bytes32,address)",
        words: [jobIdWord, accumulatorWord],
        dynamic: []
      )
    }

    public static func asCall(account: String, jobId: Data, accumulator: String) throws -> Call {
      Call(
        to: account,
        dataHex: "0x" + (try encodeCall(jobId: jobId, accumulator: accumulator)).toHexString(),
        valueWei: "0"
      )
    }
  }

  public enum Initialize {
    public static func encodeCall(passkeyPublicKey: PasskeyPublicKey) throws -> Data {
      let qx = try ABIWord.bytes32(passkeyPublicKey.x)
      let qy = try ABIWord.bytes32(passkeyPublicKey.y)
      return ABIEncoder.functionCall(
        signature: "initialize(bytes32,bytes32)",
        words: [qx, qy],
        dynamic: []
      )
    }

    public static func asCall(account: String, passkeyPublicKey: PasskeyPublicKey) throws -> Call {
      Call(
        to: account,
        dataHex: "0x" + (try encodeCall(passkeyPublicKey: passkeyPublicKey)).toHexString(),
        valueWei: "0"
      )
    }
  }

  public enum AccumulatorFactory {
    public static func encodeComputeAddressCall(userAccount: String, messenger: String) throws -> Data {
      let userWord = try ABIWord.address(userAccount)
      let messengerWord = try ABIWord.address(messenger)
      return ABIEncoder.functionCall(
        signature: "computeAddress(address,address)",
        words: [userWord, messengerWord],
        dynamic: []
      )
    }

    public static func encodeDeployCall(messenger: String) throws -> Data {
      let messengerWord = try ABIWord.address(messenger)
      return ABIEncoder.functionCall(
        signature: "deploy(address)",
        words: [messengerWord],
        dynamic: []
      )
    }

    public static func deployCall(factory: String, messenger: String) throws -> Call {
      Call(
        to: factory,
        dataHex: "0x" + (try encodeDeployCall(messenger: messenger)).toHexString(),
        valueWei: "0"
      )
    }
  }

  public enum GetNonce {
    public static func encodeCall() -> Data {
      ABIEncoder.functionCall(signature: "getNonce()", words: [], dynamic: [])
    }

    public static func encodeCall(key: UInt64) -> Data {
      ABIEncoder.functionCall(
        signature: "getNonce(uint192)",
        words: [ABIWord.uint(BigUInt(key))],
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

  public func getNonce(account: String, chainId: UInt64) async throws -> BigUInt {
    try await ethCallBigUInt(account: account, chainId: chainId, data: SmartAccount.GetNonce.encodeCall())
  }

  public func getNonce(account: String, chainId: UInt64, key: UInt64) async throws -> BigUInt {
    try await ethCallBigUInt(account: account, chainId: chainId, data: SmartAccount.GetNonce.encodeCall(key: key))
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
    let accumulatorFactory = try AAConstants.accumulatorFactoryAddress(chainId: chainId)
    let messenger = try AAConstants.messengerAddress(chainId: chainId)
    let data = try SmartAccount.AccumulatorFactory.encodeComputeAddressCall(
      userAccount: account,
      messenger: messenger
    )
    let response = try await ethCallHex(account: accumulatorFactory, chainId: chainId, data: data)
    return try ABIUtils.decodeAddressFromABIWord(response)
  }

  public func buildExecutePayload(
    account: String,
    chainId: UInt64,
    passkeyPublicKey: PasskeyPublicKey,
    calls: [Call]
  ) async throws -> ExecuteBuildResult {
    guard !calls.isEmpty else { throw SmartAccountError.emptyCalls }
    let accumulatorFactory = try AAConstants.accumulatorFactoryAddress(chainId: chainId)
    let messenger = try AAConstants.messengerAddress(chainId: chainId)

    var prelude: [Call] = []

    async let accountDeployedTask = isDeployed(account: account, chainId: chainId)
    async let accumulatorAddressTask = computeAccumulatorAddress(
      account: account,
      chainId: chainId
    )
    let accountDeployed = try await accountDeployedTask
    let accumulatorAddress = try await accumulatorAddressTask

    if !accountDeployed {
      prelude.insert(try SmartAccount.Initialize.asCall(account: account, passkeyPublicKey: passkeyPublicKey), at: 0)
    }

    if try await !isDeployed(account: accumulatorAddress, chainId: chainId) {
      prelude.append(
        try SmartAccount.AccumulatorFactory.deployCall(
          factory: accumulatorFactory,
          messenger: messenger
        )
      )
    }

    let finalCalls = prelude + calls
    let payload = try SmartAccount.Execute.encodeCall(finalCalls)
    return ExecuteBuildResult(payload: payload, calls: finalCalls)
  }

  public func execute(
    account: String,
    chainId: UInt64,
    passkeyPublicKey: PasskeyPublicKey,
    calls: [Call]
  ) async throws -> ExecuteBuildResult {
    try await buildExecutePayload(
      account: account,
      chainId: chainId,
      passkeyPublicKey: passkeyPublicKey,
      calls: calls
    )
  }

  public func buildExecuteChainCallsPayload(
    account: String,
    destinationChainId: UInt64,
    jobId: Data,
    passkeyPublicKey: PasskeyPublicKey,
    chainCalls: [ChainCalls]
  ) async throws -> ExecuteChainCallsBuildResult {
    guard !chainCalls.isEmpty else { throw SmartAccountError.emptyCalls }

    var destination: ChainCalls?
    var others: [ChainCalls] = []

    for bundle in chainCalls {
      let rebuilt = try await buildBundleWithPrelude(
        account: account,
        bundle: bundle,
        destinationChainId: destinationChainId,
        jobId: jobId,
        passkeyPublicKey: passkeyPublicKey
      )

      if rebuilt.chainId == destinationChainId {
        destination = rebuilt
      } else {
        others.append(rebuilt)
      }
    }

    if destination == nil {
      // If destination chain isn't provided, create one with only required destination prelude.
      destination = try await buildBundleWithPrelude(
        account: account,
        bundle: ChainCalls(chainId: destinationChainId, calls: []),
        destinationChainId: destinationChainId,
        jobId: jobId,
        passkeyPublicKey: passkeyPublicKey
      )
    }

    guard let destination else {
      throw SmartAccountError.malformedRPCResponse("Failed to build destination chain bundle")
    }

    let payload = [destination] + others
    return ExecuteChainCallsBuildResult(
      payload: payload,
      destinationChainCall: destination,
      otherChainCalls: others
    )
  }

  public func executeChainCalls(
    account: String,
    destinationChainId: UInt64,
    jobId: Data,
    passkeyPublicKey: PasskeyPublicKey,
    chainCalls: [ChainCalls]
  ) async throws -> ExecuteChainCallsBuildResult {
    try await buildExecuteChainCallsPayload(
      account: account,
      destinationChainId: destinationChainId,
      jobId: jobId,
      passkeyPublicKey: passkeyPublicKey,
      chainCalls: chainCalls
    )
  }

  private func ethCallBigUInt(account: String, chainId: UInt64, data: Data) async throws -> BigUInt {
    let response = try await ethCallHex(account: account, chainId: chainId, data: data)
    let valueHex = response.replacingOccurrences(of: "0x", with: "")
    return BigUInt(valueHex, radix: 16) ?? .zero
  }

  private func ethCallHex(account: String, chainId: UInt64, data: Data) async throws -> String {
    let txObject: [String: Any] = [
      "to": account,
      "data": "0x" + data.toHexString()
    ]
    let response: String = try await rpcClient.makeRpcCall(
      chainId: chainId,
      method: "eth_call",
      params: [AnyCodable(txObject), AnyCodable("latest")],
      responseType: String.self
    )
    return response
  }

  private func buildBundleWithPrelude(
    account: String,
    bundle: ChainCalls,
    destinationChainId: UInt64,
    jobId: Data,
    passkeyPublicKey: PasskeyPublicKey
  ) async throws -> ChainCalls {
    var prelude: [Call] = []

    if try await !isDeployed(account: account, chainId: bundle.chainId) {
      // initialize must remain the first prelude call whenever included.
      prelude.insert(
        try SmartAccount.Initialize.asCall(account: account, passkeyPublicKey: passkeyPublicKey),
        at: 0
      )
    }

    if bundle.chainId == destinationChainId {
      let accumulatorFactory = try AAConstants.accumulatorFactoryAddress(chainId: bundle.chainId)
      let messenger = try AAConstants.messengerAddress(chainId: bundle.chainId)
      let accumulatorAddress = try await computeAccumulatorAddress(account: account, chainId: bundle.chainId)

      if try await !isDeployed(account: accumulatorAddress, chainId: bundle.chainId) {
        prelude.append(
          try SmartAccount.AccumulatorFactory.deployCall(
            factory: accumulatorFactory,
            messenger: messenger
          )
        )
      }

      // Destination chain must always register the job before business calls.
      prelude.append(
        try SmartAccount.RegisterJob.asCall(
          account: account,
          jobId: jobId,
          accumulator: accumulatorAddress
        )
      )
    }

    return ChainCalls(chainId: bundle.chainId, calls: prelude + bundle.calls)
  }

}

public struct ExecuteBuildResult: Sendable, Equatable {
  public let payload: Data
  public let calls: [Call]

  public init(payload: Data, calls: [Call]) {
    self.payload = payload
    self.calls = calls
  }
}

public struct ExecuteChainCallsBuildResult: Sendable, Equatable {
  public let payload: [ChainCalls]
  public let destinationChainCall: ChainCalls
  public let otherChainCalls: [ChainCalls]

  public init(payload: [ChainCalls], destinationChainCall: ChainCalls, otherChainCalls: [ChainCalls]) {
    self.payload = payload
    self.destinationChainCall = destinationChainCall
    self.otherChainCalls = otherChainCalls
  }
}
