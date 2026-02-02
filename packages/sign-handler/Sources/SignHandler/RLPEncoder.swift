import Foundation

public enum RLP {
  public static func encode(_ value: RLPItem) -> Data {
    switch value {
    case .bytes(let data):
      return encodeBytes(data)
    case .list(let items):
      let payload = items.reduce(into: Data()) { partial, item in
        partial.append(encode(item))
      }
      return encodeLength(prefixOffset: 0xC0, length: payload.count) + payload
    }
  }

  public static func encodeUInt(_ value: UInt64) -> Data {
    encodeBytes(uintData(value))
  }

  public static func uintData(_ value: UInt64) -> Data {
    if value == 0 { return Data() }
    var be = withUnsafeBytes(of: value.bigEndian, Array.init)
    while be.first == 0 { be.removeFirst() }
    return Data(be)
  }

  public static func encodeBigUInt256(hex: String) -> Data {
    let cleaned = hex.replacingOccurrences(of: "0x", with: "")
    let data = Data(hexString: cleaned)
    return encodeBytes(data.trimmedLeadingZeros())
  }

  private static func encodeBytes(_ data: Data) -> Data {
    if data.count == 1, let first = data.first, first < 0x80 {
      return data
    }
    return encodeLength(prefixOffset: 0x80, length: data.count) + data
  }

  private static func encodeLength(prefixOffset: UInt8, length: Int) -> Data {
    if length <= 55 {
      return Data([prefixOffset + UInt8(length)])
    }

    var lenBytes = withUnsafeBytes(of: UInt64(length).bigEndian, Array.init)
    while lenBytes.first == 0 { lenBytes.removeFirst() }
    return Data([prefixOffset + 55 + UInt8(lenBytes.count)]) + Data(lenBytes)
  }
}

public enum RLPItem {
  case bytes(Data)
  case list([RLPItem])
}

private extension Data {
  init(hexString: String) {
    self.init()
    var input = hexString
    if input.count % 2 != 0 { input = "0" + input }

    var index = input.startIndex
    while index < input.endIndex {
      let next = input.index(index, offsetBy: 2)
      let byte = UInt8(input[index..<next], radix: 16) ?? 0
      append(byte)
      index = next
    }
  }

  func trimmedLeadingZeros() -> Data {
    var bytes = [UInt8](self)
    while bytes.first == 0, bytes.count > 1 {
      bytes.removeFirst()
    }
    return Data(bytes)
  }
}
