import Balance
import Foundation

struct GasTankFundingAssetDefinition {
    let symbol: String
    let displaySymbol: String
    let name: String
    let assetImageName: String
    let decimals: Int
    let isNative: Bool

    func placeholderBalance(
        totalBalance: Decimal = 0,
        totalValueUSD: Decimal = 0,
        quoteRate: Decimal = 0,
    ) -> TokenBalanceModel {
        TokenBalanceModel(
            id: symbol.lowercased(),
            symbol: symbol,
            name: name,
            contractAddress: "",
            decimals: decimals,
            isNative: isNative,
            totalBalance: totalBalance,
            totalValueUSD: totalValueUSD,
            quoteRate: quoteRate,
            quoteRate24h: nil,
            logoURL: nil,
            chainBalances: [],
        )
    }
}

extension GasTankFundingAssetDefinition {
    static var previewBalances: [TokenBalanceModel] {
        [
            supported[0].placeholderBalance(totalBalance: 3.14, totalValueUSD: 3.14, quoteRate: 1),
            supported[1].placeholderBalance(totalBalance: 100.6, totalValueUSD: 100.6, quoteRate: 1),
            supported[2].placeholderBalance(totalBalance: 0.6134, totalValueUSD: 1430, quoteRate: 2331.91),
            supported[3].placeholderBalance(totalBalance: 0.6134, totalValueUSD: 0.6134, quoteRate: 1),
            supported[4].placeholderBalance(totalBalance: 0.004, totalValueUSD: 270, quoteRate: 67500),
        ]
    }

    static let supported: [GasTankFundingAssetDefinition] = [
        .init(
            symbol: "USDC",
            displaySymbol: "USDC",
            name: "USD Coin",
            assetImageName: "usdc-3d",
            decimals: 6,
            isNative: false,
        ),
        .init(
            symbol: "USDT",
            displaySymbol: "USDT",
            name: "Tether USD",
            assetImageName: "usdt-3d",
            decimals: 6,
            isNative: false,
        ),
        .init(
            symbol: "ETH",
            displaySymbol: "ETH",
            name: "Ethereum",
            assetImageName: "ethereum-3d",
            decimals: 18,
            isNative: true,
        ),
        .init(
            symbol: "DAI",
            displaySymbol: "DAI",
            name: "Dai",
            assetImageName: "dai-3d",
            decimals: 18,
            isNative: false,
        ),
        .init(
            symbol: "WBTC",
            displaySymbol: "wBTC",
            name: "Wrapped Bitcoin",
            assetImageName: "bitcoin-3d",
            decimals: 8,
            isNative: false,
        ),
    ]
}
