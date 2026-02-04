import Foundation
import Transactions

public struct RegisterNameRequest: Sendable {
  public let registrarControllerAddress: String
  public let name: String
  public let ownerAddress: String
  public let duration: UInt
  public let secretHex: String?
  public let rentPriceWeiOverride: String?

  public init(
    registrarControllerAddress: String,
    name: String,
    ownerAddress: String,
    duration: UInt,
    secretHex: String? = nil,
    rentPriceWeiOverride: String? = nil
  ) {
    self.registrarControllerAddress = registrarControllerAddress
    self.name = name
    self.ownerAddress = ownerAddress
    self.duration = duration
    self.secretHex = secretHex
    self.rentPriceWeiOverride = rentPriceWeiOverride
  }
}

public struct RegisterNameResult: Sendable {
  public let calls: [Call]
  public let secretHex: String

  public init(calls: [Call], secretHex: String) {
    self.calls = calls
    self.secretHex = secretHex
  }
}

public struct NameAvailabilityQuote: Sendable {
  public let label: String
  public let normalizedName: String
  public let available: Bool
  public let rentPriceWei: String

  public init(
    label: String,
    normalizedName: String,
    available: Bool,
    rentPriceWei: String
  ) {
    self.label = label
    self.normalizedName = normalizedName
    self.available = available
    self.rentPriceWei = rentPriceWei
  }
}

public struct ResolveNameRequest: Sendable {
  public let name: String

  public init(name: String) {
    self.name = name
  }
}

public struct ReverseAddressRequest: Sendable {
  public let address: String

  public init(address: String) {
    self.address = address
  }
}

public struct AddRecordRequest: Sendable {
  public let name: String
  public let recordKey: String
  public let recordValue: String

  public init(
    name: String,
    recordKey: String,
    recordValue: String
  ) {
    self.name = name
    self.recordKey = recordKey
    self.recordValue = recordValue
  }
}

public struct UpdateRecordRequest: Sendable {
  public let name: String
  public let recordKey: String
  public let recordValue: String

  public init(
    name: String,
    recordKey: String,
    recordValue: String
  ) {
    self.name = name
    self.recordKey = recordKey
    self.recordValue = recordValue
  }
}
