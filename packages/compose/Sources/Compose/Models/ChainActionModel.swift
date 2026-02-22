import Foundation
import Transactions

public struct ChainActionModel: Sendable, Codable, Equatable {
    public let chainId: UInt64
    public let calls: [Call]

    public init(chainId: UInt64, calls: [Call]) {
        self.chainId = chainId
        self.calls = calls
    }
}
