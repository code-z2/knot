// AccountSetupServiceError.swift
// Created by Peter Anyaogu on 02/03/2026.

import Foundation

enum AccountSetupServiceError: Error {
    case createWalletFailed(Error)

    case signInFailed(Error)

    case restoreSessionFailed(Error)

    case walletMaterialLookupFailed(Error)

    case passkeyLookupFailed(Error)

    case passkeySignFailed(Error)
}

extension AccountSetupServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .createWalletFailed(error):
            "Create account failed: \(error.localizedDescription)"
        case let .signInFailed(error):
            "Sign-in failed: \(error.localizedDescription)"
        case let .restoreSessionFailed(error):
            "Session restore failed: \(error.localizedDescription)"
        case let .walletMaterialLookupFailed(error):
            "Wallet material lookup failed: \(error.localizedDescription)"
        case let .passkeyLookupFailed(error):
            "Passkey lookup failed: \(error.localizedDescription)"
        case let .passkeySignFailed(error):
            "Passkey signing failed: \(error.localizedDescription)"
        }
    }
}
