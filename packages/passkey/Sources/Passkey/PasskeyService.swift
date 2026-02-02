import AuthenticationServices
import CryptoKit
import Foundation
import SwiftCBOR
#if canImport(UIKit)
import UIKit
#endif

public struct PasskeyRelyingParty: Sendable, Equatable {
  public let rpID: String
  public let rpName: String

  public init(rpID: String, rpName: String) {
    self.rpID = rpID
    self.rpName = rpName
  }
}

public struct PasskeyPublicKey: Sendable, Equatable, Codable {
  public let x: Data
  public let y: Data
  public let credentialID: Data
  public let userName: String
  public let aaGuid: Data
  public let rawAttestationObject: Data
  public let rawClientDataJSON: Data

  public init(
    x: Data,
    y: Data,
    credentialID: Data,
    userName: String,
    aaGuid: Data,
    rawAttestationObject: Data,
    rawClientDataJSON: Data
  ) {
    self.x = x
    self.y = y
    self.credentialID = credentialID
    self.userName = userName
    self.aaGuid = aaGuid
    self.rawAttestationObject = rawAttestationObject
    self.rawClientDataJSON = rawClientDataJSON
  }
}

public struct PasskeySignature: Sendable, Equatable, Codable {
  public let r: Data
  public let s: Data
  public let clientDataJSON: Data
  public let authData: Data
  public let credentialID: Data

  public init(r: Data, s: Data, clientDataJSON: Data, authData: Data, credentialID: Data) {
    self.r = r
    self.s = s
    self.clientDataJSON = clientDataJSON
    self.authData = authData
    self.credentialID = credentialID
  }

  public func normalized() -> PasskeySignature {
    let normalizedS = SignatureNormalizer.normalizeP256S(s)
    return PasskeySignature(
      r: SignatureNormalizer.leftPadTo32(r),
      s: normalizedS,
      clientDataJSON: clientDataJSON,
      authData: authData,
      credentialID: credentialID
    )
  }

  public func getTypePosition() -> Int? {
    guard let json = String(data: clientDataJSON, encoding: .utf8) else { return nil }
    return json.range(of: "\"type\"")?.lowerBound.utf16Offset(in: json)
  }

  public func getChallengePosition(payload: Data) -> Int? {
    guard let json = String(data: clientDataJSON, encoding: .utf8) else { return nil }
    let challenge = Data(SHA256.hash(data: payload)).base64URLEncodedStringNoPadding()
    return json.range(of: challenge)?.lowerBound.utf16Offset(in: json)
  }
}

public enum PasskeyServiceError: Error {
  case missingWindowAnchor
  case unsupportedResponse
  case malformedAttestationObject
  case malformedAuthenticatorData
  case malformedCoseKey
  case malformedSignature
  case authorizationFailed(code: Int?, message: String)
}

extension PasskeyServiceError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .missingWindowAnchor:
      return "No presentation anchor is available for passkey prompt."
    case .unsupportedResponse:
      return "Received unsupported passkey response type."
    case .malformedAttestationObject:
      return "Passkey attestation object is malformed."
    case .malformedAuthenticatorData:
      return "Passkey authenticator data is malformed."
    case .malformedCoseKey:
      return "Passkey COSE public key is malformed."
    case .malformedSignature:
      return "Passkey signature payload is malformed."
    case .authorizationFailed(let code, let message):
      if let code {
        return "Passkey authorization failed (\(code)): \(message)"
      }
      return "Passkey authorization failed: \(message)"
    }
  }
}

public protocol PasskeyServicing {
  func register(
    rpId: String,
    rpName: String,
    challenge: Data,
    userName: String,
    userID: Data
  ) async throws -> PasskeyPublicKey

  func sign(rpId: String, payload: Data) async throws -> PasskeySignature
}

@MainActor
public final class PasskeyService: NSObject, PasskeyServicing {
  private weak var anchor: ASPresentationAnchor?
  private var continuation: CheckedContinuation<ResultPayload, Error>?

  public init(anchor: ASPresentationAnchor?) {
    self.anchor = anchor
  }

