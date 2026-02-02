import XCTest
@testable import Passkey

final class PasskeyTests: XCTestCase {
  func testRelyingPartyConfig() {
    let config = PasskeyRelyingParty(rpID: "peteranyaogu.com", rpName: "peteranyaogu")
    XCTAssertEqual(config.rpID, "peteranyaogu.com")
  }
}
