import Foundation
import BigInt
import Security
import Web3Core
import Transactions
import web3swift

struct ENSResolverContext {
  let normalizedName: String
  let web3: Web3
  let resolverAddress: EthereumAddress
  let nodeHash: Data
}

extension ENSClient {
  static let universalResolverABI = """
  [{"inputs":[{"internalType":"bytes","name":"name","type":"bytes"}],"name":"findResolver","outputs":[{"internalType":"address","name":"resolver","type":"address"},{"internalType":"bytes32","name":"node","type":"bytes32"},{"internalType":"uint256","name":"resolverOffset","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes","name":"name","type":"bytes"},{"internalType":"bytes","name":"data","type":"bytes"}],"name":"resolve","outputs":[{"internalType":"bytes","name":"","type":"bytes"}],"stateMutability":"view","type":"function"}]
  """

  static let zeroAddressHex = "0x0000000000000000000000000000000000000000"

  static func normalizedENSName(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  static func ethLabel(from value: String) -> String {
    let normalized = normalizedENSName(value)
    if normalized.hasSuffix(".eth") {
      return String(normalized.dropLast(4))
    }
    return normalized
  }

  static func reverseNode(for address: EthereumAddress) -> String {
    let trimmed = address.address.lowercased().replacingOccurrences(of: "0x", with: "")
    return "\(trimmed).addr.reverse"
  }

  static func secretHex(from providedSecret: String?) -> String {
    if let providedSecret,
      let secret = Data.fromHex(providedSecret),
      secret.count == 32
    {
      return secret.toHexString().addHexPrefix()
    }

    var random = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, random.count, &random)
    return Data(random).toHexString().addHexPrefix()
  }

  static func dnsEncodedName(_ name: String) -> Data? {
    let normalized = normalizedENSName(name)
    guard !normalized.isEmpty else { return nil }

    var encoded = Data()
    let labels = normalized.split(separator: ".", omittingEmptySubsequences: false)
    guard !labels.isEmpty else { return nil }

    for label in labels {
      let bytes = Array(label.utf8)
      guard bytes.count <= 63 else { return nil }
      encoded.append(UInt8(bytes.count))
      encoded.append(contentsOf: bytes)
    }

    encoded.append(0x00)
    return encoded
  }

  static func parseAddress(_ any: Any?) -> EthereumAddress? {
    if let address = any as? EthereumAddress {
      return address
    }
    if let string = any as? String {
      return EthereumAddress(string)
    }
    return nil
  }

  static func normalizedBytes32(_ value: Data) -> Data {
    if value.count == 32 { return value }
    if value.count > 32 { return Data(value.suffix(32)) }
    return Data(repeating: 0, count: 32 - value.count) + value
  }

  static func abiDecodeAddress(from data: Data) -> EthereumAddress? {
    guard data.count >= 32 else { return nil }
    let addressBytes = Data(data.suffix(20))
    return EthereumAddress(addressBytes.toHexString().addHexPrefix())
  }

  static func abiDecodeString(from data: Data) -> String? {
    guard data.count >= 64 else { return nil }
    guard let offset = BigUInt(Data(data[0..<32]).toHexString(), radix: 16) else { return nil }
    let offsetInt = Int(offset)
    guard offsetInt >= 0, offsetInt + 32 <= data.count else { return nil }

    let lengthRange = offsetInt..<(offsetInt + 32)
    guard let length = BigUInt(Data(data[lengthRange]).toHexString(), radix: 16) else { return nil }
    let lengthInt = Int(length)
    let contentStart = offsetInt + 32
    let contentEnd = contentStart + lengthInt
    guard contentStart >= 0, contentEnd <= data.count else { return nil }

    return String(data: data[contentStart..<contentEnd], encoding: .utf8)
  }

  func makeWritePayload(
    web3: Web3,
    abi: String,
    to: EthereumAddress,
    method: String,
    parameters: [Any],
    valueWei: BigUInt = .zero
  ) throws -> Call {
    guard let contract = web3.contract(abi, at: to, abiVersion: 2) else {
      throw Web3Error.transactionSerializationError
    }
    guard let op = contract.createWriteOperation(method, parameters: parameters) else {
      throw Web3Error.transactionSerializationError
    }
    let data = op.transaction.data
    return Call(
      to: to.address,
      dataHex: data.toHexString().addHexPrefix(),
      valueWei: valueWei.description
    )
  }

  func makeReadResult(
    web3: Web3,
    abi: String,
    to: EthereumAddress,
    method: String,
    parameters: [Any] = []
  ) async throws -> [String: Any] {
    guard let contract = web3.contract(abi, at: to, abiVersion: 2) else {
      throw Web3Error.transactionSerializationError
    }
    guard let op = contract.createReadOperation(method, parameters: parameters) else {
      throw Web3Error.transactionSerializationError
    }
    return try await op.callContractMethod()
  }

  func makeCallData(
    web3: Web3,
    abi: String,
    method: String,
    parameters: [Any]
  ) throws -> Data {
    guard let placeholderAddress = EthereumAddress(configuration.universalResolverAddress) else {
      throw ENSError.invalidAddress(configuration.universalResolverAddress)
    }
    guard let contract = web3.contract(abi, at: placeholderAddress, abiVersion: 2) else {
      throw Web3Error.transactionSerializationError
    }
    guard let op = contract.createWriteOperation(method, parameters: parameters) else {
      throw Web3Error.transactionSerializationError
    }
    return op.transaction.data
  }

  func universalResolve(
    web3: Web3,
    normalizedName: String,
    callData: Data
  ) async throws -> Data {
    guard let universalResolverAddress = EthereumAddress(configuration.universalResolverAddress) else {
      throw ENSError.invalidAddress(configuration.universalResolverAddress)
    }
    guard let dnsName = Self.dnsEncodedName(normalizedName) else {
      throw ENSError.invalidName
    }

    let result = try await makeReadResult(
      web3: web3,
      abi: Self.universalResolverABI,
      to: universalResolverAddress,
      method: "resolve",
      parameters: [dnsName, callData]
    )

    if let bytes = result["0"] as? Data {
      return bytes
    }
    if let bytes = result[""] as? Data {
      return bytes
    }
    throw ENSError.missingResult("resolve")
  }

  func universalResolverContext(forName name: String) async throws -> ENSResolverContext {
    let normalizedName = Self.normalizedENSName(name)
    guard !normalizedName.isEmpty else { throw ENSError.invalidName }

    let web3 = try await rpcClient.getWeb3Client(chainId: configuration.chainID)
    guard
      let universalResolverAddress = EthereumAddress(configuration.universalResolverAddress),
      let dnsName = Self.dnsEncodedName(normalizedName)
    else {
      throw ENSError.invalidAddress(configuration.universalResolverAddress)
    }

    let result = try await makeReadResult(
      web3: web3,
      abi: Self.universalResolverABI,
      to: universalResolverAddress,
      method: "findResolver",
      parameters: [dnsName]
    )

    guard let resolverAddress = Self.parseAddress(result["0"] ?? result["resolver"]) else {
      throw ENSError.ensUnavailable
    }
    if resolverAddress.address.lowercased() == Self.zeroAddressHex {
      throw ENSError.ensUnavailable
    }

    let nodeHash = (result["1"] as? Data) ?? (result["node"] as? Data) ?? NameHash.nameHash(normalizedName)
    guard let nodeHash else { throw ENSError.invalidName }

    return ENSResolverContext(
      normalizedName: normalizedName,
      web3: web3,
      resolverAddress: resolverAddress,
      nodeHash: Self.normalizedBytes32(nodeHash)
    )
  }
}
