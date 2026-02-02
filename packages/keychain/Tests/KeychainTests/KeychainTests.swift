import XCTest
@testable import Keychain

final class KeychainTests: XCTestCase {
  func testStoreInit() {
    _ = KeychainStore()
  }
}
