import Web3Core
import XCTest

@testable import ENS

final class ENSTests: XCTestCase {
  func testDefaultConfigurationIsSepolia() {
    let client = ENSClient()
    XCTAssertEqual(client.configuration.chainID, 11_155_111)
    XCTAssertEqual(
      client.configuration.registrarControllerAddress, "0xfb3cE5D01e0f33f41DbB39035dB9745962F1f968")
    XCTAssertEqual(
      client.configuration.publicResolverAddress, "0xE99638b40E4Fff0129D56f03b55b6bbC4BBE49b5")
    XCTAssertEqual(
      client.configuration.universalResolverAddress, "0xeEeEEEeE14D718C2B47D9923Deab1335E144EeEe")
  }

  func testExplicitSepoliaConfigurationMatchesDefault() {
    let client = ENSClient(configuration: .sepolia)
    XCTAssertEqual(client.configuration.chainID, 11_155_111)
    XCTAssertEqual(
      client.configuration.registrarControllerAddress, "0xfb3cE5D01e0f33f41DbB39035dB9745962F1f968")
    XCTAssertEqual(
      client.configuration.publicResolverAddress, "0xE99638b40E4Fff0129D56f03b55b6bbC4BBE49b5")
    XCTAssertEqual(
      client.configuration.universalResolverAddress, "0xeEeEEEeE14D718C2B47D9923Deab1335E144EeEe")
  }

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

  func testDNSEncodedName() {
    let encoded = ENSClient.dnsEncodedName("vitalik.eth")
    XCTAssertEqual(encoded?.toHexString(), "07766974616c696b0365746800")
  }
}
