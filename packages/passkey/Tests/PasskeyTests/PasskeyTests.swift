import XCTest

@testable import Passkey

final class PasskeyTests: XCTestCase {
  func testRelyingPartyConfig() {
    let config = PasskeyRelyingParty(rpID: "knot.fi", rpName: "knot")
    XCTAssertEqual(config.rpID, "knot.fi")
  }
}
