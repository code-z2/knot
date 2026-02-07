import XCTest
@testable import RPC

final class RPCTests: XCTestCase {
  func testGetConfiguredUrls() async throws {
    let client = RPCClient(
      endpointsByChain: [
        1: ChainEndpoints(
          rpcURL: "https://rpc.example",
          bundlerURL: "https://bundler.example",
          paymasterURL: "https://paymaster.example",
          walletAPIURL: "https://wallet.example",
          walletAPIBearerToken: "wallet-token-123",
          transactionsAPIURL: "https://transactions.example",
          transactionsAPIBearerToken: "txn-token-456"
        )
      ]
    )

    let rpc = try await client.getRpcUrl(chainId: 1)
    let bundler = try await client.getBundlerUrl(chainId: 1)
    let paymaster = try await client.getPaymasterUrl(chainId: 1)
    let wallet = try await client.getWalletApiUrl(chainId: 1)
    let walletToken = try await client.getWalletApiBearerToken(chainId: 1)
    let transactions = try await client.getTransactionsApiUrl(chainId: 1)
    let txnToken = try await client.getTransactionsApiBearerToken(chainId: 1)
    let chains = await client.getSupportedChains()

    XCTAssertEqual(rpc, "https://rpc.example")
    XCTAssertEqual(bundler, "https://bundler.example")
    XCTAssertEqual(paymaster, "https://paymaster.example")
    XCTAssertEqual(wallet, "https://wallet.example")
    XCTAssertEqual(walletToken, "wallet-token-123")
    XCTAssertEqual(transactions, "https://transactions.example")
    XCTAssertEqual(txnToken, "txn-token-456")
    XCTAssertEqual(chains, [1])
  }
}
