import Foundation

public struct FlightAsset: Sendable, Equatable {
    public let symbol: String

    public let contractAddress: String

    public let decimals: Int

    public init(symbol: String, contractAddress: String, decimals: Int) {
        self.symbol = symbol
        self.contractAddress = contractAddress
        self.decimals = decimals
    }
}
