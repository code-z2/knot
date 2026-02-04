import Foundation
import BigInt
import Security
import Web3Core
import Transactions
import web3swift

extension ENSClient {
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
}
