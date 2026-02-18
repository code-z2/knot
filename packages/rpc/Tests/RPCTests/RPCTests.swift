@testable import RPC
import XCTest

final class RPCTests: XCTestCase {
    func testGetConfiguredUrls() async throws {
        let resolver = StaticRPCEndpointResolver(
            endpointsByChain: [
                1: ChainEndpoints(
                    rpcURL: "https://rpc.example",
                    walletAPIURL: "https://wallet.example",
                    walletAPIBearerToken: "wallet-token-123",
                    addressActivityAPIURL: "https://activity.example",
                    addressActivityAPIBearerToken: "activity-token-456",
                ),
            ],
        )
        let client = RPCClient(
            resolver: resolver,
        )

        let rpc = try await client.getRpcUrl(chainId: 1)
        let wallet = try await client.getWalletApiUrl(chainId: 1)
        let walletToken = try await client.getWalletApiBearerToken(chainId: 1)
        let activity = try await client.getAddressActivityApiUrl(chainId: 1)
        let activityToken = try await client.getAddressActivityApiBearerToken(chainId: 1)
        let chains = await client.getSupportedChains()

        XCTAssertEqual(rpc, "https://rpc.example")
        XCTAssertEqual(wallet, "https://wallet.example")
        XCTAssertEqual(walletToken, "wallet-token-123")
        XCTAssertEqual(activity, "https://activity.example")
        XCTAssertEqual(activityToken, "activity-token-456")
        XCTAssertEqual(chains, [1])
    }

    func testResolveModeDefaultsToLimitedTestnetWhenSettingMissing() {
        let mode = ChainSupportRuntime.resolveMode(bundle: Bundle(for: Self.self))
        XCTAssertEqual(mode, .limitedTestnet)
    }

    func testResolveSupportedChainIDsFallbackToModeDefaultsWhenSettingMissing() {
        let bundle = Bundle(for: Self.self)

        XCTAssertEqual(
            ChainSupportRuntime.resolveSupportedChainIDs(mode: .limitedTestnet, bundle: bundle),
            [11_155_111, 84532, 421_614],
        )
        XCTAssertEqual(
            ChainSupportRuntime.resolveSupportedChainIDs(mode: .limitedMainnet, bundle: bundle),
            [1, 42161, 8453, 137, 143],
        )
        XCTAssertEqual(
            ChainSupportRuntime.resolveSupportedChainIDs(mode: .fullMainnet, bundle: bundle),
            [1, 10, 137, 8453, 42161, 143],
        )
    }
}
