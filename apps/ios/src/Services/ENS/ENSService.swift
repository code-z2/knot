import ENS
import Foundation
import RPC
import Transactions

enum ENSServiceError: Error {
    case actionFailed(Error)
}

struct ENSNameQuote {
    let normalizedName: String
    let available: Bool
    let rentPriceWei: String
}

struct ENSRecordDraft {
    let key: String
    let value: String
}

struct ENSRegistrationPayloads {
    let commitCall: Call
    let registerCall: Call
    let minCommitmentAgeSeconds: UInt64

    var calls: [Call] {
        [commitCall, registerCall]
    }
}

extension ENSServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .actionFailed(error):
            "ENS action failed: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class ENSService {
    private let client: ENSClient
    let configuration: ENSConfiguration

    var chainID: UInt64 {
        configuration.chainID
    }

    init(
        mode: ChainSupportMode = ChainSupportRuntime.resolveMode(),
        configuration: ENSConfiguration? = nil,
        client: ENSClient? = nil,
    ) {
        let resolvedConfiguration = configuration ?? ENSService.configuration(for: mode)
        self.configuration = resolvedConfiguration
        self.client = client ?? ENSClient(configuration: resolvedConfiguration)
    }

    private nonisolated static func configuration(
        for mode: ChainSupportMode,
    ) -> ENSConfiguration {
        switch mode {
        case .limitedTestnet:
            .sepolia
        case .limitedMainnet, .fullMainnet:
            .mainnet
        }
    }

    func resolveName(name: String) async throws -> String {
        do {
            return try await withRetry {
                try await self.client.resolveName(
                    ResolveNameRequestModel(name: name),
                )
            }
        } catch {
            throw ENSServiceError.actionFailed(error)
        }
    }

    func reverseAddress(address: String) async throws -> String {
        do {
            return try await withRetry {
                try await self.client.reverseAddress(
                    ReverseAddressRequestModel(address: address),
                )
            }
        } catch {
            throw ENSServiceError.actionFailed(error)
        }
    }

    func registerNamePayloads(
        name: String,
        ownerAddress: String,
        initialRecords: [ENSRecordDraft] = [],
        duration: UInt = 31_536_000,
    ) async throws -> ENSRegistrationPayloads {
        print("⚙️ [ENSService] Resolving ENS Registration Payloads for \(name)")
        do {
            let result = try await withRetry {
                try await self.client.registerName(
                    RegisterNameRequestModel(
                        name: name,
                        ownerAddress: ownerAddress,
                        duration: duration,
                        initialTextRecords: initialRecords.map {
                            InitialTextRecordModel(key: $0.key, value: $0.value)
                        },
                    ),
                )
            }
            print("✅ [ENSService] Payloads determined.")
            print("   - Commit Call Value (Wei): \(result.commitCall.valueWei)")
            print("   - Register Call Value (Wei): \(result.registerCall.valueWei)")
            return ENSRegistrationPayloads(
                commitCall: result.commitCall,
                registerCall: result.registerCall,
                minCommitmentAgeSeconds: result.minCommitmentAgeSeconds,
            )
        } catch {
            throw ENSServiceError.actionFailed(error)
        }
    }

    func setTextRecordPayload(
        name: String,
        key: String,
        value: String,
    ) async throws -> Call {
        do {
            return try await withRetry {
                try await self.client.setTextRecord(
                    TextRecordRequestModel(
                        name: name,
                        recordKey: key,
                        recordValue: value,
                    ),
                )
            }
        } catch {
            throw ENSServiceError.actionFailed(error)
        }
    }

    func textRecord(
        name: String,
        key: String,
    ) async throws -> String {
        do {
            return try await withRetry {
                try await self.client.textRecord(
                    TextRecordRequestModel(name: name, recordKey: key),
                )
            }
        } catch {
            throw ENSServiceError.actionFailed(error)
        }
    }

    private func withRetry<T>(
        maxAttempts: Int = 2,
        operation: @escaping () async throws -> T,
    ) async throws -> T {
        precondition(maxAttempts >= 1)
        var attempt = 0
        var lastError: Error?

        while attempt < maxAttempts {
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                attempt += 1
                guard attempt < maxAttempts, shouldRetry(error: error) else {
                    throw error
                }
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    throw error
                }
            }
        }

        throw lastError
            ?? ENSServiceError.actionFailed(
                NSError(
                    domain: "ENSService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown ENS error"],
                ),
            )
    }

    private func shouldRetry(error: Error) -> Bool {
        if error is URLError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return true
        }

        return false
    }
}
