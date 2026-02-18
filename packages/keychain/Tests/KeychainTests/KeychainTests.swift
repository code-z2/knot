@testable import Keychain
import XCTest

final class KeychainTests: XCTestCase {
    func testStoreInit() {
        _ = KeychainStore()
    }
}
