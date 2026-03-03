// AAExecutionServiceError.swift
// Created by Peter Anyaogu on 24/02/2026.

import Foundation

enum AAExecutionServiceError: Error {
    case executionFailed(Error)

    case relayFailed(Error)

    case signingFailed(Error)

    case relayStatusFailed(chainId: UInt64, id: String, status: String, reason: String?)

    case missingRelaySubmission(chainId: UInt64)

    case missingConfiguration
}

extension AAExecutionServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .executionFailed(error):
            return "AA execution failed: \(error.localizedDescription)"
        case let .relayFailed(error):
            return "Relay flow failed: \(error.localizedDescription)"
        case let .signingFailed(error):
            return "Signing failed: \(error.localizedDescription)"
        case let .relayStatusFailed(chainId, id, status, reason):
            if let reason, !reason.isEmpty {
                return "Relay task \(id) failed on chain \(chainId) with status \(status): \(reason)"
            }
            return "Relay task \(id) failed on chain \(chainId) with status \(status)"
        case let .missingRelaySubmission(chainId):
            return "Relay submission missing for chain \(chainId)"
        case .missingConfiguration:
            return "Missing singleton configuration for execution"
        }
    }
}
