@testable import AccountSetup
import Keychain
import Passkey
import XCTest

final class AccountSetupTests: XCTestCase {
    func testCreatedAccountModel() {
        let passkey = PasskeyPublicKeyModel(
            x: Data(repeating: 1, count: 32),
            y: Data(repeating: 2, count: 32),
            credentialID: Data([1, 2, 3]),
        )
        let account = AccountProvisioningResult(
            eoaAddress: "0x1",
            accumulatorAddress: "0x2",
            passkey: passkey,
        )
        XCTAssertEqual(account.eoaAddress, "0x1")
    }
}
