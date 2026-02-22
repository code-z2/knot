import Foundation

public struct ChainSupportConfigModel: Sendable, Equatable {
    public let mode: ChainSupportMode
    public let chainIDs: [UInt64]

    public init(mode: ChainSupportMode, chainIDs: [UInt64]) {
        self.mode = mode
        self.chainIDs = chainIDs
    }
}