  public func register(
    rpId: String,
    rpName _: String,
    challenge: Data,
    userName: String,
    userID: Data
  ) async throws -> PasskeyPublicKey {
    let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
    let request = provider.createCredentialRegistrationRequest(
      challenge: challenge,
      name: userName,
      userID: userID
    )

    let result = try await performRequest(request)
    guard case .registration(let registration) = result else {
      throw PasskeyServiceError.unsupportedResponse
    }

    let parsed = try WebAuthnAttestationParser.parse(registration.rawAttestationObject ?? Data())

    return PasskeyPublicKey(
      x: parsed.x,
      y: parsed.y,
      credentialID: registration.credentialID,
      userName: userName,
      aaGuid: parsed.aaguid,
      rawAttestationObject: registration.rawAttestationObject ?? Data(),
      rawClientDataJSON: registration.rawClientDataJSON
    )
  }

  public func sign(rpId: String, payload: Data) async throws -> PasskeySignature {
    let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
    let challenge = Data(SHA256.hash(data: payload))
    let request = provider.createCredentialAssertionRequest(challenge: challenge)

    let result = try await performRequest(request)
    guard case .assertion(let assertion) = result else {
      throw PasskeyServiceError.unsupportedResponse
    }

    let (r, s) = try DERP256SignatureParser.parse(assertion.signature)

    return PasskeySignature(
      r: r,
      s: s,
      clientDataJSON: assertion.rawClientDataJSON,
      authData: assertion.rawAuthenticatorData,
      credentialID: assertion.credentialID
    )
  }

  private func performRequest(_ request: ASAuthorizationRequest) async throws -> ResultPayload {
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      let controller = ASAuthorizationController(authorizationRequests: [request])
      controller.delegate = self
      controller.presentationContextProvider = self
      controller.performRequests()
    }
  }

  private enum ResultPayload {
    case registration(ASAuthorizationPlatformPublicKeyCredentialRegistration)
    case assertion(ASAuthorizationPlatformPublicKeyCredentialAssertion)
  }
}

extension PasskeyService: ASAuthorizationControllerDelegate {
  public func authorizationController(
    controller _: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    if let registration = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
      continuation?.resume(returning: .registration(registration))
      continuation = nil
      return
    }

    if let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
      continuation?.resume(returning: .assertion(assertion))
      continuation = nil
      return
    }

    continuation?.resume(throwing: PasskeyServiceError.unsupportedResponse)
    continuation = nil
  }

  public func authorizationController(
    controller _: ASAuthorizationController,
    didCompleteWithError error: Error
  ) {
    let nsError = error as NSError
    continuation?.resume(
      throwing: PasskeyServiceError.authorizationFailed(
        code: nsError.code,
        message: nsError.localizedDescription
      )
    )
    continuation = nil
  }
}

extension PasskeyService: ASAuthorizationControllerPresentationContextProviding {
  public func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
    if let anchor {
      return anchor
    }
#if canImport(UIKit)
    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
    {
      return window
    }
#endif
    return ASPresentationAnchor()
  }
}

private enum WebAuthnAttestationParser {
  static func parse(_ attestationObject: Data) throws -> (aaguid: Data, x: Data, y: Data) {
    let decoded = try CBOR.decode([UInt8](attestationObject))

    guard
      case let .map(attestationMap) = decoded,
      let authDataNode = attestationMap[.utf8String("authData")],
      case let .byteString(authDataBytes) = authDataNode
    else {
      throw PasskeyServiceError.malformedAttestationObject
    }

    let authData = Data(authDataBytes)
    guard authData.count >= 55 else { throw PasskeyServiceError.malformedAuthenticatorData }

    let flags = authData[32]
    let hasAttestedCredentialData = (flags & 0x40) != 0
    guard hasAttestedCredentialData else {
      throw PasskeyServiceError.malformedAuthenticatorData
    }

    var index = 37
    let aaguid = authData[index..<(index + 16)]
    index += 16

    let credIdLength = Int(UInt16(authData[index]) << 8 | UInt16(authData[index + 1]))
    index += 2

    guard authData.count >= index + credIdLength else {
      throw PasskeyServiceError.malformedAuthenticatorData
    }

    index += credIdLength
    guard authData.count > index else {
      throw PasskeyServiceError.malformedAuthenticatorData
    }

    let coseBytes = Data(authData[index...])
    let coseDecoded = try CBOR.decode([UInt8](coseBytes))

    guard case let .map(coseMap) = coseDecoded else {
      throw PasskeyServiceError.malformedCoseKey
    }

    let xKey = CBOR.negativeInt(1) // -2 => encoded as -(1+1)
    let yKey = CBOR.negativeInt(2) // -3 => encoded as -(2+1)

    guard
      let xNode = coseMap[xKey],
      let yNode = coseMap[yKey],
      case let .byteString(xBytes) = xNode,
      case let .byteString(yBytes) = yNode
    else {
      throw PasskeyServiceError.malformedCoseKey
    }

    return (
      aaguid: Data(aaguid),
      x: SignatureNormalizer.leftPadTo32(Data(xBytes)),
      y: SignatureNormalizer.leftPadTo32(Data(yBytes))
    )
  }
}

