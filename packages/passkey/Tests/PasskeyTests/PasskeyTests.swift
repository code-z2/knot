import CryptoKit
import XCTest

@testable import Passkey

final class PasskeyTests: XCTestCase {
  func testRelyingPartyConfig() {
    let config = PasskeyRelyingParty(rpID: "knot.fi", rpName: "knot")
    XCTAssertEqual(config.rpID, "knot.fi")
  }

  func testAssertionVerifierAcceptsValidSignature() throws {
    let privateKey = P256.Signing.PrivateKey()
    let x963 = privateKey.publicKey.x963Representation
    let passkey = PasskeyPublicKey(
      x: Data(x963[1..<33]),
      y: Data(x963[33..<65]),
      credentialID: Data([0xAA, 0xBB, 0xCC])
    )
    let payload = Data("wallet-backup".utf8)
    let clientDataJSON = makeClientDataJSON(payload: payload)
    let authData = makeAuthData(rpId: "knot.fi", flags: 0x05)
    let signedData = authData + Data(SHA256.hash(data: clientDataJSON))
    let rawSignature = try privateKey.signature(for: signedData).rawRepresentation
    let assertion = PasskeySignature(
      r: Data(rawSignature.prefix(32)),
      s: Data(rawSignature.suffix(32)),
      clientDataJSON: clientDataJSON,
      authData: authData,
      credentialID: passkey.credentialID
    )

    XCTAssertNoThrow(
      try PasskeyAssertionVerifier.verify(
        signature: assertion,
        payload: payload,
        expectedPasskey: passkey,
        rpId: "knot.fi"
      )
    )
  }

  func testAssertionVerifierRejectsMissingUserVerification() throws {
    let privateKey = P256.Signing.PrivateKey()
    let x963 = privateKey.publicKey.x963Representation
    let passkey = PasskeyPublicKey(
      x: Data(x963[1..<33]),
      y: Data(x963[33..<65]),
      credentialID: Data([0xAA, 0xBB, 0xCC])
    )
    let payload = Data("wallet-backup".utf8)
    let clientDataJSON = makeClientDataJSON(payload: payload)
    let authData = makeAuthData(rpId: "knot.fi", flags: 0x01)
    let signedData = authData + Data(SHA256.hash(data: clientDataJSON))
    let rawSignature = try privateKey.signature(for: signedData).rawRepresentation
    let assertion = PasskeySignature(
      r: Data(rawSignature.prefix(32)),
      s: Data(rawSignature.suffix(32)),
      clientDataJSON: clientDataJSON,
      authData: authData,
      credentialID: passkey.credentialID
    )

    do {
      try PasskeyAssertionVerifier.verify(
        signature: assertion,
        payload: payload,
        expectedPasskey: passkey,
        rpId: "knot.fi"
      )
      XCTFail("Expected user verification failure.")
    } catch let error as PasskeyServiceError {
      guard case .userVerificationRequired = error else {
        XCTFail("Unexpected error: \(error)")
        return
      }
    }
  }

  private func makeClientDataJSON(payload: Data) -> Data {
    let challenge = Data(SHA256.hash(data: payload)).base64urlNoPadding()
    let json = #"{"type":"webauthn.get","challenge":"\#(challenge)","origin":"https://knot.fi"}"#
    return Data(json.utf8)
  }

  private func makeAuthData(rpId: String, flags: UInt8) -> Data {
    var data = Data(SHA256.hash(data: Data(rpId.utf8)))
    data.append(flags)
    data.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
    return data
  }
}

private extension Data {
  func base64urlNoPadding() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
