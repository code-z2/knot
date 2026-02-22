import Foundation
import Security

public enum KeychainStoreError: Error {
    case unexpectedStatus(OSStatus)

    case dataNotFound

    case invalidData
}

extension KeychainStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain operation failed (\(status)): \(message)"
            }

            return "Keychain operation failed with status \(status)."

        case .dataNotFound:
            return "No keychain item was found for the requested account/service."

        case .invalidData:
            return "Keychain returned data in an unexpected format."
        }
    }
}
