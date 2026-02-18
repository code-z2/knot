import Foundation

public struct Call: Sendable, Codable, Equatable {
    public let to: String
    public let dataHex: String
    public let valueWei: String

    public init(to: String, dataHex: String, valueWei: String = "0") {
        self.to = to
        self.dataHex = dataHex
        self.valueWei = valueWei
    }
}

public struct ChainCalls: Sendable, Codable, Equatable {
    public let chainId: UInt64
    public let calls: [Call]

    public init(chainId: UInt64, calls: [Call]) {
        self.chainId = chainId
        self.calls = calls
    }
}
