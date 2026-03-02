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
    let rentPriceWei: String

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

    var tld: String {
        configuration.tld
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

    nonisolated func ensLabel(_ value: String) -> String {
        ENSClient.ethLabel(from: value, tld: configuration.tld)
    }

    nonisolated func canonicalENSName(_ value: String) -> String {
        ENSClient.canonicalENSName(value, tld: configuration.tld)
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
        let label = ensLabel(name)
        do {
            let result = try await withRetry {
                try await self.client.registerName(
                    RegisterNameRequestModel(
                        name: label,
                        ownerAddress: ownerAddress,
                        duration: duration,
                        setReverseRecord: true,
                        initialTextRecords: initialRecords.map {
                            InitialTextRecordModel(key: $0.key, value: $0.value)
                        },
                    ),
                )
            }
            return ENSRegistrationPayloads(
                commitCall: result.commitCall,
                registerCall: result.registerCall,
                minCommitmentAgeSeconds: result.minCommitmentAgeSeconds,
                rentPriceWei: result.rentPriceWei,
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
        let canonicalName = canonicalENSName(name)
        do {
            return try await withRetry {
                try await self.client.setTextRecord(
                    TextRecordRequestModel(
                        name: canonicalName,
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
        let canonicalName = canonicalENSName(name)
        do {
            return try await withRetry {
                try await self.client.textRecord(
                    TextRecordRequestModel(name: canonicalName, recordKey: key),
                )
            }
        } catch {
            throw ENSServiceError.actionFailed(error)
        }
    }

    func prefetchProfile(eoaAddress: String, cache: ENSProfileCache) async {
        do {
            let resolvedName = try await reverseAddress(address: eoaAddress)
            let label = ensLabel(resolvedName)
            let fullName = canonicalENSName(resolvedName)
            guard !label.isEmpty, !fullName.isEmpty else { return }

            async let avatarFetch: String =
                await (try? textRecord(name: fullName, key: "avatar"))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            async let bioFetch: String = await (try? textRecord(name: fullName, key: "description")) ?? ""

            let avatar = await avatarFetch
            let bio = await bioFetch

            cache.save(
                CachedENSProfileModel(name: label, avatarURL: avatar, bio: bio, updatedAt: Date()),
                for: eoaAddress,
            )
        } catch {
            // Pre-warm is best-effort; ignore errors
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
                    domain: "ENSService", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unknown ENS error"],
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
