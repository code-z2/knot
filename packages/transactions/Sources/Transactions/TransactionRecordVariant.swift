import Foundation

public enum TransactionRecordVariant: Hashable, Sendable, Codable {
    case received

    case transfer

    case contract

    case multichain
}
