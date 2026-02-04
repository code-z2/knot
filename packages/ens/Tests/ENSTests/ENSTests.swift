import XCTest
@testable import ENS
import Web3Core

final class ENSTests: XCTestCase {
  func testEthLabelRemovesSuffix() {
    XCTAssertEqual(ENSClient.ethLabel(from: "vitalik.eth"), "vitalik")
    XCTAssertEqual(ENSClient.ethLabel(from: "vitalik"), "vitalik")
  }

  func testReverseNodeFormat() {
    let address = EthereumAddress("0xF5bB7F874D8e3f41821175c0Aa9910d30d10e193")!
    XCTAssertEqual(
      ENSClient.reverseNode(for: address),
      "f5bb7f874d8e3f41821175c0aa9910d30d10e193.addr.reverse"
    )
  }
}
