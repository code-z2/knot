import XCTest
@testable import RPC

final class RPCTests: XCTestCase {
  func testGetConfiguredUrls() async throws {
    let client = RPCClient(
      endpointsByChain: [
        1: ChainEndpoints(rpcURL: "https://rpc.example", bundlerURL: "https://bundler.example", paymasterURL: "https://paymaster.example")
      ]
    )

    let rpc = try await client.getRpcUrl(chainId: 1)
    let bundler = try await client.getBundlerUrl(chainId: 1)
    let paymaster = try await client.getPaymasterUrl(chainId: 1)

    XCTAssertEqual(rpc, "https://rpc.example")
    XCTAssertEqual(bundler, "https://bundler.example")
    XCTAssertEqual(paymaster, "https://paymaster.example")
  }
}
