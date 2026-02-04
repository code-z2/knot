import BigInt
import Foundation
import Transactions
import web3swift

enum ABIWord {
  static func address(_ value: String) throws -> Data {
    let clean = value.lowercased().replacingOccurrences(of: "0x", with: "")
    guard clean.count == 40, let raw = Data.fromHex(clean) else {
      throw SmartAccountError.invalidAddress(value)
    }
    return Data(repeating: 0, count: 12) + raw
  }

  static func bytes32(_ value: Data) throws -> Data {
    guard value.count <= 32 else {
      throw SmartAccountError.invalidBytes32Length(value.count)
    }
    return Data(repeating: 0, count: 32 - value.count) + value
  }

  static func uint(_ decimal: String) throws -> Data {
    let number: BigUInt?
    if decimal.hasPrefix("0x") {
      number = BigUInt(decimal.replacingOccurrences(of: "0x", with: ""), radix: 16)
    } else {
      number = BigUInt(decimal, radix: 10)
    }
    guard let number else {
      throw SmartAccountError.invalidUIntValue(decimal)
    }
    return uint(number)
  }

  static func uint(_ value: BigUInt) -> Data {
    let serialized = value.serialize()
    return Data(repeating: 0, count: max(0, 32 - serialized.count)) + serialized
  }

  static func bytes(_ hex: String) throws -> Data {
    let clean = hex.replacingOccurrences(of: "0x", with: "")
    if clean.isEmpty {
      return ABIEncoder.encodeBytes(Data())
    }
    guard let value = Data.fromHex(clean) else {
      throw SmartAccountError.invalidHex(hex)
    }
    return ABIEncoder.encodeBytes(value)
  }
}

enum ABIEncoder {
  static func functionCall(signature: String, words: [Data], dynamic: [Data]) -> Data {
    let selector = Data(signature.utf8).sha3(.keccak256).prefix(4)

    if dynamic.isEmpty {
      return selector + words.reduce(into: Data(), { $0.append($1) })
    }

    var head = Data()
    for word in words {
      head.append(word)
    }

    let totalHeadWords = words.count + dynamic.count
    var dynamicOffset = totalHeadWords * 32
    var tail = Data()
    for encoded in dynamic {
      head.append(ABIWord.uint(BigUInt(dynamicOffset)))
      tail.append(encoded)
      dynamicOffset += encoded.count
    }

    return selector + head + tail
  }

  static func encodeBytes(_ value: Data) -> Data {
    var out = ABIWord.uint(BigUInt(value.count))
    out.append(value)
    let remainder = value.count % 32
    if remainder != 0 {
      out.append(Data(repeating: 0, count: 32 - remainder))
    }
    return out
  }

  static func encodeCallTuple(_ call: Call) throws -> Data {
    let target = try ABIWord.address(call.to)
    let value = try ABIWord.uint(call.valueWei)
    let data = try ABIWord.bytes(call.dataHex)
    let offset = ABIWord.uint(BigUInt(96))
    return target + value + offset + data
  }

  static func encodeCallTupleArray(_ calls: [Call]) throws -> Data {
    var out = ABIWord.uint(BigUInt(calls.count))
    if calls.isEmpty {
      return out
    }

    let encodedCalls = try calls.map { try encodeCallTuple($0) }
    var offsets = Data()
    var currentOffset = 32 + (calls.count * 32)
    for encoded in encodedCalls {
      offsets.append(ABIWord.uint(BigUInt(currentOffset)))
      currentOffset += encoded.count
    }

    out.append(offsets)
    for encoded in encodedCalls {
      out.append(encoded)
    }
    return out
  }

  static func encodeChainCallsTuple(_ bundle: ChainCalls) throws -> Data {
    let chainId = ABIWord.uint(BigUInt(bundle.chainId))
    let calls = try encodeCallTupleArray(bundle.calls)
    let callsOffset = ABIWord.uint(BigUInt(64))
    return chainId + callsOffset + calls
  }

  static func encodeChainCallsArray(_ bundles: [ChainCalls]) throws -> Data {
    var out = ABIWord.uint(BigUInt(bundles.count))
    if bundles.isEmpty {
      return out
    }

    let encodedBundles = try bundles.map { try encodeChainCallsTuple($0) }
    var offsets = Data()
    var currentOffset = 32 + (bundles.count * 32)
    for encoded in encodedBundles {
      offsets.append(ABIWord.uint(BigUInt(currentOffset)))
      currentOffset += encoded.count
    }

    out.append(offsets)
    for encoded in encodedBundles {
      out.append(encoded)
    }
    return out
  }
}

enum ABIUtils {
  static func decodeAddressFromABIWord(_ hex: String) throws -> String {
    let clean = hex.lowercased().replacingOccurrences(of: "0x", with: "")
    guard clean.count >= 64 else {
      throw SmartAccountError.malformedRPCResponse(hex)
    }
    let word = String(clean.prefix(64))
    let address = String(word.suffix(40))
    return "0x" + address
  }
}
