import Foundation

public enum ChainRegistry {
    public static let known: [ChainDefinitionModel] = [
        .init(
            chainID: 1,
            slug: "eth-mainnet",
            name: "Ethereum",
            assetName: "ethereum",
            keywords: ["eth", "mainnet"],
            rpcURL: nil,
            explorerBaseURL: "https://etherscan.io",
            spokePoolAddress: "0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5",
            wrappedNativeTokenAddress: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
        ),
        .init(
            chainID: 11_155_111,
            slug: "eth-sepolia",
            name: "Sepolia",
            assetName: "ethereum",
            keywords: ["eth", "testnet"],
            rpcURL: nil,
            explorerBaseURL: "https://sepolia.etherscan.io",
            isTestnet: true,
            spokePoolAddress: "0x5ef6C01E11889d86803e0B23e3cB3F9E9d97B662",
            wrappedNativeTokenAddress: "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14",
        ),
        .init(
            chainID: 8453,
            slug: "base-mainnet",
            name: "Base",
            assetName: "base",
            keywords: ["coinbase"],
            rpcURL: nil,
            explorerBaseURL: "https://basescan.org",
            spokePoolAddress: "0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64",
            wrappedNativeTokenAddress: "0x4200000000000000000000000000000000000006",
        ),
        .init(
            chainID: 84532,
            slug: "base-sepolia",
            name: "Base Sepolia",
            assetName: "base",
            keywords: ["base", "testnet"],
            rpcURL: nil,
            explorerBaseURL: "https://sepolia.basescan.org",
            isTestnet: true,
            spokePoolAddress: "0x82B564983aE7274c86695917BBf8C99ECb6F0F8F",
            wrappedNativeTokenAddress: "0x4200000000000000000000000000000000000006",
        ),
        .init(
            chainID: 42161,
            slug: "arb-mainnet",
            name: "Arbitrum",
            assetName: "arbitrum",
            keywords: ["arb"],
            rpcURL: nil,
            explorerBaseURL: "https://arbiscan.io",
            spokePoolAddress: "0xe35e9842fceaCA96570B734083f4a58e8F7C5f2A",
            wrappedNativeTokenAddress: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
        ),
        .init(
            chainID: 421_614,
            slug: "arb-sepolia",
            name: "Arbitrum Sepolia",
            assetName: "arbitrum",
            keywords: ["arb", "testnet"],
            rpcURL: nil,
            explorerBaseURL: "https://sepolia.arbiscan.io",
            isTestnet: true,
            spokePoolAddress: "0x7E63A5f1a8F0B4d0934B2f2327DAED3F6bb2ee75",
            wrappedNativeTokenAddress: "0x980B62Da83eFf3D4576C647993b0c1D7faf17c73",
        ),
        .init(
            chainID: 10,
            slug: "opt-mainnet",
            name: "Optimism",
            assetName: "optimism",
            keywords: ["op"],
            rpcURL: nil,
            explorerBaseURL: "https://optimistic.etherscan.io",
            spokePoolAddress: "0x6f26Bf09B1C792e3228e5467807a900A503c0281",
            wrappedNativeTokenAddress: "0x4200000000000000000000000000000000000006",
        ),
        .init(
            chainID: 137,
            slug: "polygon-mainnet",
            name: "Polygon",
            assetName: "polygon",
            keywords: ["matic", "pol"],
            rpcURL: nil,
            explorerBaseURL: "https://polygonscan.com",
            spokePoolAddress: "0x9295ee1d8C5b022Be115A2AD3c30C72E34e7F096",
            wrappedNativeTokenAddress: "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619",
        ),
        .init(
            chainID: 143,
            slug: "monad-mainnet",
            name: "Monad",
            assetName: "monad",
            keywords: ["monad"],
            rpcURL: nil,
            explorerBaseURL: nil,
            spokePoolAddress: "0xd2ecb3afe598b746F8123CaE365a598DA831A449",
            wrappedNativeTokenAddress: "0xee8c0e9f1bffb4eb878d8f15f368a02a35481242",
        ),
        .init(
            chainID: 56,
            slug: "bnb-mainnet",
            name: "BNB Smart Chain",
            assetName: "bnb-smart-chain",
            keywords: ["bnb", "bsc", "binance"],
            rpcURL: nil,
            explorerBaseURL: "https://bscscan.com",
            spokePoolAddress: "0x4e8E101924eDE233C13e2D8622DC8aED2872d505",
            wrappedNativeTokenAddress: "0x2170Ed0880ac9A755fd29B2688956BD959F933F8",
        ),
        .init(
            chainID: 81457,
            slug: "blast-mainnet",
            name: "Blast",
            assetName: "blast",
            keywords: [],
            rpcURL: nil,
            explorerBaseURL: "https://blastscan.io",
            spokePoolAddress: "0x2D509190Ed0172ba588407D4c2df918F955Cc6E1",
            wrappedNativeTokenAddress: "0x4300000000000000000000000000000000000004",
        ),
        .init(
            chainID: 59144,
            slug: "linea-mainnet",
            name: "Linea",
            assetName: "linea",
            keywords: [],
            rpcURL: nil,
            explorerBaseURL: "https://explorer.linea.build",
            spokePoolAddress: "0x7E63A5f1a8F0B4d0934B2f2327DAED3F6bb2ee75",
            wrappedNativeTokenAddress: "0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f",
        ),
        .init(
            chainID: 1135,
            slug: "lisk",
            name: "Lisk",
            assetName: "lisk",
            keywords: [],
            rpcURL: nil,
            explorerBaseURL: "https://blockscout.lisk.com",
            spokePoolAddress: "0x9552a0a6624A23B848060AE5901659CDDa1f83f8",
            wrappedNativeTokenAddress: "0x4200000000000000000000000000000000000006",
        ),
        .init(
            chainID: 34443,
            slug: "mode-mainnet",
            name: "Mode",
            assetName: "mode",
            keywords: [],
            rpcURL: nil,
            explorerBaseURL: "https://explorer.mode.network",
            spokePoolAddress: "0x3baD7AD0728f9917d1Bf08af5782dCbD516cDd96",
            wrappedNativeTokenAddress: "0x4200000000000000000000000000000000000006",
        ),
        .init(
            chainID: 9745,
            slug: "plasma-mainnet",
            name: "Plasma",
            assetName: "plasma",
            keywords: [],
            rpcURL: nil,
            explorerBaseURL: "https://plasmascan.to",
            spokePoolAddress: "0x50039fAEfebef707cFD94D6d462fE6D10B39207a",
            wrappedNativeTokenAddress: "0x9895D81bB462A195b4922ED7De0e3ACD007c32CB",
        ),
        .init(
            chainID: 534_352,
            slug: "scroll-mainnet",
            name: "Scroll",
            assetName: "scroll",
            keywords: [],
            rpcURL: nil,
            explorerBaseURL: "https://scroll.blockscout.com",
            spokePoolAddress: "0x3baD7AD0728f9917d1Bf08af5782dCbD516cDd96",
            wrappedNativeTokenAddress: "0x5300000000000000000000000000000000000004",
        ),
        .init(
            chainID: 1868,
            slug: "soneium-mainnet",
            name: "Soneium",
            assetName: "soneium",
            keywords: [],
            rpcURL: nil,
            explorerBaseURL: "https://soneium.blockscout.com",
            spokePoolAddress: "0x3baD7AD0728f9917d1Bf08af5782dCbD516cDd96",
            wrappedNativeTokenAddress: "0x4200000000000000000000000000000000000006",
        ),
        .init(
            chainID: 130,
            slug: "unichain-mainnet",
            name: "Unichain",
            assetName: "unichain",
            keywords: [],
            rpcURL: nil,
            explorerBaseURL: "https://unichain.blockscout.com",
            spokePoolAddress: "0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64",
            wrappedNativeTokenAddress: "0x4200000000000000000000000000000000000006",
        ),
        .init(
            chainID: 480,
            slug: "worldchain-mainnet",
            name: "World Chain",
            assetName: "world-chain",
            keywords: ["world"],
            rpcURL: nil,
            explorerBaseURL: "https://worldchain-mainnet.explorer.alchemy.com",
            spokePoolAddress: "0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64",
            wrappedNativeTokenAddress: "0x4200000000000000000000000000000000000006",
        ),
        .init(
            chainID: 324,
            slug: "zksync-mainnet",
            name: "zkSync",
            assetName: "zksync",
            keywords: ["zk"],
            rpcURL: nil,
            explorerBaseURL: "https://zksync.blockscout.com",
            spokePoolAddress: "0xE0B015E54d54fc84a6cB9B666099c46adE9335FF",
            wrappedNativeTokenAddress: "0x5AEa5775959fBC2557Cc8789bC1bf90A239D9a91",
        ),
        .init(
            chainID: 7_777_777,
            slug: "zora-mainnet",
            name: "Zora",
            assetName: "zora",
            keywords: [],
            rpcURL: nil,
            explorerBaseURL: "https://explorer.zora.energy",
            spokePoolAddress: "0x13fDac9F9b4777705db45291bbFF3c972c6d1d97",
            wrappedNativeTokenAddress: "0x4200000000000000000000000000000000000006",
        ),
        .init(
            chainID: 999,
            slug: "hyperliquid-mainnet",
            name: "HyperEVM",
            assetName: "hyperevm",
            keywords: ["hyper"],
            rpcURL: nil,
            explorerBaseURL: "https://hyperevmscan.io",
            spokePoolAddress: "0x35E63eA3eb0fb7A3bc543C71FB66412e1F6B0E04",
            wrappedNativeTokenAddress: "0xBe6727B535545C67d5cAa73dEa54865B92CF7907", // uETH
        ),
        .init(
            chainID: 57073,
            slug: "ink-mainnet",
            name: "Ink",
            assetName: "ink",
            keywords: [],
            rpcURL: nil,
            explorerBaseURL: "https://explorer.inkonchain.com",
            spokePoolAddress: "0xeF684C38F94F48775959ECf2012D7E864ffb9dd4",
            wrappedNativeTokenAddress: "0x4200000000000000000000000000000000000006",
        ),
    ]