private enum DERP256SignatureParser {
  static func parse(_ der: Data) throws -> (r: Data, s: Data) {
    let bytes = [UInt8](der)
    guard bytes.count > 8, bytes[0] == 0x30 else {
      throw PasskeyServiceError.malformedSignature
    }

    var index = 2
    guard bytes[index] == 0x02 else { throw PasskeyServiceError.malformedSignature }
    index += 1

    let rLength = Int(bytes[index])
    index += 1
    guard bytes.count >= index + rLength else { throw PasskeyServiceError.malformedSignature }
    let r = Data(bytes[index..<(index + rLength)])
    index += rLength

    guard bytes.count > index, bytes[index] == 0x02 else {
      throw PasskeyServiceError.malformedSignature
    }
    index += 1

    let sLength = Int(bytes[index])
    index += 1
    guard bytes.count >= index + sLength else { throw PasskeyServiceError.malformedSignature }
    let s = Data(bytes[index..<(index + sLength)])

    return (
      SignatureNormalizer.leftPadTo32(r.stripLeadingZeroDERByte()),
      SignatureNormalizer.leftPadTo32(s.stripLeadingZeroDERByte())
    )
  }
}

private enum SignatureNormalizer {
  private static let p256Order = Data(hex: "FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551")
  private static let p256HalfOrder = Data(hex: "7FFFFFFF800000007FFFFFFFFFFFFFFFDE737D56D38BCF4279DCE5617E3192A8")

  static func normalizeP256S(_ s: Data) -> Data {
    let paddedS = leftPadTo32(s)
    guard paddedS.lexicographicallyPrecedes(p256HalfOrder) == false, paddedS != p256HalfOrder else {
      return paddedS
    }
    return subtract(p256Order, paddedS)
  }

  static func leftPadTo32(_ data: Data) -> Data {
    if data.count >= 32 { return Data(data.suffix(32)) }
    return Data(repeating: 0, count: 32 - data.count) + data
  }

  private static func subtract(_ lhs: Data, _ rhs: Data) -> Data {
    var a = [UInt8](lhs)
    let b = [UInt8](rhs)
    var borrow = 0

    for i in stride(from: a.count - 1, through: 0, by: -1) {
      var value = Int(a[i]) - Int(b[i]) - borrow
      if value < 0 {
        value += 256
        borrow = 1
      } else {
        borrow = 0
      }
      a[i] = UInt8(value)
    }

    return Data(a)
  }
}

private extension Data {
  init(hex: String) {
    self.init()
    var input = hex.replacingOccurrences(of: "0x", with: "")
    if input.count % 2 != 0 { input = "0" + input }

    var index = input.startIndex
    while index < input.endIndex {
      let next = input.index(index, offsetBy: 2)
      append(UInt8(input[index..<next], radix: 16) ?? 0)
      index = next
    }
  }

  func stripLeadingZeroDERByte() -> Data {
    guard count > 1, first == 0x00 else { return self }
    return Data(dropFirst())
  }

  func base64URLEncodedStringNoPadding() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
