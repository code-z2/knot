import Foundation

public struct AnyCodable: Codable, @unchecked Sendable {
  public let value: Any

  public init(_ value: Any) {
    self.value = value
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(String.self) { self.value = value; return }
    if let value = try? container.decode(Int.self) { self.value = value; return }
    if let value = try? container.decode(Double.self) { self.value = value; return }
    if let value = try? container.decode(Bool.self) { self.value = value; return }
    if let value = try? container.decode([AnyCodable].self) { self.value = value.map(\.value); return }
    if let value = try? container.decode([String: AnyCodable].self) {
      self.value = value.mapValues(\.value)
      return
    }
    if container.decodeNil() {
      self.value = NSNull()
      return
    }
    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch value {
    case let value as String:
      try container.encode(value)
    case let value as Int:
      try container.encode(value)
    case let value as Int64:
      try container.encode(value)
    case let value as Double:
      try container.encode(value)
    case let value as Bool:
      try container.encode(value)
    case let value as [Any]:
      try container.encode(value.map(AnyCodable.init))
    case let value as [String: Any]:
      try container.encode(value.mapValues(AnyCodable.init))
    case _ as NSNull:
      try container.encodeNil()
    default:
      throw EncodingError.invalidValue(
        value,
        EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported JSON value")
      )
    }
  }
}
