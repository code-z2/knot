import XCTest
@testable import AccountSetup
import Passkey
import Keychain
import SignHandler

final class AccountSetupTests: XCTestCase {
  func testCreatedAccountModel() {
    let passkey = PasskeyPublicKey(
      x: Data(repeating: 1, count: 32),
      y: Data(repeating: 2, count: 32),
      credentialID: Data([1, 2, 3]),
      userName: "0x1",
      aaGuid: Data(repeating: 0, count: 16),
      rawAttestationObject: Data(),
      rawClientDataJSON: Data()
    )
    let authorization = EIP7702AuthorizationSigned(
      chainId: 1,
      delegateAddress: "0x0000000000000000000000000000000000000001",
      nonce: 0,
      yParity: 0,
      r: "0x1",
      s: "0x2"
    )
    let account = CreatedAccount(
      eoaAddress: "0x1",
      passkey: passkey,
      signedAuthorization: authorization
    )
    XCTAssertEqual(account.eoaAddress, "0x1")
  }
}
