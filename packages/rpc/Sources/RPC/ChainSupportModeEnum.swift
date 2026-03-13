import Foundation

public enum ChainSupportMode: String, Sendable {
    case testnet
    case mainnet

    public var supportedChainsKey: String {
        "SUPPORTED_CHAINS_\(rawValue.uppercased())"
    }

    public var defaultChainIDs: [UInt64] {
        switch self {
        case .testnet:
            [11_155_111, 84532, 421_614]

        case .mainnet:
            [1, 10, 137, 8453, 42161, 143]
        }
    }
}
