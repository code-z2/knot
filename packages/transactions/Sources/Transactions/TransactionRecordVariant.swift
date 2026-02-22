import Foundation

public enum TransactionRecordVariant: Hashable, Sendable, Codable {
    case received

    case sent

    case contract

    case multichain
}
