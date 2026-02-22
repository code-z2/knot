import Foundation

public enum AAError: Error {
    case invalidPayloadType

    case invalidAddress(String)

    case invalidHexValue(String)

    case invalidQuantity(String)

    case invalidPackedWord(String)

    case invalidEip7702SenderCodePrefix(String)

    case missingEip7702Auth
}

extension AAError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPayloadType:
            "Unsupported AA payload type."

        case let .invalidAddress(value):
            "Invalid address: \(value)"

        case let .invalidHexValue(value):
            "Invalid hex value: \(value)"

        case let .invalidQuantity(value):
            "Invalid numeric quantity: \(value)"

        case let .invalidPackedWord(value):
            "Invalid packed word: \(value)"

        case let .invalidEip7702SenderCodePrefix(value):
            "Invalid EIP-7702 sender code prefix: \(value)"

        case .missingEip7702Auth:
            "Missing EIP-7702 authorization."
        }
    }
}
