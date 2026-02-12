import Foundation

public enum ECDSASignatureCodecError: Error {
  case signingUnavailable
  case invalidPrivateKey
  case malformedDigest
  case malformedSignature
}

extension ECDSASignatureCodecError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .signingUnavailable:
      return "ECDSA signing is unavailable (web3swift/Web3Core missing)."
    case .invalidPrivateKey:
      return "Invalid private key format."
    case .malformedDigest:
      return "Digest must be exactly 32 bytes."
    case .malformedSignature:
      return "Recovered signature payload is malformed."
    }
  }
}

public enum ECDSASignatureCodec {
  private static let ethereumMessagePrefix = Data("\u{19}Ethereum Signed Message:\n32".utf8)

  /// Ethereum `eth_sign` digest for a 32-byte preimage digest:
  /// keccak256("\x19Ethereum Signed Message:\n32" || digest32)
  public static func toEthSignedMessageHash(_ digest32: Data) throws -> Data {
    guard digest32.count == 32 else {
      throw ECDSASignatureCodecError.malformedDigest
    }
#if canImport(web3swift)
    return Data((ethereumMessagePrefix + digest32).sha3(.keccak256))
#else
    throw ECDSASignatureCodecError.signingUnavailable
#endif
  }

  /// Returns a 65-byte recoverable signature [r || s || v] where v is 27/28.
  public static func signDigest(
    _ digest32: Data,
    privateKeyHex: String
  ) throws -> Data {
#if canImport(web3swift) && canImport(Web3Core)
    guard digest32.count == 32 else {
      throw ECDSASignatureCodecError.malformedDigest
    }
    guard let privateKey = Data.fromHex(privateKeyHex) else {
      throw ECDSASignatureCodecError.invalidPrivateKey
    }

    let (recoverableSignature, _) = SECP256K1.signForRecovery(hash: digest32, privateKey: privateKey)
    guard let recoverable = recoverableSignature, recoverable.count >= 65 else {
      throw ECDSASignatureCodecError.malformedSignature
    }

    let r = Data(recoverable[0..<32])
    let s = Data(recoverable[32..<64])
    let rawV = recoverable[64]
    let v: UInt8 = (rawV == 27 || rawV == 28) ? rawV : (rawV + 27)
    return r + s + Data([v])
#else
    throw ECDSASignatureCodecError.signingUnavailable
#endif
  }
}

#if canImport(Web3Core)
import Web3Core
#endif
#if canImport(web3swift)
import web3swift
#endif
