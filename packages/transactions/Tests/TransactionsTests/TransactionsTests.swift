import XCTest
@testable import Transactions

final class TransactionsTests: XCTestCase {
  func testCallModel() {
    let call = Call(to: "0xabc", dataHex: "0x1234")
    XCTAssertEqual(call.to, "0xabc")
    XCTAssertEqual(call.dataHex, "0x1234")
    XCTAssertEqual(call.valueWei, "0")
  }

  func testChainCallsModel() {
    let call = Call(to: "0xabc", dataHex: "0x1234")
    let bundle = ChainCalls(chainId: 1, calls: [call])
    XCTAssertEqual(bundle.chainId, 1)
    XCTAssertEqual(bundle.calls.count, 1)
    XCTAssertEqual(bundle.calls.first?.to, "0xabc")
  }
}
