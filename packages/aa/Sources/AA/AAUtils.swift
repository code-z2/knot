import BigInt
import Foundation
import web3swift

enum AAUtils {
  static let packedUserOpTypeHash = Data(
    "PackedUserOperation(address sender,uint256 nonce,bytes initCode,bytes callData,bytes32 accountGasLimits,uint256 preVerificationGas,bytes32 gasFees,bytes paymasterAndData)"
      .utf8
  ).sha3(.keccak256)
  static let eip712DomainTypeHash = Data(
    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)".utf8
  ).sha3(.keccak256)
  static let domainNameHash = Data("ERC4337".utf8).sha3(.keccak256)
  static let domainVersionHash = Data("1".utf8).sha3(.keccak256)
  static let eip7702Marker = Data([0x77, 0x02]) + Data(repeating: 0, count: 18)
  static let eip7702Prefix = Data([0xef, 0x01, 0x00])
  static let paymasterSigMagic = Data([0x22, 0xe3, 0x25, 0xa2, 0x97, 0x43, 0x96, 0x56])
  static let paymasterStaticPrefixLength = 52
  static let paymasterSigSuffixLength = 10

  static func normalizeHexBytes(_ value: String) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized.isEmpty || normalized == "0x" { return "0x" }
    return normalized.hasPrefix("0x") ? normalized : "0x" + normalized
  }

  static func normalizeAddressOrEmpty(_ value: String) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized.isEmpty || normalized == "0x" { return "0x" }
    return normalized.hasPrefix("0x") ? normalized : "0x" + normalized
  }

  static func normalizeHexQuantity(_ value: String) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized.hasPrefix("0x") {
      var stripped = String(normalized.dropFirst(2))
      while stripped.hasPrefix("0") && stripped.count > 1 {
        stripped.removeFirst()
      }
      return "0x" + stripped
    }

    guard let number = BigUInt(normalized, radix: 10) else { return normalized }
    if number == .zero { return "0x0" }
    return "0x" + number.serialize().toHexString()
  }

  static func parseQuantity(_ value: String) throws -> BigUInt {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized.hasPrefix("0x") {
      let hex = String(normalized.dropFirst(2))
      if hex.isEmpty { return .zero }
      guard let out = BigUInt(hex, radix: 16) else { throw AAError.invalidHexValue(value) }
      return out
    }
    guard let out = BigUInt(normalized, radix: 10) else { throw AAError.invalidQuantity(value) }
    return out
  }

  static func hexToData(_ value: String) throws -> Data {
    let clean = normalizeHexBytes(value).replacingOccurrences(of: "0x", with: "")
    if clean.isEmpty { return Data() }
    guard let out = Data.fromHex(clean) else { throw AAError.invalidHexValue(value) }
    return out
  }

  static func addressData(_ value: String) throws -> Data {
    let clean = normalizeAddressOrEmpty(value).replacingOccurrences(of: "0x", with: "")
    guard clean.count == 40, let out = Data.fromHex(clean) else {
      throw AAError.invalidAddress(value)
    }
    return out
  }

  static func uint128Data(_ value: String) throws -> Data {
    let n = try parseQuantity(value)
    if n > ((BigUInt(1) << 128) - 1) { throw AAError.invalidQuantity(value) }
    let s = n.serialize()
    return Data(repeating: 0, count: max(0, 16 - s.count)) + s
  }

  static func wordData(_ value: String) throws -> Data {
    let d = try hexToData(value)
    guard d.count == 32 else { throw AAError.invalidPackedWord(value) }
    return d
  }

  static func uintWord(_ value: String) throws -> Data {
    ABIWord.uint(try parseQuantity(value))
  }

  static func wordHex(_ value: BigUInt) -> String {
    let bytes = value.serialize()
    let padded = Data(repeating: 0, count: max(0, 32 - bytes.count)) + bytes
    return "0x" + padded.toHexString()
  }

  static func domainSeparator(chainId: UInt64, entryPoint: String) throws -> Data {
    let chainWord = ABIWord.uint(BigUInt(chainId))
    let entryWord = try ABIWord.address(entryPoint)
    return Data(
      (eip712DomainTypeHash + domainNameHash + domainVersionHash + chainWord + entryWord).sha3(
        .keccak256))
  }

  static func looksLikeEip7702SenderCode(_ code: Data) -> Bool {
    code.count >= 23 && code.prefix(3) == eip7702Prefix
  }

  static func paymasterAndDataHash(_ paymasterAndData: Data) throws -> Data {
    guard paymasterAndData.count >= paymasterStaticPrefixLength + paymasterSigSuffixLength else {
      return Data(paymasterAndData.sha3(.keccak256))
    }

    let suffixStart = paymasterAndData.count - paymasterSigMagic.count
    let suffix = paymasterAndData[suffixStart..<paymasterAndData.count]
    guard Data(suffix) == paymasterSigMagic else {
      return Data(paymasterAndData.sha3(.keccak256))
    }

    let lenWordStart = paymasterAndData.count - paymasterSigSuffixLength
    let lenData = Data(paymasterAndData[lenWordStart..<(lenWordStart + 2)])
    let sigLen = Int(
      lenData.withUnsafeBytes { rawBuffer in
        UInt16(bigEndian: rawBuffer.load(as: UInt16.self))
      })

    let signedLen = paymasterAndData.count - sigLen - paymasterSigSuffixLength
    guard signedLen >= paymasterStaticPrefixLength else {
      throw AAError.invalidQuantity("Invalid paymaster signature suffix length")
    }

    return Data(paymasterAndData.prefix(signedLen).sha3(.keccak256))
  }
}
