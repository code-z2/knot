import Foundation

public enum ChainSupportMode: String, Sendable {
    case limitedTestnet = "LIMITED_TESTNET"

    case limitedMainnet = "LIMITED_MAINNET"

    case fullMainnet = "FULL_MAINNET"

    public var supportedChainsKey: String {
        switch self {
        case .limitedTestnet:
            "SUPPORTED_CHAINS_LIMITED_TESTNET"

        case .limitedMainnet:
            "SUPPORTED_CHAINS_LIMITED_MAINNET"

        case .fullMainnet:
            "SUPPORTED_CHAINS_FULL_MAINNET"
        }
    }

    public var defaultChainIDs: [UInt64] {
        switch self {
        case .limitedTestnet:
            [11_155_111, 84532, 421_614]

        case .limitedMainnet:
            [1, 42161, 8453, 137, 143]

        case .fullMainnet:
            [1, 10, 137, 8453, 42161, 143]
        }
    }
}
