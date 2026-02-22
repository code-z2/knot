import Foundation
import Transactions

public struct InitialTextRecordModel: Sendable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct RegisterNameRequestModel: Sendable {
    public let name: String
    public let ownerAddress: String
    public let duration: UInt
    public let resolverAddress: String?
    public let setReverseRecord: Bool
    public let ownerControlledFuses: UInt16
    public let initialTextRecords: [InitialTextRecordModel]
    public let secretHex: String?
    public let rentPriceWeiOverride: String?

    public init(
        name: String,
        ownerAddress: String,
        duration: UInt,
        resolverAddress: String? = nil,
        setReverseRecord: Bool = false,
        ownerControlledFuses: UInt16 = 0,
        initialTextRecords: [InitialTextRecordModel] = [],
        secretHex: String? = nil,
        rentPriceWeiOverride: String? = nil,
    ) {
        self.name = name
        self.ownerAddress = ownerAddress
        self.duration = duration
        self.resolverAddress = resolverAddress
        self.setReverseRecord = setReverseRecord
        self.ownerControlledFuses = ownerControlledFuses
        self.initialTextRecords = initialTextRecords
        self.secretHex = secretHex
        self.rentPriceWeiOverride = rentPriceWeiOverride
    }
}

public struct RegisterNameResultModel: Sendable {
    public let commitCall: Call
    public let registerCall: Call
    public let minCommitmentAgeSeconds: UInt64
    public let secretHex: String

    public var calls: [Call] {
        [commitCall, registerCall]
    }

    public init(
        commitCall: Call,
        registerCall: Call,
        minCommitmentAgeSeconds: UInt64,
        secretHex: String,
    ) {
        self.commitCall = commitCall
        self.registerCall = registerCall
        self.minCommitmentAgeSeconds = minCommitmentAgeSeconds
        self.secretHex = secretHex
    }
}

public struct NameAvailabilityQuoteModel: Sendable {
    public let label: String
    public let normalizedName: String
    public let available: Bool
    public let rentPriceWei: String

    public init(
        label: String,
        normalizedName: String,
        available: Bool,
        rentPriceWei: String,
    ) {
        self.label = label
        self.normalizedName = normalizedName
        self.available = available
        self.rentPriceWei = rentPriceWei
    }
}

public struct ResolveNameRequestModel: Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct ReverseAddressRequestModel: Sendable {
    public let address: String

    public init(address: String) {
        self.address = address
    }
}

public struct TextRecordRequestModel: Sendable {
    public let name: String
    public let recordKey: String
    public let recordValue: String?

    public init(name: String, recordKey: String, recordValue: String? = nil) {
        self.name = name
        self.recordKey = recordKey
        self.recordValue = recordValue
    }
}
