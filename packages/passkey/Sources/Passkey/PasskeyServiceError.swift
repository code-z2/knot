import Foundation

public enum PasskeyServiceError: Error {
    case missingWindowAnchor

    case unsupportedResponse

    case malformedAttestationObject

    case malformedAuthenticatorData

    case malformedCoseKey

    case malformedSignature

    case malformedClientDataJSON

    case challengeMismatch

    case relyingPartyMismatch

    case credentialIDMismatch

    case userVerificationRequired

    case signatureVerificationFailed

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

        case .malformedClientDataJSON:
            return "Passkey clientDataJSON is malformed."

        case .challengeMismatch:
            return "Passkey challenge does not match the expected payload."

        case .relyingPartyMismatch:
            return "Passkey relying party does not match."

        case .credentialIDMismatch:
            return "Passkey credential ID does not match the expected credential."

        case .userVerificationRequired:
            return "Passkey user verification is required."

        case .signatureVerificationFailed:
            return "Passkey signature verification failed."

        case let .authorizationFailed(code, message):
            if let code {
                return "Passkey authorization failed (\(code)): \(message)"
            }

            return "Passkey authorization failed: \(message)"
        }
    }
}