    private static let knownByChainID: [UInt64: ChainDefinitionModel] = Dictionary(
        uniqueKeysWithValues: known.map { ($0.chainID, $0) },
    )

    public static func resolve(chainID: UInt64) -> ChainDefinitionModel? {
        knownByChainID[chainID]
    }

    public static func resolveOrFallback(chainID: UInt64) -> ChainDefinitionModel {
        if let known = resolve(chainID: chainID) {
            return known
        }
        return ChainDefinitionModel(
            chainID: chainID,
            slug: "chain-\(chainID)",
            name: "Chain \(chainID)",
            assetName: "ethereum",
            keywords: ["custom", String(chainID)],
            rpcURL: nil,
            explorerBaseURL: nil,
            isTestnet: false,
        )
    }

    public static func spokePoolAddress(chainID: UInt64) -> String? {
        knownByChainID[chainID]?.spokePoolAddress
    }

    public static func wrappedNativeTokenAddress(chainID: UInt64) -> String? {
        knownByChainID[chainID]?.wrappedNativeTokenAddress
    }

    public static func isTestnet(chainID: UInt64) -> Bool {
        knownByChainID[chainID]?.isTestnet ?? false
    }

    public static func getChains(
        bundle: Bundle = .main,
    ) -> [ChainDefinitionModel] {
        let configuredChainIDs = ChainSupportRuntime.resolveSupportedChainIDs(bundle: bundle)
        guard !configuredChainIDs.isEmpty else { return [] }
        return configuredChainIDs.map(resolveOrFallback(chainID:))
    }
}
