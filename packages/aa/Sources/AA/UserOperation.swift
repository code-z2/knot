import BigInt
import Foundation
import web3swift

public struct EIP7702Auth: Sendable, Codable, Equatable {
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

public struct PackedUserOperationForSignature: Sendable, Codable, Equatable {
  public let sender: String
  public let nonce: String
  public let initCodeHash: String
  public let callDataHash: String
  public let accountGasLimits: String
  public let preVerificationGas: String
  public let gasFees: String
  public let paymasterAndDataHash: String
}

public struct UserOperation: Sendable, Codable, Equatable {
  public var chainId: UInt64
  public var entryPoint: String
  public var sender: String
  public var nonce: String
  public var callData: String
  public var maxPriorityFeePerGas: String
  public var maxFeePerGas: String
  public var callGasLimit: String
  public var verificationGasLimit: String
  public var preVerificationGas: String
  public var paymaster: String
  public var paymasterData: String?
  public var paymasterPostOpGasLimit: String
  public var paymasterVerificationGasLimit: String
  public var signature: String
  public var eip7702Auth: EIP7702Auth?

  public init(
    chainId: UInt64,
    entryPoint: String = AAConstants.entryPointV09,
    sender: String,
    nonce: String,
    callData: String,
    maxPriorityFeePerGas: String = "0x0",
    maxFeePerGas: String = "0x0",
    callGasLimit: String = "0x0",
    verificationGasLimit: String = "0x0",
    preVerificationGas: String = "0x0",
    paymaster: String = "0x",
    paymasterData: String? = nil,
    paymasterPostOpGasLimit: String = "0x0",
    paymasterVerificationGasLimit: String = "0x0",
    signature: String = "0x",
    eip7702Auth: EIP7702Auth? = nil
  ) {
    self.chainId = chainId
    self.entryPoint = entryPoint
    self.sender = sender
    self.nonce = nonce
    self.callData = callData
    self.maxPriorityFeePerGas = maxPriorityFeePerGas
    self.maxFeePerGas = maxFeePerGas
    self.callGasLimit = callGasLimit
    self.verificationGasLimit = verificationGasLimit
    self.preVerificationGas = preVerificationGas
    self.paymaster = paymaster
    self.paymasterData = paymasterData
    self.paymasterPostOpGasLimit = paymasterPostOpGasLimit
    self.paymasterVerificationGasLimit = paymasterVerificationGasLimit
    self.signature = signature
    self.eip7702Auth = eip7702Auth
  }

  public func update(signature: Data) -> UserOperation {
    update(signature: "0x" + signature.toHexString())
  }

  public func update(signature: String) -> UserOperation {
    var copy = self
    copy.signature = AAUtils.normalizeHexBytes(signature)
    return copy
  }

  public mutating func setGasPrice(maxFeePerGas: String, maxPriorityFeePerGas: String) {
    self.maxFeePerGas = AAUtils.normalizeHexQuantity(maxFeePerGas)
    self.maxPriorityFeePerGas = AAUtils.normalizeHexQuantity(maxPriorityFeePerGas)
  }

  public mutating func applyGasEstimate(_ estimate: UserOperationGasEstimate) {
    if let callGasLimit = estimate.callGasLimit { self.callGasLimit = AAUtils.normalizeHexQuantity(callGasLimit) }
    if let verificationGasLimit = estimate.verificationGasLimit {
      self.verificationGasLimit = AAUtils.normalizeHexQuantity(verificationGasLimit)
    }
    if let preVerificationGas = estimate.preVerificationGas {
      self.preVerificationGas = AAUtils.normalizeHexQuantity(preVerificationGas)
    }
    if let paymasterVerificationGasLimit = estimate.paymasterVerificationGasLimit {
      self.paymasterVerificationGasLimit = AAUtils.normalizeHexQuantity(paymasterVerificationGasLimit)
    }
    if let paymasterPostOpGasLimit = estimate.paymasterPostOpGasLimit {
      self.paymasterPostOpGasLimit = AAUtils.normalizeHexQuantity(paymasterPostOpGasLimit)
    }
  }

  public mutating func applyPaymaster(_ sponsor: SponsoredPaymasterData) {
    self.paymaster = AAUtils.normalizeAddressOrEmpty(sponsor.paymaster)
    self.paymasterData = AAUtils.normalizeHexBytes(sponsor.paymasterData)
    self.paymasterVerificationGasLimit = AAUtils.normalizeHexQuantity(sponsor.paymasterVerificationGasLimit)
    self.paymasterPostOpGasLimit = AAUtils.normalizeHexQuantity(sponsor.paymasterPostOpGasLimit)
  }

