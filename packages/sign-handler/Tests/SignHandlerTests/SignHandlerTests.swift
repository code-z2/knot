import XCTest
@testable import SignHandler

final class SignHandlerTests: XCTestCase {
  func testAuthorizationMessageHasMagicPrefix() {
    let unsigned = EIP7702AuthorizationUnsigned(
      chainId: 1,
      delegateAddress: "0x0000000000000000000000000000000000000001",
      nonce: 7
    )
    let message = EIP7702AuthorizationCodec.messageToSign(unsigned)
    XCTAssertEqual(message.first, EIP7702AuthorizationCodec.magic)
  }

  func testRecoverAuthorityAddressMatchesSigner() throws {
    let privateKey = "0x4c0883a69102937d6231471b5dbb6204fe5129617082794a3f7f6f7d4f5f3d55"
    let expectedAddress = "0xdc4b0a7e76826b703d958af790e48db401f37794"
    let unsigned = EIP7702AuthorizationUnsigned(
      chainId: 1,
      delegateAddress: "0x0000000000000000000000000000000000000001",
      nonce: 1
    )

    let signed = try EIP7702AuthorizationCodec.signAuthorization(unsigned, privateKeyHex: privateKey)
    let recovered = try EIP7702AuthorizationCodec.recoverAuthorityAddress(signed).lowercased()

    XCTAssertEqual(recovered, expectedAddress)
  }
}
