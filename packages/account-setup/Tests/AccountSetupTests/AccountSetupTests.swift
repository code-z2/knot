@testable import AccountSetup
import Keychain
import Passkey
import SignHandler
import XCTest

final class AccountSetupTests: XCTestCase {
    func testCreatedAccountModel() {
        let passkey = PasskeyPublicKey(
            x: Data(repeating: 1, count: 32),
            y: Data(repeating: 2, count: 32),
            credentialID: Data([1, 2, 3]),
        )
        let authorization = EIP7702AuthorizationSigned(
            chainId: 1,
            delegateAddress: "0x0000000000000000000000000000000000000001",
            nonce: 0,
            yParity: 0,
            r: "0x1",
            s: "0x2",
        )
        let account = CreatedAccount(
            eoaAddress: "0x1",
            accumulatorAddress: "0x2",
            passkey: passkey,
            signedAuthorization: authorization,
        )
        XCTAssertEqual(account.eoaAddress, "0x1")
    }
}