  public func packForSignature() throws -> PackedUserOperationForSignature {
    let verificationGas = try AAUtils.parseQuantity(verificationGasLimit)
    let callGas = try AAUtils.parseQuantity(callGasLimit)
    let accountGasLimits = (verificationGas << 128) | callGas

    let maxPriority = try AAUtils.parseQuantity(maxPriorityFeePerGas)
    let maxFee = try AAUtils.parseQuantity(maxFeePerGas)
    let gasFees = (maxPriority << 128) | maxFee

    let initCodeHash = try self.initCodeHashForEip7702()
    let callDataHash = Data((try AAUtils.hexToData(callData)).sha3(.keccak256))
    let paymasterAndDataHash = try AAUtils.paymasterAndDataHash(buildPaymasterAndData())

    return PackedUserOperationForSignature(
      sender: AAUtils.normalizeAddressOrEmpty(sender),
      nonce: AAUtils.normalizeHexQuantity(nonce),
      initCodeHash: "0x" + initCodeHash.toHexString(),
      callDataHash: "0x" + callDataHash.toHexString(),
      accountGasLimits: AAUtils.wordHex(accountGasLimits),
      preVerificationGas: AAUtils.normalizeHexQuantity(preVerificationGas),
      gasFees: AAUtils.wordHex(gasFees),
      paymasterAndDataHash: "0x" + paymasterAndDataHash.toHexString()
    )
  }

  public func hash() throws -> Data {
    let packed = try packForSignature()
    let senderWord = try ABIWord.address(packed.sender)
    let nonceWord = try AAUtils.uintWord(packed.nonce)
    let initCodeHash = try AAUtils.wordData(packed.initCodeHash)
    let callDataHash = try AAUtils.wordData(packed.callDataHash)
    let accountGasLimits = try AAUtils.wordData(packed.accountGasLimits)
    let preVerificationGas = try AAUtils.uintWord(packed.preVerificationGas)
    let gasFees = try AAUtils.wordData(packed.gasFees)
    let paymasterAndDataHash = try AAUtils.wordData(packed.paymasterAndDataHash)
    let encoded =
      AAUtils.packedUserOpTypeHash +
      senderWord +
      nonceWord +
      initCodeHash +
      callDataHash +
      accountGasLimits +
      preVerificationGas +
      gasFees +
      paymasterAndDataHash
    let opStructHash = Data(encoded.sha3(.keccak256))
    let domain = try AAUtils.domainSeparator(chainId: chainId, entryPoint: entryPoint)
    return Data((Data([0x19, 0x01]) + domain + opStructHash).sha3(.keccak256))
  }

  public var rpcObject: [String: Any] {
    var object: [String: Any] = [
      "sender": AAUtils.normalizeAddressOrEmpty(sender),
      "nonce": AAUtils.normalizeHexQuantity(nonce),
      "factory": "0x",
      "factoryData": "0x",
      "callData": AAUtils.normalizeHexBytes(callData),
      "signature": AAUtils.normalizeHexBytes(signature),
      "maxFeePerGas": AAUtils.normalizeHexQuantity(maxFeePerGas),
      "maxPriorityFeePerGas": AAUtils.normalizeHexQuantity(maxPriorityFeePerGas),
      "callGasLimit": AAUtils.normalizeHexQuantity(callGasLimit),
      "verificationGasLimit": AAUtils.normalizeHexQuantity(verificationGasLimit),
      "preVerificationGas": AAUtils.normalizeHexQuantity(preVerificationGas),
      "paymaster": AAUtils.normalizeAddressOrEmpty(paymaster),
      "paymasterData": paymasterData.map(AAUtils.normalizeHexBytes) ?? "0x",
      "paymasterPostOpGasLimit": AAUtils.normalizeHexQuantity(paymasterPostOpGasLimit),
      "paymasterVerificationGasLimit": AAUtils.normalizeHexQuantity(paymasterVerificationGasLimit),
    ]
    if let eip7702Auth {
      object["eip7702Auth"] = eip7702Auth.rpcObject
    }
    return object
  }

  private func initCodeHashForEip7702() throws -> Data {
    guard let eip7702Auth else { throw AAError.missingEip7702Auth }
    let initCode = AAUtils.eip7702Marker
    let delegate = try AAUtils.addressData(eip7702Auth.address)
    if initCode.count <= 20 { return Data(delegate.sha3(.keccak256)) }
    let suffix = Data(initCode.dropFirst(20))
    return Data((delegate + suffix).sha3(.keccak256))
  }

  private func buildPaymasterAndData() throws -> Data {
    let paymasterAddress = AAUtils.normalizeAddressOrEmpty(paymaster)
    if paymasterAddress == "0x" || paymasterAddress == "0x0000000000000000000000000000000000000000" {
      return Data()
    }

    let address = try AAUtils.addressData(paymasterAddress)
    let verification = try AAUtils.uint128Data(paymasterVerificationGasLimit)
    let postOp = try AAUtils.uint128Data(paymasterPostOpGasLimit)
    let data = try AAUtils.hexToData(paymasterData ?? "0x")
    return address + verification + postOp + data
  }
}

public struct UserOperationGasPrice: Sendable, Codable, Equatable {
  public let maxFeePerGas: String
  public let maxPriorityFeePerGas: String
}

public struct UserOperationGasEstimate: Sendable, Codable, Equatable {
  public let preVerificationGas: String?
  public let verificationGasLimit: String?
  public let callGasLimit: String?
  public let paymasterVerificationGasLimit: String?
  public let paymasterPostOpGasLimit: String?
}

public struct PaymasterStubData: Sendable, Codable, Equatable {
  public let paymaster: String?
  public let paymasterData: String?
  public let paymasterVerificationGasLimit: String?
  public let paymasterPostOpGasLimit: String?
}

public struct SponsoredPaymasterData: Sendable, Codable, Equatable {
  public let paymaster: String
  public let paymasterData: String
  public let paymasterVerificationGasLimit: String
  public let paymasterPostOpGasLimit: String
}
